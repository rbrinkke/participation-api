# PARTICIPATION API - WERKZAAMHEDEN VOOR CLAUDE CODE

## 🎯 MISSIE
Bouw de **Participation API** volledig volgens de specificaties in document `Weerzaamheden`. Deze API beheert alle participant-gerelateerde operaties voor activities.

---

## 📁 PROJECT STRUCTUUR

Creëer deze directory structuur:

```
participation-api/
├── app/
│   ├── __init__.py
│   ├── main.py                    # FastAPI app setup + CORS + middleware
│   ├── config.py                  # Environment variables + settings
│   ├── database.py                # PostgreSQL connection pool (asyncpg)
│   ├── auth.py                    # JWT token validation + get_current_user
│   ├── dependencies.py            # Shared dependencies
│   ├── models/
│   │   ├── __init__.py
│   │   ├── requests.py            # Pydantic request models
│   │   └── responses.py           # Pydantic response models
│   ├── routes/
│   │   ├── __init__.py
│   │   ├── health.py              # Health check endpoint
│   │   ├── participation.py       # Join/leave/cancel endpoints
│   │   ├── role_management.py     # Promote/demote endpoints
│   │   ├── attendance.py          # Attendance + peer verification
│   │   ├── invitations.py         # All invitation endpoints
│   │   └── waitlist.py            # Waitlist management
│   └── utils/
│       ├── __init__.py
│       ├── errors.py              # Error mapping functions
│       └── rate_limit.py          # Rate limiting setup
├── tests/
│   ├── __init__.py
│   ├── test_participation.py
│   ├── test_attendance.py
│   └── test_invitations.py
├── .env.example                   # Environment variables template
├── requirements.txt               # Python dependencies
├── Dockerfile
└── README.md
```

---

## 🔧 STAP 1: SETUP & CONFIGURATIE

### 1.1 requirements.txt
```txt
fastapi==0.104.1
uvicorn[standard]==0.24.0
asyncpg==0.29.0
pydantic==2.5.0
pydantic[email]
python-jose[cryptography]==3.3.0
slowapi==0.1.9
redis==5.0.1
python-dotenv==1.0.0
pytest==7.4.3
httpx==0.25.0
```

### 1.2 .env.example
```env
# Database
DB_HOST=localhost
DB_PORT=5432
DB_NAME=activity_platform
DB_USER=postgres
DB_PASSWORD=your_password

# JWT
JWT_SECRET_KEY=your-secret-key-min-32-chars
JWT_ALGORITHM=HS256

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# API
API_HOST=0.0.0.0
API_PORT=8001
ENVIRONMENT=development
```

### 1.3 app/config.py
```python
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
```

---

## 🔧 STAP 2: DATABASE CONNECTION

### 2.1 app/database.py
```python
import asyncpg
from app.config import get_settings

settings = get_settings()

async def get_db_pool():
    """Create asyncpg connection pool"""
    return await asyncpg.create_pool(
        host=settings.DB_HOST,
        port=settings.DB_PORT,
        database=settings.DB_NAME,
        user=settings.DB_USER,
        password=settings.DB_PASSWORD,
        min_size=10,
        max_size=50,
        command_timeout=60
    )

# Global pool instance
db_pool = None

async def init_db():
    """Initialize database pool on startup"""
    global db_pool
    db_pool = await get_db_pool()
    
async def close_db():
    """Close database pool on shutdown"""
    global db_pool
    if db_pool:
        await db_pool.close()
```

**INSTRUCTIE**: Deze functie gebruikt asyncpg voor PostgreSQL. Pool wordt bij startup geïnitialiseerd.

---

## 🔧 STAP 3: JWT AUTHENTICATIE

### 3.1 app/auth.py
```python
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt, JWTError
from app.config import get_settings

settings = get_settings()
security = HTTPBearer()

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> dict:
    """
    Extract and validate JWT token.
    
    Returns dict with:
    - user_id: UUID
    - email: str
    - subscription_level: str ('free', 'club', 'premium')
    - ghost_mode: bool
    - org_id: Optional[UUID]
    """
    try:
        token = credentials.credentials
        payload = jwt.decode(
            token, 
            settings.JWT_SECRET_KEY, 
            algorithms=[settings.JWT_ALGORITHM]
        )
        
        return {
            "user_id": payload["sub"],
            "email": payload["email"],
            "subscription_level": payload.get("subscription_level", "free"),
            "ghost_mode": payload.get("ghost_mode", False),
            "org_id": payload.get("org_id")
        }
    except JWTError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token"
        )
```

**INSTRUCTIE**: Deze functie valideert JWT tokens van Auth API. Retourneert altijd dict met user info.

---

## 🔧 STAP 4: PYDANTIC MODELS

