"""Cross-user IDOR tests.

Verify that user B cannot view, delete, or modify resources owned by user A.
"""

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


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
