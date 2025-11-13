from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    # Database
    DB_HOST: str
    DB_PORT: int
    DB_NAME: str
    DB_USER: str
    DB_PASSWORD: str

    # JWT
    JWT_SECRET_KEY: str
    JWT_ALGORITHM: str = "HS256"

    # Redis
    REDIS_HOST: str
    REDIS_PORT: int

    # API
    API_HOST: str = "0.0.0.0"
    API_PORT: int = 8001
    ENVIRONMENT: str = "development"

    class Config:
        env_file = ".env"


@lru_cache()
def get_settings():
    return Settings()
