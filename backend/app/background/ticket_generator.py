import asyncio
import base64
import logging
from io import BytesIO

import qrcode
from pymongo.errors import DuplicateKeyError

from app.core.identifiers import parse_object_id
from app.core.security import create_ticket_payload
from app.db.mongo import get_database
from app.models.ticket import TicketInDB

logger = logging.getLogger(__name__)


def _generate_qr_data_uri(payload: str) -> str:
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=10,
        border=4,
    )
    qr.add_data(payload)
    qr.make(fit=True)
    image = qr.make_image(fill_color="black", back_color="white")
    buffered = BytesIO()
    image.save(buffered, format="PNG")
    encoded = base64.b64encode(buffered.getvalue()).decode("ascii")
    return f"data:image/png;base64,{encoded}"


async def generate_ticket_for_registration(registration_id: str) -> bool:
    db = get_database()
    registration_object_id = parse_object_id(registration_id, "registration")
    registration = await db.registrations.find_one(
        {"_id": registration_object_id}
    )
    if not registration:
        raise ValueError(f"Missing registration {registration_id}")
    if registration.get("status") not in {"confirmed", "checked_in"}:
        raise ValueError(f"Registration {registration_id} is not ticket-eligible")

    existing_ticket = await db.tickets.find_one(
        {"registrationId": registration_object_id}
    )
    if existing_ticket and existing_ticket.get("isValid"):
        return True

    payload = create_ticket_payload(
        registration_id=str(registration["_id"]),
        event_id=str(registration["eventId"]),
        user_id=str(registration["userId"]),
    )
    qr_image_ref = await asyncio.to_thread(_generate_qr_data_uri, payload)
    ticket = TicketInDB(
        registrationId=registration_object_id,
        qrPayload=payload,
        qrImageRef=qr_image_ref,
    )
    ticket_document = ticket.model_dump(by_alias=True, exclude={"id"})
    if existing_ticket:
        await db.tickets.replace_one(
            {"_id": existing_ticket["_id"], "isValid": False},
            {**ticket_document, "_id": existing_ticket["_id"]},
        )
    else:
        try:
            await db.tickets.insert_one(ticket_document)
        except DuplicateKeyError:
            logger.info("Ticket already generated for registration %s", registration_id)
    return True
