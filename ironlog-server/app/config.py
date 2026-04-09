from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    mongodb_url: str = "mongodb://mongo:27017"
    mongodb_db: str = "ironlog"
    jwt_secret: str = "change-me-in-production"
    jwt_expire_days: int = 90
    jwt_refresh_threshold_days: int = 30

    model_config = {"env_prefix": "", "case_sensitive": False}


settings = Settings()
