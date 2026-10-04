import hashlib
import json
import logging
import re
from datetime import datetime, timezone
from typing import Any

from redis.exceptions import RedisError

from app.core.config import settings
from app.core.identifiers import parse_object_id
from app.db.mongo import get_database
from app.db.redis_client import get_redis
from app.exceptions.handlers import AppException
from app.models.event import EventResponse

logger = logging.getLogger(__name__)


def serialize_public_event(document: dict[str, Any]) -> dict[str, Any]:
    data = EventResponse(**document).model_dump(mode="json", by_alias=True)
    data.pop("inviteCode", None)
    return data


class EventService:
    @staticmethod
    async def get_events(
        page: int = 1,
        limit: int = 20,
        category: str | None = None,
        location: str | None = None,
        date_from: datetime | None = None,
        date_to: datetime | None = None,
        available_only: bool = False,
    ) -> dict[str, Any]:
        now = datetime.now(timezone.utc)
        query: dict[str, Any] = {
            "isDeleted": False,
            "isPrivate": {"$ne": True},
            "eventDate": {"$gte": max(date_from or now, now)},
        }
        if date_to is not None:
            query["eventDate"]["$lte"] = date_to
        if category:
            query["category"] = {
                "$regex": f"^{re.escape(category)}$",
                "$options": "i",
            }
        if location:
            query["location"] = {
                "$regex": f"^{re.escape(location)}$",
                "$options": "i",
            }
        if available_only:
            query.update(
                {
                    "isRegistrationOpen": True,
                    "registrationDeadline": {"$gte": now},
                    "$expr": {"$lt": ["$registeredCount", "$capacity"]},
                }
            )
        return await EventService._get_event_page(query, page, limit)

    @staticmethod
    async def _get_event_page(
        query: dict[str, Any],
        page: int,
        limit: int,
    ) -> dict[str, Any]:
        cache_payload = {"page": page, "limit": limit, "query": query}
        cache_json = json.dumps(cache_payload, default=str, sort_keys=True)
        cache_hash = hashlib.sha256(cache_json.encode()).hexdigest()[:20]
        cache_key = f"events:list:{cache_hash}"
        redis = get_redis()

        if redis is not None:
            try:
                cached_data = await redis.get(cache_key)
                if cached_data:
                    return json.loads(cached_data)
            except RedisError:
                logger.warning("Redis cache read failed", exc_info=True)

        db = get_database()
        skip = (page - 1) * limit
        total_events = await db.events.count_documents(query)
        cursor = (
            db.events.find(query)
            .sort("eventDate", 1)
            .skip(skip)
            .limit(limit)
        )
        items = [
            serialize_public_event(document)
            async for document in cursor
        ]
        result = {
            "items": items,
            "pagination": {
                "page": page,
                "limit": limit,
                "total": total_events,
                "totalPages": (total_events + limit - 1) // limit,
            },
        }
        if redis is not None:
            try:
                await redis.set(
                    cache_key,
                    json.dumps(result),
                    ex=settings.EVENT_CACHE_TTL_SECONDS,
                )
            except RedisError:
                logger.warning("Redis cache write failed", exc_info=True)
        return result

    @staticmethod
    async def get_event(event_id: str) -> dict[str, Any]:
        db = get_database()
        obj_id = parse_object_id(event_id, "event")
        event = await db.events.find_one({"_id": obj_id, "isDeleted": False})
        if not event:
            raise AppException(
                code="EVENT_NOT_FOUND",
                message="Event not found",
                status_code=404,
            )
        return serialize_public_event(event)

    @staticmethod
    async def get_event_by_invite_code(invite_code: str) -> dict[str, Any]:
        db = get_database()
        event = await db.events.find_one({"inviteCode": invite_code, "isDeleted": False})
        if not event:
            raise AppException(
                code="EVENT_NOT_FOUND",
                message="Invalid invite code or event not found",
                status_code=404,
            )
        return serialize_public_event(event)

    @staticmethod
    async def search_events(
        q: str,
        page: int = 1,
        limit: int = 20,
        date_from: datetime | None = None,
        date_to: datetime | None = None,
        available_only: bool = False,
    ) -> dict[str, Any]:
        now = datetime.now(timezone.utc)
        pattern = re.escape(q.strip())
        query: dict[str, Any] = {
            "isDeleted": False,
            "isPrivate": {"$ne": True},
            "eventDate": {"$gte": max(date_from or now, now)},
            "$or": [
                {"name": {"$regex": pattern, "$options": "i"}},
                {"category": {"$regex": pattern, "$options": "i"}},
                {"location": {"$regex": pattern, "$options": "i"}},
            ],
        }
        if date_to is not None:
            query["eventDate"]["$lte"] = date_to
        if available_only:
            query.update(
                {
                    "isRegistrationOpen": True,
                    "registrationDeadline": {"$gte": now},
                    "$expr": {"$lt": ["$registeredCount", "$capacity"]},
                }
            )
        return await EventService._get_event_page(query, page, limit)
