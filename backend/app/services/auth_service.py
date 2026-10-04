import hmac
from typing import Any

from pymongo.errors import DuplicateKeyError

from app.core.config import settings
from app.core.security import (
    create_access_token,
    get_password_hash,
    password_hash_needs_upgrade,
    verify_password,
)
from app.db.mongo import get_database
from app.exceptions.handlers import AppException
from app.models.user import UserCreate, UserInDB, UserLogin, UserResponse


class AuthService:
    @staticmethod
    async def register_user(user_data: UserCreate) -> dict[str, Any]:
        db = get_database()
        if user_data.role == "admin":
            expected = settings.ORGANIZER_SIGNUP_CODE
            if expected is None or user_data.organizerCode is None or not hmac.compare_digest(user_data.organizerCode, expected):
                raise AppException(
                    code="ORGANIZER_SIGNUP_FORBIDDEN",
                    message="A valid organizer invitation code is required",
                    status_code=403,
                )
        email = str(user_data.email).lower()
        hashed_pw = get_password_hash(user_data.password)
        new_user = UserInDB(
            name=user_data.name,
            email=email,
            role=user_data.role,
            passwordHash=hashed_pw,
        )
        user_dict = new_user.model_dump(by_alias=True, exclude={"id"})
        try:
            result = await db.users.insert_one(user_dict)
        except DuplicateKeyError as exc:
            raise AppException(
                code="EMAIL_IN_USE",
                message="Email is already registered",
                status_code=409,
            ) from exc

        created_user = await db.users.find_one({"_id": result.inserted_id})
        return UserResponse(**created_user).model_dump(mode="json", by_alias=True)

    @staticmethod
    async def login_user(login_data: UserLogin) -> dict[str, str]:
        db = get_database()
        user = await db.users.find_one({"email": str(login_data.email).lower()})
        if not user:
            raise AppException(
                code="INVALID_CREDENTIALS",
                message="Invalid credentials",
                status_code=401,
            )
        if not verify_password(login_data.password, user["passwordHash"]):
            raise AppException(
                code="INVALID_CREDENTIALS",
                message="Invalid credentials",
                status_code=401,
            )

        if password_hash_needs_upgrade(user["passwordHash"]):
            await db.users.update_one(
                {"_id": user["_id"]},
                {"$set": {"passwordHash": get_password_hash(login_data.password)}},
            )

        access_token = create_access_token(
            subject=str(user["_id"]),
            role=user.get("role", "user"),
        )
        return {
            "accessToken": access_token,
            "tokenType": "bearer",
        }

    @staticmethod
    async def update_profile(user_id: str, name: str | None = None, current_password: str | None = None, new_password: str | None = None) -> dict[str, Any]:
        from bson import ObjectId
        db = get_database()
        
        try:
            obj_id = ObjectId(user_id)
        except Exception:
            raise AppException(code="INVALID_USER_ID", message="Invalid User ID format", status_code=400)
            
        user = await db.users.find_one({"_id": obj_id})
        if not user:
            raise AppException(code="USER_NOT_FOUND", message="User not found", status_code=404)
            
        update_data = {}
        if name:
            update_data["name"] = name
            
        if new_password:
            if not current_password:
                raise AppException(code="PASSWORD_REQUIRED", message="Current password is required to set a new password", status_code=400)
            if not verify_password(current_password, user["passwordHash"]):
                raise AppException(code="INVALID_PASSWORD", message="Current password is incorrect", status_code=401)
            update_data["passwordHash"] = get_password_hash(new_password)
            
        if update_data:
            await db.users.update_one({"_id": obj_id}, {"$set": update_data})
            
        updated_user = await db.users.find_one({"_id": obj_id})
        return UserResponse(**updated_user).model_dump(mode="json", by_alias=True)
