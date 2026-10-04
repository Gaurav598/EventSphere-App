import logging
from datetime import datetime, timezone

from pymongo import ASCENDING, TEXT, AsyncMongoClient, IndexModel, ReturnDocument
from pymongo.errors import OperationFailure

from app.core.config import settings

logger = logging.getLogger(__name__)


class MongoDB:
    client: AsyncMongoClient | None = None
    db = None


db = MongoDB()


async def create_indexes() -> None:
    database = get_database()
    event_indexes = await database.events.index_information()
    if "events_invite_unique" in event_indexes:
        # The original sparse unique index still indexed explicit null values.
        # Replace it once with a partial index that covers real invite strings.
        try:
            await database.events.drop_index("events_invite_unique")
        except OperationFailure as exc:
            # Another replica may have completed the same one-time migration.
            if exc.code != 27:  # IndexNotFound
                raise
            logger.info("Legacy invite index was already removed")
    await database.users.create_indexes(
        [IndexModel([("email", ASCENDING)], unique=True, name="users_email_unique")]
    )
    await database.events.create_indexes(
        [
            IndexModel([("eventDate", ASCENDING)], name="events_event_date"),
            IndexModel([("category", ASCENDING)], name="events_category"),
            IndexModel([("location", ASCENDING)], name="events_location"),
            IndexModel(
                [("name", TEXT), ("description", TEXT)],
                name="events_name_description_text",
            ),
            IndexModel([("createdBy", ASCENDING), ("isDeleted", ASCENDING)], name="events_owner_active"),
            IndexModel(
                [("inviteCode", ASCENDING)],
                unique=True,
                partialFilterExpression={"inviteCode": {"$type": "string"}},
                name="events_invite_unique_v2",
            ),
        ]
    )
    await database.registrations.create_indexes(
        [
            IndexModel(
                [("userId", ASCENDING), ("eventId", ASCENDING)],
                unique=True,
                name="registrations_user_event_unique",
            ),
            IndexModel([("eventId", ASCENDING)], name="registrations_event"),
            IndexModel(
                [("eventId", ASCENDING), ("status", ASCENDING), ("waitlistSequence", ASCENDING)],
                name="registrations_waitlist",
            ),
        ]
    )
    await database.tickets.create_indexes(
        [
            IndexModel(
                [("registrationId", ASCENDING)],
                unique=True,
                name="tickets_registration_unique",
            )
        ]
    )
    await database.ticket_jobs.create_indexes(
        [
            IndexModel(
                [("registrationId", ASCENDING)],
                unique=True,
                name="ticket_jobs_registration_unique",
            ),
            IndexModel(
                [("status", ASCENDING), ("nextAttemptAt", ASCENDING)],
                name="ticket_jobs_ready",
            ),
        ]
    )
    await database.favorites.create_indexes(
        [
            IndexModel(
                [("userId", ASCENDING), ("eventId", ASCENDING)],
                unique=True,
                name="favorites_user_event_unique",
            )
        ]
    )


