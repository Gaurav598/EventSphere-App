from collections.abc import AsyncIterator, Callable, Coroutine
from typing import Any

import fakeredis.aioredis
import pytest
from httpx import ASGITransport, AsyncClient
from mongomock_motor import AsyncMongoMockClient

from app.core.config import settings
from app.core.security import get_password_hash
from app.db import mongo, redis_client
from app.db.mongo import create_indexes
from app.main import app
from app.models.user import UserInDB


@pytest.fixture(autouse=True)
async def setup_db_and_redis() -> AsyncIterator[None]:
    mongo.db.client = AsyncMongoMockClient(tz_aware=True)
    mongo.db.db = mongo.db.client[settings.MONGO_DB_NAME]
    await create_indexes()
    redis_client.redis_db.client = fakeredis.aioredis.FakeRedis(
        decode_responses=True
    )
    await redis_client.redis_db.client.flushdb()
    yield
    await redis_client.redis_db.client.flushdb()
    await redis_client.redis_db.client.aclose()
    redis_client.redis_db.client = None
    mongo.db.client = None
    mongo.db.db = None


@pytest.fixture
async def async_client() -> AsyncIterator[AsyncClient]:
    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url="http://test",
    ) as client:
        yield client


@pytest.fixture
def create_user() -> Callable[..., Coroutine[Any, Any, dict[str, Any]]]:
    async def _create_user(
        *,
        name: str,
        email: str,
        password: str,
        role: str = "user",
    ) -> dict[str, Any]:
        document = UserInDB(
            name=name,
            email=email,
            role=role,
            passwordHash=get_password_hash(password),
        ).model_dump(by_alias=True, exclude={"id"})
        result = await mongo.db.db.users.insert_one(document)
        return await mongo.db.db.users.find_one({"_id": result.inserted_id})

    return _create_user
