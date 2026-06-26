"""Cross-user IDOR tests.

Verify that user B cannot view, delete, or modify resources owned by user A.
"""

import uuid
from datetime import datetime, timezone

from httpx import ASGITransport, AsyncClient

from app.main import app
from app.models.workout import WorkoutProgram, WorkoutProgramDay

# ---- Meals ----


async def test_user_b_cannot_delete_user_a_meal(auth_client, auth_client_b):
    """User A creates a meal; user B should get 404 when trying to delete it."""
    # User A creates a meal
    resp = await auth_client.post(
        "/api/v1/meals",
        json={"meal_type": "breakfast", "meal_date": "2026-04-01"},
    )
    assert resp.status_code == 201
    meal_id = resp.json()["id"]

    # User B tries to delete user A's meal
    del_resp = await auth_client_b.delete(f"/api/v1/meals/{meal_id}")
    assert del_resp.status_code == 404

    # Verify user A can still see their meal
    get_resp = await auth_client.get("/api/v1/meals/2026-04-01")
    assert get_resp.status_code == 200
    ids = [m["id"] for m in get_resp.json()]
    assert meal_id in ids


async def test_user_b_cannot_view_user_a_meals(auth_client, auth_client_b):
    """User B should not see user A's meals when querying the same date."""
    # User A creates a meal
    resp = await auth_client.post(
        "/api/v1/meals",
        json={"meal_type": "lunch", "meal_date": "2026-04-02"},
    )
    assert resp.status_code == 201

    # User B queries the same date -- should see no meals
    get_resp = await auth_client_b.get("/api/v1/meals/2026-04-02")
    assert get_resp.status_code == 200
    assert get_resp.json() == []


# ---- Meal Plans ----


async def test_user_b_cannot_delete_user_a_meal_plan(auth_client, auth_client_b):
    """User A creates a meal plan; user B should get 404 when deleting it."""
    resp = await auth_client.post(
        "/api/v1/meal-plans",
        json={"name": "IDOR Plan", "week_start_date": "2026-04-06"},
    )
    assert resp.status_code == 201
    plan_id = resp.json()["id"]

    # User B tries to delete
    del_resp = await auth_client_b.delete(f"/api/v1/meal-plans/{plan_id}")
    assert del_resp.status_code == 404

    # User A can still access it
    get_resp = await auth_client.get(f"/api/v1/meal-plans/{plan_id}")
    assert get_resp.status_code == 200


async def test_user_b_cannot_view_user_a_meal_plan(auth_client, auth_client_b):
    """User B should get 404 when fetching user A's meal plan by ID."""
    resp = await auth_client.post(
        "/api/v1/meal-plans",
        json={"name": "Private Plan", "week_start_date": "2026-04-13"},
    )
    assert resp.status_code == 201
    plan_id = resp.json()["id"]

    # User B tries to view
    get_resp = await auth_client_b.get(f"/api/v1/meal-plans/{plan_id}")
    assert get_resp.status_code == 404


# ---- Workout Programs (Codex cycle 1 fix: get_program detail IDOR) ----


async def test_user_b_cannot_view_user_a_private_program(auth_client, auth_client_b):
    """User A creates a private program; user B must get 404 on the detail route."""
    resp = await auth_client.post(
        "/api/v1/workouts/programs",
        json={"name": "Private Program", "days_per_week": 3},
    )
    assert resp.status_code == 201
    program_id = resp.json()["id"]

    # Owner can read it
    own = await auth_client.get(f"/api/v1/workouts/programs/{program_id}")
    assert own.status_code == 200

    # User B cannot (no IDOR leak)
    other = await auth_client_b.get(f"/api/v1/workouts/programs/{program_id}")
    assert other.status_code == 404


async def test_program_detail_requires_auth(auth_client):
    """The program detail route must require authentication (no anonymous reads).

    Uses a fresh unauthenticated client: the shared `client`/`auth_client`
    fixtures are the same instance, so we can't reuse it for an anon request.
    """
    resp = await auth_client.post(
        "/api/v1/workouts/programs",
        json={"name": "Auth-required Program", "days_per_week": 4},
    )
    assert resp.status_code == 201
    program_id = resp.json()["id"]

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as anon:
        r = await anon.get(f"/api/v1/workouts/programs/{program_id}")
        assert r.status_code == 401


# ---- Shopping List (Codex cycle 1 fix: cross-user generation IDOR) ----


async def test_user_b_cannot_generate_shopping_list_from_user_a_plan(auth_client, auth_client_b):
    """User B generating a shopping list from user A's meal plan must 404."""
    resp = await auth_client.post(
        "/api/v1/meal-plans",
        json={"name": "A's Plan", "week_start_date": "2026-04-20"},
    )
    assert resp.status_code == 201
    plan_id = resp.json()["id"]

    # User B attempts to generate a shopping list from A's plan -> blocked
    gen = await auth_client_b.get(f"/api/v1/meal-plans/{plan_id}/shopping-list")
    assert gen.status_code == 404

    # User A can generate their own
    own = await auth_client.get(f"/api/v1/meal-plans/{plan_id}/shopping-list")
    assert own.status_code == 200


