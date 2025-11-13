# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FastAPI-based Participation API for managing activity participation, attendance, invitations, and waitlist functionality. Part of the larger Activities Platform microservices architecture.

**Key Point**: This API is **completely stored-procedure driven**. ALL business logic resides in PostgreSQL stored procedures in the `activity` schema. The Python code only handles HTTP routing, JWT validation, rate limiting, and data transformation.

## Docker Development Workflow

**CRITICAL**: After ANY code changes, you MUST rebuild the Docker container for changes to take effect. A simple `docker compose restart` will NOT pick up code changes - it reuses the old image.

**IMPORTANT**: The Dockerfile uses `uvicorn` directly (not `python -m app.main`) to ensure the lifespan context manager works correctly for database pool initialization.

### Standard Development Commands

```bash
# Build and start (REQUIRED after code changes)
docker compose build
docker compose up -d

# Force rebuild without cache (when dependencies change)
docker compose build --no-cache
docker compose up -d

# View logs
docker compose logs -f participation-api

# Stop and remove
docker compose down

# Restart container (only for config changes, NOT code changes)
docker compose restart participation-api
```

### Testing API

```bash
# Health check
curl http://localhost:8004/health

# Interactive API docs (Swagger UI)
open http://localhost:8004/docs

# Alternative docs (ReDoc)
open http://localhost:8004/redoc
```

## Architecture Overview

### Stored Procedure Pattern

Every endpoint follows this pattern:

1. **Route handler** validates request and extracts JWT claims
2. **Call stored procedure** with parameters (activity_id, user_id, etc.)
3. **SP returns** `{success: bool, error_code: str, error_message: str, ...data}`
4. **Error mapping** converts SP error codes to HTTP exceptions
5. **Response transformation** maps SP result to Pydantic response models

Example from `app/routes/participation.py:38-49`:
```python
async with db_pool.acquire() as conn:
    result = await conn.fetchrow(
        """
        SELECT * FROM activity.sp_join_activity($1, $2, $3)
        """,
        activity_id,
        UUID(current_user["user_id"]),
        current_user["subscription_level"]
    )

    if not result["success"]:
        raise map_sp_error(result["error_code"], result["error_message"])
```

### Stored Procedures Used

Located in central database schema `activity`:

- `sp_join_activity` - Join activity or waitlist
- `sp_leave_activity` - Leave and auto-promote from waitlist
- `sp_cancel_participation` - Cancel with reason
- `sp_list_participants` - List with blocking enforcement
- `sp_get_user_activities` - User's activity history
- `sp_promote_participant` - Promote to co-organizer
- `sp_demote_participant` - Remove co-organizer role
- `sp_mark_attendance` - Bulk attendance marking
- `sp_confirm_attendance` - Peer verification
- `sp_get_pending_verifications` - Unconfirmed attendances
- `sp_send_invitations` - Bulk invite sending
- `sp_accept_invitation` - Accept with auto-join
- `sp_decline_invitation` - Decline invitation
- `sp_cancel_invitation` - Cancel sent invitation
- `sp_get_received_invitations` - User's received invites
- `sp_get_sent_invitations` - User's sent invites
- `sp_get_waitlist` - Waitlist ordered by position

### Database Connection

- **Host**: `activity-postgres-db` (shared container)
- **Database**: `activitydb` (central database with 40+ tables)
- **Schema**: `activity` (all stored procedures live here)
- **Pool**: asyncpg with 10-50 connections, 60s timeout
- **Lifecycle**: Pool initialized on startup via `lifespan` context manager

### Authentication Flow

JWT validation extracts these claims (see `app/auth.py:10-43`):

```python
{
    "user_id": UUID,              # from 'sub' claim
    "email": str,                 # user email
    "subscription_level": str,    # 'free', 'club', 'premium'
    "ghost_mode": bool,           # visibility flag
    "org_id": Optional[UUID]      # organization ID
}
```

**Important**: Premium users can skip `joinable_at_free` restrictions. This is enforced by stored procedures, not Python code.

### Rate Limiting

Redis-backed rate limiting via SlowAPI:

