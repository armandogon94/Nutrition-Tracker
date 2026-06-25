"""Timezone-aware serialization tests (backend hardening).

iOS decodes RFC3339 timestamps that carry a timezone offset; a naive
``"yyyy-MM-dd'T'HH:mm:ss"`` string fails to decode. The DB stores naive UTC,
so we re-attach UTC at the Pydantic serialization boundary via the
``UTCDateTime`` annotated type. These tests lock that contract at both the
schema level and through real endpoints (workout session, product).
"""

import re
from datetime import datetime, timezone

from pydantic import BaseModel

from app.core.datetime_utils import UTCDateTime, ensure_utc
from app.models.product import Product

# Matches a trailing timezone designator: Z or ±HH:MM.
_TZ_SUFFIX = re.compile(r"(Z|[+-]\d{2}:\d{2})$")


def _has_tz(value: str) -> bool:
    return bool(_TZ_SUFFIX.search(value))


def test_ensure_utc_stamps_naive_as_utc():
    naive = datetime(2026, 6, 25, 10, 30, 0)
    aware = ensure_utc(naive)
    assert aware.tzinfo is not None
    assert aware.utcoffset().total_seconds() == 0


def test_ensure_utc_converts_other_zone_to_utc():
    from datetime import timedelta

    plus2 = datetime(2026, 6, 25, 12, 0, 0, tzinfo=timezone(timedelta(hours=2)))
    aware = ensure_utc(plus2)
    assert aware.utcoffset().total_seconds() == 0
    assert aware.hour == 10  # 12:00+02:00 == 10:00 UTC


def test_utcdatetime_serializes_naive_value_with_offset():
    """A naive UTC value (our storage convention) serializes WITH an offset."""

    class _M(BaseModel):
        ts: UTCDateTime

    naive = datetime(2026, 6, 25, 10, 30, 0)  # no tzinfo
    dumped = _M(ts=naive).model_dump(mode="json")
    assert _has_tz(dumped["ts"]), f"expected tz offset, got {dumped['ts']!r}"
    assert dumped["ts"].startswith("2026-06-25T10:30:00")


async def test_workout_session_timestamps_carry_tz(auth_client):
    """Real /workouts/sessions response: started_at must carry a tz offset."""
    now = datetime.now(timezone.utc).isoformat()
    resp = await auth_client.post(
        "/api/v1/workouts/sessions", json={"started_at": now}
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert _has_tz(body["started_at"]), (
        f"started_at must be tz-aware for iOS, got {body['started_at']!r}"
    )


async def test_completed_session_timestamps_carry_tz(auth_client):
    """completed_at is populated on /complete and must also carry a tz offset."""
    now = datetime.now(timezone.utc).isoformat()
    start = await auth_client.post(
        "/api/v1/workouts/sessions", json={"started_at": now}
    )
    session_id = start.json()["id"]

    done = await auth_client.patch(
        f"/api/v1/workouts/sessions/{session_id}/complete", json={}
    )
    assert done.status_code == 200, done.text
    body = done.json()
    assert body["completed_at"] is not None
    assert _has_tz(body["completed_at"]), (
        f"completed_at must be tz-aware, got {body['completed_at']!r}"
    )
    assert _has_tz(body["started_at"])


async def test_product_created_at_carries_tz(auth_client, db_session):
    """ProductResponse.created_at (read from a naive column) carries a tz."""
    product = Product(
        barcode="TZ-TEST-0001",
        name="TZ Product",
        brand="TZ",
        serving_size_g=100.0,
        calories=100.0,
        source="manual",
    )
    db_session.add(product)
    await db_session.commit()

    resp = await auth_client.get(f"/api/v1/products/barcode/{product.barcode}")
    assert resp.status_code == 200, resp.text
    created_at = resp.json()["created_at"]
    assert _has_tz(created_at), f"created_at must be tz-aware, got {created_at!r}"
