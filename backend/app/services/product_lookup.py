import hashlib
import hmac
import time
import urllib.parse
import uuid
from base64 import b64encode

import httpx

from app.core.config import settings
from app.schemas.product import ProductCreate


async def lookup_open_food_facts(barcode: str, client: httpx.AsyncClient) -> ProductCreate | None:
    """Query Open Food Facts API v2. Free, 100 req/min, direct barcode lookup."""
    try:
        response = await client.get(
            f"{settings.off_base_url}/api/v2/product/{barcode}.json",
            headers={"User-Agent": settings.off_user_agent},
            timeout=10.0,
        )
        if response.status_code != 200:
            return None

        data = response.json()
        if data.get("status") != 1:
            return None

        product = data.get("product", {})
        nutrients = product.get("nutriments", {})

        return ProductCreate(
            barcode=barcode,
            name=product.get("product_name") or "Unknown",
            brand=product.get("brands") or None,
            serving_size_g=float(product.get("serving_quantity") or 100),
            calories=float(nutrients.get("energy-kcal") or nutrients.get("energy-kcal_100g") or 0),
            protein_g=float(nutrients.get("proteins") or nutrients.get("proteins_100g") or 0),
            carbs_g=float(nutrients.get("carbohydrates") or nutrients.get("carbohydrates_100g") or 0),
            fat_g=float(nutrients.get("fat") or nutrients.get("fat_100g") or 0),
            fiber_g=float(nutrients.get("fiber") or nutrients.get("fiber_100g") or 0),
            source="open_food_facts",
            image_url=product.get("image_front_url"),
        )
    except (httpx.RequestError, KeyError, ValueError):
        return None


async def lookup_usda_fdc(barcode: str, client: httpx.AsyncClient) -> ProductCreate | None:
    """Query USDA FoodData Central. 1,000 req/hr, text search (no barcode endpoint)."""
    if not settings.usda_fdc_key:
        return None

    try:
        response = await client.get(
            "https://api.nal.usda.gov/fdc/v1/foods/search",
            params={"query": barcode, "pageSize": 1, "api_key": settings.usda_fdc_key},
            timeout=10.0,
        )
        if response.status_code != 200:
            return None

        foods = response.json().get("foods", [])
        if not foods:
            return None

        food = foods[0]
        nutrients = {n["nutrientName"]: n.get("value", 0) for n in food.get("foodNutrients", [])}

        return ProductCreate(
            barcode=barcode,
            name=food.get("description") or "Unknown",
            brand=food.get("brandOwner") or None,
            serving_size_g=float(food.get("servingSize") or 100),
            calories=float(nutrients.get("Energy", 0)),
            protein_g=float(nutrients.get("Protein", 0)),
            carbs_g=float(nutrients.get("Carbohydrate, by difference", 0)),
            fat_g=float(nutrients.get("Total lipid (fat)", 0)),
            fiber_g=float(nutrients.get("Fiber, total dietary", 0)),
            source="usda",
        )
    except (httpx.RequestError, KeyError, ValueError):
        return None


def _fatsecret_oauth_header(method: str, url: str) -> dict[str, str]:
    """Generate OAuth 1.0a header for FatSecret API."""
    if not settings.fatsecret_consumer_key:
        return {}

    oauth_params = {
        "oauth_consumer_key": settings.fatsecret_consumer_key,
        "oauth_nonce": uuid.uuid4().hex,
        "oauth_signature_method": "HMAC-SHA1",
        "oauth_timestamp": str(int(time.time())),
        "oauth_version": "1.0",
    }

    # Build signature base string
    sorted_params = "&".join(f"{k}={urllib.parse.quote(v, safe='')}" for k, v in sorted(oauth_params.items()))
    base_string = f"{method.upper()}&{urllib.parse.quote(url, safe='')}&{urllib.parse.quote(sorted_params, safe='')}"
    signing_key = f"{urllib.parse.quote(settings.fatsecret_consumer_secret, safe='')}&"

    signature = b64encode(
        hmac.new(signing_key.encode(), base_string.encode(), hashlib.sha1).digest()
    ).decode()
    oauth_params["oauth_signature"] = signature

    auth_header = "OAuth " + ", ".join(f'{k}="{urllib.parse.quote(v, safe="")}"' for k, v in oauth_params.items())
    return {"Authorization": auth_header}


async def lookup_fatsecret(barcode: str, client: httpx.AsyncClient) -> ProductCreate | None:
    """Query FatSecret Platform API. OAuth 1.0a, 90%+ barcode hit rate."""
    if not settings.fatsecret_consumer_key:
        return None

    url = "https://platform.fatsecret.com/rest/server.api"
    try:
        headers = _fatsecret_oauth_header("GET", url)
        response = await client.get(
            url,
            params={"method": "food.find_id_for_barcode", "barcode": barcode, "format": "json"},
            headers=headers,
            timeout=10.0,
        )
        if response.status_code != 200:
            return None

        data = response.json()
        food_id = data.get("food_id", {}).get("value")
        if not food_id:
            return None

        # Get food details
        headers = _fatsecret_oauth_header("GET", url)
        response = await client.get(
            url,
            params={"method": "food.get.v2", "food_id": food_id, "format": "json"},
            headers=headers,
            timeout=10.0,
        )
        if response.status_code != 200:
            return None

        food = response.json().get("food", {})
        servings = food.get("servings", {}).get("serving", [])
        serving = servings[0] if isinstance(servings, list) and servings else servings if isinstance(servings, dict) else {}

        return ProductCreate(
            barcode=barcode,
            name=food.get("food_name") or "Unknown",
            brand=food.get("brand_name") or None,
            serving_size_g=float(serving.get("metric_serving_amount") or 100),
            calories=float(serving.get("calories") or 0),
            protein_g=float(serving.get("protein") or 0),
            carbs_g=float(serving.get("carbohydrate") or 0),
            fat_g=float(serving.get("fat") or 0),
            fiber_g=float(serving.get("fiber") or 0),
            source="fatsecret",
        )
    except (httpx.RequestError, KeyError, ValueError, TypeError):
        return None


async def lookup_product(barcode: str, client: httpx.AsyncClient) -> ProductCreate | None:
    """Cascade through all sources: OFF -> FatSecret -> USDA FDC.

    Flash G2: FatSecret is queried BEFORE USDA FDC. FatSecret has a real
    barcode endpoint with a ~90% hit rate, whereas USDA FDC has no barcode
    endpoint at all — it only does text search on the barcode string, which is
    slow and usually a false/empty match. Querying the high-hit-rate barcode
    source first matches the documented order in CLAUDE.md (OFF -> FatSecret ->
    USDA FDC) and avoids paying for a near-useless USDA round-trip on every miss.
    """
    result = await lookup_open_food_facts(barcode, client)
    if result:
        return result

    result = await lookup_fatsecret(barcode, client)
    if result:
        return result

    result = await lookup_usda_fdc(barcode, client)
    if result:
        return result

    return None