### 4.1 app/models/requests.py
```python
from pydantic import BaseModel, Field
from typing import Optional, List
from uuid import UUID
from enum import Enum

class CancelParticipationRequest(BaseModel):
    reason: Optional[str] = Field(None, max_length=500)

class PromoteParticipantRequest(BaseModel):
    user_id: UUID

class DemoteParticipantRequest(BaseModel):
    user_id: UUID

class AttendanceEntry(BaseModel):
    user_id: UUID
    status: str = Field(..., pattern="^(attended|no_show)$")

class MarkAttendanceRequest(BaseModel):
    attendances: List[AttendanceEntry] = Field(..., min_items=1, max_items=100)

class ConfirmAttendanceRequest(BaseModel):
    activity_id: UUID
    confirmed_user_id: UUID

class SendInvitationsRequest(BaseModel):
    user_ids: List[UUID] = Field(..., min_items=1, max_items=50)
    message: Optional[str] = Field(None, max_length=1000)
    expires_in_hours: int = Field(72, ge=1, le=168)

class ParticipationStatus(str, Enum):
    REGISTERED = "registered"
    CANCELLED = "cancelled"
    DECLINED = "declined"
    WAITLISTED = "waitlisted"

class ParticipantRole(str, Enum):
    ORGANIZER = "organizer"
    CO_ORGANIZER = "co_organizer"
    MEMBER = "member"

class InvitationStatus(str, Enum):
    PENDING = "pending"
    ACCEPTED = "accepted"
    DECLINED = "declined"
    EXPIRED = "expired"
```

**INSTRUCTIE**: Alle request body models met Pydantic validatie. Gebruik deze exact zoals gedefinieerd.

### 4.2 app/models/responses.py
```python
from pydantic import BaseModel
from typing import Optional, List
from uuid import UUID
from datetime import datetime

class JoinActivityResponse(BaseModel):
    activity_id: UUID
    user_id: UUID
    role: Optional[str] = None
    participation_status: str
    waitlist_position: Optional[int] = None
    joined_at: datetime
    message: str

class WaitlistPromotedInfo(BaseModel):
    user_id: UUID
    promoted_at: datetime

class LeaveActivityResponse(BaseModel):
    activity_id: UUID
    user_id: UUID
    left_at: datetime
    waitlist_promoted: Optional[WaitlistPromotedInfo] = None
    message: str

class CancelParticipationResponse(BaseModel):
    activity_id: UUID
    user_id: UUID
    participation_status: str
    left_at: datetime
    waitlist_promoted: Optional[WaitlistPromotedInfo] = None
    message: str

class ParticipantInfo(BaseModel):
    user_id: UUID
    username: str
    first_name: Optional[str]
    last_name: Optional[str]
    profile_photo_url: Optional[str]
    role: str
    participation_status: str
    attendance_status: str
    joined_at: datetime
    is_verified: bool
    verification_count: int

class ListParticipantsResponse(BaseModel):
    activity_id: UUID
    total_count: int
    participants: List[ParticipantInfo]

# ... Add all other response models following the specs
```

**INSTRUCTIE**: Response models matchen exact de JSON responses uit specificaties document.

---

## 🔧 STAP 5: ERROR HANDLING

