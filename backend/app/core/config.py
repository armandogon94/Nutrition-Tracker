from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/fit_db"
    environment: str = "development"
    secret_key: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    # Slice 9.5 — access tokens shrink from 24h to 1h now that refresh
    # rotation is available. Mobile clients silently refresh before expiry.
    jwt_expire_hours: int = 1
    # Refresh tokens persist for 30 days; rotated on every /auth/refresh.
    refresh_token_expire_days: int = 30

    # Slice 9.6 — Sign in with Apple verification
    apple_bundle_id: str = "com.armandointeligencia.FitTracker"
    apple_jwk_url: str = "https://appleid.apple.com/auth/keys"
    apple_issuer: str = "https://appleid.apple.com"

    # Open Food Facts
    off_base_url: str = "https://world.openfoodfacts.org"
    off_user_agent: str = "FitTracker/2.0 (fit.armandointeligencia.com)"

    # USDA FoodData Central
    usda_fdc_key: str = ""

    # FatSecret Platform API
    fatsecret_consumer_key: str = ""
    fatsecret_consumer_secret: str = ""

    # Claude Vision (photo food recognition)
    anthropic_api_key: str = ""
    anthropic_base_url: str = "https://api.anthropic.com"
    anthropic_version: str = "2023-06-01"
    # Sonnet handles vision; overridable so we can pin a snapshot in prod.
    vision_model: str = "claude-sonnet-4-5"
    # Reject oversized uploads before they reach the vision provider.
    max_image_bytes: int = 5 * 1024 * 1024  # 5 MiB

    # CORS
    frontend_url: str = "http://localhost:3000"

    model_config = {"env_file": "../.env", "extra": "ignore"}


settings = Settings()
