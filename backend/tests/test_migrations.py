"""Regression: a fresh, empty database bootstraps via ``alembic upgrade head``.

Closes codex review B1. The previous first migration assumed a pre-existing
schema (its opening op created ``refresh_tokens`` with a FK to ``users`` and
altered ``users``), so ``alembic upgrade head`` could never provision an empty
database — and the rest of the suite hid it by building the schema with
``Base.metadata.create_all`` directly. This test runs the real migration chain
against a throwaway database and asserts the schema actually materializes.
"""

import os
import subprocess
import sys
import uuid
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

import asyncpg

BACKEND_DIR = Path(__file__).resolve().parents[1]


def _admin_dsn(test_db_url: str) -> tuple[str, str]:
    """Return (admin DSN to the maintenance DB, netloc) from the test DB URL."""
    raw = test_db_url.replace("+asyncpg", "")
    parts = urlsplit(raw)
    admin = urlunsplit((parts.scheme, parts.netloc, "/postgres", "", ""))
    return admin, parts.netloc


async def test_alembic_bootstraps_empty_database():
    from tests.conftest import TEST_DB_URL

    admin_dsn, netloc = _admin_dsn(TEST_DB_URL)
    db_name = f"fit_db_migtest_{uuid.uuid4().hex[:8]}"

    try:
        admin = await asyncpg.connect(admin_dsn)
    except Exception as exc:  # pragma: no cover - env without admin access
        import pytest

        pytest.skip(f"cannot reach postgres admin to create a throwaway DB: {exc}")

    try:
        await admin.execute(f'CREATE DATABASE "{db_name}"')
    finally:
        await admin.close()

    fresh_async = urlunsplit(("postgresql+asyncpg", netloc, f"/{db_name}", "", ""))
    fresh_plain = urlunsplit(("postgresql", netloc, f"/{db_name}", "", ""))
    try:
        result = subprocess.run(
            [sys.executable, "-m", "alembic", "upgrade", "head"],
            cwd=BACKEND_DIR,
            env={**os.environ, "DATABASE_URL": fresh_async},
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert result.returncode == 0, (
            f"alembic upgrade head failed on an empty DB:\n{result.stdout}\n{result.stderr}"
        )

        check = await asyncpg.connect(fresh_plain)
        try:
            n_tables = await check.fetchval(
                "SELECT count(*) FROM information_schema.tables "
                "WHERE table_schema='public'"
            )
            assert n_tables >= 18, f"expected the full schema, got {n_tables} tables"
            for table in ("users", "meals", "workout_sets", "personal_records"):
                assert (
                    await check.fetchval("SELECT to_regclass($1)", f"public.{table}")
                    is not None
                ), f"table {table} missing after migration"
            # The bootstrap leaves the DB stamped at the single head revision.
            stamped = await check.fetchval("SELECT version_num FROM alembic_version")
            assert stamped == "20260626_000001"
        finally:
            await check.close()
    finally:
        admin = await asyncpg.connect(admin_dsn)
        try:
            await admin.execute(
                "SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
                "WHERE datname=$1 AND pid <> pg_backend_pid()",
                db_name,
            )
            await admin.execute(f'DROP DATABASE IF EXISTS "{db_name}"')
        finally:
            await admin.close()