- **Write operations**: 5-10 requests/minute
- **Read operations**: 60 requests/minute
- **Per IP address** tracking
- **Returns**: HTTP 429 with `retry_after` header

Configuration in `app/utils/rate_limit.py`

### Error Handling Pattern

Stored procedure errors follow this contract:

```sql
-- SP returns on error:
{
  success: false,
  error_code: 'ACTIVITY_NOT_FOUND',
  error_message: 'Activity does not exist'
}
```

Python maps these to HTTP exceptions via `app/utils/errors.py:4-140`:

```python
'ACTIVITY_NOT_FOUND': (404, 'Activity not found')
'BLOCKED_USER': (403, 'Cannot join this activity')
'ALREADY_JOINED': (400, 'Already joined this activity')
```

## Central Database Integration

**This API does NOT have its own database.** It connects to the shared `activity-postgres-db` container that hosts the central `activitydb` database.

Key tables (in `activity` schema):
- `activities` - Activity master data (24 columns)
- `activity_participants` - Participation records (10 columns)
- `activity_invitations` - Invitation management
- `activity_waitlist` - Waitlist queue
- `users` - User data (34 columns)
- `user_settings` - User preferences (14 columns)

**Migration Note**: See `MIGRATION_TO_CENTRAL_DB.md` for details on centralization.

## Network Architecture

- **Container**: `participation-api`
- **Internal Port**: 8001 (FastAPI listens here)
- **External Port**: 8004 (mapped in docker-compose.yml)
- **Network**: `activity_default` (external, shared with other microservices)

Other services on same network:
- `auth-api` - Port 8000
- `moderation-api` - Port 8002
- `community-api` - Port 8003
- `activity-postgres-db` - Port 5432
- `auth-redis` - Port 6379

## Code Structure

```
app/
├── main.py              # FastAPI setup, middleware, router registration
├── config.py            # Environment variables via Pydantic Settings
├── database.py          # asyncpg connection pool management
├── auth.py              # JWT validation and claims extraction
├── dependencies.py      # Shared FastAPI dependencies
├── models/
│   ├── requests.py      # Pydantic request models (input validation)
│   └── responses.py     # Pydantic response models (output serialization)
├── routes/
│   ├── health.py        # Health check (no auth required)
│   ├── participation.py # Join/leave/cancel/list
│   ├── role_management.py # Promote/demote co-organizers
│   ├── attendance.py    # Mark attendance + peer verification
│   ├── invitations.py   # Send/accept/decline invitations
│   └── waitlist.py      # View waitlist (organizer only)
└── utils/
    ├── errors.py        # SP error code → HTTP exception mapping
    └── rate_limit.py    # Redis-backed rate limiting setup
```

## Development Guidelines

### When Adding New Endpoints

1. **Stored procedure MUST exist first** - Business logic lives in PostgreSQL
2. **Create request model** in `app/models/requests.py` if accepting body
3. **Create response model** in `app/models/responses.py` matching SP output
4. **Add route handler** in appropriate router file
5. **Map error codes** in `app/utils/errors.py` for SP error responses
6. **Apply rate limit** decorator with appropriate limit
7. **Add to router** in `app/main.py` if new router file created
8. **REBUILD container** for changes to take effect

### Testing Pattern

```bash
# 1. Make code changes
# 2. Rebuild container (REQUIRED)
docker compose build && docker compose up -d

# 3. Check logs for startup errors
docker compose logs -f participation-api

# 4. Test endpoint
curl -X POST http://localhost:8004/api/v1/participation/activities/{uuid}/join \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json"

# 5. Check interactive docs
open http://localhost:8004/docs
```

### Environment Variables

Required variables (from `.env` file):

```bash
# Database (central DB)
DB_HOST=activity-postgres-db
DB_PORT=5432
DB_NAME=activitydb
DB_USER=postgres
DB_PASSWORD=postgres_secure_password_change_in_prod

# JWT (must match auth-api configuration)
JWT_SECRET_KEY=dev-secret-key-change-in-production
JWT_ALGORITHM=HS256

# Redis (shared instance)
REDIS_HOST=auth-redis
REDIS_PORT=6379

# API Configuration
API_HOST=0.0.0.0
API_PORT=8001
ENVIRONMENT=development
```

