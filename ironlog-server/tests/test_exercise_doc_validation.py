import pytest
from fastapi import HTTPException

from app.routes._exercise_doc_validators import (
    normalize_exercise_doc,
    validate_exercise_doc_payload_shape,
    validate_locale,
)


def _ok_doc(**overrides):
    base = {
        "title": "Жим ногами",
        "summary": "Машинное упражнение для квадрицепсов и ягодиц.",
        "setup": ["Настройте сиденье так, чтобы таз оставался на опоре."],
        "execution": ["Опускайте платформу подконтрольно и выжимайте без рывка."],
        "breathing": "Вдох на опускании, выдох на усилии.",
        "cues": ["Колени движутся по линии стоп."],
        "common_mistakes": ["Слишком глубокое опускание с отрывом таза."],
        "safety_notes": ["Не блокируйте колени жестко в верхней точке."],
        "alternative_slugs": ["leg_extension_machine"],
        "media": [],
        "sources": [{
            "title": "Exercise Library",
            "publisher": "ACE",
            "url": "https://www.acefitness.org/resources/everyone/exercise-library/",
            "type": "exercise_library",
        }],
        "status": "draft",
    }
    base.update(overrides)
    return base


def test_valid_exercise_doc_passes():
    validate_exercise_doc_payload_shape(_ok_doc())


def test_locale_accepts_short_and_region_forms():
    validate_locale("ru")
    validate_locale("en-US")


def test_locale_rejects_bad_shape():
    with pytest.raises(HTTPException) as exc:
        validate_locale("russian")
    assert exc.value.status_code == 422


def test_exercise_doc_requires_sources():
    with pytest.raises(HTTPException) as exc:
        validate_exercise_doc_payload_shape(_ok_doc(sources=[]))
    assert exc.value.status_code == 422
    assert "sources" in exc.value.detail


def test_exercise_doc_rejects_bad_status():
    with pytest.raises(HTTPException) as exc:
        validate_exercise_doc_payload_shape(_ok_doc(status="approved"))
    assert exc.value.status_code == 422
    assert "status" in exc.value.detail


def test_exercise_doc_rejects_bad_alternative_slug():
    with pytest.raises(HTTPException) as exc:
        validate_exercise_doc_payload_shape(_ok_doc(alternative_slugs=["Bad Slug"]))
    assert exc.value.status_code == 422
    assert "alternative_slugs" in exc.value.detail


def test_exercise_doc_media_requires_absolute_url():
    with pytest.raises(HTTPException) as exc:
        validate_exercise_doc_payload_shape(_ok_doc(media=[{
            "kind": "image",
            "url": "/local.png",
            "alt": "Техника",
            "source": "Owned",
            "license": "owned",
        }]))
    assert exc.value.status_code == 422
    assert "media.url" in exc.value.detail


def test_normalize_exercise_doc_strips_strings():
    out = normalize_exercise_doc(_ok_doc(title="  Жим ногами  "))
    assert out["title"] == "Жим ногами"
    assert out["sources"][0]["publisher"] == "ACE"
