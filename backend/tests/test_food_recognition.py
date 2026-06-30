"""Food-recognition service unit tests (backend hardening).

Focus of THIS file (complements tests/test_nutrition_recognize.py, which covers
the endpoint contract + PII gate):

- Flash C1: the Claude Vision prompt is Spanish and explicitly requests the food
  name "en español latinoamericano", while keeping the JSON/parse contract
  (English keys + high/medium/low confidence enum) identical.
"""

import json

import httpx

from app.services.food_recognition import (
    _PROMPT,
    _build_messages_payload,
    recognize_food,
)

_FAKE_JPEG = b"\xff\xd8\xff\xe0fake-jpeg-bytes\xff\xd9"


def _anthropic_text_response(payload: dict) -> dict:
    return {
        "id": "msg_test",
        "type": "message",
        "role": "assistant",
        "content": [{"type": "text", "text": json.dumps(payload)}],
    }


def test_prompt_is_spanish_and_requests_latam_food_name():
    """Flash C1: the prompt must drive Spanish (LATAM) food names."""
    low = _PROMPT.lower()
    # Spanish instruction, explicitly LATAM.
    assert "español latinoamericano" in low
    assert "asistente de nutrición" in low
    # It must NOT be the old English prompt.
    assert "you are a nutrition assistant" not in low


def test_prompt_preserves_json_parse_contract():
    """The JSON keys and confidence enum stay in English so the parser still
    works — only the food NAME is localized."""
    keys = ("food", "grams", "confidence", "calories", "protein_g", "carbs_g", "fat_g")
    for key in keys:
        assert f'"{key}"' in _PROMPT
    # Confidence enum values remain the English tokens the parser checks.
    assert '"high"|"medium"|"low"' in _PROMPT


def test_built_payload_carries_the_spanish_prompt():
    """The Spanish prompt is what actually goes to the provider."""
    payload = _build_messages_payload("ZmFrZQ==", "image/jpeg")
    content = payload["messages"][0]["content"]
    text_block = next(b for b in content if b["type"] == "text")
    assert "español latinoamericano" in text_block["text"].lower()


async def test_service_still_parses_spanish_food_name(httpx_mock, monkeypatch):
    """End to end: a Spanish food name comes back through the unchanged parser."""
    monkeypatch.setattr("app.core.config.settings.anthropic_api_key", "sk-test")
    httpx_mock.add_response(
        url="https://api.anthropic.com/v1/messages",
        json=_anthropic_text_response(
            {
                "food": "Pechuga de pollo a la plancha",
                "grams": 150,
                "confidence": "high",
                "calories": 247.5,
                "protein_g": 46.5,
                "carbs_g": 0.0,
                "fat_g": 5.4,
            }
        ),
    )

    async with httpx.AsyncClient() as ac:
        result = await recognize_food(_FAKE_JPEG, "image/jpeg", ac)

    assert result.food == "Pechuga de pollo a la plancha"
    assert result.confidence == "high"
    assert result.grams == 150.0
