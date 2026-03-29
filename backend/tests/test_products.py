import pytest
from httpx import AsyncClient

from app.services.product_lookup import (
    lookup_open_food_facts,
    lookup_usda_fdc,
)


@pytest.fixture
def off_response():
    return {
        "status": 1,
        "product": {
            "product_name": "Nutella",
            "brands": "Ferrero",
            "serving_quantity": 15,
            "nutriments": {
                "energy-kcal": 80,
                "proteins": 0.9,
                "carbohydrates": 8.4,
                "fat": 4.6,
                "fiber": 0.4,
            },
            "image_front_url": "https://images.openfoodfacts.org/nutella.jpg",
        },
    }


@pytest.fixture
def usda_response():
    return {
        "foods": [
            {
                "description": "Chicken breast, raw",
                "brandOwner": "Generic",
                "servingSize": 100,
                "foodNutrients": [
                    {"nutrientName": "Energy", "value": 165},
                    {"nutrientName": "Protein", "value": 31},
                    {"nutrientName": "Carbohydrate, by difference", "value": 0},
                    {"nutrientName": "Total lipid (fat)", "value": 3.6},
                    {"nutrientName": "Fiber, total dietary", "value": 0},
                ],
            }
        ]
    }


async def test_lookup_open_food_facts_success(httpx_mock, off_response):
    httpx_mock.add_response(
        url="https://world.openfoodfacts.org/api/v2/product/3017624010701.json",
        json=off_response,
    )

    async with AsyncClient() as client:
        result = await lookup_open_food_facts("3017624010701", client)

    assert result is not None
    assert result.name == "Nutella"
    assert result.brand == "Ferrero"
    assert result.calories == 80
    assert result.protein_g == 0.9
    assert result.source == "open_food_facts"


async def test_lookup_open_food_facts_not_found(httpx_mock):
    httpx_mock.add_response(
        url="https://world.openfoodfacts.org/api/v2/product/0000000000000.json",
        json={"status": 0},
    )

    async with AsyncClient() as client:
        result = await lookup_open_food_facts("0000000000000", client)

    assert result is None


async def test_lookup_open_food_facts_timeout(httpx_mock):
    import httpx as httpx_lib

    httpx_mock.add_exception(
        httpx_lib.ReadTimeout("timeout"),
        url="https://world.openfoodfacts.org/api/v2/product/1234567890123.json",
    )

    async with AsyncClient() as client:
        result = await lookup_open_food_facts("1234567890123", client)

    assert result is None


async def test_lookup_usda_fdc_success(httpx_mock, usda_response, monkeypatch):
    monkeypatch.setattr("app.services.product_lookup.settings.usda_fdc_key", "test-key")
    httpx_mock.add_response(json=usda_response)

    async with AsyncClient() as client:
        result = await lookup_usda_fdc("chicken", client)

    assert result is not None
    assert result.name == "Chicken breast, raw"
    assert result.calories == 165
    assert result.protein_g == 31
    assert result.source == "usda"


async def test_lookup_usda_fdc_no_key():
    async with AsyncClient() as client:
        result = await lookup_usda_fdc("chicken", client)

    assert result is None


async def test_health_check(client):
    response = await client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
