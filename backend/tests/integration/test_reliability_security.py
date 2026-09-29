import asyncio
from datetime import datetime, timedelta, timezone

import pytest
from bson import ObjectId

from app.background.ticket_generator import generate_ticket_for_registration
from app.background.ticket_queue import enqueue_ticket, process_ticket_job, retry_ticket
from app.core.security import create_ticket_payload
from app.db.mongo import get_database
from app.exceptions.handlers import AppException
from app.services.admin_service import AdminService
from app.services.registration_service import RegistrationService


async def _event(*, owner: ObjectId | None = None, capacity: int = 1, private: bool = False, waitlist: bool = False):
    db = get_database()
    event_id = ObjectId()
    now = datetime.now(timezone.utc)
    await db.events.insert_one({
        "_id": event_id,
        "name": "Reliability Event",
        "description": "Test",
        "category": "test",
        "location": "Online",
        "eventDate": now + timedelta(days=2),
        "registrationDeadline": now + timedelta(days=1),
        "capacity": capacity,
        "registeredCount": 0,
        "confirmedRegistrationIds": [],
        "nextWaitlistSequence": 0,
        "isRegistrationOpen": True,
        "isDeleted": False,
        "isPrivate": private,
        "inviteCode": "PRV-RELIABLE1" if private else None,
        "allowWaitlist": waitlist,
        "createdBy": owner or ObjectId(),
        "createdAt": now,
        "updatedAt": now,
        "categoryFields": {},
    })
    return event_id


@pytest.mark.asyncio
async def test_concurrent_registration_never_exceeds_capacity():
    event_id = await _event(capacity=1)
    results = await asyncio.gather(
        RegistrationService.register_user_for_event(str(ObjectId()), str(event_id)),
        RegistrationService.register_user_for_event(str(ObjectId()), str(event_id)),
        return_exceptions=True,
    )
    assert sum(isinstance(item, dict) and item["status"] == "confirmed" for item in results) == 1
    assert sum(isinstance(item, AppException) and item.code == "EVENT_FULL" for item in results) == 1
    event = await get_database().events.find_one({"_id": event_id})
    assert event["registeredCount"] == 1
    assert len(event["confirmedRegistrationIds"]) == 1


@pytest.mark.asyncio
async def test_private_approvals_compete_for_one_seat():
    owner = ObjectId()
    event_id = await _event(owner=owner, capacity=1, private=True)
    with pytest.raises(AppException) as exc:
        await RegistrationService.register_user_for_event(str(ObjectId()), str(event_id))
    assert exc.value.code == "PRIVATE_INVITE_REQUIRED"
    first = await RegistrationService.register_user_for_event(
        str(ObjectId()), str(event_id), invite_code="PRV-RELIABLE1"
    )
    second = await RegistrationService.register_user_for_event(
        str(ObjectId()), str(event_id), invite_code="PRV-RELIABLE1"
    )
    results = await asyncio.gather(
        AdminService.update_registration_status(first["registrationId"], "confirmed", str(owner)),
        AdminService.update_registration_status(second["registrationId"], "confirmed", str(owner)),
        return_exceptions=True,
    )
    assert sum(isinstance(item, dict) for item in results) == 1
    assert sum(isinstance(item, AppException) and item.code == "EVENT_FULL" for item in results) == 1
    statuses = [doc["status"] async for doc in get_database().registrations.find({"eventId": event_id})]
    assert sorted(statuses) == ["confirmed", "pending"]


@pytest.mark.asyncio
async def test_organizers_cannot_access_each_others_events():
    owner = ObjectId()
    outsider = ObjectId()
    event_id = await _event(owner=owner)
    registration = await RegistrationService.register_user_for_event(str(ObjectId()), str(event_id))
    with pytest.raises(AppException) as exc:
        await AdminService.get_event_registrations(str(event_id), str(outsider))
    assert exc.value.code == "EVENT_NOT_FOUND"
    with pytest.raises(AppException) as exc:
        await AdminService.update_registration_status(registration["registrationId"], "rejected", str(outsider))
    assert exc.value.code == "EVENT_NOT_FOUND"


