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


async def test_search_product_by_barcode_cache_hit(client, db_session):
    """Search endpoint returns a cached product from the local DB."""
    from app.models.product import Product as ProductModel

    product = ProductModel(
        barcode="7501000315109",
        name="Cached Chicken",
        brand="TestBrand",
        serving_size_g=100.0,
        calories=165.0,
        protein_g=31.0,
        carbs_g=0.0,
        fat_g=3.6,
        fiber_g=0.0,
        source="manual",
    )
    db_session.add(product)
    await db_session.commit()

    response = await client.get("/api/v1/products/search", params={"barcode": "7501000315109"})
    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "Cached Chicken"
    assert data["barcode"] == "7501000315109"
    assert data["calories"] == 165.0


async def test_search_product_by_barcode_external_api(client, monkeypatch):
    """Search endpoint cascades to external APIs when not in cache."""
    from app.schemas.product import ProductCreate

    mock_result = ProductCreate(
        barcode="0049000006346",
        name="Coca-Cola Classic",
        brand="Coca-Cola",
        serving_size_g=355.0,
        calories=140.0,
        protein_g=0.0,
        carbs_g=39.0,
        fat_g=0.0,
        fiber_g=0.0,
        source="open_food_facts",
    )

    async def mock_lookup(barcode, http_client):
        return mock_result

    monkeypatch.setattr("app.api.v1.products.lookup_product", mock_lookup)

    response = await client.get("/api/v1/products/search", params={"barcode": "0049000006346"})
    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "Coca-Cola Classic"
    assert data["barcode"] == "0049000006346"
    assert data["source"] == "open_food_facts"


async def test_search_product_by_barcode_not_found(client, monkeypatch):
    """Search endpoint returns 404 when product not found anywhere."""
    async def mock_lookup(barcode, http_client):
        return None

    monkeypatch.setattr("app.api.v1.products.lookup_product", mock_lookup)

    response = await client.get("/api/v1/products/search", params={"barcode": "0000000000000"})
    assert response.status_code == 404
    assert "not found" in response.json()["detail"].lower()


async def test_health_check(client):
    response = await client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
