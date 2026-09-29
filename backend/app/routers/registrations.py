from fastapi import APIRouter, BackgroundTasks, Depends
from pydantic import BaseModel, Field

from app.background.ticket_queue import process_ticket_job, retry_ticket
from app.core.identifiers import parse_object_id
from app.db.mongo import get_database
from app.exceptions.handlers import AppException
from app.dependencies.auth import get_current_user
from app.dependencies.rate_limit import RateLimiter
from app.models.user import UserInDB
from app.services.event_service import serialize_public_event
from app.services.registration_service import RegistrationService

router = APIRouter()
registration_rate_limiter = RateLimiter(
    key_prefix="register",
    limit=10,
    window=3600,
)


class RegistrationRequest(BaseModel):
    inviteCode: str | None = Field(default=None, min_length=8, max_length=64)


@router.post("/events/{event_id}/register", status_code=201)
async def register_for_event(
    event_id: str,
    background_tasks: BackgroundTasks,
    payload: RegistrationRequest | None = None,
    current_user: UserInDB = Depends(get_current_user),
):
    await registration_rate_limiter.check(str(current_user.id))
    result = await RegistrationService.register_user_for_event(
        str(current_user.id),
        event_id,
        invite_code=payload.inviteCode if payload else None,
    )
    if result["status"] == "confirmed":
        # Fast-path only: the durable ticket_jobs record already exists.
        background_tasks.add_task(process_ticket_job, result["registrationId"])
    return {
        "success": True,
        "data": result,
        "message": "Registration request accepted.",
    }


@router.get("/registrations/me")
async def get_my_registrations(
    current_user: UserInDB = Depends(get_current_user),
):
    result = await RegistrationService.get_my_registrations(str(current_user.id))
    return {
        "success": True,
        "data": result,
        "message": "User registrations retrieved successfully",
    }


@router.get("/registrations/{registration_id}/ticket")
async def get_ticket(
    registration_id: str,
    current_user: UserInDB = Depends(get_current_user),
):
    result = await RegistrationService.get_ticket(
        registration_id,
        str(current_user.id),
    )
    return {
        "success": True,
        "data": result,
        "message": "Ticket retrieved successfully",
    }


@router.delete("/registrations/{registration_id}")
async def cancel_registration(
    registration_id: str,
    current_user: UserInDB = Depends(get_current_user),
):
    result = await RegistrationService.cancel_registration(
        registration_id, str(current_user.id)
    )
    return {"success": True, "data": result, "message": "Registration cancelled"}


@router.post("/registrations/{registration_id}/ticket/retry", status_code=202)
async def retry_registration_ticket(
    registration_id: str,
    background_tasks: BackgroundTasks,
    current_user: UserInDB = Depends(get_current_user),
):
    db = get_database()
    reg_id = parse_object_id(registration_id, "registration")
    user_id = parse_object_id(str(current_user.id), "user")
    registration = await db.registrations.find_one(
        {"_id": reg_id, "userId": user_id, "status": {"$in": ["confirmed", "checked_in"]}}
    )
    if not registration:
        raise AppException(code="REGISTRATION_NOT_FOUND", message="Eligible registration not found", status_code=404)
    if not await retry_ticket(registration_id):
        raise AppException(
            code="TICKET_NOT_RETRYABLE",
            message="This ticket job is not currently retryable",
            status_code=409,
        )
    background_tasks.add_task(process_ticket_job, registration_id)
    return {"success": True, "data": {"ticketStatus": "PENDING"}, "message": "Ticket retry queued"}


@router.get("/favorites")
async def get_favorites(current_user: UserInDB = Depends(get_current_user)):
    db = get_database()
    user_id = parse_object_id(str(current_user.id), "user")
    event_ids = [doc["eventId"] async for doc in db.favorites.find({"userId": user_id}).sort("createdAt", -1)]
    events = [
        serialize_public_event(doc)
        async for doc in db.events.find({"_id": {"$in": event_ids}, "isDeleted": False})
    ]
    by_id = {item["_id"]: item for item in events}
    return {"success": True, "data": [by_id[str(event_id)] for event_id in event_ids if str(event_id) in by_id], "message": "Favorites retrieved"}


@router.post("/events/{event_id}/favorite", status_code=201)
async def add_favorite(event_id: str, current_user: UserInDB = Depends(get_current_user)):
    from datetime import datetime, timezone
    from pymongo.errors import DuplicateKeyError

    db = get_database()
    event_object_id = parse_object_id(event_id, "event")
    if not await db.events.find_one({"_id": event_object_id, "isDeleted": False}):
        raise AppException(code="EVENT_NOT_FOUND", message="Event not found", status_code=404)
    try:
        await db.favorites.insert_one({"userId": parse_object_id(str(current_user.id), "user"), "eventId": event_object_id, "createdAt": datetime.now(timezone.utc)})
    except DuplicateKeyError:
        pass
    return {"success": True, "data": {"eventId": event_id, "isFavorite": True}, "message": "Event saved"}


@router.delete("/events/{event_id}/favorite")
async def remove_favorite(event_id: str, current_user: UserInDB = Depends(get_current_user)):
    await get_database().favorites.delete_one({
        "userId": parse_object_id(str(current_user.id), "user"),
        "eventId": parse_object_id(event_id, "event"),
    })
    return {"success": True, "data": {"eventId": event_id, "isFavorite": False}, "message": "Event removed from favorites"}
