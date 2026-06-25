"""Photo food-recognition endpoint + service tests (backend hardening, Task 3).

Covers ``POST /api/v1/nutrition/recognize``:

- auth required
- content-type and size validation (415 / 413 / 400) BEFORE any provider call
- happy path returns the iOS ``VisionRecognitionResponse`` shape
- 503 when the vision provider is unconfigured, 502 on upstream failure
- PII gate: the request to the vision provider carries ONLY the image + a
  fixed prompt — no user id, email, or other identity (asserted against the
  real outgoing httpx request body)

The vision call is mocked: endpoint-contract tests monkeypatch
``recognize_food``; the PII-gate / parsing tests mock the Anthropic HTTP call
with pytest-httpx.
"""

import base64
import json

import httpx
import pytest

from app.schemas.nutrition import FoodRecognitionResponse

# A few bytes that stand in for JPEG data — the route validates the declared
# content-type, not the magic number, and the service just base64-encodes bytes.
_FAKE_JPEG = b"\xff\xd8\xff\xe0fake-jpeg-bytes\xff\xd9"


def _image_file(data: bytes = _FAKE_JPEG, content_type: str = "image/jpeg"):
    return {"image": ("meal.jpg", data, content_type)}


# --------------------------------------------------------------------------
# Endpoint contract
# --------------------------------------------------------------------------


async def test_recognize_requires_auth(client):
    resp = await client.post("/api/v1/nutrition/recognize", files=_image_file())
    assert resp.status_code == 401