### 5.1 app/utils/errors.py
```python
from fastapi import HTTPException

def map_sp_error(error_code: str, error_message: str) -> HTTPException:
    """
    Map stored procedure error codes to HTTP exceptions.
    
    Args:
        error_code: Error code from SP (e.g., 'ACTIVITY_NOT_FOUND')
        error_message: Error message from SP
        
    Returns:
        HTTPException with appropriate status code and detail
    """
    # Error mapping for join_activity
    join_activity_errors = {
        'ACTIVITY_NOT_FOUND': (404, 'Activity not found'),
        'USER_NOT_FOUND': (404, 'User not found'),
        'ALREADY_JOINED': (400, 'Already joined this activity'),
        'BLOCKED_USER': (403, 'Cannot join this activity'),
        'FRIENDS_ONLY': (403, 'Activity is friends only'),
        'INVITE_ONLY': (403, 'Activity is invite only'),
        'PREMIUM_ONLY_PERIOD': (403, 'Activity is currently only open to Premium members'),
        'USER_BANNED': (403, 'Account is banned'),
        'ACTIVITY_IN_PAST': (400, 'Cannot join past activities'),
        'ACTIVITY_NOT_PUBLISHED': (400, 'Activity is not published'),
        'USER_IS_ORGANIZER': (400, 'Organizer cannot join own activity')
    }
    
    # Error mapping for leave_activity
    leave_activity_errors = {
        'ACTIVITY_NOT_FOUND': (404, 'Activity not found'),
        'NOT_PARTICIPANT': (400, 'Not a participant of this activity'),
        'IS_ORGANIZER': (403, 'Organizer cannot leave activity'),
        'ACTIVITY_IN_PAST': (400, 'Cannot leave past activities')
    }
    
    # Error mapping for cancel_participation
    cancel_participation_errors = {
        'ACTIVITY_NOT_FOUND': (404, 'Activity not found'),
        'NOT_PARTICIPANT': (400, 'Not a participant of this activity'),
        'ALREADY_CANCELLED': (400, 'Participation already cancelled'),
        'ACTIVITY_IN_PAST': (400, 'Cannot cancel past activities')
    }
    
    # Error mapping for promote_participant
    promote_errors = {
        'ACTIVITY_NOT_FOUND': (404, 'Activity not found'),
        'NOT_ORGANIZER': (403, 'Only organizer can promote participants'),
        'TARGET_NOT_MEMBER': (400, 'User is not a member participant'),
        'ALREADY_CO_ORGANIZER': (400, 'User is already a co-organizer')
    }
    
    # Error mapping for demote_participant
    demote_errors = {
        'ACTIVITY_NOT_FOUND': (404, 'Activity not found'),
        'NOT_ORGANIZER': (403, 'Only organizer can demote participants'),
        'NOT_CO_ORGANIZER': (400, 'User is not a co-organizer')
    }
    
    # Error mapping for mark_attendance
    attendance_errors = {
        'ACTIVITY_NOT_FOUND': (404, 'Activity not found'),
        'NOT_AUTHORIZED': (403, 'Only organizer or co-organizer can mark attendance'),
        'ACTIVITY_NOT_COMPLETED': (400, 'Activity has not yet completed'),
        'TOO_MANY_UPDATES': (400, 'Maximum 100 attendances per request')
    }
    
    # Error mapping for confirm_attendance
    confirm_errors = {
        'ACTIVITY_NOT_FOUND': (404, 'Activity not found'),
        'ACTIVITY_NOT_COMPLETED': (400, 'Activity has not yet completed'),
        'CONFIRMER_NOT_ATTENDED': (400, 'You must have attended status to confirm others'),
        'CONFIRMED_NOT_ATTENDED': (400, 'User does not have attended status'),
        'SELF_CONFIRMATION': (400, 'Cannot confirm your own attendance'),
        'ALREADY_CONFIRMED': (400, 'You already confirmed this user for this activity')
    }
    
    # Error mapping for invitations
    invitation_errors = {
        'ACTIVITY_NOT_FOUND': (404, 'Activity not found'),
        'NOT_INVITE_ONLY': (400, 'Activity is not invite-only'),
        'NOT_AUTHORIZED': (403, 'Only organizer or co-organizer can send invitations'),
        'TOO_MANY_INVITATIONS': (400, 'Maximum 50 invitations per request'),
        'INVITATION_NOT_FOUND': (404, 'Invitation not found'),
        'NOT_YOUR_INVITATION': (403, 'This invitation is not for you'),
        'ALREADY_RESPONDED': (400, 'Invitation already responded to'),
        'INVITATION_EXPIRED': (400, 'Invitation has expired'),
        'ACTIVITY_IN_PAST': (400, 'Activity has already occurred')
    }
    
    # Combine all error maps
    all_errors = {
        **join_activity_errors,
        **leave_activity_errors,
        **cancel_participation_errors,
        **promote_errors,
        **demote_errors,
        **attendance_errors,
        **confirm_errors,
        **invitation_errors
    }
    
    # Get status code and message
    status_code, detail = all_errors.get(error_code, (400, error_message))
    
    return HTTPException(status_code=status_code, detail=detail)
```

**INSTRUCTIE**: Deze functie mapped ALLE error codes uit stored procedures naar HTTP exceptions. Gebruik altijd deze functie bij SP errors.

---

## 🔧 STAP 6: RATE LIMITING

### 6.1 app/utils/rate_limit.py
```python
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from fastapi import Request, HTTPException

limiter = Limiter(key_func=get_remote_address)

async def _rate_limit_exceeded_handler(request: Request, exc: RateLimitExceeded):
    """Custom rate limit handler"""
    raise HTTPException(
        status_code=429,
        detail={
            "error": "Rate limit exceeded",
            "retry_after": exc.retry_after
        }
    )
```

**INSTRUCTIE**: Rate limiter voor alle write endpoints. Gebruik zoals gespecificeerd per endpoint.

---

## 🔧 STAP 7: ENDPOINTS - PARTICIPATION

### 7.1 app/routes/participation.py

**INSTRUCTIE**: Implementeer deze 3 endpoints:
1. `POST /api/v1/participation/activities/{activity_id}/join`
2. `DELETE /api/v1/participation/activities/{activity_id}/leave`
3. `POST /api/v1/participation/activities/{activity_id}/cancel`

**Template per endpoint**:
```python
from fastapi import APIRouter, Depends, HTTPException, Request
from uuid import UUID
from app.auth import get_current_user
from app.database import db_pool
from app.models.requests import CancelParticipationRequest
from app.models.responses import JoinActivityResponse, LeaveActivityResponse
from app.utils.errors import map_sp_error
from app.utils.rate_limit import limiter

router = APIRouter(prefix="/api/v1/participation", tags=["participation"])

@router.post("/activities/{activity_id}/join", response_model=JoinActivityResponse)
@limiter.limit("10/minute")
async def join_activity(
    request: Request,
    activity_id: UUID,
    current_user: dict = Depends(get_current_user)
):
    """
    Join an activity (or join waitlist if full).
    
    Premium users can skip joinable_at_free period.
    Blocking is enforced (except for XXL activities).
    """
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
        
        # Build response based on participation_status
        if result["participation_status"] == "waitlisted":
            return JoinActivityResponse(
                activity_id=activity_id,
                user_id=UUID(current_user["user_id"]),
                participation_status="waitlisted",
                waitlist_position=result["waitlist_position"],
                joined_at=datetime.now(),
                message=f"Activity is full. You have been added to the waitlist at position {result['waitlist_position']}."
            )
        else:
            return JoinActivityResponse(
                activity_id=activity_id,
                user_id=UUID(current_user["user_id"]),
                role="member",
                participation_status="registered",
                joined_at=datetime.now(),
                message="Successfully joined activity"
            )
```

