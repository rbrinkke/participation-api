"""
Shared dependencies for the Participation API.

This module contains shared dependencies that can be used across multiple routes.
Currently all dependencies are defined in their respective modules (auth, database).
"""

# Placeholder for future shared dependencies
# Import and re-export commonly used dependencies here if needed
from app.auth import get_current_user
from app.database import db_pool

__all__ = ["get_current_user", "db_pool"]
