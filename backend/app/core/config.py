from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/nutrition_db"
    environment: str = "development"
    secret_key: str = "change-me-in-production"

    # Open Food Facts
    off_base_url: str = "https://world.openfoodfacts.org"
    off_user_agent: str = "NutritionTracker/1.0 (nutrition.armandointeligencia.com)"

    # USDA FoodData Central
    usda_fdc_key: str = ""

    # FatSecret Platform API
    fatsecret_consumer_key: str = ""
    fatsecret_consumer_secret: str = ""

    # CORS
    frontend_url: str = "http://localhost:3000"

    model_config = {"env_file": "../.env", "extra": "ignore"}


settings = Settings()
