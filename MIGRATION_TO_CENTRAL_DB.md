# Migratie naar Centrale Database

**Datum:** 2025-11-13
**Status:** ✅ Compleet

## Wijzigingen

### 1. Docker Compose Configuratie

**Voor:**
- Geen docker-compose.yml
- Verwachtte lokale PostgreSQL en Redis

**Na:**
- ✅ docker-compose.yml aangemaakt
- ✅ Gebruikt centrale `activity-postgres-db` container
- ✅ Gebruikt gedeelde `auth-redis` container
- ✅ Gebruikt `activity_default` netwerk
- ✅ Port 8004 (om conflicten te voorkomen)

### 2. Database Configuratie

**Database Connectie:**
```
Host: activity-postgres-db
Port: 5432
Database: activitydb
User: postgres
Password: postgres_secure_password_change_in_prod
```

**Belangrijke punten:**
- Host: `activity-postgres-db` (centrale database container)
- Database: `activitydb` (met alle 40 tabellen)
- Schema: `activity` (automatisch via migraties)

### 3. Redis Configuratie

**Redis Connectie:**
```
Host: auth-redis
Port: 6379
```

Gebruikt dezelfde Redis instance als andere APIs voor:
- Rate limiting
- Caching
- Session management

### 4. Netwerk Configuratie

Gebruikt `activity_default` external network:
- Alle activity services in zelfde netwerk
- Direct communicatie tussen services
- Geen port mapping conflicts

### 5. Container Naam

Container naam: `participation-api`
- Makkelijk te identificeren
- Consistent met andere services
- Gebruikt in logs en monitoring

## Database Schema

De participation-api gebruikt tabellen uit het centrale schema:

**Activity Tabellen:**
- `activities` (24 kolommen) - Activity data
- `activity_participants` (10 kolommen) - Participant management
- `activity_tags` (4 kolommen) - Activity categorization

**User Tabellen:**
- `users` (34 kolommen) - User info
- `user_settings` (14 kolommen) - User preferences

## Deployment

### Starten

```bash
cd /mnt/d/activity/participation-api
docker compose build
docker compose up -d
```

### Logs Checken

```bash
docker compose logs -f participation-api
```

### Health Check

```bash
curl http://localhost:8004/health
```

### Stoppen

```bash
docker compose down
```

## Belangrijke Opmerkingen

1. **Geen eigen database meer** - Alle data in centrale database
2. **Gedeelde Redis** - Rate limiting gedeeld met andere APIs
3. **Port 8004** - Om conflict met andere APIs te voorkomen
4. **External network** - Moet `activity_default` netwerk bestaan
5. **API draait intern op port 8001** - Extern toegankelijk via 8004

## Port Overzicht

| Service | Port | Functie |
|---------|------|---------|
| auth-api | 8000 | Authenticatie & gebruikers |
| moderation-api | 8002 | Content moderatie |
| community-api | 8003 | Communities & posts |
| participation-api | 8004 | Activity deelname |

## Verificatie

Checklist na deployment:
- [ ] Container start zonder errors
- [ ] Database connectie succesvol
- [ ] Redis connectie succesvol
- [ ] Health endpoint reageert
- [ ] Auth-API communicatie werkt
- [ ] Participation endpoints werken

## Rollback

Als er problemen zijn:
```bash
cd /mnt/d/activity/participation-api
docker compose down
# Fix issues
docker compose up -d
```

---

**Status:** ✅ Klaar voor gebruik met centrale database
