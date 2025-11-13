# Participation API

Activity participation management API for the Activities Platform.

## Features

- **Join/Leave Activities**: Join activities with automatic waitlist management when activities are full
- **Role Management**: Promote/demote co-organizers (organizer only)
- **Attendance Tracking**: Mark attendance with bulk operations and peer verification system
- **Invitation System**: Send/accept/decline invitations with expiry management
- **Waitlist Management**: Automatic promotion when spots become available
- **Blocking System**: Enforcement of user blocking (except for XXL activities)
- **Premium Priority**: Premium users can skip joinable_at_free period

## Architecture

- **FastAPI** with async/await for high performance
- **PostgreSQL** with asyncpg for database connections
- **JWT Authentication** via Auth API
- **Rate Limiting** with Redis backend
- **Stored Procedures** for all business logic
- **Pydantic** for request/response validation

## Setup

### Prerequisites

- Python 3.11+
- PostgreSQL 13+
- Redis 6+

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd participation-api
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

3. Configure environment:
```bash
cp .env.example .env
# Edit .env with your values
```

4. Run the application:
```bash
python -m app.main
```

The API will be available at `http://localhost:8001`

### Docker Deployment

Build and run with Docker:
```bash
docker build -t participation-api .
docker run -p 8001:8001 --env-file .env participation-api
```

## API Documentation

Interactive API documentation is available at:
- Swagger UI: `http://localhost:8001/docs`
- ReDoc: `http://localhost:8001/redoc`

## Endpoints

### Health Check
- `GET /api/v1/participation/health` - Health check endpoint (no auth required)

### Participation
- `POST /api/v1/participation/activities/{activity_id}/join` - Join activity
  - Rate limit: 10/minute
  - Returns: JoinActivityResponse (registered or waitlisted)

- `DELETE /api/v1/participation/activities/{activity_id}/leave` - Leave activity
  - Rate limit: 10/minute
  - Note: Organizer cannot leave, automatically promotes from waitlist

- `POST /api/v1/participation/activities/{activity_id}/cancel` - Cancel participation
  - Rate limit: 10/minute
  - Body: `{ "reason": "optional reason" }`
  - Note: Keeps record but marks as cancelled

- `GET /api/v1/participation/activities/{activity_id}/participants` - List participants
  - Rate limit: 60/minute
  - Query params: status, role, limit, offset
  - Note: Respects blocking rules

- `GET /api/v1/participation/users/{user_id}/activities` - User's activities
  - Rate limit: 60/minute
  - Query params: type (upcoming/past/organized/attended), status, limit, offset

### Role Management
- `POST /api/v1/participation/activities/{activity_id}/promote` - Promote to co-organizer
  - Rate limit: 10/minute
  - Body: `{ "user_id": "uuid" }`
  - Auth: Organizer only

- `POST /api/v1/participation/activities/{activity_id}/demote` - Demote from co-organizer
  - Rate limit: 10/minute
  - Body: `{ "user_id": "uuid" }`
  - Auth: Organizer only

### Attendance
- `POST /api/v1/participation/activities/{activity_id}/attendance` - Mark attendance (bulk)
  - Rate limit: 5/minute
  - Body: `{ "attendances": [{ "user_id": "uuid", "status": "attended|no_show" }] }`
  - Max 100 updates per request
  - Auth: Organizer or co-organizer only

- `POST /api/v1/participation/attendance/confirm` - Peer verification
  - Rate limit: 20/minute
  - Body: `{ "activity_id": "uuid", "confirmed_user_id": "uuid" }`
  - Note: Both users must have attended status

- `GET /api/v1/participation/attendance/pending` - Pending verifications
  - Rate limit: 60/minute
  - Query params: limit, offset
  - Returns activities with unconfirmed participants

### Invitations
- `POST /api/v1/participation/activities/{activity_id}/invitations` - Send invitations (bulk)
  - Rate limit: 5/minute
  - Body: `{ "user_ids": ["uuid"], "message": "optional", "expires_in_hours": 72 }`
  - Max 50 invitations per request
  - Auth: Organizer or co-organizer only

- `POST /api/v1/participation/invitations/{invitation_id}/accept` - Accept invitation
  - Rate limit: 10/minute
  - May result in registered or waitlisted status

