from datetime import datetime, timezone
from typing import Any

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)

from app.models.pyobjectid import PyObjectId


def _ensure_timezone(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("Datetime values must include a timezone")
    return value.astimezone(timezone.utc)


class EventBase(BaseModel):
    model_config = ConfigDict(
        extra="forbid",
        populate_by_name=True,
        str_strip_whitespace=True,
    )

    name: str = Field(min_length=2, max_length=150)
    description: str = Field(min_length=1, max_length=5000)
    category: str = Field(min_length=2, max_length=50)
    location: str = Field(min_length=2, max_length=250)
    eventDate: datetime
    registrationDeadline: datetime
    capacity: int = Field(gt=0, le=1_000_000)
    categoryFields: dict[str, Any] = Field(default_factory=dict)
    isPrivate: bool = False
    allowWaitlist: bool = True

    _validate_datetimes = field_validator(
        "eventDate",
        "registrationDeadline",
        mode="after",
    )(_ensure_timezone)

    @model_validator(mode="after")
    def validate_deadline(self) -> "EventBase":
        if self.registrationDeadline > self.eventDate:
            raise ValueError("registrationDeadline cannot be after eventDate")
        return self


class EventCreate(EventBase):
    pass


class EventUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    name: str | None = Field(default=None, min_length=2, max_length=150)
    description: str | None = Field(default=None, min_length=1, max_length=5000)
    category: str | None = Field(default=None, min_length=2, max_length=50)
    location: str | None = Field(default=None, min_length=2, max_length=250)
    eventDate: datetime | None = None
    registrationDeadline: datetime | None = None
    capacity: int | None = Field(default=None, gt=0, le=1_000_000)
    categoryFields: dict[str, Any] | None = None
    isPrivate: bool | None = None
    allowWaitlist: bool | None = None

    _validate_datetimes = field_validator(
        "eventDate",
        "registrationDeadline",
        mode="after",
    )(
        lambda value: _ensure_timezone(value) if value is not None else None
    )


class EventInDB(EventBase):
    id: PyObjectId | None = Field(alias="_id", default=None)
    registeredCount: int = 0
    isRegistrationOpen: bool = True
    isDeleted: bool = False
    inviteCode: str | None = None
    createdBy: PyObjectId
    createdAt: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updatedAt: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    confirmedRegistrationIds: list[PyObjectId] = Field(default_factory=list)
    nextWaitlistSequence: int = 0


class EventResponse(EventBase):
    id: PyObjectId = Field(alias="_id")
    registeredCount: int
    isRegistrationOpen: bool
    isDeleted: bool = False
    inviteCode: str | None = None
    createdBy: PyObjectId
    createdAt: datetime
    updatedAt: datetime
    # Accepted for DB hydration but intentionally not exposed over the API.
    confirmedRegistrationIds: list[PyObjectId] = Field(default_factory=list, exclude=True)
    nextWaitlistSequence: int = Field(default=0, exclude=True)