**KRITISCHE INSTRUCTIES**:
- Roep ALTIJD stored procedure aan via `conn.fetchrow()`
- Gebruik EXACT de procedure naam uit specs: `activity.sp_join_activity`
- Geef ALTIJD alle parameters mee in CORRECTE volgorde
- Check ALTIJD `result["success"]` boolean
- Als `success=FALSE`: gebruik `map_sp_error()` functie
- Build response volgens Pydantic model
- Rate limit: 10/minute voor write endpoints

**Herhaal dit patroon voor**:
- `leave_activity`: roept `activity.sp_leave_activity($1, $2)`
- `cancel_participation`: roept `activity.sp_cancel_participation($1, $2, $3)`

---

### 7.2 app/routes/participation.py (LIST PARTICIPANTS)

**INSTRUCTIE**: Implementeer GET endpoint:
```python
@router.get("/activities/{activity_id}/participants", response_model=ListParticipantsResponse)
@limiter.limit("60/minute")
async def list_participants(
    request: Request,
    activity_id: UUID,
    status: Optional[str] = None,
    role: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
    current_user: dict = Depends(get_current_user)
):
    """
    List participants of activity (respects blocking).
    
    Query params:
    - status: Filter by participation_status
    - role: Filter by role
    - limit: Max results (1-100)
    - offset: Pagination
    """
    async with db_pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT * FROM activity.sp_list_participants($1, $2, $3, $4, $5, $6)
            """,
            activity_id,
            UUID(current_user["user_id"]),
            status,
            role,
            limit,
            offset
        )
        
        # Check for errors (empty result = access denied or not found)
        if not rows:
            raise HTTPException(status_code=404, detail="Activity not found or access denied")
        
        # Get total count from first row
        total_count = rows[0]["total_count"] if rows else 0
        
        # Build participant list
        participants = [
            ParticipantInfo(
                user_id=row["user_id"],
                username=row["username"],
                first_name=row["first_name"],
                last_name=row["last_name"],
                profile_photo_url=row["profile_photo_url"],
                role=row["role"],
                participation_status=row["participation_status"],
                attendance_status=row["attendance_status"],
                joined_at=row["joined_at"],
                is_verified=row["is_verified"],
                verification_count=row["verification_count"]
            )
            for row in rows
        ]
        
        return ListParticipantsResponse(
            activity_id=activity_id,
            total_count=total_count,
            participants=participants
        )
```

**KRITISCHE INSTRUCTIES**:
- Gebruik `conn.fetch()` voor meerdere rows (niet fetchrow)
- Total count zit IN elke row (window function)
- Leeg result = access denied (niet error)
- Rate limit: 60/minute voor read endpoints

---

### 7.3 app/routes/participation.py (USER ACTIVITIES)

**INSTRUCTIE**: Implementeer GET endpoint:
```python
@router.get("/users/{user_id}/activities", response_model=UserActivitiesResponse)
@limiter.limit("60/minute")
async def get_user_activities(
    request: Request,
    user_id: UUID,
    type: Optional[str] = None,  # 'upcoming', 'past', 'organized', 'attended'
    status: Optional[str] = None,
    limit: int = 20,
    offset: int = 0,
    current_user: dict = Depends(get_current_user)
):
    """
    List user's activities (own or other if allowed).
    
    Respects blocking if viewing other user's activities.
    """
    async with db_pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT * FROM activity.sp_get_user_activities($1, $2, $3, $4, $5, $6)
            """,
            user_id,
            UUID(current_user["user_id"]),
            type,
            status,
            limit,
            offset
        )
        
        # Empty result = blocked or user not found (silent fail for privacy)
        total_count = rows[0]["total_count"] if rows else 0
        
        activities = [
            # Build ActivityInfo from row
            # ... (follow specs document for fields)
        ]
        
        return UserActivitiesResponse(
            user_id=user_id,
            total_count=total_count,
            activities=activities
        )
```

---

## 🔧 STAP 8: ENDPOINTS - ROLE MANAGEMENT

### 8.1 app/routes/role_management.py

**INSTRUCTIE**: Implementeer 2 endpoints:
1. `POST /api/v1/participation/activities/{activity_id}/promote`
2. `POST /api/v1/participation/activities/{activity_id}/demote`

