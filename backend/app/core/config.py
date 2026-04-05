from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/fit_db"
    environment: str = "development"
    secret_key: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    jwt_expire_hours: int = 24

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

    # CORS
    frontend_url: str = "http://localhost:3000"

    model_config = {"env_file": "../.env", "extra": "ignore"}


settings = Settings()
