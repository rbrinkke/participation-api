-- test_setup.sql
-- Creates deterministic test data for participation API tests
-- Can be run multiple times (idempotent via ON CONFLICT)

\echo '================================================='
\echo 'Setting up test data for Participation API tests'
\echo '================================================='

-- Create test users with deterministic UUIDs
\echo 'Creating test users...'

INSERT INTO activity.users (
    user_id,
    id,
    email,
    username,
    password_hash,
    hashed_password,
    first_name,
    last_name,
    subscription_level,
    status,
    is_active,
    is_verified,
    created_at,
    updated_at
) VALUES
    -- Organizer user (premium, verified)
    (
        '00000001-0000-0000-0000-000000000001',
        '00000001-0000-0000-0000-000000000001',
        'organizer@test.com',
        'test_organizer',
        '$argon2id$v=19$m=65536,t=3,p=4$test',  -- dummy hash
        '$argon2id$v=19$m=65536,t=3,p=4$test',
        'Test',
        'Organizer',
        'premium',
        'active',
        true,
        true,
        NOW(),
        NOW()
    ),
    -- Premium user (verified)
    (
        '00000001-0000-0000-0000-000000000002',
        '00000001-0000-0000-0000-000000000002',
        'premium@test.com',
        'test_premium',
        '$argon2id$v=19$m=65536,t=3,p=4$test',
        '$argon2id$v=19$m=65536,t=3,p=4$test',
        'Premium',
        'User',
        'premium',
        'active',
        true,
        true,
        NOW(),
        NOW()
    ),
    -- Free user 1
    (
        '00000001-0000-0000-0000-000000000003',
        '00000001-0000-0000-0000-000000000003',
        'free1@test.com',
        'test_free1',
        '$argon2id$v=19$m=65536,t=3,p=4$test',
        '$argon2id$v=19$m=65536,t=3,p=4$test',
        'Free',
        'User1',
        'free',
        'active',
        true,
        true,
        NOW(),
        NOW()
    ),
    -- Free user 2
    (
        '00000001-0000-0000-0000-000000000004',
        '00000001-0000-0000-0000-000000000004',
        'free2@test.com',
        'test_free2',
        '$argon2id$v=19$m=65536,t=3,p=4$test',
        '$argon2id$v=19$m=65536,t=3,p=4$test',
        'Free',
        'User2',
        'free',
        'active',
        true,
        true,
        NOW(),
        NOW()
    ),
    -- Free user 3
    (
        '00000001-0000-0000-0000-000000000005',
        '00000001-0000-0000-0000-000000000005',
        'free3@test.com',
        'test_free3',
        '$argon2id$v=19$m=65536,t=3,p=4$test',
        '$argon2id$v=19$m=65536,t=3,p=4$test',
        'Free',
        'User3',
        'free',
        'active',
        true,
        true,
        NOW(),
        NOW()
    ),
    -- Free user 4
    (
        '00000001-0000-0000-0000-000000000006',
        '00000001-0000-0000-0000-000000000006',
        'free4@test.com',
        'test_free4',
        '$argon2id$v=19$m=65536,t=3,p=4$test',
        '$argon2id$v=19$m=65536,t=3,p=4$test',
        'Free',
        'User4',
        'free',
        'active',
        true,
        true,
        NOW(),
        NOW()
    ),
    -- Free user 5
    (
        '00000001-0000-0000-0000-000000000007',
        '00000001-0000-0000-0000-000000000007',
        'free5@test.com',
        'test_free5',
        '$argon2id$v=19$m=65536,t=3,p=4$test',
        '$argon2id$v=19$m=65536,t=3,p=4$test',
        'Free',
        'User5',
        'free',
        'active',
        true,
        true,
        NOW(),
        NOW()
    ),
    -- Blocked user (for blocking tests)
    (
        '00000001-0000-0000-0000-000000000008',
        '00000001-0000-0000-0000-000000000008',
        'blocked@test.com',
        'test_blocked',
        '$argon2id$v=19$m=65536,t=3,p=4$test',
        '$argon2id$v=19$m=65536,t=3,p=4$test',
        'Blocked',
        'User',
        'free',
        'active',
        true,
        true,
        NOW(),
        NOW()
    ),
    -- Invitee 1
    (
        '00000001-0000-0000-0000-000000000009',
        '00000001-0000-0000-0000-000000000009',
        'invitee1@test.com',
        'test_invitee1',
        '$argon2id$v=19$m=65536,t=3,p=4$test',
        '$argon2id$v=19$m=65536,t=3,p=4$test',
        'Invitee',
        'One',
        'free',
        'active',
        true,
        true,
        NOW(),
        NOW()
    ),
    -- Invitee 2
    (
        '00000001-0000-0000-0000-000000000010',
        '00000001-0000-0000-0000-000000000010',
        'invitee2@test.com',
        'test_invitee2',
        '$argon2id$v=19$m=65536,t=3,p=4$test',
        '$argon2id$v=19$m=65536,t=3,p=4$test',
        'Invitee',
        'Two',
        'free',
        'active',
        true,
        true,
        NOW(),
        NOW()
    )
