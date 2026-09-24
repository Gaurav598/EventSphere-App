import asyncio
import csv
import io
import random
import string
from datetime import datetime, timezone
from typing import Any

from pymongo import ReturnDocument

from app.core.identifiers import parse_object_id
from app.core.config import settings
from app.core.security import decode_ticket_payload
from app.core.websocket_manager import manager
from app.db.mongo import get_database
from app.db.redis_client import invalidate_event_cache
from app.exceptions.handlers import AppException
from app.models.event import EventCreate, EventInDB, EventResponse, EventUpdate
from app.models.user import UserResponse
from app.background.ticket_queue import enqueue_ticket
from app.services.registration_service import RegistrationService


class AdminService:
    @staticmethod
    async def get_events(
        admin_id: str,
        page: int = 1,
        limit: int = 20,
    ) -> dict[str, Any]:
        db = get_database()
        admin_object_id = parse_object_id(admin_id, "admin")
        query = {"createdBy": admin_object_id, "isDeleted": False}
        skip = (page - 1) * limit
        total_events = await db.events.count_documents(query)
        cursor = (
            db.events.find(query)
            .sort("createdAt", -1)
            .skip(skip)
            .limit(limit)
        )
        items = [
            EventResponse(**document).model_dump(mode="json", by_alias=True)
            async for document in cursor
        ]
        return {
            "items": items,
            "pagination": {
                "page": page,
                "limit": limit,
                "total": total_events,
                "totalPages": (total_events + limit - 1) // limit,
            },
        }

    @staticmethod
    async def create_event(
        event_data: EventCreate,
        admin_id: str,
    ) -> dict[str, Any]:
        now = datetime.now(timezone.utc)
        AdminService._validate_event_timing(
            event_data.eventDate,
            event_data.registrationDeadline,
            now,
        )
        db = get_database()
        
        admin_obj_id = parse_object_id(admin_id, "admin")
        active_events_count = await db.events.count_documents({"createdBy": admin_obj_id, "isDeleted": False})
        if active_events_count >= 3:
            raise AppException(
                code="EVENT_LIMIT_REACHED",
                message="You have reached the maximum limit of 3 active events. Delete or archive an existing event before creating another.",
                status_code=403,
            )
            
        event = EventInDB(
            **event_data.model_dump(),
            createdBy=admin_obj_id,
        )
        if event.isPrivate:
            code = ''.join(random.choices(string.ascii_uppercase + string.digits, k=6))
            event.inviteCode = f"PRV-{code}"
        
        event_document = event.model_dump(by_alias=True, exclude={"id"})
        result = await db.events.insert_one(event_document)
        created_event = await db.events.find_one({"_id": result.inserted_id})
        await invalidate_event_cache()
        return EventResponse(**created_event).model_dump(
            mode="json",
            by_alias=True,
        )

    @staticmethod
    async def update_event(
        event_id: str,
        event_data: EventUpdate,
        admin_id: str,
    ) -> dict[str, Any]:
        db = get_database()
        event_object_id = parse_object_id(event_id, "event")
        admin_object_id = parse_object_id(admin_id, "admin")
        current = await AdminService._get_owned_event_or_404(event_object_id, admin_object_id)
        now = datetime.now(timezone.utc)
        if current["eventDate"] <= now:
            raise AppException(
                code="EVENT_STARTED",
                message="An event cannot be edited after it starts",
                status_code=400,
            )

        update_data = event_data.model_dump(exclude_none=True)
        if not update_data:
            return EventResponse(**current).model_dump(
                mode="json",
                by_alias=True,
            )

        merged = {
            field: update_data.get(field, current[field])
            for field in (
                "name",
                "description",
                "category",
                "location",
                "eventDate",
                "registrationDeadline",
                "capacity",
                "categoryFields",
            )
        }
        validated = EventCreate(**merged)
        AdminService._validate_event_timing(
            validated.eventDate,
            validated.registrationDeadline,
            now,
        )
        update_data["updatedAt"] = now

        update_filter: dict[str, Any] = {
            "_id": event_object_id,
            "createdBy": admin_object_id,
            "isDeleted": False,
            "eventDate": {"$gt": now},
        }
        if "capacity" in update_data:
            update_filter["$expr"] = {
                "$lte": ["$registeredCount", update_data["capacity"]]
            }

        updated = await db.events.find_one_and_update(
            update_filter,
            {"$set": update_data},
            return_document=ReturnDocument.AFTER,
        )
        if updated is None:
            latest = await AdminService._get_owned_event_or_404(event_object_id, admin_object_id)
            if update_data.get("capacity", latest["capacity"]) < latest.get(
                "registeredCount",
                0,
            ):
                raise AppException(
                    code="INVALID_CAPACITY",
                    message=(
                        "Cannot reduce capacity below current registration count"
                    ),
                    status_code=400,
                )
            raise AppException(
                code="EVENT_UPDATE_CONFLICT",
                message="The event changed while it was being updated",
                status_code=409,
            )

        await invalidate_event_cache()
        return EventResponse(**updated).model_dump(mode="json", by_alias=True)

    @staticmethod
    async def delete_event(event_id: str, admin_id: str) -> None:
        db = get_database()
        event_object_id = parse_object_id(event_id, "event")
        admin_object_id = parse_object_id(admin_id, "admin")
        event = await AdminService._get_owned_event_or_404(event_object_id, admin_object_id)
        now = datetime.now(timezone.utc)
        result = await db.events.update_one(
            {"_id": event_object_id, "createdBy": admin_object_id, "isDeleted": False},
            {
                "$set": {
                    "isDeleted": True,
                    "isRegistrationOpen": False,
                    "registeredCount": 0,
                    "confirmedRegistrationIds": [],
                    "updatedAt": now,
                }
            },
        )
        if result.matched_count == 0:
            raise AppException(
                code="EVENT_NOT_FOUND",
                message="Event not found",
                status_code=404,
            )
        registration_ids = [doc["_id"] async for doc in db.registrations.find({"eventId": event_object_id})]
        await db.registrations.update_many(
            {"eventId": event_object_id, "status": {"$in": ["processing", "pending", "waitlisted", "confirmed"]}},
            {"$set": {"status": "cancelled", "cancelledAt": now, "ticketStatus": "NOT_REQUIRED", "updatedAt": now}},
        )
        if registration_ids:
            await db.tickets.update_many(
                {"registrationId": {"$in": registration_ids}, "isValid": True},
                {"$set": {"isValid": False, "invalidatedAt": now}},
            )
        await invalidate_event_cache()

    @staticmethod
    async def close_registration(event_id: str, admin_id: str) -> None:
        db = get_database()
        event_object_id = parse_object_id(event_id, "event")
        admin_object_id = parse_object_id(admin_id, "admin")
        event = await db.events.find_one_and_update(
            {"_id": event_object_id, "createdBy": admin_object_id, "isDeleted": False},
            {
                "$set": {
                    "isRegistrationOpen": False,
                    "updatedAt": datetime.now(timezone.utc),
                }
            },
            return_document=ReturnDocument.AFTER,
        )
        if event is None:
            raise AppException(
                code="EVENT_NOT_FOUND",
                message="Event not found",
                status_code=404,
            )
        await invalidate_event_cache()

    @staticmethod
    async def update_registration_status(registration_id: str, new_status: str, admin_id: str) -> dict[str, Any]:
        db = get_database()
        now = datetime.now(timezone.utc)
        reg_obj_id = parse_object_id(registration_id, "registration")
        
        reg = await db.registrations.find_one({"_id": reg_obj_id})
        if not reg:
            raise AppException(code="REGISTRATION_NOT_FOUND", message="Registration not found", status_code=404)
        
        if reg.get("status") == new_status:
            return {"status": new_status}
            
        event_id = reg["eventId"]
        admin_object_id = parse_object_id(admin_id, "admin")
        await AdminService._get_owned_event_or_404(event_id, admin_object_id)
        
        if new_status == "confirmed":
            claimed = await db.registrations.update_one(
                {"_id": reg_obj_id, "status": "pending"},
                {"$set": {"status": "processing", "updatedAt": now}},
            )
            if claimed.modified_count != 1:
                raise AppException(code="INVALID_STATUS", message="Only a pending registration can be approved", status_code=409)
            if not await RegistrationService._reserve_capacity(event_id, reg_obj_id):
                await db.registrations.update_one(
                    {"_id": reg_obj_id, "status": "processing"},
                    {"$set": {"status": "pending", "updatedAt": datetime.now(timezone.utc)}},
                )
                raise AppException(code="EVENT_FULL", message="Cannot confirm: event is full or unavailable", status_code=409)
            await db.registrations.update_one(
                {"_id": reg_obj_id, "status": "processing"},
                {"$set": {"status": "confirmed", "ticketStatus": "PENDING", "updatedAt": datetime.now(timezone.utc)}},
            )
            await enqueue_ticket(registration_id)
        elif new_status == "rejected":
            result = await db.registrations.update_one(
                {"_id": reg_obj_id, "status": "pending"},
                {"$set": {"status": "rejected", "ticketStatus": "NOT_REQUIRED", "updatedAt": now}},
            )
            if result.modified_count != 1:
                raise AppException(code="INVALID_STATUS", message="Only a pending registration can be rejected", status_code=409)
        
        # Broadcast the update
        import asyncio
        asyncio.create_task(manager.broadcast({"type": "REGISTRATION_UPDATE", "eventId": str(event_id)}))
            
        return {"status": new_status}

    @staticmethod
    async def checkin_attendee(event_id: str, ticket_payload: str, admin_id: str) -> dict[str, Any]:
        db = get_database()
        event_obj_id = parse_object_id(event_id, "event")
        admin_object_id = parse_object_id(admin_id, "admin")
        event = await AdminService._get_owned_event_or_404(event_obj_id, admin_object_id)
        claims = decode_ticket_payload(ticket_payload)
        if claims is None:
            raise AppException(code="INVALID_TICKET", message="Ticket signature is invalid", status_code=400)
        if claims["eventId"] != event_id:
            raise AppException(code="WRONG_EVENT", message="This ticket belongs to a different event", status_code=409)
        if event.get("eventDate") and datetime.now(timezone.utc) > event["eventDate"] + settings.ticket_checkin_grace:
            raise AppException(code="TICKET_EXPIRED", message="The check-in window for this ticket has expired", status_code=409)
        reg_obj_id = parse_object_id(claims["registrationId"], "registration")
        reg = await db.registrations.find_one({"_id": reg_obj_id, "eventId": event_obj_id})
        if not reg:
            raise AppException(code="REGISTRATION_NOT_FOUND", message="Registration not found for this event", status_code=404)
        if str(reg["userId"]) != claims["userId"]:
            raise AppException(code="INVALID_TICKET_OWNER", message="Ticket ownership does not match the registration", status_code=409)
        ticket = await db.tickets.find_one({"registrationId": reg_obj_id, "qrPayload": ticket_payload, "isValid": True})
        if not ticket:
            raise AppException(code="INVALID_TICKET", message="Ticket was not issued or has been cancelled", status_code=409)
        if reg.get("status") == "checked_in":
            raise AppException(code="ALREADY_CHECKED_IN", message="Ticket has already been used", status_code=409)
        if reg.get("status") != "confirmed":
            raise AppException(code="INVALID_STATUS", message="Registration is not confirmed", status_code=409)
        checked_in = await db.registrations.find_one_and_update(
            {"_id": reg_obj_id, "eventId": event_obj_id, "status": "confirmed"},
            {"$set": {"status": "checked_in", "checkedInAt": datetime.now(timezone.utc), "updatedAt": datetime.now(timezone.utc)}},
            return_document=ReturnDocument.AFTER,
        )
        if checked_in is None:
            latest = await db.registrations.find_one({"_id": reg_obj_id})
            if latest and latest.get("status") == "checked_in":
                raise AppException(code="ALREADY_CHECKED_IN", message="Ticket has already been used", status_code=409)
            raise AppException(code="CHECKIN_CONFLICT", message="Check-in state changed; scan again", status_code=409)
        
        # Broadcast the update
        import asyncio
        asyncio.create_task(manager.broadcast({"type": "REGISTRATION_UPDATE", "eventId": str(event_obj_id)}))
        
        return {"status": "checked_in", "registrationId": str(reg_obj_id), "message": "Successfully checked in"}

    @staticmethod
    async def get_event_registrations(
        event_id: str,
        admin_id: str,
    ) -> list[dict[str, Any]]:
        db = get_database()
        event_object_id = parse_object_id(event_id, "event")
        await AdminService._get_owned_event_or_404(event_object_id, parse_object_id(admin_id, "admin"))
        pipeline = [
            {"$match": {"eventId": event_object_id}},
            {
                "$lookup": {
                    "from": "users",
                    "localField": "userId",
                    "foreignField": "_id",
                    "as": "user",
                }
            },
            {"$unwind": "$user"},
            {"$sort": {"registeredAt": -1}},
        ]
        registrations = []
        cursor = db.registrations.aggregate(pipeline)
        async for document in cursor:
            registrations.append(
                {
                    "registrationId": str(document["_id"]),
                    "status": document["status"],
                    "registeredAt": document["registeredAt"].isoformat(),
                    "user": UserResponse(**document["user"]).model_dump(
                        mode="json",
                        by_alias=True,
                    ),
                }
            )
        return registrations

    @staticmethod
    async def export_registrations(event_id: str, admin_id: str) -> str:
        registrations = await AdminService.get_event_registrations(event_id, admin_id)
        output = io.StringIO()
        writer = csv.writer(output)
        writer.writerow(
            [
                "Registration ID",
                "Status",
                "Registered At",
                "User Name",
                "User Email",
            ]
        )
        for registration in registrations:
            writer.writerow(
                [
                    registration["registrationId"],
                    registration["status"],
                    registration["registeredAt"],
                    AdminService._safe_csv_cell(
                        registration["user"]["name"]
                    ),
                    AdminService._safe_csv_cell(
                        registration["user"]["email"]
                    ),
                ]
            )
        return output.getvalue()

    @staticmethod
    async def get_top_events(admin_id: str) -> list[dict[str, Any]]:
        db = get_database()
        event_ids = await AdminService._owned_event_ids(admin_id)
        pipeline = [
            {"$match": {"eventId": {"$in": event_ids}, "status": {"$in": ["confirmed", "checked_in"]}}},
            {
                "$group": {
                    "_id": "$eventId",
                    "totalRegistrations": {"$sum": 1},
                }
            },
            {"$sort": {"totalRegistrations": -1}},
            {"$limit": 5},
            {
                "$lookup": {
                    "from": "events",
                    "localField": "_id",
                    "foreignField": "_id",
                    "as": "event",
                }
            },
            {"$unwind": "$event"},
        ]
        results = []
        cursor = db.registrations.aggregate(pipeline)
        async for document in cursor:
            results.append(
                {
                    "eventId": str(document["_id"]),
                    "totalRegistrations": document["totalRegistrations"],
                    "event": EventResponse(**document["event"]).model_dump(
                        mode="json",
                        by_alias=True,
                    ),
                }
            )
        return results

    @staticmethod
    async def get_category_wise(admin_id: str) -> list[dict[str, Any]]:
        db = get_database()
        event_ids = await AdminService._owned_event_ids(admin_id)
        pipeline = [
            {"$match": {"eventId": {"$in": event_ids}, "status": {"$in": ["confirmed", "checked_in"]}}},
            {
                "$lookup": {
                    "from": "events",
                    "localField": "eventId",
                    "foreignField": "_id",
                    "as": "event",
                }
            },
            {"$unwind": "$event"},
            {
                "$group": {
                    "_id": "$event.category",
                    "count": {"$sum": 1},
                }
            },
            {"$sort": {"count": -1}},
        ]
        cursor = db.registrations.aggregate(pipeline)
        return [
            {"category": document["_id"], "count": document["count"]}
            async for document in cursor
        ]

    @staticmethod
    async def get_monthly_trend(admin_id: str) -> list[dict[str, Any]]:
        db = get_database()
        event_ids = await AdminService._owned_event_ids(admin_id)
        pipeline = [
            {"$match": {"eventId": {"$in": event_ids}, "status": {"$in": ["confirmed", "checked_in"]}}},
            {
                "$group": {
                    "_id": {
                        "$dateToString": {
                            "format": "%Y-%m",
                            "date": "$registeredAt",
                        }
                    },
                    "count": {"$sum": 1},
                }
            },
            {"$sort": {"_id": 1}},
        ]
        cursor = db.registrations.aggregate(pipeline)
        return [
            {"month": document["_id"], "count": document["count"]}
            async for document in cursor
        ]

    @staticmethod
    async def get_analytics_summary(admin_id: str) -> dict[str, Any]:
        db = get_database()
        admin_object_id = parse_object_id(admin_id, "admin")
        event_ids = await AdminService._owned_event_ids(admin_id)
        pipeline = [
            {"$match": {"eventId": {"$in": event_ids}}},
            {"$group": {"_id": "$status", "count": {"$sum": 1}}},
        ]
        cursor = db.registrations.aggregate(pipeline)
        
        status_counts = {"pending": 0, "waitlisted": 0, "confirmed": 0, "checked_in": 0, "cancelled": 0, "rejected": 0}
        total_requests = 0
        async for doc in cursor:
            status = doc.get("_id")
            count = doc.get("count", 0)
            if status in status_counts:
                status_counts[status] = count
            total_requests += count
            
        confirmed_total = status_counts["confirmed"] + status_counts["checked_in"]
        acceptance_rate = (confirmed_total / total_requests * 100) if total_requests > 0 else 0.0

        upcoming_events = await db.events.count_documents(
            {
                "eventDate": {"$gte": datetime.now(timezone.utc)},
                "isDeleted": False,
                "createdBy": admin_object_id,
            }
        )
        
        return {
            "totalRegistrations": confirmed_total,
            "upcomingEventsCount": upcoming_events,
            "pendingRegistrations": status_counts["pending"],
            "confirmedRegistrations": confirmed_total,
            "checkedInRegistrations": status_counts["checked_in"],
            "waitlistedRegistrations": status_counts["waitlisted"],
            "cancelledRegistrations": status_counts["cancelled"],
            "rejectedRegistrations": status_counts["rejected"],
            "totalRequests": total_requests,
            "acceptanceRate": round(acceptance_rate, 2),
        }

    @staticmethod
    async def _get_event_or_404(event_id):
        event = await get_database().events.find_one(
            {"_id": event_id, "isDeleted": False}
        )
        if event is None:
            raise AppException(
                code="EVENT_NOT_FOUND",
                message="Event not found",
                status_code=404,
            )
        return event

    @staticmethod
    async def _get_owned_event_or_404(event_id, admin_id):
        event = await get_database().events.find_one(
            {"_id": event_id, "createdBy": admin_id, "isDeleted": False}
        )
        if event is None:
            raise AppException(
                code="EVENT_NOT_FOUND",
                message="Event not found or not owned by this organizer",
                status_code=404,
            )
        return event

    @staticmethod
    async def _owned_event_ids(admin_id: str) -> list[Any]:
        admin_object_id = parse_object_id(admin_id, "admin")
        return [
            document["_id"]
            async for document in get_database().events.find(
                {"createdBy": admin_object_id, "isDeleted": False}, {"_id": 1}
            )
        ]

    @staticmethod
    def _validate_event_timing(
        event_date: datetime,
        registration_deadline: datetime,
        now: datetime,
    ) -> None:
        if event_date <= now:
            raise AppException(
                code="INVALID_EVENT_DATE",
                message="eventDate must be in the future",
                status_code=400,
            )
        if registration_deadline < now:
            raise AppException(
                code="INVALID_REGISTRATION_DEADLINE",
                message="registrationDeadline cannot be in the past",
                status_code=400,
            )
        if registration_deadline > event_date:
            raise AppException(
                code="INVALID_REGISTRATION_DEADLINE",
                message="registrationDeadline cannot be after eventDate",
                status_code=400,
            )

    @staticmethod
    def _safe_csv_cell(value: str) -> str:
        if value.startswith(("=", "+", "-", "@")):
            return f"'{value}"
        return value