**Template**:
```python
@router.post("/activities/{activity_id}/promote")
@limiter.limit("10/minute")
async def promote_participant(
    request: Request,
    activity_id: UUID,
    body: PromoteParticipantRequest,
    current_user: dict = Depends(get_current_user)
):
    """
    Promote member to co-organizer (organizer only).
    """
    async with db_pool.acquire() as conn:
        result = await conn.fetchrow(
            """
            SELECT * FROM activity.sp_promote_participant($1, $2, $3)
            """,
            activity_id,
            UUID(current_user["user_id"]),
            body.user_id
        )
        
        if not result["success"]:
            raise map_sp_error(result["error_code"], result["error_message"])
        
        return {
            "activity_id": activity_id,
            "user_id": body.user_id,
            "role": "co_organizer",
            "promoted_at": datetime.now(),
            "message": "User promoted to co-organizer successfully"
        }
```

**Herhaal voor demote met `activity.sp_demote_participant`**

---

## 🔧 STAP 9: ENDPOINTS - ATTENDANCE

### 9.1 app/routes/attendance.py

**INSTRUCTIE**: Implementeer 3 endpoints:
1. `POST /api/v1/participation/activities/{activity_id}/attendance` - Mark attendance (bulk)
2. `POST /api/v1/participation/attendance/confirm` - Peer verification
3. `GET /api/v1/participation/attendance/pending` - Pending verifications

**Attendance Marking Template**:
```python
@router.post("/activities/{activity_id}/attendance")
@limiter.limit("5/minute")
async def mark_attendance(
    request: Request,
    activity_id: UUID,
    body: MarkAttendanceRequest,
    current_user: dict = Depends(get_current_user)
):
    """
    Mark attendance for participants (organizer/co-organizer only).
    
    Supports bulk updates (max 100).
    No-shows increment user's no_show_count.
    """
    # Convert attendances to JSONB format for SP
    import json
    attendances_json = json.dumps([
        {"user_id": str(att.user_id), "status": att.status}
        for att in body.attendances
    ])
    
    async with db_pool.acquire() as conn:
        result = await conn.fetchrow(
            """
            SELECT * FROM activity.sp_mark_attendance($1, $2, $3::jsonb)
            """,
            activity_id,
            UUID(current_user["user_id"]),
            attendances_json
        )
        
        if not result["success"]:
            raise map_sp_error(result["error_code"], result["error_message"])
        
        # Parse failed_updates JSONB
        failed_updates = json.loads(result["failed_updates"]) if result["failed_updates"] else []
        
        return {
            "activity_id": activity_id,
            "updated_count": result["updated_count"],
            "attendances": [
                # Build from body.attendances where not in failed
            ],
            "message": "Attendance updated successfully"
        }
```

**KRITISCHE INSTRUCTIES**:
- Body.attendances → JSON → `$3::jsonb` parameter
- SP returnt `failed_updates` als JSONB string → parse met json.loads()
- Max 100 attendances (Pydantic validatie)

**Peer Verification Template**:
```python
@router.post("/attendance/confirm")
@limiter.limit("20/minute")
async def confirm_attendance(
    request: Request,
    body: ConfirmAttendanceRequest,
    current_user: dict = Depends(get_current_user)
):
    """
    Confirm other participant's attendance (peer verification).
    
    Both users must have attendance_status='attended'.
    Increments verified user's verification_count.
    """
    async with db_pool.acquire() as conn:
        result = await conn.fetchrow(
            """
            SELECT * FROM activity.sp_confirm_attendance($1, $2, $3)
            """,
            body.activity_id,
            body.confirmed_user_id,
            UUID(current_user["user_id"])
        )
        
        if not result["success"]:
            raise map_sp_error(result["error_code"], result["error_message"])
        
        return {
            "confirmation_id": result["confirmation_id"],
            "activity_id": body.activity_id,
            "confirmed_user_id": body.confirmed_user_id,
            "confirmer_user_id": UUID(current_user["user_id"]),
            "created_at": datetime.now(),
            "verification_count_updated": result["new_verification_count"],
            "message": "Attendance confirmed successfully"
        }
```

**Pending Verifications Template**:
```python
@router.get("/attendance/pending")
@limiter.limit("60/minute")
async def get_pending_verifications(
    request: Request,
    limit: int = 20,
    offset: int = 0,
    current_user: dict = Depends(get_current_user)
):
    """
    List activities where user attended but hasn't confirmed all participants.
    
    Returns activities with list of unconfirmed participants.
    """
    async with db_pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT * FROM activity.sp_get_pending_verifications($1, $2, $3)
            """,
            UUID(current_user["user_id"]),
            limit,
            offset
        )
        
        total_count = rows[0]["total_count"] if rows else 0
        
        # Parse participants_to_confirm JSONB for each row
        pending_verifications = []
        for row in rows:
            participants = json.loads(row["participants_to_confirm"]) if row["participants_to_confirm"] else []
            pending_verifications.append({
                "activity_id": row["activity_id"],
                "title": row["title"],
                "scheduled_at": row["scheduled_at"],
                "participants_to_confirm": participants
            })
        
        return {
            "total_count": total_count,
            "pending_verifications": pending_verifications
        }
```