### Debugging Tips

**Always include debug logging in stored procedures** - This is emphasized in the global instructions. When modifying or creating stored procedures, add comprehensive logging:

```sql
-- Example SP logging pattern
RAISE NOTICE 'sp_join_activity called: activity_id=%, user_id=%', p_activity_id, p_user_id;
RAISE NOTICE 'User subscription level: %', p_subscription_level;
```

**Connection pool issues**: Check `docker compose logs` for asyncpg errors. Pool exhaustion indicates either:
- Too many concurrent requests (increase `max_size` in `database.py:19`)
- Long-running queries (check stored procedure performance)
- Leaked connections (ensure `async with db_pool.acquire()` pattern)

**JWT validation failures**: Ensure `JWT_SECRET_KEY` matches auth-api configuration. Check token expiry and claims structure.

**Rate limit tuning**: Adjust limits in route decorators. Redis must be accessible for rate limiting to work.

## Running Tests

Currently, tests directory exists but is empty (`tests/__init__.py` only).

For future test implementation:
```bash
# Install test dependencies (already in requirements.txt)
pip install pytest httpx

# Run tests
pytest tests/ -v

# Run specific test file
pytest tests/test_participation.py -v
```

## Common Issues & Solutions

**"Code changes not working"**: You forgot to rebuild. Run `docker compose build && docker compose up -d`

**"Cannot connect to database"**: Check that `activity-postgres-db` container is running and `activity-network` network exists.

**"Database pool not initialized"**:
- Check container logs for lifespan startup messages
- Verify Dockerfile uses `uvicorn app.main:app` directly (not `python -m app.main`)
- ENVIRONMENT should be set to "production" (not "development") to disable reload mode

**"Rate limit exceeded immediately"**: Redis connection failed. Check `auth-redis` container status.

**"Invalid token"**: JWT secret mismatch with auth-api or token expired. Get fresh token from auth-api.

**"Stored procedure doesn't exist"**: Database migrations haven't run. Check central database for SP existence in `activity` schema.

**"Schema mismatch errors"**:
- Verify stored procedures use correct column names (`activity_privacy_level` not `privacy_level`)
- Check `participation_stored_procedures.sql` against actual database schema
- Reload stored procedures after fixes: `docker exec -i activity-postgres-db psql -U postgres -d activitydb < participation_stored_procedures.sql`

## API Endpoint Summary

All endpoints require JWT auth except `/health`.

Base path: `/api/v1/participation`

**Participation**:
- `POST /activities/{id}/join` - Join or waitlist (10/min)
- `DELETE /activities/{id}/leave` - Leave + auto-promote (10/min)
- `POST /activities/{id}/cancel` - Cancel with reason (10/min)
- `GET /activities/{id}/participants` - List participants (60/min)
- `GET /users/{id}/activities` - User activity history (60/min)

**Role Management** (organizer only):
- `POST /activities/{id}/promote` - Make co-organizer (10/min)
- `POST /activities/{id}/demote` - Remove co-organizer (10/min)

**Attendance** (organizer/co-organizer):
- `POST /activities/{id}/attendance` - Bulk mark (5/min, max 100)
- `POST /attendance/confirm` - Peer verify (20/min)
- `GET /attendance/pending` - Unconfirmed list (60/min)

**Invitations**:
- `POST /activities/{id}/invitations` - Bulk send (5/min, max 50)
- `POST /invitations/{id}/accept` - Accept invite (10/min)
- `POST /invitations/{id}/decline` - Decline invite (10/min)
- `DELETE /invitations/{id}` - Cancel sent (10/min)
- `GET /invitations/received` - My received (60/min)
- `GET /invitations/sent` - My sent (60/min)

**Waitlist** (organizer/co-organizer only):
- `GET /activities/{id}/waitlist` - View queue (60/min)

See `README.md` for detailed endpoint specifications and response models.
