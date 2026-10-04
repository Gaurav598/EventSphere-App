from datetime import datetime, timezone
from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.models.pyobjectid import PyObjectId


class UserBase(BaseModel):
    model_config = ConfigDict(populate_by_name=True, str_strip_whitespace=True)

    name: str = Field(min_length=2, max_length=100)
    email: EmailStr
    role: Literal["user", "admin"] = "user"


class UserCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    name: str = Field(min_length=2, max_length=100)
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    role: Literal["user", "admin"] = "user"
    organizerCode: str | None = Field(default=None, min_length=12, max_length=128)


class UserLogin(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class UserInDB(UserBase):
    id: PyObjectId | None = Field(alias="_id", default=None)
    passwordHash: str
    createdAt: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updatedAt: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class UserResponse(UserBase):
    id: PyObjectId = Field(alias="_id")
    createdAt: datetime
    updatedAt: datetime
