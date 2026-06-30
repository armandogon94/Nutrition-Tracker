"""Claude Vision food recognition (Slice 3.5 backend).

The iOS ``VisionService`` uploads a JPEG to ``POST /api/v1/nutrition/recognize``
so the Anthropic API key never lives on the device. This module performs the
actual vision call and normalizes the model output into a
:class:`~app.schemas.nutrition.FoodRecognitionResponse`.

Privacy contract (enforced, not just documented):
    The ONLY user-derived bytes that leave the server are the image itself and a
    fixed, generic prompt. No user id, email, display name, or device id is ever
    included in the request to the vision provider. ``_build_messages_payload``
    is pure (image + constant prompt) and the route never passes identifying
    data here, so this is structurally guaranteed.

Cost: Claude Vision is metered (~$0.005-0.015/image). We do not retry inside the
service — transient failures surface as :class:`VisionRecognitionError` so the
client can let the user re-tap rather than double-billing on a network blip.
"""

from __future__ import annotations

import base64
import json

import httpx

from app.core.config import settings
from app.schemas.nutrition import FoodRecognitionResponse

# Accepted upload content types. JPEG/PNG/WebP/HEIC cover what the iOS camera and
# photo picker produce; anything else is rejected at the route boundary.
ALLOWED_IMAGE_TYPES: frozenset[str] = frozenset(
    {"image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"}
)

# Anthropic's vision API does not accept HEIC/HEIF; map them to a type it does.
# (iOS encodes to JPEG before upload in practice, but be defensive.)
_VISION_MEDIA_TYPE = {
    "image/heic": "image/jpeg",
    "image/heif": "image/jpeg",
}

# A5: ISO base-media-file brands used by HEIC/HEIF (the `ftyp` box at bytes 4-7
# is followed by one of these major brands).
_HEIF_BRANDS: frozenset[bytes] = frozenset(
    {b"heic", b"heix", b"heif", b"mif1", b"msf1", b"hevc", b"hevx"}
)


def looks_like_supported_image(data: bytes) -> bool:
    """Magic-byte sniff for the image types we accept (A5).

    The route otherwise trusts the client's Content-Type header and would
    forward arbitrary bytes (a paid-resource abuse / polyglot vector) to the
    vision provider. This validates the actual leading bytes against the
    signatures for JPEG / PNG / WebP / HEIC-HEIF so non-image content is rejected
    BEFORE any provider call. It is intentionally a cheap header check, not a
    full decode.
    """
    if len(data) < 12:
        return False
    # JPEG: FF D8 FF
    if data[:3] == b"\xff\xd8\xff":
        return True
    # PNG: 89 50 4E 47 0D 0A 1A 0A
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return True
    # WebP: "RIFF" .... "WEBP"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return True
    # HEIC/HEIF: ISO-BMFF — "....ftyp<brand>"
    if data[4:8] == b"ftyp" and data[8:12] in _HEIF_BRANDS:
        return True
    return False

# Flash C1: the prompt is in Spanish and explicitly requests the food name "en
# español latinoamericano" so recognized names are stored in Spanish (the
# Spanish-first requirement). The JSON keys and the `confidence` enum values
# stay in English because the parser (`_to_response`) pins that exact contract —
# only the `food` VALUE is localized.
_PROMPT = (
    "Eres un asistente de nutrición. Identifica el único alimento principal en "
    "esta imagen y estima la porción. El nombre del alimento (campo \"food\") "
    "debe estar SIEMPRE en español latinoamericano (por ejemplo: \"plátano\", "
    "\"arroz blanco\", \"pechuga de pollo a la plancha\"), nunca en inglés. "
    "Responde ÚNICAMENTE con un objeto JSON compacto, sin texto adicional, con "
    "exactamente estas claves: "
    '{"food": string, "grams": number, "confidence": "high"|"medium"|"low", '
    '"calories": number, "protein_g": number, "carbs_g": number, "fat_g": number}. '
    "Las claves del JSON y los valores de \"confidence\" (high/medium/low) deben "
    "permanecer en inglés tal cual. \"grams\" es el peso comestible estimado de "
    "la porción mostrada; \"calories\" y los macros corresponden a esa porción. "
    "Si no puedes determinarlo, usa tu mejor estimación y pon \"confidence\" en "
    '"low". No incluyas ningún texto fuera del objeto JSON.'
)