---

## 🔧 STAP 10: ENDPOINTS - INVITATIONS

### 10.1 app/routes/invitations.py

**INSTRUCTIE**: Implementeer 6 endpoints:
1. `POST /api/v1/participation/activities/{activity_id}/invitations` - Send bulk invitations
2. `POST /api/v1/participation/invitations/{invitation_id}/accept` - Accept invitation
3. `POST /api/v1/participation/invitations/{invitation_id}/decline` - Decline invitation
4. `DELETE /api/v1/participation/invitations/{invitation_id}` - Cancel invitation
5. `GET /api/v1/participation/invitations/received` - My received invitations
6. `GET /api/v1/participation/invitations/sent` - My sent invitations

**Send Invitations Template**:
```python
@router.post("/activities/{activity_id}/invitations")
@limiter.limit("5/minute")
async def send_invitations(
    request: Request,
    activity_id: UUID,
    body: SendInvitationsRequest,
    current_user: dict = Depends(get_current_user)
):
    """
    Send invitations to users (organizer/co-organizer only).
    
    Supports bulk (max 50).
    Only for invite-only activities.
    """
    # Convert user_ids to PostgreSQL UUID array
    user_ids_array = [str(uid) for uid in body.user_ids]
    
    async with db_pool.acquire() as conn:
        result = await conn.fetchrow(
            """
            SELECT * FROM activity.sp_send_invitations($1, $2, $3::uuid[], $4, $5)
            """,
            activity_id,
            UUID(current_user["user_id"]),
            user_ids_array,
            body.message,
            body.expires_in_hours
        )
        
        if not result["success"]:
            raise map_sp_error(result["error_code"], result["error_message"])
        
        # Parse invitations and failed_invitations JSONB
        invitations = json.loads(result["invitations"]) if result["invitations"] else []
        failed_invitations = json.loads(result["failed_invitations"]) if result["failed_invitations"] else []
        
        return {
            "activity_id": activity_id,
            "invited_count": result["invited_count"],
            "failed_count": result["failed_count"],
            "invitations": invitations,
            "failed_invitations": failed_invitations,
            "message": f"{result['invited_count']} invitation(s) sent successfully"
        }
```

**KRITISCHE INSTRUCTIES**:
- user_ids → PostgreSQL UUID array: `$3::uuid[]`
- SP returnt JSONB arrays → parse beide
- failed_invitations bevat: `[{"user_id": "...", "reason": "..."}]`

**Accept/Decline Templates**:
```python
@router.post("/invitations/{invitation_id}/accept")
@limiter.limit("10/minute")
async def accept_invitation(
    request: Request,
    invitation_id: UUID,
    current_user: dict = Depends(get_current_user)
):
    """
    Accept invitation and join activity.
    
    May result in registered or waitlisted status.
    """
    async with db_pool.acquire() as conn:
        result = await conn.fetchrow(
            """
            SELECT * FROM activity.sp_accept_invitation($1, $2)
            """,
            invitation_id,
            UUID(current_user["user_id"])
        )
        
        if not result["success"]:
            raise map_sp_error(result["error_code"], result["error_message"])
        
        return {
            "invitation_id": invitation_id,
            "activity_id": result["activity_id"],
            "status": "accepted",
            "participation_status": result["participation_status"],
            "waitlist_position": result["waitlist_position"],
            "responded_at": datetime.now(),
            "message": "Invitation accepted and joined activity successfully"
        }

@router.post("/invitations/{invitation_id}/decline")
@limiter.limit("10/minute")
async def decline_invitation(
    request: Request,
    invitation_id: UUID,
    current_user: dict = Depends(get_current_user)
):
    """Decline invitation"""
    async with db_pool.acquire() as conn:
        result = await conn.fetchrow(
            """
            SELECT * FROM activity.sp_decline_invitation($1, $2)
            """,
            invitation_id,
            UUID(current_user["user_id"])
        )
        
        if not result["success"]:
            raise map_sp_error(result["error_code"], result["error_message"])
        
        return {
            "invitation_id": invitation_id,
            "activity_id": result["activity_id"],
            "status": "declined",
            "responded_at": datetime.now(),
            "message": "Invitation declined"
        }
```

