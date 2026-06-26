import os

# Test DB is configurable via TEST_DB_URL so parallel test runs (e.g. separate
# worktrees / CI shards) can target separate databases without corrupting each
# other's data. Default is unchanged for local/dev use.
TEST_DB_URL = os.environ.get(
    "TEST_DB_URL", "postgresql+asyncpg://postgres:postgres@localhost:5433/fit_db_test"
)
os.environ["DATABASE_URL"] = TEST_DB_URL

import uuid

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.security import create_access_token, hash_password
from app.main import app
from app.models.user import User


@pytest.fixture(scope="session", autouse=True)
async def setup_db():
    """Create a fresh engine in the test's event loop, replace app's engine."""
    import app.core.database as db_mod

    # Create a new engine in the current event loop
    new_engine = create_async_engine(TEST_DB_URL, echo=False)
    new_session_factory = async_sessionmaker(new_engine, class_=AsyncSession, expire_on_commit=False)

    # Replace the app's global engine and session factory
    old_engine = db_mod.engine
    db_mod.engine = new_engine
    db_mod.async_session = new_session_factory

    # Create tables
    async with new_engine.begin() as conn:
        await conn.run_sync(db_mod.Base.metadata.drop_all)
        await conn.run_sync(db_mod.Base.metadata.create_all)

    yield new_engine, new_session_factory

    # Cleanup
    async with new_engine.begin() as conn:
        await conn.run_sync(db_mod.Base.metadata.drop_all)
    await new_engine.dispose()

    # Restore (not strictly needed since tests are ending)
    db_mod.engine = old_engine


@pytest.fixture(autouse=True)
async def clean_tables(setup_db):
    """Truncate all tables after each test."""
    yield
    _engine, session_factory = setup_db
    from app.core.database import Base
    async with session_factory() as session:
        for table in reversed(Base.metadata.sorted_tables):
            await session.execute(table.delete())
        await session.commit()


@pytest.fixture(autouse=True)
def _reset_rate_limiter():
    """Slice 9.8: clear in-memory rate-limit storage between tests so the
    `testclient` IP doesn't accumulate counts across the suite."""
    from app.core.rate_limit import limiter

    def _clear():
        try:
            limiter.reset()
        except Exception:
            storage = getattr(limiter, "_storage", None)
            inner = getattr(storage, "storage", None)
            if isinstance(inner, dict):
                inner.clear()

    _clear()
    yield
    _clear()


@pytest.fixture
async def client():
    """HTTP test client."""
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as ac:
        yield ac


@pytest.fixture
async def db_session(setup_db):
    """Direct DB session for test data setup."""
    _, session_factory = setup_db
    async with session_factory() as session:
        yield session


# ---- Auth fixtures ----

TEST_USER_ID = uuid.UUID("00000000-0000-0000-0000-000000000099")
TEST_USER_EMAIL = "testuser@test.dev"
TEST_USER_PASSWORD = "testpass123"


@pytest.fixture
async def test_user(setup_db):
    """Create a test user directly in DB."""
    _, session_factory = setup_db
    async with session_factory() as session:
        user = User(
            id=TEST_USER_ID,
            email=TEST_USER_EMAIL,
            password_hash=hash_password(TEST_USER_PASSWORD),
            display_name="Test User",
        )
        session.add(user)
        await session.commit()
        await session.refresh(user)
        return user


@pytest.fixture
def auth_token(test_user):
    """JWT token for the test user."""
    return create_access_token(str(test_user.id), test_user.email)


@pytest.fixture
async def auth_client(client, auth_token):
    """HTTP client with Bearer token."""
    client.headers["Authorization"] = f"Bearer {auth_token}"
    return client


# ---- Second user fixtures (for IDOR / cross-user tests) ----

TEST_USER_B_ID = uuid.UUID("00000000-0000-0000-0000-000000000088")
TEST_USER_B_EMAIL = "userb@test.dev"
TEST_USER_B_PASSWORD = "testpass456"


@pytest.fixture
async def test_user_b(setup_db):
    """Create a second test user directly in DB."""
    _, session_factory = setup_db
    async with session_factory() as session:
        user = User(
            id=TEST_USER_B_ID,
            email=TEST_USER_B_EMAIL,
            password_hash=hash_password(TEST_USER_B_PASSWORD),
            display_name="Test User B",
        )
        session.add(user)
        await session.commit()
        await session.refresh(user)
        return user


@pytest.fixture
def auth_token_b(test_user_b):
    """JWT token for the second test user."""
    return create_access_token(str(test_user_b.id), test_user_b.email)


@pytest.fixture
async def auth_client_b(auth_token_b):
    """HTTP client with Bearer token for user B."""
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as ac:
        ac.headers["Authorization"] = f"Bearer {auth_token_b}"
        yield ac
