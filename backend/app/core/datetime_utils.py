"""Datetime helpers.

`datetime.utcnow()` is deprecated in Python 3.12+. We use
`datetime.now(timezone.utc)` instead. Our existing database columns are
`TIMESTAMP WITHOUT TIME ZONE`, so values we *persist* are naive UTC
(`utcnow_naive()` / the per-model `_utcnow` helpers).

The wire contract is a different concern. iOS (and any RFC3339 consumer)
must receive timezone-aware ISO8601 with an explicit offset (`...Z` /
`+00:00`); a naive `"yyyy-MM-dd'T'HH:mm:ss"` string fails to decode on the
client (see `APIClient.swift` date strategy). Because the DB stores naive
UTC, we re-attach UTC at the *serialization* boundary instead of migrating
columns: use the `UTCDateTime` annotated type on response-schema datetime
fields and Pydantic will emit an offset-bearing string regardless of whether
the value came back naive (current columns) or aware (post-migration).
"""

from datetime import datetime, timezone
from typing import Annotated

from pydantic import PlainSerializer


def utcnow_naive() -> datetime:
    """Return current UTC time as a naive datetime (no tzinfo).

    This is what we persist into `TIMESTAMP WITHOUT TIME ZONE` columns.
    Use this anywhere you previously called `datetime.utcnow()`.
    """
    return datetime.now(timezone.utc).replace(tzinfo=None)


def ensure_utc(value: datetime) -> datetime:
    """Return ``value`` as a timezone-aware UTC datetime.

    Naive values are assumed to already be UTC (our storage convention) and are
    stamped with ``timezone.utc``. Aware values in another zone are converted to
    UTC so the serialized offset is always ``+00:00``.
    """
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def to_naive_utc(value: datetime) -> datetime:
    """Normalize an inbound datetime to naive UTC for storage.

    This is the *write*-boundary counterpart to ``ensure_utc``: a client may
    send a tz-aware instant in any offset (e.g. ``2026-06-26T23:30:00-05:00``).
    We must convert it to UTC *before* dropping ``tzinfo``, otherwise the wall
    clock (``23:30``) is stored as if it were UTC and the instant is wrong by
    the offset. Naive inputs are assumed to already be UTC (our convention) and
    are returned unchanged.
    """
    if value.tzinfo is None:
        return value
    return value.astimezone(timezone.utc).replace(tzinfo=None)


def _serialize_utc(value: datetime) -> str:
    """Serialize a datetime as timezone-aware UTC ISO8601 (always with offset).

    Naive DB values become ``...+00:00``; aware values are normalized to UTC.
    """
    return ensure_utc(value).isoformat()


# Annotated datetime for response schemas. Drop-in for `datetime` on any
# Pydantic response field whose value is read from the DB and shipped to a
# client. Guarantees the JSON string carries a timezone offset so RFC3339
# decoders (iOS) can parse it.
UTCDateTime = Annotated[datetime, PlainSerializer(_serialize_utc, return_type=str)]