ON CONFLICT (user_id) DO UPDATE SET
    subscription_level = EXCLUDED.subscription_level,
    is_active = EXCLUDED.is_active,
    is_verified = EXCLUDED.is_verified,
    updated_at = NOW();

\echo '✓ Test users created (10 users)'

-- Create test activities
\echo 'Creating test activities...'

INSERT INTO activity.activities (
    activity_id,
    organizer_user_id,
    title,
    description,
    activity_type,
    activity_privacy_level,
    status,
    scheduled_at,
    duration_minutes,
    max_participants,
    current_participants_count,
    waitlist_count,
    location_name,
    city,
    created_at,
    updated_at
) VALUES
    -- Public activity (normal capacity, 10 max)
    (
        '00000002-0000-0000-0000-000000000001',
        '00000001-0000-0000-0000-000000000001',  -- organizer
        'Test Public Activity',
        'This is a test public activity for testing participation',
        'standard',
        'public',
        'published',
        NOW() + INTERVAL '7 days',
        120,
        10,
        0,
        0,
        'Test Location',
        'Amsterdam',
        NOW(),
        NOW()
    ),
    -- Small activity (max 2 participants, for waitlist testing)
    (
        '00000002-0000-0000-0000-000000000002',
        '00000001-0000-0000-0000-000000000001',  -- organizer
        'Test Small Activity',
        'Small activity with max 2 participants for waitlist testing',
        'standard',
        'public',
        'published',
        NOW() + INTERVAL '7 days',
        60,
        2,
        0,
        0,
        'Test Location',
        'Amsterdam',
        NOW(),
        NOW()
    ),
    -- Friends-only activity
    (
        '00000002-0000-0000-0000-000000000003',
        '00000001-0000-0000-0000-000000000001',  -- organizer
        'Test Friends-Only Activity',
        'Activity with friends_only privacy for testing access control',
        'standard',
        'friends_only',
        'published',
        NOW() + INTERVAL '7 days',
        90,
        10,
        0,
        0,
        'Test Location',
        'Rotterdam',
        NOW(),
        NOW()
    ),
    -- Invite-only activity
    (
        '00000002-0000-0000-0000-000000000004',
        '00000001-0000-0000-0000-000000000001',  -- organizer
        'Test Invite-Only Activity',
        'Activity with invite_only privacy for testing invitations',
        'standard',
        'invite_only',
        'published',
        NOW() + INTERVAL '7 days',
        90,
        10,
        0,
        0,
        'Test Location',
        'Utrecht',
        NOW(),
        NOW()
    ),
    -- Activity for attendance testing
    (
        '00000002-0000-0000-0000-000000000005',
        '00000001-0000-0000-0000-000000000001',  -- organizer
        'Test Attendance Activity',
        'Activity for testing attendance marking and confirmation',
        'standard',
        'public',
        'published',
        NOW() + INTERVAL '7 days',
        120,
        10,
        0,
        0,
        'Test Location',
        'Den Haag',
        NOW(),
        NOW()
    )
ON CONFLICT (activity_id) DO UPDATE SET
    title = EXCLUDED.title,
    status = EXCLUDED.status,
    scheduled_at = EXCLUDED.scheduled_at,
    max_participants = EXCLUDED.max_participants,
    updated_at = NOW();

\echo '✓ Test activities created (5 activities)'

\echo ''
\echo '================================================='
\echo 'Test data setup complete!'
\echo '================================================='
\echo ''
\echo 'Test Users:'
\echo '  - organizer@test.com (premium, organizer)'
\echo '  - premium@test.com (premium user)'
\echo '  - free1@test.com through free5@test.com (free users)'
\echo '  - blocked@test.com (for blocking tests)'
\echo '  - invitee1@test.com, invitee2@test.com (for invitation tests)'
\echo ''
\echo 'Test Activities:'
\echo '  - Public Activity (max 10)'
\echo '  - Small Activity (max 2, for waitlist)'
\echo '  - Friends-Only Activity'
\echo '  - Invite-Only Activity'
\echo '  - Attendance Activity'
\echo '================================================='
