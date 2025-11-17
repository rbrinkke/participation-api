from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Environment
    ENVIRONMENT: str = "development"

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

    # API Documentation (Swagger UI / OpenAPI)
    ENABLE_DOCS: bool = True
    API_VERSION: str = "1.0.0"
    PROJECT_NAME: str = "Activity Platform - Participation API"

    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
