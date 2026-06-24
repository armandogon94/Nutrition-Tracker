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


# ---------------------------------------------------------------------------
# Endpoint contract tests. These PIN the request paths, query-param names, and
# response shapes the iOS client depends on (see ios ProductServiceTests):
#   GET /api/v1/products/search?q=<text>   -> {"results": [ProductResponse]}
#   GET /api/v1/products/barcode/{barcode} -> ProductResponse | 404
#   GET /api/v1/products/{uuid}            -> ProductResponse | 404
# NOTE: ProductResponse here uses the *backend* field names (`calories`,
# `source`). The iOS ProductDTO renames (`calories_per_serving`, `category`)
# are a SEPARATE decode-mismatch bug tracked outside this change — these tests
# deliberately don't touch it; they pin the envelope/path/query contract only.
# ---------------------------------------------------------------------------


def _make_product(**overrides):
    """Build a Product row with sane defaults; override only what matters."""
    from app.models.product import Product as ProductModel

    fields = dict(
        barcode="000",
        name="Generic Food",
        brand=None,
        serving_size_g=100.0,
        calories=100.0,
        protein_g=1.0,
        carbs_g=1.0,
        fat_g=1.0,
        fiber_g=0.0,
        source="manual",
    )
    fields.update(overrides)
    return ProductModel(**fields)


# ---- Barcode lookup: GET /api/v1/products/barcode/{barcode} ----


async def test_barcode_lookup_accepts_raw_numeric_barcode(client, db_session):
    """Regression: the barcode route must accept a *raw* (non-UUID) barcode.

    iOS previously hit GET /products/{barcode}, which is UUID-typed and 422s
    on a numeric barcode, so real barcodes never resolved. The dedicated
    /barcode/{barcode} route fixes that.
    """
    db_session.add(_make_product(barcode="7501055302345", name="Avena", brand="Quaker"))
    await db_session.commit()

    response = await client.get("/api/v1/products/barcode/7501055302345")
    assert response.status_code == 200
    assert response.json()["barcode"] == "7501055302345"


async def test_barcode_lookup_cache_hit(client, db_session):
    """Barcode lookup returns a cached product from the local DB."""
    db_session.add(
        _make_product(
            barcode="7501000315109",
            name="Cached Chicken",
            brand="TestBrand",
            calories=165.0,
            protein_g=31.0,
            carbs_g=0.0,
            fat_g=3.6,
        )
    )
    await db_session.commit()

    response = await client.get("/api/v1/products/barcode/7501000315109")
    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "Cached Chicken"
    assert data["barcode"] == "7501000315109"
    assert data["calories"] == 165.0


async def test_barcode_lookup_cascades_to_external_api(client, monkeypatch):
    """Barcode lookup cascades to external APIs when not cached."""
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

    response = await client.get("/api/v1/products/barcode/0049000006346")
    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "Coca-Cola Classic"
    assert data["barcode"] == "0049000006346"
    assert data["source"] == "open_food_facts"


async def test_barcode_lookup_not_found_returns_404(client, monkeypatch):
    """Barcode lookup returns 404 when no source recognizes the barcode."""

    async def mock_lookup(barcode, http_client):
        return None

    monkeypatch.setattr("app.api.v1.products.lookup_product", mock_lookup)

    response = await client.get("/api/v1/products/barcode/0000000000000")
    assert response.status_code == 404
    assert "not found" in response.json()["detail"].lower()


# ---- Text search: GET /api/v1/products/search?q=<text> ----