**List Invitations Templates**:
```python
@router.get("/invitations/received")
@limiter.limit("60/minute")
async def get_received_invitations(
    request: Request,
    status: Optional[str] = None,
    limit: int = 20,
    offset: int = 0,
    current_user: dict = Depends(get_current_user)
):
    """List invitations received by current user"""
    async with db_pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT * FROM activity.sp_get_received_invitations($1, $2, $3, $4)
            """,
            UUID(current_user["user_id"]),
            status,
            limit,
            offset
        )
        
        total_count = rows[0]["total_count"] if rows else 0
        
        invitations = [
            {
                "invitation_id": row["invitation_id"],
                "activity_id": row["activity_id"],
                "activity_title": row["activity_title"],
                "activity_scheduled_at": row["activity_scheduled_at"],
                "invited_by_user_id": row["invited_by_user_id"],
                "invited_by_username": row["invited_by_username"],
                "status": row["status"],
                "message": row["message"],
                "invited_at": row["invited_at"],
                "expires_at": row["expires_at"],
                "responded_at": row["responded_at"]
            }
            for row in rows
        ]
        
        return {
            "total_count": total_count,
            "invitations": invitations
        }

@router.get("/invitations/sent")
@limiter.limit("60/minute")
async def get_sent_invitations(
    request: Request,
    activity_id: Optional[UUID] = None,
    status: Optional[str] = None,
    limit: int = 20,
    offset: int = 0,
    current_user: dict = Depends(get_current_user)
):
    """List invitations sent by current user"""
    async with db_pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT * FROM activity.sp_get_sent_invitations($1, $2, $3, $4, $5)
            """,
            UUID(current_user["user_id"]),
            activity_id,
            status,
            limit,
            offset
        )
        
        # Similar structure as received
        # ...
```

---

## 🔧 STAP 11: ENDPOINTS - WAITLIST

### 11.1 app/routes/waitlist.py

**INSTRUCTIE**: Implementeer 1 endpoint:
```python
@router.get("/activities/{activity_id}/waitlist")
@limiter.limit("60/minute")
async def get_waitlist(
    request: Request,
    activity_id: UUID,
    limit: int = 50,
    offset: int = 0,
    current_user: dict = Depends(get_current_user)
):
    """
    View waitlist (organizer/co-organizer only).
    
    Sorted by position ASC.
    """
    async with db_pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT * FROM activity.sp_get_waitlist($1, $2, $3, $4)
            """,
            activity_id,
            UUID(current_user["user_id"]),
            limit,
            offset
        )
        
        # Empty = not authorized or no waitlist
        if not rows:
            raise HTTPException(
                status_code=403,
                detail="Only organizer or co-organizer can view waitlist"
            )
        
        total_count = rows[0]["total_count"] if rows else 0
        
        waitlist = [
            {
                "waitlist_id": row["waitlist_id"],
                "user_id": row["user_id"],
                "username": row["username"],
                "first_name": row["first_name"],
                "profile_photo_url": row["profile_photo_url"],
                "position": row["position"],
                "created_at": row["created_at"],
                "notified_at": row["notified_at"]
            }
            for row in rows
        ]
        
        return {
            "activity_id": activity_id,
            "total_count": total_count,
            "waitlist": waitlist
        }
```

---

## 🔧 STAP 12: MAIN APP SETUP

### 12.1 app/main.py
```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

from app.database import init_db, close_db
from app.routes import participation, role_management, attendance, invitations, waitlist, health
from app.utils.rate_limit import limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown events"""
    # Startup
    await init_db()
    yield
    # Shutdown
    await close_db()

app = FastAPI(
    title="Participation API",
    description="Activity participation management API",
    version="1.0.0",
    lifespan=lifespan
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Rate limiting
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Register routers
app.include_router(health.router)
app.include_router(participation.router)
app.include_router(role_management.router)
app.include_router(attendance.router)
app.include_router(invitations.router)
app.include_router(waitlist.router)

if __name__ == "__main__":
    import uvicorn
    from app.config import get_settings
    settings = get_settings()
    uvicorn.run(
        "app.main:app",
        host=settings.API_HOST,
        port=settings.API_PORT,
        reload=settings.ENVIRONMENT == "development"
    )
```

### 12.2 app/routes/health.py
```python
from fastapi import APIRouter
from datetime import datetime

router = APIRouter(prefix="/api/v1/participation", tags=["health"])

@router.get("/health")
async def health_check():
    """Health check endpoint (no auth required)"""
    return {
        "status": "healthy",
        "service": "participation-api",
        "version": "1.0.0",
        "timestamp": datetime.now().isoformat()
    }
```

---

## 🔧 STAP 13: DOCKERFILE

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY app/ ./app/

# Expose port
EXPOSE 8001

# Run application
CMD ["python", "-m", "app.main"]
```

---

## 🔧 STAP 14: README.md

```markdown
# Participation API

Activity participation management API for the Activities Platform.

## Features
- Join/leave activities with waitlist management
- Role management (promote/demote co-organizers)
- Attendance tracking & peer verification
- Invitation system with expiry
- Blocking system enforcement
- Premium priority access

## Setup

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Configure environment:
```bash
cp .env.example .env
# Edit .env with your values
```

3. Run:
```bash
python -m app.main
```

## API Documentation
Visit http://localhost:8001/docs for interactive API documentation.

## Endpoints

### Participation
- `POST /api/v1/participation/activities/{activity_id}/join` - Join activity
- `DELETE /api/v1/participation/activities/{activity_id}/leave` - Leave activity
- `POST /api/v1/participation/activities/{activity_id}/cancel` - Cancel participation
- `GET /api/v1/participation/activities/{activity_id}/participants` - List participants
- `GET /api/v1/participation/users/{user_id}/activities` - User's activities

