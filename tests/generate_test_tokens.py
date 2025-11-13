#!/usr/bin/env python3
"""
generate_test_tokens.py
Generates JWT tokens for test users with specified claims
"""

import sys
from datetime import datetime, timedelta
from jose import jwt

# JWT configuration (must match API configuration)
JWT_SECRET = "dev-secret-key-change-in-production"
JWT_ALGORITHM = "HS256"

# Test user configurations
TEST_USERS = {
    "organizer": {
        "user_id": "00000001-0000-0000-0000-000000000001",
        "email": "organizer@test.com",
        "subscription_level": "premium",
        "ghost_mode": False,
        "org_id": None
    },
    "premium": {
        "user_id": "00000001-0000-0000-0000-000000000002",
        "email": "premium@test.com",
        "subscription_level": "premium",
        "ghost_mode": False,
        "org_id": None
    },
    "free1": {
        "user_id": "00000001-0000-0000-0000-000000000003",
        "email": "free1@test.com",
        "subscription_level": "free",
        "ghost_mode": False,
        "org_id": None
    },
    "free2": {
        "user_id": "00000001-0000-0000-0000-000000000004",
        "email": "free2@test.com",
        "subscription_level": "free",
        "ghost_mode": False,
        "org_id": None
    },
    "free3": {
        "user_id": "00000001-0000-0000-0000-000000000005",
        "email": "free3@test.com",
        "subscription_level": "free",
        "ghost_mode": False,
        "org_id": None
    },
    "free4": {
        "user_id": "00000001-0000-0000-0000-000000000006",
        "email": "free4@test.com",
        "subscription_level": "free",
        "ghost_mode": False,
        "org_id": None
    },
    "free5": {
        "user_id": "00000001-0000-0000-0000-000000000007",
        "email": "free5@test.com",
        "subscription_level": "free",
        "ghost_mode": False,
        "org_id": None
    },
    "blocked": {
        "user_id": "00000001-0000-0000-0000-000000000008",
        "email": "blocked@test.com",
        "subscription_level": "free",
        "ghost_mode": False,
        "org_id": None
    },
    "invitee1": {
        "user_id": "00000001-0000-0000-0000-000000000009",
        "email": "invitee1@test.com",
        "subscription_level": "free",
        "ghost_mode": False,
        "org_id": None
    },
    "invitee2": {
        "user_id": "00000001-0000-0000-0000-000000000010",
        "email": "invitee2@test.com",
        "subscription_level": "free",
        "ghost_mode": False,
        "org_id": None
    }
}


def generate_token(user_config):
    """Generate JWT token for user"""
    payload = {
        "sub": user_config["user_id"],
        "email": user_config["email"],
        "subscription_level": user_config["subscription_level"],
        "ghost_mode": user_config["ghost_mode"],
        "exp": datetime.utcnow() + timedelta(days=1)
    }

    if user_config["org_id"]:
        payload["org_id"] = user_config["org_id"]

    token = jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)
    return token


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 generate_test_tokens.py <user_key>", file=sys.stderr)
        print(f"Available users: {', '.join(TEST_USERS.keys())}", file=sys.stderr)
        sys.exit(1)

    user_key = sys.argv[1]

    if user_key == "all":
        # Generate tokens for all users and export as environment variables
        for key, config in TEST_USERS.items():
            token = generate_token(config)
            var_name = f"TOKEN_{key.upper()}"
            print(f'export {var_name}="{token}"')
    elif user_key in TEST_USERS:
        # Generate token for specific user
        token = generate_token(TEST_USERS[user_key])
        print(token)
    else:
        print(f"Error: Unknown user '{user_key}'", file=sys.stderr)
        print(f"Available users: {', '.join(TEST_USERS.keys())}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