async def test_search_by_name_returns_results_envelope(client, db_session):
    """Text search returns a {"results": [...]} envelope of name matches."""
    db_session.add_all(
        [
            _make_product(barcode="111", name="Avena tradicional", brand="Quaker"),
            _make_product(barcode="222", name="Coca-Cola", brand="Coca-Cola"),
        ]
    )
    await db_session.commit()

    response = await client.get("/api/v1/products/search", params={"q": "avena"})
    assert response.status_code == 200
    data = response.json()
    # Envelope shape, NOT a bare array and NOT a single object.
    assert isinstance(data, dict)
    assert isinstance(data["results"], list)
    assert len(data["results"]) == 1
    assert data["results"][0]["name"] == "Avena tradicional"
    assert data["results"][0]["barcode"] == "111"


async def test_search_matches_brand_case_insensitively(client, db_session):
    """Text search also matches the brand, case-insensitively."""
    db_session.add_all(
        [
            _make_product(barcode="111", name="Avena tradicional", brand="Quaker"),
            _make_product(barcode="222", name="Refresco", brand="Coca-Cola"),
        ]
    )
    await db_session.commit()

    response = await client.get("/api/v1/products/search", params={"q": "QUAKER"})
    assert response.status_code == 200
    results = response.json()["results"]
    assert len(results) == 1
    assert results[0]["brand"] == "Quaker"


async def test_search_no_match_returns_empty_results_not_404(client, db_session):
    """No matches is an empty envelope (200), not a 404."""
    db_session.add(_make_product(barcode="111", name="Avena"))
    await db_session.commit()

    response = await client.get("/api/v1/products/search", params={"q": "zzz-nope"})
    assert response.status_code == 200
    assert response.json() == {"results": []}


async def test_search_escapes_like_wildcards(client, db_session):
    """SECURITY: a literal `%` in the query must match literally, not act as a
    SQL LIKE wildcard. Without escaping, q='%' would match every row."""
    db_session.add_all(
        [
            _make_product(barcode="111", name="Plain Oats"),
            _make_product(barcode="222", name="100% Whole Wheat"),
        ]
    )
    await db_session.commit()

    response = await client.get("/api/v1/products/search", params={"q": "%"})
    assert response.status_code == 200
    results = response.json()["results"]
    # Escaped → only the name that literally contains "%", not all rows.
    assert len(results) == 1
    assert results[0]["name"] == "100% Whole Wheat"


async def test_search_respects_limit(client, db_session):
    """The `limit` query param caps the number of results."""
    db_session.add_all(
        [
            _make_product(barcode=str(i), name=f"Protein Bar {i}", brand="Brand")
            for i in range(5)
        ]
    )
    await db_session.commit()

    response = await client.get(
        "/api/v1/products/search", params={"q": "protein", "limit": 2}
    )
    assert response.status_code == 200
    assert len(response.json()["results"]) == 2


async def test_search_requires_q_param(client):
    """`q` is required — a missing query param is a 422, not a 200/500."""
    response = await client.get("/api/v1/products/search")
    assert response.status_code == 422


async def test_search_rejects_blank_q(client):
    """`q` has min_length=1 — a blank query is rejected with 422."""
    response = await client.get("/api/v1/products/search", params={"q": ""})
    assert response.status_code == 422


# ---- By-id lookup: GET /api/v1/products/{product_id} (UUID) ----


async def test_get_product_by_uuid_found_and_missing(client, db_session):
    """The by-id route resolves a real UUID and 404s on an unknown one."""
    import uuid as _uuid

    product = _make_product(barcode="111", name="Avena")
    db_session.add(product)
    await db_session.commit()
    await db_session.refresh(product)

    found = await client.get(f"/api/v1/products/{product.id}")
    assert found.status_code == 200
    assert found.json()["id"] == str(product.id)

    missing = await client.get(f"/api/v1/products/{_uuid.uuid4()}")
    assert missing.status_code == 404


async def test_get_product_by_nonuuid_path_is_422(client):
    """A non-UUID path segment on the by-id route is a 422. This documents
    exactly why barcode lookups must use /barcode/{barcode} instead."""
    response = await client.get("/api/v1/products/7501055302345")
    assert response.status_code == 422


async def test_health_check(client):
    response = await client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
