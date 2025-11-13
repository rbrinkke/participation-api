-- test_cleanup.sql
-- Removes all test data created by test_setup.sql
-- Cleans up participants, waitlist entries, invitations, attendance records, and test users/activities

\echo '================================================='
\echo 'Cleaning up test data for Participation API tests'
\echo '================================================='

-- Delete participants for test activities (CASCADE will handle related records)
\echo 'Removing test participants...'
DELETE FROM activity.participants
WHERE activity_id IN (
    '00000002-0000-0000-0000-000000000001',
    '00000002-0000-0000-0000-000000000002',
    '00000002-0000-0000-0000-000000000003',
    '00000002-0000-0000-0000-000000000004',
    '00000002-0000-0000-0000-000000000005'
);

-- Delete waitlist entries for test activities
\echo 'Removing test waitlist entries...'
DELETE FROM activity.waitlist_entries
WHERE activity_id IN (
    '00000002-0000-0000-0000-000000000001',
    '00000002-0000-0000-0000-000000000002',
    '00000002-0000-0000-0000-000000000003',
    '00000002-0000-0000-0000-000000000004',
    '00000002-0000-0000-0000-000000000005'
);

-- Delete invitations for test activities
\echo 'Removing test invitations...'
DELETE FROM activity.activity_invitations
WHERE activity_id IN (
    '00000002-0000-0000-0000-000000000001',
    '00000002-0000-0000-0000-000000000002',
    '00000002-0000-0000-0000-000000000003',
    '00000002-0000-0000-0000-000000000004',
    '00000002-0000-0000-0000-000000000005'
);

-- Note: Attendance is tracked in participants table via attendance_status column
-- No separate attendance table to clean

-- Delete attendance confirmations for test activities
\echo 'Removing test attendance confirmations...'
DELETE FROM activity.attendance_confirmations
WHERE activity_id IN (
    '00000002-0000-0000-0000-000000000001',
    '00000002-0000-0000-0000-000000000002',
    '00000002-0000-0000-0000-000000000003',
    '00000002-0000-0000-0000-000000000004',
    '00000002-0000-0000-0000-000000000005'
);

-- Delete test activities (CASCADE should handle remaining related records)
\echo 'Removing test activities...'
DELETE FROM activity.activities
WHERE activity_id IN (
    '00000002-0000-0000-0000-000000000001',
    '00000002-0000-0000-0000-000000000002',
    '00000002-0000-0000-0000-000000000003',
    '00000002-0000-0000-0000-000000000004',
    '00000002-0000-0000-0000-000000000005'
);

-- Delete any blocks involving test users
\echo 'Removing test user blocks...'
DELETE FROM activity.user_blocks
WHERE blocker_user_id IN (
    '00000001-0000-0000-0000-000000000001',
    '00000001-0000-0000-0000-000000000002',
    '00000001-0000-0000-0000-000000000003',
    '00000001-0000-0000-0000-000000000004',
    '00000001-0000-0000-0000-000000000005',
    '00000001-0000-0000-0000-000000000006',
    '00000001-0000-0000-0000-000000000007',
    '00000001-0000-0000-0000-000000000008',
    '00000001-0000-0000-0000-000000000009',
    '00000001-0000-0000-0000-000000000010'
)
OR blocked_user_id IN (
    '00000001-0000-0000-0000-000000000001',
    '00000001-0000-0000-0000-000000000002',
    '00000001-0000-0000-0000-000000000003',
    '00000001-0000-0000-0000-000000000004',
    '00000001-0000-0000-0000-000000000005',
    '00000001-0000-0000-0000-000000000006',
    '00000001-0000-0000-0000-000000000007',
    '00000001-0000-0000-0000-000000000008',
    '00000001-0000-0000-0000-000000000009',
    '00000001-0000-0000-0000-000000000010'
);

-- Delete test users (CASCADE should handle remaining related records)
\echo 'Removing test users...'
DELETE FROM activity.users
WHERE user_id IN (
    '00000001-0000-0000-0000-000000000001',
    '00000001-0000-0000-0000-000000000002',
    '00000001-0000-0000-0000-000000000003',
    '00000001-0000-0000-0000-000000000004',
    '00000001-0000-0000-0000-000000000005',
    '00000001-0000-0000-0000-000000000006',
    '00000001-0000-0000-0000-000000000007',
    '00000001-0000-0000-0000-000000000008',
    '00000001-0000-0000-0000-000000000009',
    '00000001-0000-0000-0000-000000000010'
);

\echo ''
\echo '================================================='
\echo 'Test data cleanup complete!'
\echo '================================================='
\echo 'All test users, activities, and related records have been removed.'
\echo '================================================='
