import asyncio
import logging
from contextlib import suppress
from datetime import datetime, timedelta, timezone

from pymongo import ReturnDocument

from app.background.ticket_generator import generate_ticket_for_registration
from app.core.identifiers import parse_object_id
from app.db.mongo import get_database

logger = logging.getLogger(__name__)

MAX_TICKET_ATTEMPTS = 5


async def enqueue_ticket(registration_id: str) -> None:
    """Persist a unique ticket job before an API reports confirmation."""
    db = get_database()
    registration_object_id = parse_object_id(registration_id, "registration")
    now = datetime.now(timezone.utc)
    await db.ticket_jobs.update_one(
        {"registrationId": registration_object_id},
        {
            "$setOnInsert": {
                "registrationId": registration_object_id,
                "status": "pending",
                "attempts": 0,
                "nextAttemptAt": now,
                "createdAt": now,
            },
            "$set": {"updatedAt": now},
        },
        upsert=True,
    )
    await db.registrations.update_one(
        {"_id": registration_object_id, "status": {"$in": ["confirmed", "checked_in"]}},
        {"$set": {"ticketStatus": "PENDING", "ticketError": None, "updatedAt": now}},
    )


async def process_ticket_job(registration_id: str) -> bool:
    """Claim and run one job. Safe to call concurrently and after restarts."""
    db = get_database()
    registration_object_id = parse_object_id(registration_id, "registration")
    now = datetime.now(timezone.utc)
    job = await db.ticket_jobs.find_one_and_update(
        {
            "registrationId": registration_object_id,
            "status": {"$in": ["pending", "retryable"]},
            "nextAttemptAt": {"$lte": now},
        },
        {
            "$set": {
                "status": "processing",
                "leaseExpiresAt": now + timedelta(minutes=2),
                "updatedAt": now,
            },
            "$inc": {"attempts": 1},
        },
        return_document=ReturnDocument.AFTER,
    )
    if job is None:
        ticket = await db.tickets.find_one({"registrationId": registration_object_id})
        return ticket is not None

    try:
        created = await generate_ticket_for_registration(registration_id)
        await db.ticket_jobs.update_one(
            {"_id": job["_id"]},
            {"$set": {"status": "completed", "completedAt": datetime.now(timezone.utc), "updatedAt": datetime.now(timezone.utc)}},
        )
        await db.registrations.update_one(
            {"_id": registration_object_id},
            {"$set": {"ticketStatus": "READY", "ticketError": None, "updatedAt": datetime.now(timezone.utc)}},
        )
        return created
    except Exception as exc:
        attempts = int(job.get("attempts", 1))
        terminal = attempts >= MAX_TICKET_ATTEMPTS
        retry_at = datetime.now(timezone.utc) + timedelta(seconds=min(300, 2 ** attempts))
        status = "failed" if terminal else "retryable"
        public_status = "FAILED" if terminal else "RETRYABLE"
        error = type(exc).__name__
        await db.ticket_jobs.update_one(
            {"_id": job["_id"]},
            {"$set": {"status": status, "lastError": error, "nextAttemptAt": retry_at, "updatedAt": datetime.now(timezone.utc)}},
        )
        await db.registrations.update_one(
            {"_id": registration_object_id},
            {"$set": {"ticketStatus": public_status, "ticketError": "Ticket generation will be retried" if not terminal else "Ticket generation failed", "updatedAt": datetime.now(timezone.utc)}},
        )
        logger.exception("Ticket generation failed for registration %s", registration_id)
        return False


async def retry_ticket(registration_id: str) -> None:
    db = get_database()
    registration_object_id = parse_object_id(registration_id, "registration")
    now = datetime.now(timezone.utc)
    result = await db.ticket_jobs.update_one(
        {"registrationId": registration_object_id, "status": {"$in": ["failed", "retryable"]}},
        {"$set": {"status": "pending", "attempts": 0, "nextAttemptAt": now, "updatedAt": now}},
    )
    if result.matched_count:
        await db.registrations.update_one(
            {"_id": registration_object_id},
            {"$set": {"ticketStatus": "PENDING", "ticketError": None, "updatedAt": now}},
        )


async def recover_ticket_jobs() -> None:
    db = get_database()
    now = datetime.now(timezone.utc)
    await db.ticket_jobs.update_many(
        {"status": "processing", "leaseExpiresAt": {"$lte": now}},
        {"$set": {"status": "retryable", "nextAttemptAt": now, "updatedAt": now}},
    )


async def ticket_worker(stop_event: asyncio.Event | None = None) -> None:
    await recover_ticket_jobs()
    while stop_event is None or not stop_event.is_set():
        db = get_database()
        now = datetime.now(timezone.utc)
        job = await db.ticket_jobs.find_one(
            {"status": {"$in": ["pending", "retryable"]}, "nextAttemptAt": {"$lte": now}},
            sort=[("nextAttemptAt", 1)],
        )
        if job:
            await process_ticket_job(str(job["registrationId"]))
            continue
        with suppress(asyncio.TimeoutError):
            if stop_event is None:
                await asyncio.sleep(1)
            else:
                await asyncio.wait_for(stop_event.wait(), timeout=1)