async def reconcile_registration_counters() -> None:
    """Recover interrupted claims, backfill jobs, and repair capacity counters.

    This runs before the API accepts traffic, so no live request races the repair.
    A public ``processing`` registration is an interrupted reserve/confirm operation;
    a private one is an interrupted organizer approval and is returned to ``pending``
    unless its seat token proves that capacity was already reserved.
    """
    database = get_database()
    now = datetime.now(timezone.utc)

    async for registration in database.registrations.find({"status": "processing"}):
        event = await database.events.find_one({"_id": registration["eventId"]})
        if not event or event.get("isDeleted"):
            await database.registrations.update_one(
                {"_id": registration["_id"], "status": "processing"},
                {"$set": {"status": "cancelled", "cancelledAt": now, "ticketStatus": "NOT_REQUIRED", "updatedAt": now}},
            )
            continue

        has_reservation = registration["_id"] in event.get("confirmedRegistrationIds", [])
        if has_reservation:
            await database.registrations.update_one(
                {"_id": registration["_id"], "status": "processing"},
                {"$set": {"status": "confirmed", "ticketStatus": "PENDING", "updatedAt": now}},
            )
            continue

        if event.get("isPrivate"):
            await database.registrations.update_one(
                {"_id": registration["_id"], "status": "processing"},
                {"$set": {"status": "pending", "updatedAt": now}},
            )
            continue

        reserved = await database.events.find_one_and_update(
            {
                "_id": event["_id"],
                "isDeleted": False,
                "isRegistrationOpen": True,
                "eventDate": {"$gt": now},
                "registrationDeadline": {"$gte": now},
                "confirmedRegistrationIds": {"$ne": registration["_id"]},
                "$expr": {"$lt": ["$registeredCount", "$capacity"]},
            },
            {
                "$addToSet": {"confirmedRegistrationIds": registration["_id"]},
                "$inc": {"registeredCount": 1},
                "$set": {"updatedAt": now},
            },
            return_document=ReturnDocument.AFTER,
        )
        if reserved:
            await database.registrations.update_one(
                {"_id": registration["_id"], "status": "processing"},
                {"$set": {"status": "confirmed", "ticketStatus": "PENDING", "updatedAt": now}},
            )
        elif (
            event.get("allowWaitlist")
            and event.get("isRegistrationOpen")
            and event.get("eventDate") > now
            and event.get("registrationDeadline") is not None
            and event["registrationDeadline"] >= now
        ):
            sequenced = await database.events.find_one_and_update(
                {"_id": event["_id"], "isDeleted": False},
                {"$inc": {"nextWaitlistSequence": 1}},
                return_document=ReturnDocument.AFTER,
            )
            if sequenced:
                await database.registrations.update_one(
                    {"_id": registration["_id"], "status": "processing"},
                    {"$set": {"status": "waitlisted", "waitlistSequence": sequenced["nextWaitlistSequence"], "updatedAt": now}},
                )
        else:
            await database.registrations.update_one(
                {"_id": registration["_id"], "status": "processing"},
                {"$set": {"status": "cancelled", "cancelledAt": now, "ticketStatus": "NOT_REQUIRED", "updatedAt": now}},
            )

    async for event in database.events.find({}, {"_id": 1, "isDeleted": 1}):
        if event.get("isDeleted"):
            registration_ids = []
        else:
            registration_ids = [
                registration["_id"]
                async for registration in database.registrations.find(
                    {"eventId": event["_id"], "status": {"$in": ["confirmed", "checked_in"]}},
                    {"_id": 1},
                )
            ]
        await database.events.update_one(
            {"_id": event["_id"]},
            {"$set": {"confirmedRegistrationIds": registration_ids, "registeredCount": len(registration_ids)}},
        )

    # Legacy and recovered confirmations must also have durable ticket work.
    async for registration in database.registrations.find(
        {"status": {"$in": ["confirmed", "checked_in"]}},
        {"_id": 1},
    ):
        ticket = await database.tickets.find_one(
            {"registrationId": registration["_id"], "isValid": True},
            {"_id": 1},
        )
        if ticket:
            await database.registrations.update_one(
                {"_id": registration["_id"]},
                {"$set": {"ticketStatus": "READY", "ticketError": None}},
            )
            continue
        await database.ticket_jobs.update_one(
            {"registrationId": registration["_id"]},
            {
                "$setOnInsert": {
                    "registrationId": registration["_id"],
                    "status": "pending",
                    "attempts": 0,
                    "nextAttemptAt": now,
                    "createdAt": now,
                },
                "$set": {"updatedAt": now},
            },
            upsert=True,
        )
        job = await database.ticket_jobs.find_one(
            {"registrationId": registration["_id"]},
            {"status": 1},
        )
        job_status = job.get("status") if job else "pending"
        if job_status == "completed":
            # A completed job without a valid ticket is an inconsistent legacy
            # state; make it runnable again.
            await database.ticket_jobs.update_one(
                {"registrationId": registration["_id"], "status": "completed"},
                {"$set": {"status": "pending", "attempts": 0, "nextAttemptAt": now, "updatedAt": now}},
            )
            job_status = "pending"
        public_ticket_status = {
            "failed": "FAILED",
            "retryable": "RETRYABLE",
        }.get(job_status, "PENDING")
        registration_update = {"ticketStatus": public_ticket_status}
        if public_ticket_status == "PENDING":
            registration_update["ticketError"] = None
        await database.registrations.update_one(
            {"_id": registration["_id"]},
            {"$set": registration_update},
        )


async def connect_to_mongo() -> None:
    logger.info("Connecting to MongoDB...")
    db.client = AsyncMongoClient(
        settings.MONGO_URI,
        serverSelectionTimeoutMS=settings.MONGO_CONNECT_TIMEOUT_SECONDS * 1000,
        tz_aware=True,
    )
    await db.client.admin.command("ping")
    db.db = db.client[settings.MONGO_DB_NAME]
    await create_indexes()
    await reconcile_registration_counters()
    logger.info("Connected to MongoDB")


async def close_mongo_connection() -> None:
    logger.info("Closing MongoDB connection...")
    if db.client is not None:
        await db.client.close()
    db.client = None
    db.db = None
    logger.info("MongoDB connection closed")


def get_database():
    if db.db is None:
        raise RuntimeError("MongoDB has not been initialized")
    return db.db