# ---- Workout Sessions (Codex cycle 4 #5: program/day IDOR on session create) ----
#
# start_session used to store ANY supplied program_id / program_day_id without
# checking ownership. GET /history then returns program_name / day_name, so a
# user who learns another user's PRIVATE program/day UUID could attach it to
# their own session and read those names back. The fix validates ownership at
# create time; these tests pin that behaviour.


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


async def test_session_create_rejects_another_users_private_program(
    auth_client, auth_client_b
):
    """User B must NOT attach user A's private program to a B-owned session."""
    a_prog = await auth_client.post(
        "/api/v1/workouts/programs",
        json={"name": "A's Secret Program", "days_per_week": 3},
    )
    assert a_prog.status_code == 201
    a_program_id = a_prog.json()["id"]

    resp = await auth_client_b.post(
        "/api/v1/workouts/sessions",
        json={"started_at": _now_iso(), "program_id": a_program_id},
    )
    assert resp.status_code == 404

    # And nothing leaked: B's history carries no session referencing A's program.
    hist = await auth_client_b.get("/api/v1/workouts/history")
    assert hist.status_code == 200
    assert hist.json() == []


async def test_session_create_rejects_another_users_private_day(
    auth_client, auth_client_b, db_session
):
    """User B must NOT read A's private day_name by attaching A's program_day_id.

    Even when B pairs A's real program_id with A's real day_id, ownership of the
    program fails first -> 404, so the day_name never surfaces through history.
    """
    program = WorkoutProgram(
        user_id=None,
        name="Preset For Day IDOR",
        days_per_week=3,
        is_preset=False,  # private, owned by nobody-but-A below
    )
    # Make it A-owned so only A can use it.
    from tests.conftest import TEST_USER_ID

    program.user_id = TEST_USER_ID
    db_session.add(program)
    await db_session.commit()

    day = WorkoutProgramDay(
        program_id=program.id, day_number=1, day_name="Leak Me Day"
    )
    db_session.add(day)
    await db_session.commit()

    resp = await auth_client_b.post(
        "/api/v1/workouts/sessions",
        json={
            "started_at": _now_iso(),
            "program_id": str(program.id),
            "program_day_id": str(day.id),
        },
    )
    assert resp.status_code == 404


async def test_session_create_rejects_unknown_program(auth_client):
    """A program_id that does not exist at all is rejected (404)."""
    resp = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={"started_at": _now_iso(), "program_id": str(uuid.uuid4())},
    )
    assert resp.status_code == 404


async def test_session_create_rejects_day_without_program(auth_client):
    """A program_day_id with no program_id has nothing to scope to -> 422."""
    resp = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={"started_at": _now_iso(), "program_day_id": str(uuid.uuid4())},
    )
    assert resp.status_code == 422


async def test_session_create_rejects_day_from_other_program(
    auth_client, db_session
):
    """A day that belongs to a DIFFERENT (even accessible) program is rejected."""
    # Two preset programs the caller can see.
    p1 = WorkoutProgram(
        user_id=None, name="Preset One", days_per_week=3, is_preset=True
    )
    p2 = WorkoutProgram(
        user_id=None, name="Preset Two", days_per_week=3, is_preset=True
    )
    db_session.add_all([p1, p2])
    await db_session.commit()

    # Day belongs to p2.
    day_p2 = WorkoutProgramDay(program_id=p2.id, day_number=1, day_name="P2 Day")
    db_session.add(day_p2)
    await db_session.commit()

    # Caller claims p1 but p2's day -> mismatch -> 404.
    resp = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={
            "started_at": _now_iso(),
            "program_id": str(p1.id),
            "program_day_id": str(day_p2.id),
        },
    )
    assert resp.status_code == 404


async def test_session_create_accepts_preset_program_and_day(
    auth_client, db_session
):
    """The legitimate path still works: a preset program + its own day succeed."""
    program = WorkoutProgram(
        user_id=None, name="Legit Preset", days_per_week=3, is_preset=True
    )
    db_session.add(program)
    await db_session.commit()
    day = WorkoutProgramDay(program_id=program.id, day_number=1, day_name="Push")
    db_session.add(day)
    await db_session.commit()

    resp = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={
            "started_at": _now_iso(),
            "program_id": str(program.id),
            "program_day_id": str(day.id),
        },
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["program_id"] == str(program.id)
    assert body["program_day_id"] == str(day.id)

    # And the name flows through history for the rightful caller.
    hist = await auth_client.get("/api/v1/workouts/history")
    entry = [e for e in hist.json() if e["id"] == body["id"]]
    assert len(entry) == 1
    assert entry[0]["program_name"] == "Legit Preset"
    assert entry[0]["day_name"] == "Push"


async def test_session_create_accepts_own_private_program(auth_client):
    """A caller may attach their OWN private (non-preset) program."""
    own = await auth_client.post(
        "/api/v1/workouts/programs",
        json={"name": "My Own Program", "days_per_week": 4},
    )
    assert own.status_code == 201
    program_id = own.json()["id"]

    resp = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={"started_at": _now_iso(), "program_id": program_id},
    )
    assert resp.status_code == 201
    assert resp.json()["program_id"] == program_id