async def test_recognize_happy_path_matches_ios_shape(auth_client, monkeypatch):
    """A successful recognition returns exactly the iOS DTO field set."""

    async def _fake_recognize(image_bytes, media_type, http_client):
        assert image_bytes == _FAKE_JPEG
        assert media_type == "image/jpeg"
        return FoodRecognitionResponse(
            food="Grilled chicken breast",
            grams=150.0,
            confidence="high",
            calories=247.5,
            protein_g=46.5,
            carbs_g=0.0,
            fat_g=5.4,
        )

    monkeypatch.setattr(
        "app.api.v1.nutrition.recognize_food", _fake_recognize
    )

    resp = await auth_client.post(
        "/api/v1/nutrition/recognize", files=_image_file()
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert set(body.keys()) == {
        "food",
        "grams",
        "confidence",
        "calories",
        "protein_g",
        "carbs_g",
        "fat_g",
    }
    assert body["food"] == "Grilled chicken breast"
    assert body["grams"] == 150.0
    assert body["confidence"] == "high"
    assert body["protein_g"] == 46.5


async def test_recognize_rejects_non_image_content_type(auth_client, monkeypatch):
    called = False

    async def _fake_recognize(*args, **kwargs):
        nonlocal called
        called = True
        raise AssertionError("provider must not be called for invalid type")

    monkeypatch.setattr(
        "app.api.v1.nutrition.recognize_food", _fake_recognize
    )

    resp = await auth_client.post(
        "/api/v1/nutrition/recognize",
        files={"image": ("notes.txt", b"hello", "text/plain")},
    )
    assert resp.status_code == 415
    assert called is False


async def test_recognize_rejects_oversized_image(auth_client, monkeypatch):
    monkeypatch.setattr("app.core.config.settings.max_image_bytes", 1024)

    async def _fake_recognize(*args, **kwargs):
        raise AssertionError("provider must not be called for oversized image")

    monkeypatch.setattr(
        "app.api.v1.nutrition.recognize_food", _fake_recognize
    )

    big = b"\xff\xd8" + b"x" * 2048
    resp = await auth_client.post(
        "/api/v1/nutrition/recognize", files=_image_file(data=big)
    )
    assert resp.status_code == 413


async def test_recognize_rejects_empty_image(auth_client):
    resp = await auth_client.post(
        "/api/v1/nutrition/recognize", files=_image_file(data=b"")
    )
    assert resp.status_code == 400


async def test_recognize_unconfigured_provider_returns_503(auth_client, monkeypatch):
    from app.services.food_recognition import VisionUnavailableError

    async def _fake_recognize(*args, **kwargs):
        raise VisionUnavailableError("no key")

    monkeypatch.setattr(
        "app.api.v1.nutrition.recognize_food", _fake_recognize
    )
    resp = await auth_client.post(
        "/api/v1/nutrition/recognize", files=_image_file()
    )
    assert resp.status_code == 503


async def test_recognize_upstream_failure_returns_502(auth_client, monkeypatch):
    from app.services.food_recognition import VisionRecognitionError

    async def _fake_recognize(*args, **kwargs):
        raise VisionRecognitionError("model exploded")

    monkeypatch.setattr(
        "app.api.v1.nutrition.recognize_food", _fake_recognize
    )
    resp = await auth_client.post(
        "/api/v1/nutrition/recognize", files=_image_file()
    )
    assert resp.status_code == 502


# --------------------------------------------------------------------------
# Service: parsing + PII gate (mock the Anthropic HTTP call directly)
# --------------------------------------------------------------------------


def _anthropic_text_response(payload: dict) -> dict:
    """Shape of a Messages API response with a single text block."""
    return {
        "id": "msg_test",
        "type": "message",
        "role": "assistant",
        "content": [{"type": "text", "text": json.dumps(payload)}],
    }


async def test_service_parses_model_json(httpx_mock, monkeypatch):
    monkeypatch.setattr("app.core.config.settings.anthropic_api_key", "sk-test")
    httpx_mock.add_response(
        url="https://api.anthropic.com/v1/messages",
        json=_anthropic_text_response(
            {
                "food": "Banana",
                "grams": 120,
                "confidence": "medium",
                "calories": 107,
                "protein_g": 1.3,
                "carbs_g": 27,
                "fat_g": 0.4,
            }
        ),
    )

    from app.services.food_recognition import recognize_food

    async with httpx.AsyncClient() as ac:
        result = await recognize_food(_FAKE_JPEG, "image/jpeg", ac)

    assert isinstance(result, FoodRecognitionResponse)
    assert result.food == "Banana"
    assert result.grams == 120.0
    assert result.confidence == "medium"
    assert result.calories == 107.0


async def test_service_sends_only_image_and_prompt_no_pii(httpx_mock, monkeypatch):
    """PII gate: the outgoing provider request contains the image + prompt only.

    Asserts the user's email / id / display name (and the literal field names)
    appear nowhere in the request body, and that the body is the image block +
    a text prompt block.
    """
    monkeypatch.setattr("app.core.config.settings.anthropic_api_key", "sk-test")
    httpx_mock.add_response(
        url="https://api.anthropic.com/v1/messages",
        json=_anthropic_text_response(
            {"food": "Apple", "grams": 100, "confidence": "high"}
        ),
    )

    from app.services.food_recognition import recognize_food

    async with httpx.AsyncClient() as ac:
        await recognize_food(_FAKE_JPEG, "image/jpeg", ac)

    requests = httpx_mock.get_requests()
    assert len(requests) == 1
    sent = requests[0]

    # Auth/version headers present; key is in the header, never the body.
    assert sent.headers.get("x-api-key") == "sk-test"
    assert sent.headers.get("anthropic-version")

    raw_body = sent.content.decode("utf-8")
    # No identifying data leaked into the payload.
    for forbidden in (
        "testuser@test.dev",
        "Test User",
        "00000000-0000-0000-0000-000000000099",
        "user_id",
        "email",
        "display_name",
    ):
        assert forbidden not in raw_body, f"PII leak: {forbidden!r} in body"

    parsed = json.loads(raw_body)
    content = parsed["messages"][0]["content"]
    types = {block["type"] for block in content}
    assert types == {"image", "text"}, f"unexpected content blocks: {types}"

    image_block = next(b for b in content if b["type"] == "image")
    assert image_block["source"]["type"] == "base64"
    # The image bytes that were sent are exactly our input, base64-encoded.
    assert image_block["source"]["data"] == base64.standard_b64encode(
        _FAKE_JPEG
    ).decode("ascii")


async def test_service_unconfigured_raises(monkeypatch):
    monkeypatch.setattr("app.core.config.settings.anthropic_api_key", "")
    from app.services.food_recognition import VisionUnavailableError, recognize_food

    async with httpx.AsyncClient() as ac:
        with pytest.raises(VisionUnavailableError):
            await recognize_food(_FAKE_JPEG, "image/jpeg", ac)


async def test_service_http_error_raises_recognition_error(httpx_mock, monkeypatch):
    monkeypatch.setattr("app.core.config.settings.anthropic_api_key", "sk-test")
    httpx_mock.add_response(
        url="https://api.anthropic.com/v1/messages", status_code=500
    )
    from app.services.food_recognition import VisionRecognitionError, recognize_food

    async with httpx.AsyncClient() as ac:
        with pytest.raises(VisionRecognitionError):
            await recognize_food(_FAKE_JPEG, "image/jpeg", ac)
