from datetime import date, timedelta
from uuid import UUID

from fastapi import (
    APIRouter,
    Depends,
    File,
    HTTPException,
    Request,
    UploadFile,
    status,
)
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.core.deps import get_current_user_id
from app.core.http import get_client
from app.core.rate_limit import limiter
from app.schemas.nutrition import DailyNutritionResponse, FoodRecognitionResponse
from app.services.food_recognition import (
    ALLOWED_IMAGE_TYPES,
    VisionRecognitionError,
    VisionUnavailableError,
    recognize_food,
)
from app.services.nutrition_calc import (
    calculate_daily_nutrition,
    calculate_weekly_nutrition,
)

router = APIRouter()


@router.post("/recognize", response_model=FoodRecognitionResponse)
@limiter.limit("10/minute")
async def recognize_food_photo(
    request: Request,
    image: UploadFile = File(...),
    user_id: UUID = Depends(get_current_user_id),
) -> FoodRecognitionResponse:
    """Recognize a food from an uploaded photo via Claude Vision.

    Authenticated, multipart ``image`` upload. The image is validated for
    content-type and size BEFORE any provider call, then handed to
    ``food_recognition.recognize_food`` which sends only the image bytes plus a
    fixed prompt to the vision provider (no user id/email leaves the server —
    the PII gate). Rate-limited at 10/minute because each call is metered.

    Returns the iOS ``VisionRecognitionResponse`` shape:
    ``{food, grams, confidence, calories?, protein_g?, carbs_g?, fat_g?}``.
    """
    # Per-user rate-limit keying (the limiter falls back to IP otherwise).
    request.state.user_id = str(user_id)

    content_type = (image.content_type or "").split(";")[0].strip().lower()
    if content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=(
                "Unsupported image type. Allowed: "
                + ", ".join(sorted(ALLOWED_IMAGE_TYPES))
            ),
        )

    image_bytes = await image.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="Empty image upload")
    if len(image_bytes) > settings.max_image_bytes:
        raise HTTPException(
            status_code=413,  # Content Too Large
            detail=(
                f"Image exceeds the {settings.max_image_bytes // (1024 * 1024)} "
                "MiB limit"
            ),
        )

    client = await get_client()
    try:
        return await recognize_food(image_bytes, content_type, client)
    except VisionUnavailableError as exc:
        # Feature not configured on this deployment.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Food recognition is not available",
        ) from exc
    except VisionRecognitionError as exc:
        # Upstream/model failure — let the client offer a retry.
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Could not recognize the food in this image",
        ) from exc


@router.get("/daily/{nutrition_date}", response_model=DailyNutritionResponse)
async def get_daily_nutrition(
    nutrition_date: date, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
) -> DailyNutritionResponse:
    """Get daily nutrition summary."""
    return await calculate_daily_nutrition(db, user_id, nutrition_date)


@router.get("/weekly", response_model=list[DailyNutritionResponse])
async def get_weekly_nutrition(
    user_id: UUID = Depends(get_current_user_id),
    start_date: date | None = None,
    end_date: date | None = None,
    db: AsyncSession = Depends(get_db),
) -> list[DailyNutritionResponse]:
    """Get nutrition data for a date range (defaults to last 7 days).

    B12: served by a single grouped aggregate query (see
    ``nutrition_calc.calculate_weekly_nutrition``) instead of one query per day.
    """
    if not end_date:
        end_date = date.today()
    if not start_date:
        start_date = end_date - timedelta(days=6)

    if (end_date - start_date).days > 90:
        raise HTTPException(status_code=400, detail="Date range cannot exceed 90 days")

    return await calculate_weekly_nutrition(db, user_id, start_date, end_date)