_MAX_TOKENS = 512


class VisionUnavailableError(RuntimeError):
    """Raised when the vision provider is not configured (no API key)."""


class VisionRecognitionError(RuntimeError):
    """Raised when the vision call fails or returns an unparseable result."""


def _build_messages_payload(image_b64: str, media_type: str) -> dict:
    """Build the Anthropic Messages request body.

    Pure function of (image, media_type): the prompt is a module constant and no
    caller-supplied identity is referenced. This is the PII gate — what goes here
    is exactly what goes to the provider.
    """
    return {
        "model": settings.vision_model,
        "max_tokens": _MAX_TOKENS,
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": media_type,
                            "data": image_b64,
                        },
                    },
                    {"type": "text", "text": _PROMPT},
                ],
            }
        ],
    }


def _extract_json_object(text: str) -> dict:
    """Parse the first JSON object out of the model's text response.

    Models occasionally wrap JSON in code fences or stray whitespace; we slice
    from the first ``{`` to the last ``}`` and parse that. Raises
    ``VisionRecognitionError`` if no JSON object can be recovered.
    """
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end < start:
        raise VisionRecognitionError("vision model returned no JSON object")
    snippet = text[start : end + 1]
    try:
        parsed = json.loads(snippet)
    except json.JSONDecodeError as exc:
        raise VisionRecognitionError("vision model returned invalid JSON") from exc
    if not isinstance(parsed, dict):
        raise VisionRecognitionError("vision model JSON was not an object")
    return parsed


def _coerce_float(value: object) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _to_response(parsed: dict) -> FoodRecognitionResponse:
    """Map raw model JSON to the wire response, normalizing types."""
    food = parsed.get("food")
    if not isinstance(food, str) or not food.strip():
        raise VisionRecognitionError("vision result missing 'food'")
    grams = _coerce_float(parsed.get("grams"))
    if grams is None or grams <= 0:
        # A portion estimate is the whole point; fall back to a sane default
        # rather than failing, but keep it bounded.
        grams = 100.0
    confidence = parsed.get("confidence")
    if confidence not in ("high", "medium", "low"):
        confidence = "low"
    return FoodRecognitionResponse(
        food=food.strip(),
        grams=grams,
        confidence=confidence,
        calories=_coerce_float(parsed.get("calories")),
        protein_g=_coerce_float(parsed.get("protein_g")),
        carbs_g=_coerce_float(parsed.get("carbs_g")),
        fat_g=_coerce_float(parsed.get("fat_g")),
    )


async def recognize_food(
    image_bytes: bytes,
    media_type: str,
    client: httpx.AsyncClient,
) -> FoodRecognitionResponse:
    """Recognize the food in ``image_bytes`` via Claude Vision.

    Args:
        image_bytes: Raw uploaded image bytes (already size/type validated).
        media_type: The uploaded content type (e.g. ``image/jpeg``).
        client: Shared ``httpx.AsyncClient`` (connection pooling).

    Raises:
        VisionUnavailableError: if no API key is configured.
        VisionRecognitionError: on HTTP failure or unparseable output.
    """
    if not settings.anthropic_api_key:
        raise VisionUnavailableError("vision provider is not configured")

    vision_media_type = _VISION_MEDIA_TYPE.get(media_type, media_type)
    image_b64 = base64.standard_b64encode(image_bytes).decode("ascii")
    payload = _build_messages_payload(image_b64, vision_media_type)

    try:
        resp = await client.post(
            f"{settings.anthropic_base_url}/v1/messages",
            headers={
                "x-api-key": settings.anthropic_api_key,
                "anthropic-version": settings.anthropic_version,
                "content-type": "application/json",
            },
            json=payload,
            timeout=30.0,
        )
    except httpx.RequestError as exc:
        raise VisionRecognitionError("vision provider request failed") from exc

    if resp.status_code != 200:
        raise VisionRecognitionError(
            f"vision provider returned {resp.status_code}"
        )

    data = resp.json()
    # Messages API: content is a list of blocks; take the first text block.
    blocks = data.get("content") or []
    text = next(
        (b.get("text", "") for b in blocks if b.get("type") == "text"),
        "",
    )
    if not text:
        raise VisionRecognitionError("vision provider returned no text content")

    return _to_response(_extract_json_object(text))
