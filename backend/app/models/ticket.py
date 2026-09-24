from datetime import datetime, timezone

from pydantic import BaseModel, ConfigDict, Field

from app.models.pyobjectid import PyObjectId


class TicketBase(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    registrationId: PyObjectId
    qrPayload: str
    qrImageRef: str
    isValid: bool = True
    ticketVersion: int = 1


class TicketInDB(TicketBase):
    id: PyObjectId | None = Field(alias="_id", default=None)
    generatedAt: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    invalidatedAt: datetime | None = None


class TicketResponse(TicketInDB):
    id: PyObjectId = Field(alias="_id")
