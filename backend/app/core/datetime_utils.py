"""Datetime helpers.

`datetime.utcnow()` is deprecated in Python 3.12+. We replace it with
`datetime.now(timezone.utc)` per the Python 3.12 guidance, but our existing
database columns are `TIMESTAMP WITHOUT TIME ZONE`, so we strip the tzinfo
when handing values to SQLAlchemy. Callers that compare against naive
column values (e.g., filtering `WorkoutSession.started_at >= start_date`)
should also use these helpers to stay consistent.

A future migration can switch columns to `TIMESTAMP WITH TIME ZONE` and
drop the `.replace(tzinfo=None)` once every writer is updated.
"""

from datetime import datetime, timezone


def utcnow_naive() -> datetime:
    """Return current UTC time as a naive datetime (no tzinfo).

    This is what we persist into `TIMESTAMP WITHOUT TIME ZONE` columns.
    Use this anywhere you previously called `datetime.utcnow()`.
    """
    return datetime.now(timezone.utc).replace(tzinfo=None)
