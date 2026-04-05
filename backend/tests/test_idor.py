"""Cross-user IDOR tests.

Verify that user B cannot view, delete, or modify resources owned by user A.
"""

import pytest


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