### Role Management
- `POST /api/v1/participation/activities/{activity_id}/promote` - Promote to co-organizer
- `POST /api/v1/participation/activities/{activity_id}/demote` - Demote from co-organizer

### Attendance
- `POST /api/v1/participation/activities/{activity_id}/attendance` - Mark attendance (bulk)
- `POST /api/v1/participation/attendance/confirm` - Peer verification
- `GET /api/v1/participation/attendance/pending` - Pending verifications

### Invitations
- `POST /api/v1/participation/activities/{activity_id}/invitations` - Send invitations (bulk)
- `POST /api/v1/participation/invitations/{invitation_id}/accept` - Accept invitation
- `POST /api/v1/participation/invitations/{invitation_id}/decline` - Decline invitation
- `DELETE /api/v1/participation/invitations/{invitation_id}` - Cancel invitation
- `GET /api/v1/participation/invitations/received` - My received invitations
- `GET /api/v1/participation/invitations/sent` - My sent invitations

### Waitlist
- `GET /api/v1/participation/activities/{activity_id}/waitlist` - View waitlist

## Architecture
- FastAPI with async/await
- PostgreSQL with asyncpg
- JWT authentication
- Rate limiting with Redis
- Stored procedures for all business logic
```

---

## ✅ VERIFICATIE CHECKLIST

Na implementatie, verifieer deze punten:

### Database
- [ ] asyncpg connection pool werkt
- [ ] Alle stored procedures bestaan in database
- [ ] Connection timeout is 60 seconden

### Authenticatie
- [ ] JWT token validatie werkt
- [ ] user_id wordt correct geëxtraheerd
- [ ] subscription_level komt uit token

### Endpoints
- [ ] Alle 18 endpoints geïmplementeerd
- [ ] Rate limits correct per endpoint
- [ ] Pydantic validatie werkt
- [ ] Error mapping werkt voor alle SPs

### Stored Procedures
- [ ] Alle SP calls gebruiken correcte parameter volgorde
- [ ] UUID conversie correct (UUID(string))
- [ ] JSONB parameters correct geformatteerd
- [ ] UUID array correct: `$3::uuid[]`
- [ ] success boolean check ALTIJD aanwezig

### Response Building
- [ ] Response models matchen specs
- [ ] JSONB parsing correct (json.loads)
- [ ] Total count uit eerste row
- [ ] Timestamps correct geformatteerd

### Error Handling
- [ ] map_sp_error() gebruikt voor alle SP errors
- [ ] HTTP status codes correct
- [ ] Empty results correct gehandled

### Business Logic
- [ ] Waitlist auto-promotion werkt
- [ ] Blocking enforcement (XXL exception)
- [ ] Premium priority join werkt
- [ ] Peer verification increment

---

## 🚨 KRITISCHE AANDACHTSPUNTEN

1. **JSONB Handling**:
   ```python
   # ✅ CORRECT
   import json
   data_json = json.dumps(data)
   result = await conn.fetchrow("SELECT * FROM sp($1::jsonb)", data_json)
   parsed = json.loads(result["jsonb_field"]) if result["jsonb_field"] else []
   
   # ❌ FOUT
   result = await conn.fetchrow("SELECT * FROM sp($1)", data)  # Geen ::jsonb cast
   ```

2. **UUID Array Handling**:
   ```python
   # ✅ CORRECT
   user_ids_array = [str(uid) for uid in body.user_ids]
   result = await conn.fetchrow("SELECT * FROM sp($1::uuid[])", user_ids_array)
   
   # ❌ FOUT
   result = await conn.fetchrow("SELECT * FROM sp($1)", body.user_ids)  # Geen cast
   ```

3. **Error Checking**:
   ```python
   # ✅ CORRECT
   result = await conn.fetchrow("SELECT * FROM sp($1)", param)
   if not result["success"]:
       raise map_sp_error(result["error_code"], result["error_message"])
   
   # ❌ FOUT
   result = await conn.fetchrow("SELECT * FROM sp($1)", param)
   return result  # Geen error check
   ```

4. **Response Building**:
   ```python
   # ✅ CORRECT
   return JoinActivityResponse(
       activity_id=activity_id,
       user_id=UUID(current_user["user_id"]),
       ...
   )
   
   # ❌ FOUT
   return {
       "activity_id": str(activity_id),  # Geen Pydantic model
       ...
   }
   ```

---

## 🎯 SUCCESS CRITERIA

API is compleet wanneer:
1. Alle 18 endpoints werken
2. Alle stored procedures worden correct aangeroepen
3. JWT authenticatie werkt
4. Rate limiting actief
5. Error handling consistent
6. Responses matchen specs EXACT
7. JSONB en UUID arrays correct gehandled
8. Health check endpoint werkt
9. FastAPI docs toegankelijk op /docs
10. Alle test scenarios uit specs slagen

---

**EINDE WERKZAAMHEDEN SPECIFICATIE**

Dit document bevat ALLES wat Claude Code nodig heeft om de Participation API volledig te bouwen volgens de originele specificaties.