@pytest.mark.asyncio
async def test_forged_wrong_event_and_duplicate_qr_scans_are_rejected():
    owner = ObjectId()
    other_owner = ObjectId()
    event_id = await _event(owner=owner)
    other_event_id = await _event(owner=other_owner)
    user_id = ObjectId()
    result = await RegistrationService.register_user_for_event(str(user_id), str(event_id))
    await generate_ticket_for_registration(result["registrationId"])
    ticket = await get_database().tickets.find_one({"registrationId": ObjectId(result["registrationId"])})

    forged = ticket["qrPayload"].replace(str(user_id), str(ObjectId()))
    with pytest.raises(AppException) as exc:
        await AdminService.checkin_attendee(str(event_id), forged, str(owner))
    assert exc.value.code == "INVALID_TICKET"

    with pytest.raises(AppException) as exc:
        await AdminService.checkin_attendee(str(other_event_id), ticket["qrPayload"], str(other_owner))
    assert exc.value.code == "WRONG_EVENT"

    first = await AdminService.checkin_attendee(str(event_id), ticket["qrPayload"], str(owner))
    assert first["status"] == "checked_in"
    with pytest.raises(AppException) as exc:
        await AdminService.checkin_attendee(str(event_id), ticket["qrPayload"], str(owner))
    assert exc.value.code == "ALREADY_CHECKED_IN"


@pytest.mark.asyncio
async def test_ticket_job_failure_is_durable_and_retryable(monkeypatch):
    event_id = await _event()
    user_id = ObjectId()
    result = await RegistrationService.register_user_for_event(str(user_id), str(event_id))
    registration_id = result["registrationId"]
    db = get_database()
    await db.tickets.delete_many({})
    await db.ticket_jobs.update_one(
        {"registrationId": ObjectId(registration_id)},
        {"$set": {"status": "pending", "attempts": 0, "nextAttemptAt": datetime.now(timezone.utc)}},
    )

    async def fail(_registration_id: str):
        raise RuntimeError("simulated worker crash")

    monkeypatch.setattr("app.background.ticket_queue.generate_ticket_for_registration", fail)
    assert await process_ticket_job(registration_id) is False
    job = await db.ticket_jobs.find_one({"registrationId": ObjectId(registration_id)})
    assert job["status"] == "retryable"
    registration = await db.registrations.find_one({"_id": ObjectId(registration_id)})
    assert registration["ticketStatus"] == "RETRYABLE"

    monkeypatch.setattr("app.background.ticket_queue.generate_ticket_for_registration", generate_ticket_for_registration)
    await retry_ticket(registration_id)
    assert await process_ticket_job(registration_id) is True
    assert await db.tickets.count_documents({"registrationId": ObjectId(registration_id)}) == 1


@pytest.mark.asyncio
async def test_cancellation_promotes_waitlist_without_overbooking():
    event_id = await _event(capacity=1, waitlist=True)
    first_user = ObjectId()
    first = await RegistrationService.register_user_for_event(str(first_user), str(event_id))
    second = await RegistrationService.register_user_for_event(str(ObjectId()), str(event_id))
    third = await RegistrationService.register_user_for_event(str(ObjectId()), str(event_id))
    assert [first["status"], second["status"], third["status"]] == ["confirmed", "waitlisted", "waitlisted"]

    await RegistrationService.cancel_registration(first["registrationId"], str(first_user))
    event = await get_database().events.find_one({"_id": event_id})
    assert event["registeredCount"] == 1
    statuses = [
        doc["status"]
        async for doc in get_database().registrations.find({"eventId": event_id}).sort("waitlistSequence", 1)
    ]
    assert statuses.count("confirmed") == 1
    assert statuses.count("waitlisted") == 1
    assert statuses.count("cancelled") == 1