- `POST /api/v1/participation/invitations/{invitation_id}/decline` - Decline invitation
  - Rate limit: 10/minute

- `DELETE /api/v1/participation/invitations/{invitation_id}` - Cancel invitation
  - Rate limit: 10/minute
  - Auth: Invitation sender only

- `GET /api/v1/participation/invitations/received` - My received invitations
  - Rate limit: 60/minute
  - Query params: status, limit, offset

- `GET /api/v1/participation/invitations/sent` - My sent invitations
  - Rate limit: 60/minute
  - Query params: activity_id, status, limit, offset

### Waitlist
- `GET /api/v1/participation/activities/{activity_id}/waitlist` - View waitlist
  - Rate limit: 60/minute
  - Query params: limit, offset
  - Auth: Organizer or co-organizer only
  - Returns: Sorted by position ASC

## Authentication

All endpoints (except health check) require JWT authentication via the `Authorization: Bearer <token>` header.

JWT tokens are issued by the Auth API and must contain:
- `sub`: user_id (UUID)
- `email`: user email
- `subscription_level`: "free", "club", or "premium"
- `ghost_mode`: boolean (optional)
- `org_id`: organization UUID (optional)

## Error Handling

All errors follow consistent format:
```json
{
  "detail": "Error message"
}
```

Common HTTP status codes:
- `400` - Bad Request (validation error, already joined, etc.)
- `401` - Unauthorized (invalid/missing token)
- `403` - Forbidden (blocked user, insufficient permissions)
- `404` - Not Found (activity/user/invitation not found)
- `429` - Too Many Requests (rate limit exceeded)

## Rate Limiting

Rate limits are enforced per IP address:
- Write operations: 5-10 requests/minute
- Read operations: 60 requests/minute

When rate limit is exceeded, the API returns HTTP 429 with:
```json
{
  "error": "Rate limit exceeded",
  "retry_after": <seconds>
}
```

## Database

The API connects to PostgreSQL and uses stored procedures for all business logic:
- `activity.sp_join_activity`
- `activity.sp_leave_activity`
- `activity.sp_cancel_participation`
- `activity.sp_list_participants`
- `activity.sp_get_user_activities`
- `activity.sp_promote_participant`
- `activity.sp_demote_participant`
- `activity.sp_mark_attendance`
- `activity.sp_confirm_attendance`
- `activity.sp_get_pending_verifications`
- `activity.sp_send_invitations`
- `activity.sp_accept_invitation`
- `activity.sp_decline_invitation`
- `activity.sp_cancel_invitation`
- `activity.sp_get_received_invitations`
- `activity.sp_get_sent_invitations`
- `activity.sp_get_waitlist`

Connection pooling is configured with:
- Min connections: 10
- Max connections: 50
- Command timeout: 60 seconds

## Development

Run with auto-reload:
```bash
export ENVIRONMENT=development
python -m app.main
```

Run tests:
```bash
pytest tests/
```

## Project Structure

```
participation-api/
├── app/
│   ├── __init__.py
│   ├── main.py                    # FastAPI app setup
│   ├── config.py                  # Environment variables
│   ├── database.py                # PostgreSQL connection pool
│   ├── auth.py                    # JWT token validation
│   ├── dependencies.py            # Shared dependencies
│   ├── models/
│   │   ├── __init__.py
│   │   ├── requests.py            # Pydantic request models
│   │   └── responses.py           # Pydantic response models
│   ├── routes/
│   │   ├── __init__.py
│   │   ├── health.py              # Health check
│   │   ├── participation.py       # Join/leave/cancel
│   │   ├── role_management.py     # Promote/demote
│   │   ├── attendance.py          # Attendance + verification
│   │   ├── invitations.py         # Invitation management
│   │   └── waitlist.py            # Waitlist viewing
│   └── utils/
│       ├── __init__.py
│       ├── errors.py              # Error mapping
│       └── rate_limit.py          # Rate limiting
├── tests/
│   ├── __init__.py
│   ├── test_participation.py
│   ├── test_attendance.py
│   └── test_invitations.py
├── .env.example
├── requirements.txt
├── Dockerfile
└── README.md
```

## License

[Your License Here]

## Support

For issues and questions, please open an issue on the repository.
