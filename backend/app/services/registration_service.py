import asyncio
import json
import logging
from datetime import datetime, timezone
from typing import Any

from pymongo import ReturnDocument
from pymongo.errors import DuplicateKeyError
from redis.exceptions import RedisError

from app.background.ticket_queue import enqueue_ticket
from app.core.identifiers import parse_object_id
from app.core.websocket_manager import manager
from app.db.mongo import get_database
from app.db.redis_client import get_redis, invalidate_event_cache
from app.exceptions.handlers import AppException
from app.models.event import EventResponse
from app.models.registration import RegistrationInDB, RegistrationResponse
from app.models.ticket import TicketResponse

logger = logging.getLogger(__name__)


class RegistrationService:
    """Registration state machine using durable idempotency tokens for seats."""

    @staticmethod
    async def register_user_for_event(user_id: str, event_id: str) -> dict[str, Any]:
        db = get_database()
        event_object_id = parse_object_id(event_id, "event")
        user_object_id = parse_object_id(user_id, "user")
        now = datetime.now(timezone.utc)
        event = await db.events.find_one({"_id": event_object_id, "isDeleted": False})
        RegistrationService._validate_registration_window(event, now)

        is_private = bool(event.get("isPrivate", False))
        registration = RegistrationInDB(
            userId=user_object_id,
            eventId=event_object_id,
            status="pending" if is_private else "processing",
        )
        try:
            result = await db.registrations.insert_one(
                registration.model_dump(by_alias=True, exclude={"id"})
            )
            registration_id = result.inserted_id
        except DuplicateKeyError as exc:
            existing = await db.registrations.find_one(
                {"userId": user_object_id, "eventId": event_object_id}
            )
            if existing and existing.get("status") == "processing":
                return await RegistrationService._complete_public_registration(existing, event)
            raise AppException(
                code="ALREADY_REGISTERED",
                message="User already has a registration for this event",
                status_code=409,
            ) from exc

        if is_private:
            await RegistrationService._broadcast(event_id)
            return {
                "registrationId": str(registration_id),
                "status": "pending",
                "ticketStatus": "NOT_REQUIRED",
            }

        created = await db.registrations.find_one({"_id": registration_id})
        return await RegistrationService._complete_public_registration(created, event)

    @staticmethod
    def _validate_registration_window(event: dict[str, Any] | None, now: datetime) -> None:
        if not event:
            raise AppException(code="EVENT_NOT_FOUND", message="Event not found", status_code=404)
        if event.get("eventDate") and event["eventDate"] <= now:
            raise AppException(code="EVENT_STARTED", message="This event has already started", status_code=400)
        if event.get("registrationDeadline") and event["registrationDeadline"] < now:
            raise AppException(code="REGISTRATION_DEADLINE_PASSED", message="The registration deadline has passed", status_code=400)
        if not event.get("isRegistrationOpen"):
            raise AppException(code="REGISTRATION_CLOSED", message="Registration is closed for this event", status_code=400)

    @staticmethod
    async def _complete_public_registration(
        registration: dict[str, Any], event: dict[str, Any]
    ) -> dict[str, Any]:
        db = get_database()
        registration_id = registration["_id"]
        event_id = registration["eventId"]
        reserved = await RegistrationService._reserve_capacity(event_id, registration_id)
        if not reserved:
            if event.get("allowWaitlist", False):
                sequenced_event = await db.events.find_one_and_update(
                    {"_id": event_id, "isDeleted": False},
                    {"$inc": {"nextWaitlistSequence": 1}},
                    return_document=ReturnDocument.AFTER,
                )
                sequence = sequenced_event.get("nextWaitlistSequence", 1) if sequenced_event else 1
                await db.registrations.update_one(
                    {"_id": registration_id, "status": "processing"},
                    {"$set": {"status": "waitlisted", "waitlistSequence": sequence, "updatedAt": datetime.now(timezone.utc)}},
                )
                await RegistrationService._broadcast(str(event_id))
                return {
                    "registrationId": str(registration_id),
                    "status": "waitlisted",
                    "waitlistPosition": await RegistrationService._waitlist_position(event_id, sequence),
                    "ticketStatus": "NOT_REQUIRED",
                }
            await db.registrations.delete_one({"_id": registration_id, "status": "processing"})
            raise AppException(code="EVENT_FULL", message="This event has reached full capacity", status_code=409)

        now = datetime.now(timezone.utc)
        await db.registrations.update_one(
            {"_id": registration_id, "status": "processing"},
            {"$set": {"status": "confirmed", "ticketStatus": "PENDING", "updatedAt": now}},
        )
        await enqueue_ticket(str(registration_id))
        await invalidate_event_cache()
        await RegistrationService._publish_registration(
            event_id=str(event_id),
            user_id=str(registration["userId"]),
            registration_id=str(registration_id),
            timestamp=registration.get("registeredAt", now),
        )
        await RegistrationService._broadcast(str(event_id))
        return {
            "registrationId": str(registration_id),
            "status": "confirmed",
            "ticketStatus": "PENDING",
        }

    @staticmethod
    async def _reserve_capacity(event_id, registration_id) -> bool:
        db = get_database()
        now = datetime.now(timezone.utc)
        updated = await db.events.find_one_and_update(
            {
                "_id": event_id,
                "eventDate": {"$gt": now},
                "registrationDeadline": {"$gte": now},
                "isRegistrationOpen": True,
                "isDeleted": False,
                "confirmedRegistrationIds": {"$ne": registration_id},
                "$expr": {"$lt": ["$registeredCount", "$capacity"]},
            },
            {
                "$addToSet": {"confirmedRegistrationIds": registration_id},
                "$inc": {"registeredCount": 1},
                "$set": {"updatedAt": now},
            },
            return_document=ReturnDocument.AFTER,
        )
        if updated:
            return True
        existing = await db.events.find_one({"_id": event_id, "confirmedRegistrationIds": registration_id})
        return existing is not None

    @staticmethod
    async def _release_capacity(event_id, registration_id) -> bool:
        result = await get_database().events.update_one(
            {"_id": event_id, "confirmedRegistrationIds": registration_id},
            {
                "$pull": {"confirmedRegistrationIds": registration_id},
                "$inc": {"registeredCount": -1},
                "$set": {"updatedAt": datetime.now(timezone.utc)},
            },
        )
        return result.modified_count == 1

    @staticmethod
    async def cancel_registration(registration_id: str, user_id: str) -> dict[str, Any]:
        db = get_database()
        reg_id = parse_object_id(registration_id, "registration")
        user_object_id = parse_object_id(user_id, "user")
        registration = await db.registrations.find_one({"_id": reg_id, "userId": user_object_id})
        if not registration:
            raise AppException(code="REGISTRATION_NOT_FOUND", message="Registration not found", status_code=404)
        if registration.get("status") == "checked_in":
            raise AppException(code="ALREADY_CHECKED_IN", message="A checked-in registration cannot be cancelled", status_code=409)
        if registration.get("status") in {"cancelled", "rejected"}:
            await RegistrationService._release_capacity(registration["eventId"], reg_id)
            return {"registrationId": registration_id, "status": registration["status"]}

        now = datetime.now(timezone.utc)
        result = await db.registrations.update_one(
            {"_id": reg_id, "userId": user_object_id, "status": {"$in": ["pending", "waitlisted", "confirmed"]}},
            {"$set": {"status": "cancelled", "cancelledAt": now, "ticketStatus": "NOT_REQUIRED", "updatedAt": now}},
        )
        if result.modified_count != 1:
            raise AppException(code="REGISTRATION_CONFLICT", message="Registration changed; refresh and try again", status_code=409)

        released = await RegistrationService._release_capacity(registration["eventId"], reg_id)
        await db.tickets.update_one(
            {"registrationId": reg_id, "isValid": True},
            {"$set": {"isValid": False, "invalidatedAt": now}},
        )
        if released:
            await RegistrationService.promote_waitlisted(registration["eventId"])
        await invalidate_event_cache()
        await RegistrationService._broadcast(str(registration["eventId"]))
        return {"registrationId": registration_id, "status": "cancelled"}

    @staticmethod
    async def promote_waitlisted(event_id) -> dict[str, Any] | None:
        db = get_database()
        candidate = await db.registrations.find_one_and_update(
            {"eventId": event_id, "status": "waitlisted"},
            {"$set": {"status": "processing", "updatedAt": datetime.now(timezone.utc)}},
            sort=[("waitlistSequence", 1), ("registeredAt", 1)],
            return_document=ReturnDocument.AFTER,
        )
        if not candidate:
            return None
        if not await RegistrationService._reserve_capacity(event_id, candidate["_id"]):
            await db.registrations.update_one(
                {"_id": candidate["_id"], "status": "processing"},
                {"$set": {"status": "waitlisted", "updatedAt": datetime.now(timezone.utc)}},
            )
            return None
        await db.registrations.update_one(
            {"_id": candidate["_id"], "status": "processing"},
            {"$set": {"status": "confirmed", "ticketStatus": "PENDING", "updatedAt": datetime.now(timezone.utc)}},
        )
        await enqueue_ticket(str(candidate["_id"]))
        return {"registrationId": str(candidate["_id"]), "status": "confirmed"}

    @staticmethod
    async def _waitlist_position(event_id, sequence: int) -> int:
        return await get_database().registrations.count_documents(
            {"eventId": event_id, "status": "waitlisted", "waitlistSequence": {"$lte": sequence}}
        )

    @staticmethod
    async def get_my_registrations(user_id: str) -> list[dict[str, Any]]:
        db = get_database()
        user_object_id = parse_object_id(user_id, "user")
        documents = [doc async for doc in db.registrations.find({"userId": user_object_id}).sort("registeredAt", -1)]
        event_ids = list({doc["eventId"] for doc in documents})
        events = {
            doc["_id"]: EventResponse(**doc).model_dump(mode="json", by_alias=True)
            async for doc in db.events.find({"_id": {"$in": event_ids}})
        }
        result = []
        for document in documents:
            item = RegistrationResponse(**document).model_dump(mode="json", by_alias=True)
            item["event"] = events.get(document["eventId"])
            if document.get("status") == "waitlisted" and document.get("waitlistSequence"):
                item["waitlistPosition"] = await RegistrationService._waitlist_position(
                    document["eventId"], document["waitlistSequence"]
                )
            result.append(item)
        return result

    @staticmethod
    async def get_ticket(registration_id: str, user_id: str) -> dict[str, Any]:
        db = get_database()
        reg_id = parse_object_id(registration_id, "registration")
        user_object_id = parse_object_id(user_id, "user")
        registration = await db.registrations.find_one({"_id": reg_id, "userId": user_object_id})
        if not registration:
            raise AppException(code="REGISTRATION_NOT_FOUND", message="Registration not found", status_code=404)
        if registration.get("status") not in {"confirmed", "checked_in"}:
            raise AppException(code="TICKET_UNAVAILABLE", message=f"No ticket is available for a {registration.get('status')} registration", status_code=409)
        ticket = await db.tickets.find_one({"registrationId": reg_id, "isValid": True})
        if not ticket:
            code = "TICKET_FAILED" if registration.get("ticketStatus") == "FAILED" else "TICKET_NOT_READY"
            raise AppException(code=code, message=registration.get("ticketError") or "Ticket generation is pending", status_code=409)
        data = TicketResponse(**ticket).model_dump(mode="json", by_alias=True)
        data["ticketStatus"] = "READY"
        return data

    @staticmethod
    async def _publish_registration(event_id: str, user_id: str, registration_id: str, timestamp: datetime) -> None:
        redis = get_redis()
        if redis is None:
            return
        try:
            await redis.publish("registration.created", json.dumps({
                "eventId": event_id,
                "userId": user_id,
                "registrationId": registration_id,
                "timestamp": timestamp.isoformat(),
            }))
        except RedisError:
            logger.warning("Failed to publish registration event to Redis", exc_info=True)

    @staticmethod
    async def _broadcast(event_id: str) -> None:
        asyncio.create_task(manager.broadcast({"type": "REGISTRATION_UPDATE", "eventId": event_id}))
