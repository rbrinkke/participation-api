-- =====================================================
-- PARTICIPATION API - STORED PROCEDURES
-- =====================================================
-- Complete implementation of all stored procedures for the Participation API
-- Schema: activity
-- All procedures include comprehensive RAISE NOTICE logging for debugging
-- =====================================================

-- =====================================================
-- 1. sp_join_activity
-- =====================================================
CREATE OR REPLACE FUNCTION activity.sp_join_activity(
    p_activity_id UUID,
    p_user_id UUID,
    p_subscription_level activity.subscription_level
)
RETURNS TABLE (
    success BOOLEAN,
    participation_status activity.participation_status,
    waitlist_position INT,
    error_code VARCHAR(50),
    error_message TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_activity RECORD;
    v_user RECORD;
    v_organizer_id UUID;
    v_block_exists BOOLEAN;
    v_friendship_exists BOOLEAN;
    v_invitation_exists BOOLEAN;
    v_already_joined BOOLEAN;
    v_current_count INT;
    v_next_position INT;
BEGIN
    RAISE NOTICE 'sp_join_activity called: activity_id=%, user_id=%, subscription_level=%',
        p_activity_id, p_user_id, p_subscription_level;

    -- Get activity details
    SELECT a.*, a.organizer_user_id INTO v_activity
    FROM activity.activities a
    WHERE a.activity_id = p_activity_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'Activity not found: %', p_activity_id;
        RETURN QUERY SELECT FALSE, NULL::activity.participation_status, NULL::INT,
            'ACTIVITY_NOT_FOUND'::VARCHAR(50), 'Activity does not exist'::TEXT;
        RETURN;
    END IF;

    RAISE NOTICE 'Activity found: title=%, status=%, organizer_id=%',
        v_activity.title, v_activity.status, v_activity.organizer_user_id;

    -- Check activity status
    IF v_activity.status != 'published' THEN
        RAISE NOTICE 'Activity not published: status=%', v_activity.status;
        RETURN QUERY SELECT FALSE, NULL::activity.participation_status, NULL::INT,
            'ACTIVITY_NOT_PUBLISHED'::VARCHAR(50), 'Activity is not published'::TEXT;
        RETURN;
    END IF;

    -- Check if activity is in the past
    IF v_activity.scheduled_at <= NOW() THEN
        RAISE NOTICE 'Activity is in the past: scheduled_at=%', v_activity.scheduled_at;
        RETURN QUERY SELECT FALSE, NULL::activity.participation_status, NULL::INT,
            'ACTIVITY_IN_PAST'::VARCHAR(50), 'Cannot join past activities'::TEXT;
        RETURN;
    END IF;

    -- Get user details
    SELECT u.* INTO v_user
    FROM activity.users u
    WHERE u.user_id = p_user_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'User not found: %', p_user_id;
        RETURN QUERY SELECT FALSE, NULL::activity.participation_status, NULL::INT,
            'USER_NOT_FOUND'::VARCHAR(50), 'User does not exist'::TEXT;
        RETURN;
    END IF;

    RAISE NOTICE 'User found: username=%, is_active=%, status=%',
        v_user.username, v_user.is_active, v_user.status;

    -- Check user is active
    IF NOT v_user.is_active THEN
        RAISE NOTICE 'User is not active: user_id=%', p_user_id;
        RETURN QUERY SELECT FALSE, NULL::activity.participation_status, NULL::INT,
            'USER_NOT_FOUND'::VARCHAR(50), 'User does not exist'::TEXT;
        RETURN;
    END IF;

    -- Check user is not banned
    IF v_user.status = 'banned' THEN
        RAISE NOTICE 'User is banned: user_id=%', p_user_id;
        RETURN QUERY SELECT FALSE, NULL::activity.participation_status, NULL::INT,
            'USER_BANNED'::VARCHAR(50), 'Account is banned'::TEXT;
        RETURN;
    END IF;

    -- Check user is not the organizer
    IF v_activity.organizer_user_id = p_user_id THEN
        RAISE NOTICE 'User is organizer of activity: user_id=%', p_user_id;
        RETURN QUERY SELECT FALSE, NULL::activity.participation_status, NULL::INT,
            'USER_IS_ORGANIZER'::VARCHAR(50), 'Organizer cannot join own activity'::TEXT;
        RETURN;
    END IF;

    -- Check if already joined or waitlisted
    SELECT EXISTS(
        SELECT 1 FROM activity.participants
        WHERE activity_id = p_activity_id AND user_id = p_user_id
    ) INTO v_already_joined;

    IF v_already_joined THEN
        RAISE NOTICE 'User already joined: user_id=%', p_user_id;
        RETURN QUERY SELECT FALSE, NULL::activity.participation_status, NULL::INT,
            'ALREADY_JOINED'::VARCHAR(50), 'Already joined this activity'::TEXT;
        RETURN;
    END IF;

    SELECT EXISTS(
        SELECT 1 FROM activity.waitlist_entries
        WHERE activity_id = p_activity_id AND user_id = p_user_id
    ) INTO v_already_joined;

    IF v_already_joined THEN
        RAISE NOTICE 'User already on waitlist: user_id=%', p_user_id;
        RETURN QUERY SELECT FALSE, NULL::activity.participation_status, NULL::INT,
            'ALREADY_JOINED'::VARCHAR(50), 'Already on waitlist for this activity'::TEXT;
        RETURN;
    END IF;

    -- Blocking check (CRITICAL: skip for XXL activities)
    IF v_activity.activity_type != 'xxl' THEN
        RAISE NOTICE 'Checking blocking for non-XXL activity';
        SELECT EXISTS(
            SELECT 1 FROM activity.user_blocks
            WHERE (blocker_user_id = p_user_id AND blocked_user_id = v_activity.organizer_user_id)
               OR (blocker_user_id = v_activity.organizer_user_id AND blocked_user_id = p_user_id)
        ) INTO v_block_exists;

        IF v_block_exists THEN
            RAISE NOTICE 'User is blocked: user_id=%, organizer_id=%', p_user_id, v_activity.organizer_user_id;
            RETURN QUERY SELECT FALSE, NULL::activity.participation_status, NULL::INT,
                'BLOCKED_USER'::VARCHAR(50), 'Cannot join this activity due to blocking'::TEXT;
            RETURN;
        END IF;
    ELSE
        RAISE NOTICE 'XXL activity - blocking check skipped';
    END IF;

    -- Privacy check: friends_only
    IF v_activity.activity_privacy_level = 'friends_only' THEN
        RAISE NOTICE 'Checking friendship for friends_only activity';
        SELECT EXISTS(
            SELECT 1 FROM activity.friendships
            WHERE ((user_id_1 = p_user_id AND user_id_2 = v_activity.organizer_user_id)
                OR (user_id_1 = v_activity.organizer_user_id AND user_id_2 = p_user_id))
              AND status = 'accepted'
        ) INTO v_friendship_exists;

        IF NOT v_friendship_exists THEN
            RAISE NOTICE 'Not friends with organizer for friends_only activity';
            RETURN QUERY SELECT FALSE, NULL::activity.participation_status, NULL::INT,
                'FRIENDS_ONLY'::VARCHAR(50), 'Activity is friends only'::TEXT;
            RETURN;
        END IF;
    END IF;

    -- Privacy check: invite_only
    IF v_activity.activity_privacy_level = 'invite_only' THEN
        RAISE NOTICE 'Checking invitation for invite_only activity';
        SELECT EXISTS(
            SELECT 1 FROM activity.activity_invitations
            WHERE activity_id = p_activity_id
              AND user_id = p_user_id
              AND status = 'pending'
              AND (expires_at IS NULL OR expires_at > NOW())
        ) INTO v_invitation_exists;

        IF NOT v_invitation_exists THEN
            RAISE NOTICE 'No valid invitation for invite_only activity';
            RETURN QUERY SELECT FALSE, NULL::activity.participation_status, NULL::INT,
                'INVITE_ONLY'::VARCHAR(50), 'Activity is invite only'::TEXT;
            RETURN;
        END IF;
    END IF;

    -- Premium priority check
    IF v_activity.joinable_at_free IS NOT NULL AND p_subscription_level = 'free' THEN
        IF NOW() < v_activity.joinable_at_free THEN
            RAISE NOTICE 'Premium only period active: joinable_at_free=%, now=%',
                v_activity.joinable_at_free, NOW();
            RETURN QUERY SELECT FALSE, NULL::activity.participation_status, NULL::INT,
                'PREMIUM_ONLY_PERIOD'::VARCHAR(50), 'Activity is currently only open to Premium members'::TEXT;
            RETURN;
        END IF;
    END IF;

    -- Capacity check
    v_current_count := v_activity.current_participants_count;
    RAISE NOTICE 'Capacity check: current=%, max=%', v_current_count, v_activity.max_participants;

    IF v_current_count >= v_activity.max_participants THEN
        -- Add to waitlist
        RAISE NOTICE 'Activity full - adding to waitlist';

        SELECT COALESCE(MAX(position), 0) + 1 INTO v_next_position
        FROM activity.waitlist_entries
        WHERE activity_id = p_activity_id;

        INSERT INTO activity.waitlist_entries (activity_id, user_id, position)
        VALUES (p_activity_id, p_user_id, v_next_position);

        UPDATE activity.activities
        SET waitlist_count = waitlist_count + 1
        WHERE activity_id = p_activity_id;

        RAISE NOTICE 'Added to waitlist: position=%', v_next_position;

        RETURN QUERY SELECT TRUE, 'waitlisted'::activity.participation_status, v_next_position,
            NULL::VARCHAR(50), NULL::TEXT;
        RETURN;
    ELSE
        -- Add as participant
        RAISE NOTICE 'Spots available - adding as participant';

        INSERT INTO activity.participants (activity_id, user_id, role, participation_status)
        VALUES (p_activity_id, p_user_id, 'member', 'registered');

        UPDATE activity.activities
        SET current_participants_count = current_participants_count + 1
        WHERE activity_id = p_activity_id;

        -- If invite_only, mark invitation as accepted
        IF v_activity.activity_privacy_level = 'invite_only' THEN
            UPDATE activity.activity_invitations
            SET status = 'accepted', responded_at = NOW()
            WHERE activity_id = p_activity_id AND user_id = p_user_id AND status = 'pending';
            RAISE NOTICE 'Marked invitation as accepted';
        END IF;

        RAISE NOTICE 'Successfully joined activity';

        RETURN QUERY SELECT TRUE, 'registered'::activity.participation_status, NULL::INT,
            NULL::VARCHAR(50), NULL::TEXT;
        RETURN;
    END IF;
END;
$$;

-- =====================================================
-- 2. sp_leave_activity
-- =====================================================
CREATE OR REPLACE FUNCTION activity.sp_leave_activity(
    p_activity_id UUID,
    p_user_id UUID
)
RETURNS TABLE (
    success BOOLEAN,
    was_participant BOOLEAN,
    was_waitlisted BOOLEAN,
    promoted_user_id UUID,
    error_code VARCHAR(50),
    error_message TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_activity RECORD;
    v_participant RECORD;
    v_waitlist RECORD;
    v_next_waitlist RECORD;
    v_old_position INT;
BEGIN
    RAISE NOTICE 'sp_leave_activity called: activity_id=%, user_id=%', p_activity_id, p_user_id;

    -- Get activity details
    SELECT * INTO v_activity
    FROM activity.activities
    WHERE activity_id = p_activity_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'Activity not found: %', p_activity_id;
        RETURN QUERY SELECT FALSE, FALSE, FALSE, NULL::UUID,
            'ACTIVITY_NOT_FOUND'::VARCHAR(50), 'Activity does not exist'::TEXT;
        RETURN;
    END IF;

    RAISE NOTICE 'Activity found: title=%, organizer_id=%', v_activity.title, v_activity.organizer_user_id;

    -- Check user is not the organizer
    IF v_activity.organizer_user_id = p_user_id THEN
        RAISE NOTICE 'User is organizer - cannot leave';
        RETURN QUERY SELECT FALSE, FALSE, FALSE, NULL::UUID,
            'IS_ORGANIZER'::VARCHAR(50), 'Organizer cannot leave activity'::TEXT;
        RETURN;
    END IF;

    -- Check activity is not in the past
    IF v_activity.scheduled_at <= NOW() THEN
        RAISE NOTICE 'Activity is in the past: scheduled_at=%', v_activity.scheduled_at;
        RETURN QUERY SELECT FALSE, FALSE, FALSE, NULL::UUID,
            'ACTIVITY_IN_PAST'::VARCHAR(50), 'Cannot leave past activities'::TEXT;
        RETURN;
    END IF;

    -- Check if user is participant
    SELECT * INTO v_participant
    FROM activity.participants
    WHERE activity_id = p_activity_id AND user_id = p_user_id;

    IF FOUND AND v_participant.participation_status = 'registered' THEN
        RAISE NOTICE 'User is registered participant - removing and promoting waitlist';

        -- Delete participant
        DELETE FROM activity.participants
        WHERE activity_id = p_activity_id AND user_id = p_user_id;

        UPDATE activity.activities
        SET current_participants_count = current_participants_count - 1
        WHERE activity_id = p_activity_id;

        -- Promote next from waitlist
        SELECT * INTO v_next_waitlist
        FROM activity.waitlist_entries
        WHERE activity_id = p_activity_id
        ORDER BY position ASC
        LIMIT 1;

        IF FOUND THEN
            RAISE NOTICE 'Promoting from waitlist: user_id=%, position=%',
                v_next_waitlist.user_id, v_next_waitlist.position;

            -- Add promoted user as participant
            INSERT INTO activity.participants (activity_id, user_id, role, participation_status)
            VALUES (p_activity_id, v_next_waitlist.user_id, 'member', 'registered');

            -- Remove from waitlist
            DELETE FROM activity.waitlist_entries
            WHERE waitlist_id = v_next_waitlist.waitlist_id;

            -- Update counts
            UPDATE activity.activities
            SET waitlist_count = waitlist_count - 1,
                current_participants_count = current_participants_count + 1
            WHERE activity_id = p_activity_id;

            -- Update waitlist positions
            UPDATE activity.waitlist_entries
            SET position = position - 1
            WHERE activity_id = p_activity_id;

            RAISE NOTICE 'Waitlist promotion complete';

            RETURN QUERY SELECT TRUE, TRUE, FALSE, v_next_waitlist.user_id,
                NULL::VARCHAR(50), NULL::TEXT;
            RETURN;
        ELSE
            RAISE NOTICE 'No waitlist to promote';
            RETURN QUERY SELECT TRUE, TRUE, FALSE, NULL::UUID,
                NULL::VARCHAR(50), NULL::TEXT;
            RETURN;
        END IF;
    END IF;

    -- Check if user is on waitlist
    SELECT * INTO v_waitlist
    FROM activity.waitlist_entries
    WHERE activity_id = p_activity_id AND user_id = p_user_id;

    IF FOUND THEN
        RAISE NOTICE 'User is on waitlist - removing: position=%', v_waitlist.position;
        v_old_position := v_waitlist.position;

        -- Delete from waitlist
        DELETE FROM activity.waitlist_entries
        WHERE waitlist_id = v_waitlist.waitlist_id;

        UPDATE activity.activities
        SET waitlist_count = waitlist_count - 1
        WHERE activity_id = p_activity_id;

        -- Update positions for users after this one
        UPDATE activity.waitlist_entries
        SET position = position - 1
        WHERE activity_id = p_activity_id AND position > v_old_position;

        RAISE NOTICE 'Removed from waitlist and updated positions';

        RETURN QUERY SELECT TRUE, FALSE, TRUE, NULL::UUID,
            NULL::VARCHAR(50), NULL::TEXT;
        RETURN;
    END IF;

    -- Not a participant or on waitlist
    RAISE NOTICE 'User is not a participant or on waitlist';
    RETURN QUERY SELECT FALSE, FALSE, FALSE, NULL::UUID,
        'NOT_PARTICIPANT'::VARCHAR(50), 'Not a participant of this activity'::TEXT;
    RETURN;
END;
$$;

-- =====================================================
-- 3. sp_cancel_participation
-- =====================================================
CREATE OR REPLACE FUNCTION activity.sp_cancel_participation(
    p_activity_id UUID,
    p_user_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS TABLE (
    success BOOLEAN,
    promoted_user_id UUID,
    error_code VARCHAR(50),
    error_message TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_activity RECORD;
    v_participant RECORD;
    v_next_waitlist RECORD;
BEGIN
    RAISE NOTICE 'sp_cancel_participation called: activity_id=%, user_id=%, reason=%',
        p_activity_id, p_user_id, p_reason;

    -- Get activity details
    SELECT * INTO v_activity
    FROM activity.activities
    WHERE activity_id = p_activity_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'Activity not found: %', p_activity_id;
        RETURN QUERY SELECT FALSE, NULL::UUID,
            'ACTIVITY_NOT_FOUND'::VARCHAR(50), 'Activity does not exist'::TEXT;
        RETURN;
    END IF;

    -- Check activity is not in the past
    IF v_activity.scheduled_at <= NOW() THEN
        RAISE NOTICE 'Activity is in the past: scheduled_at=%', v_activity.scheduled_at;
        RETURN QUERY SELECT FALSE, NULL::UUID,
            'ACTIVITY_IN_PAST'::VARCHAR(50), 'Cannot cancel past activities'::TEXT;
        RETURN;
    END IF;

    -- Check if user is participant
    SELECT * INTO v_participant
    FROM activity.participants
    WHERE activity_id = p_activity_id AND user_id = p_user_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'User is not a participant';
        RETURN QUERY SELECT FALSE, NULL::UUID,
            'NOT_PARTICIPANT'::VARCHAR(50), 'Not a participant of this activity'::TEXT;
        RETURN;
    END IF;

    IF v_participant.participation_status = 'cancelled' THEN
        RAISE NOTICE 'Participation already cancelled';
        RETURN QUERY SELECT FALSE, NULL::UUID,
            'ALREADY_CANCELLED'::VARCHAR(50), 'Participation already cancelled'::TEXT;
        RETURN;
    END IF;

    IF v_participant.participation_status != 'registered' THEN
        RAISE NOTICE 'Participation status is not registered: status=%', v_participant.participation_status;
        RETURN QUERY SELECT FALSE, NULL::UUID,
            'NOT_PARTICIPANT'::VARCHAR(50), 'Not a registered participant'::TEXT;
        RETURN;
    END IF;

    RAISE NOTICE 'Cancelling participation';

    -- Update participation status
    UPDATE activity.participants
    SET participation_status = 'cancelled',
        left_at = NOW(),
        payload = CASE
            WHEN p_reason IS NOT NULL THEN jsonb_set(COALESCE(payload, '{}'::jsonb), '{cancel_reason}', to_jsonb(p_reason))
            ELSE payload
        END
    WHERE activity_id = p_activity_id AND user_id = p_user_id;

    UPDATE activity.activities
    SET current_participants_count = current_participants_count - 1
    WHERE activity_id = p_activity_id;

    RAISE NOTICE 'Participation cancelled, checking waitlist for promotion';

    -- Promote next from waitlist
    SELECT * INTO v_next_waitlist
    FROM activity.waitlist_entries
    WHERE activity_id = p_activity_id
    ORDER BY position ASC
    LIMIT 1;

    IF FOUND THEN
        RAISE NOTICE 'Promoting from waitlist: user_id=%, position=%',
            v_next_waitlist.user_id, v_next_waitlist.position;

        -- Add promoted user as participant
        INSERT INTO activity.participants (activity_id, user_id, role, participation_status)
        VALUES (p_activity_id, v_next_waitlist.user_id, 'member', 'registered');

        -- Remove from waitlist
        DELETE FROM activity.waitlist_entries
        WHERE waitlist_id = v_next_waitlist.waitlist_id;

        -- Update counts
        UPDATE activity.activities
        SET waitlist_count = waitlist_count - 1,
            current_participants_count = current_participants_count + 1
        WHERE activity_id = p_activity_id;

        -- Update waitlist positions
        UPDATE activity.waitlist_entries
        SET position = position - 1
        WHERE activity_id = p_activity_id;

        RAISE NOTICE 'Waitlist promotion complete';

        RETURN QUERY SELECT TRUE, v_next_waitlist.user_id,
            NULL::VARCHAR(50), NULL::TEXT;
        RETURN;
    ELSE
        RAISE NOTICE 'No waitlist to promote';
        RETURN QUERY SELECT TRUE, NULL::UUID,
            NULL::VARCHAR(50), NULL::TEXT;
        RETURN;
    END IF;
END;
$$;

-- =====================================================
-- 4. sp_list_participants
-- =====================================================
CREATE OR REPLACE FUNCTION activity.sp_list_participants(
    p_activity_id UUID,
    p_requesting_user_id UUID,
    p_status activity.participation_status DEFAULT NULL,
    p_role activity.participant_role DEFAULT NULL,
    p_limit INT DEFAULT 50,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    user_id UUID,
    username VARCHAR(100),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    profile_photo_url VARCHAR(500),
    role activity.participant_role,
    participation_status activity.participation_status,
    attendance_status activity.attendance_status,
    joined_at TIMESTAMP WITH TIME ZONE,
    is_verified BOOLEAN,
    verification_count INT,
    total_count BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_activity RECORD;
BEGIN
    RAISE NOTICE 'sp_list_participants called: activity_id=%, requesting_user_id=%, status=%, role=%, limit=%, offset=%',
        p_activity_id, p_requesting_user_id, p_status, p_role, p_limit, p_offset;

    -- Get activity details
    SELECT * INTO v_activity
    FROM activity.activities
    WHERE activity_id = p_activity_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'Activity not found: %', p_activity_id;
        -- Return empty result set with error indicator
        RETURN;
    END IF;

    RAISE NOTICE 'Activity found: title=%', v_activity.title;

    -- Return participants with blocking enforcement
    RETURN QUERY
    SELECT
        u.user_id,
        u.username,
        u.first_name,
        u.last_name,
        u.main_photo_url AS profile_photo_url,
        p.role,
        p.participation_status,
        p.attendance_status,
        p.joined_at,
        u.is_verified,
        u.verification_count,
        COUNT(*) OVER() AS total_count
    FROM activity.participants p
    JOIN activity.users u ON p.user_id = u.user_id
    WHERE p.activity_id = p_activity_id
        -- Blocking check: hide blocked users
        AND NOT EXISTS (
            SELECT 1 FROM activity.user_blocks
            WHERE (blocker_user_id = p_requesting_user_id AND blocked_user_id = p.user_id)
               OR (blocker_user_id = p.user_id AND blocked_user_id = p_requesting_user_id)
        )
        -- Optional filters
        AND (p_status IS NULL OR p.participation_status = p_status)
        AND (p_role IS NULL OR p.role = p_role)
    ORDER BY
        CASE p.role
            WHEN 'organizer' THEN 1
            WHEN 'co_organizer' THEN 2
            ELSE 3
        END,
        p.joined_at ASC
    LIMIT p_limit OFFSET p_offset;

    RAISE NOTICE 'Participants list returned';
END;
$$;

-- =====================================================
-- 5. sp_get_user_activities
-- =====================================================
CREATE OR REPLACE FUNCTION activity.sp_get_user_activities(
    p_target_user_id UUID,
    p_requesting_user_id UUID,
    p_type VARCHAR(20) DEFAULT NULL,
    p_status activity.participation_status DEFAULT NULL,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    activity_id UUID,
    title VARCHAR(255),
    scheduled_at TIMESTAMP WITH TIME ZONE,
    location_name VARCHAR(255),
    city VARCHAR(100),
    organizer_user_id UUID,
    organizer_username VARCHAR(100),
    current_participants_count INT,
    max_participants INT,
    activity_type activity.activity_type,
    role activity.participant_role,
    participation_status activity.participation_status,
    attendance_status activity.attendance_status,
    joined_at TIMESTAMP WITH TIME ZONE,
    total_count BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_is_blocked BOOLEAN;
BEGIN
    RAISE NOTICE 'sp_get_user_activities called: target_user_id=%, requesting_user_id=%, type=%, status=%, limit=%, offset=%',
        p_target_user_id, p_requesting_user_id, p_type, p_status, p_limit, p_offset;

    -- Privacy check: if requesting different user, check blocking
    IF p_requesting_user_id != p_target_user_id THEN
        SELECT EXISTS(
            SELECT 1 FROM activity.user_blocks
            WHERE (blocker_user_id = p_requesting_user_id AND blocked_user_id = p_target_user_id)
               OR (blocker_user_id = p_target_user_id AND blocked_user_id = p_requesting_user_id)
        ) INTO v_is_blocked;

        IF v_is_blocked THEN
            RAISE NOTICE 'User is blocked - returning empty result';
            RETURN;
        END IF;
    END IF;

    RAISE NOTICE 'Privacy check passed, querying activities';

    -- Return activities
    RETURN QUERY
    SELECT
        a.activity_id,
        a.title,
        a.scheduled_at,
        a.location_name,
        a.city,
        a.organizer_user_id,
        u.username AS organizer_username,
        a.current_participants_count,
        a.max_participants,
        a.activity_type,
        p.role,
        p.participation_status,
        p.attendance_status,
        p.joined_at,
        COUNT(*) OVER() AS total_count
    FROM activity.participants p
    JOIN activity.activities a ON p.activity_id = a.activity_id
    JOIN activity.users u ON a.organizer_user_id = u.user_id
    WHERE p.user_id = p_target_user_id
        AND a.status != 'draft'  -- Hide drafts
        -- Type filters
        AND (p_type IS NULL
            OR (p_type = 'upcoming' AND a.scheduled_at > NOW())
            OR (p_type = 'past' AND a.scheduled_at <= NOW())
            OR (p_type = 'organized' AND a.organizer_user_id = p_target_user_id)
            OR (p_type = 'attended' AND p.attendance_status = 'attended')
        )
        -- Status filter
        AND (p_status IS NULL OR p.participation_status = p_status)
    ORDER BY a.scheduled_at DESC
    LIMIT p_limit OFFSET p_offset;

    RAISE NOTICE 'User activities returned';
END;
$$;

-- =====================================================
-- 6. sp_promote_participant
-- =====================================================
CREATE OR REPLACE FUNCTION activity.sp_promote_participant(
    p_activity_id UUID,
    p_organizer_user_id UUID,
    p_target_user_id UUID
)
RETURNS TABLE (
    success BOOLEAN,
    error_code VARCHAR(50),
    error_message TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_activity RECORD;
    v_participant RECORD;
BEGIN
    RAISE NOTICE 'sp_promote_participant called: activity_id=%, organizer_user_id=%, target_user_id=%',
        p_activity_id, p_organizer_user_id, p_target_user_id;

    -- Get activity details
    SELECT * INTO v_activity
    FROM activity.activities
    WHERE activity_id = p_activity_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'Activity not found: %', p_activity_id;
        RETURN QUERY SELECT FALSE,
            'ACTIVITY_NOT_FOUND'::VARCHAR(50), 'Activity does not exist'::TEXT;
        RETURN;
    END IF;

    -- Check requesting user is organizer
    IF v_activity.organizer_user_id != p_organizer_user_id THEN
        RAISE NOTICE 'User is not organizer: user_id=%, actual_organizer=%',
            p_organizer_user_id, v_activity.organizer_user_id;
        RETURN QUERY SELECT FALSE,
            'NOT_ORGANIZER'::VARCHAR(50), 'Only organizer can promote participants'::TEXT;
        RETURN;
    END IF;

    -- Get target participant
    SELECT * INTO v_participant
    FROM activity.participants
    WHERE activity_id = p_activity_id AND user_id = p_target_user_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'Target user is not a participant';
        RETURN QUERY SELECT FALSE,
            'TARGET_NOT_MEMBER'::VARCHAR(50), 'User is not a member participant'::TEXT;
        RETURN;
    END IF;

    -- Check target is a member with registered status
    IF v_participant.role != 'member' THEN
        IF v_participant.role = 'co_organizer' THEN
            RAISE NOTICE 'Target user is already co-organizer';
            RETURN QUERY SELECT FALSE,
                'ALREADY_CO_ORGANIZER'::VARCHAR(50), 'User is already a co-organizer'::TEXT;
            RETURN;
        END IF;

        RAISE NOTICE 'Target user is not a member: role=%', v_participant.role;
        RETURN QUERY SELECT FALSE,
            'TARGET_NOT_MEMBER'::VARCHAR(50), 'User is not a member participant'::TEXT;
        RETURN;
    END IF;

    IF v_participant.participation_status != 'registered' THEN
        RAISE NOTICE 'Target user is not registered: status=%', v_participant.participation_status;
        RETURN QUERY SELECT FALSE,
            'TARGET_NOT_MEMBER'::VARCHAR(50), 'User is not a registered participant'::TEXT;
        RETURN;
    END IF;

    -- Promote to co-organizer
    RAISE NOTICE 'Promoting user to co-organizer';
    UPDATE activity.participants
    SET role = 'co_organizer'
    WHERE activity_id = p_activity_id AND user_id = p_target_user_id;

    RAISE NOTICE 'User promoted successfully';

    RETURN QUERY SELECT TRUE,
        NULL::VARCHAR(50), NULL::TEXT;
    RETURN;
END;
$$;

-- =====================================================
-- 7. sp_demote_participant
-- =====================================================
CREATE OR REPLACE FUNCTION activity.sp_demote_participant(
    p_activity_id UUID,
    p_organizer_user_id UUID,
    p_target_user_id UUID
)
RETURNS TABLE (
    success BOOLEAN,
    error_code VARCHAR(50),
    error_message TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_activity RECORD;
    v_participant RECORD;
BEGIN
    RAISE NOTICE 'sp_demote_participant called: activity_id=%, organizer_user_id=%, target_user_id=%',
        p_activity_id, p_organizer_user_id, p_target_user_id;

    -- Get activity details
    SELECT * INTO v_activity
    FROM activity.activities
    WHERE activity_id = p_activity_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'Activity not found: %', p_activity_id;
        RETURN QUERY SELECT FALSE,
            'ACTIVITY_NOT_FOUND'::VARCHAR(50), 'Activity does not exist'::TEXT;
        RETURN;
    END IF;

    -- Check requesting user is organizer
    IF v_activity.organizer_user_id != p_organizer_user_id THEN
        RAISE NOTICE 'User is not organizer: user_id=%, actual_organizer=%',
            p_organizer_user_id, v_activity.organizer_user_id;
        RETURN QUERY SELECT FALSE,
            'NOT_ORGANIZER'::VARCHAR(50), 'Only organizer can demote participants'::TEXT;
        RETURN;
    END IF;

    -- Get target participant
    SELECT * INTO v_participant
    FROM activity.participants
    WHERE activity_id = p_activity_id AND user_id = p_target_user_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'Target user is not a participant';
        RETURN QUERY SELECT FALSE,
            'NOT_CO_ORGANIZER'::VARCHAR(50), 'User is not a co-organizer'::TEXT;
        RETURN;
    END IF;

    -- Check target is a co-organizer
    IF v_participant.role != 'co_organizer' THEN
        RAISE NOTICE 'Target user is not co-organizer: role=%', v_participant.role;
        RETURN QUERY SELECT FALSE,
            'NOT_CO_ORGANIZER'::VARCHAR(50), 'User is not a co-organizer'::TEXT;
        RETURN;
    END IF;

    -- Demote to member
    RAISE NOTICE 'Demoting user to member';
    UPDATE activity.participants
    SET role = 'member'
    WHERE activity_id = p_activity_id AND user_id = p_target_user_id;

    RAISE NOTICE 'User demoted successfully';

    RETURN QUERY SELECT TRUE,
        NULL::VARCHAR(50), NULL::TEXT;
    RETURN;
END;
$$;

-- =====================================================
-- 8. sp_mark_attendance
-- =====================================================
CREATE OR REPLACE FUNCTION activity.sp_mark_attendance(
    p_activity_id UUID,
    p_marking_user_id UUID,
    p_attendances JSONB
)
RETURNS TABLE (
    success BOOLEAN,
    updated_count INT,
    failed_updates JSONB,
    error_code VARCHAR(50),
    error_message TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_activity RECORD;
    v_marking_participant RECORD;
    v_attendance JSONB;
    v_target_user_id UUID;
    v_target_status activity.attendance_status;
    v_update_count INT := 0;
    v_failed_array JSONB := '[]'::jsonb;
    v_attendance_count INT;
BEGIN
    RAISE NOTICE 'sp_mark_attendance called: activity_id=%, marking_user_id=%, attendance_count=%',
        p_activity_id, p_marking_user_id, jsonb_array_length(p_attendances);

    -- Count attendances
    v_attendance_count := jsonb_array_length(p_attendances);

    IF v_attendance_count > 100 THEN
        RAISE NOTICE 'Too many attendance updates: count=%', v_attendance_count;
        RETURN QUERY SELECT FALSE, 0, NULL::JSONB,
            'TOO_MANY_UPDATES'::VARCHAR(50), 'Maximum 100 attendances per request'::TEXT;
        RETURN;
    END IF;

    -- Get activity details
    SELECT * INTO v_activity
    FROM activity.activities
    WHERE activity_id = p_activity_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'Activity not found: %', p_activity_id;
        RETURN QUERY SELECT FALSE, 0, NULL::JSONB,
            'ACTIVITY_NOT_FOUND'::VARCHAR(50), 'Activity does not exist'::TEXT;
        RETURN;
    END IF;

    -- Check activity has completed
    IF v_activity.scheduled_at > NOW() THEN
        RAISE NOTICE 'Activity has not completed: scheduled_at=%', v_activity.scheduled_at;
        RETURN QUERY SELECT FALSE, 0, NULL::JSONB,
            'ACTIVITY_NOT_COMPLETED'::VARCHAR(50), 'Activity has not yet completed'::TEXT;
        RETURN;
    END IF;

    -- Check marking user is organizer or co-organizer
    SELECT * INTO v_marking_participant
    FROM activity.participants
    WHERE activity_id = p_activity_id AND user_id = p_marking_user_id;

    IF NOT FOUND OR (v_marking_participant.role != 'organizer' AND v_marking_participant.role != 'co_organizer') THEN
        RAISE NOTICE 'User is not authorized to mark attendance: role=%',
            COALESCE(v_marking_participant.role::TEXT, 'none');
        RETURN QUERY SELECT FALSE, 0, NULL::JSONB,
            'NOT_AUTHORIZED'::VARCHAR(50), 'Only organizer or co-organizer can mark attendance'::TEXT;
        RETURN;
    END IF;

    RAISE NOTICE 'Authorization passed, processing % attendances', v_attendance_count;

    -- Process each attendance
    FOR v_attendance IN SELECT * FROM jsonb_array_elements(p_attendances)
    LOOP
        v_target_user_id := (v_attendance->>'user_id')::UUID;
        v_target_status := (v_attendance->>'status')::activity.attendance_status;

        RAISE NOTICE 'Processing attendance: user_id=%, status=%', v_target_user_id, v_target_status;

        -- Check if user is a registered participant
        IF EXISTS (
            SELECT 1 FROM activity.participants
            WHERE activity_id = p_activity_id
              AND user_id = v_target_user_id
              AND participation_status = 'registered'
        ) THEN
            -- Update attendance status
            UPDATE activity.participants
            SET attendance_status = v_target_status
            WHERE activity_id = p_activity_id AND user_id = v_target_user_id;

            -- If no_show, increment user's no_show_count
            IF v_target_status = 'no_show' THEN
                UPDATE activity.users
                SET no_show_count = no_show_count + 1
                WHERE user_id = v_target_user_id;
                RAISE NOTICE 'Incremented no_show_count for user: %', v_target_user_id;
            END IF;

            v_update_count := v_update_count + 1;
            RAISE NOTICE 'Updated attendance successfully';
        ELSE
            -- Add to failed updates
            v_failed_array := v_failed_array || jsonb_build_object(
                'user_id', v_target_user_id,
                'reason', 'Not a registered participant'
            );
            RAISE NOTICE 'Failed to update - not a registered participant';
        END IF;
    END LOOP;

    RAISE NOTICE 'Attendance marking complete: updated=%, failed=%',
        v_update_count, jsonb_array_length(v_failed_array);

    RETURN QUERY SELECT TRUE, v_update_count, v_failed_array,
        NULL::VARCHAR(50), NULL::TEXT;
    RETURN;
END;
$$;

-- =====================================================
-- 9. sp_confirm_attendance
-- =====================================================
CREATE OR REPLACE FUNCTION activity.sp_confirm_attendance(
    p_activity_id UUID,
    p_confirmed_user_id UUID,
    p_confirmer_user_id UUID
)
RETURNS TABLE (
    success BOOLEAN,
    confirmation_id UUID,
    new_verification_count INT,
    error_code VARCHAR(50),
    error_message TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_activity RECORD;
    v_confirmed_participant RECORD;
    v_confirmer_participant RECORD;
    v_new_confirmation_id UUID;
    v_verification_count INT;
    v_already_confirmed BOOLEAN;
BEGIN
    RAISE NOTICE 'sp_confirm_attendance called: activity_id=%, confirmed_user_id=%, confirmer_user_id=%',
        p_activity_id, p_confirmed_user_id, p_confirmer_user_id;

    -- Check not confirming self
    IF p_confirmed_user_id = p_confirmer_user_id THEN
        RAISE NOTICE 'Cannot confirm own attendance';
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::INT,
            'SELF_CONFIRMATION'::VARCHAR(50), 'Cannot confirm your own attendance'::TEXT;
        RETURN;
    END IF;

    -- Get activity details
    SELECT * INTO v_activity
    FROM activity.activities
    WHERE activity_id = p_activity_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'Activity not found: %', p_activity_id;
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::INT,
            'ACTIVITY_NOT_FOUND'::VARCHAR(50), 'Activity does not exist'::TEXT;
        RETURN;
    END IF;

    -- Check activity has completed
    IF v_activity.scheduled_at > NOW() THEN
        RAISE NOTICE 'Activity has not completed: scheduled_at=%', v_activity.scheduled_at;
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::INT,
            'ACTIVITY_NOT_COMPLETED'::VARCHAR(50), 'Activity has not yet completed'::TEXT;
        RETURN;
    END IF;

    -- Check confirmer attended
    SELECT * INTO v_confirmer_participant
    FROM activity.participants
    WHERE activity_id = p_activity_id AND user_id = p_confirmer_user_id;

    IF NOT FOUND OR v_confirmer_participant.attendance_status != 'attended' THEN
        RAISE NOTICE 'Confirmer did not attend: status=%',
            COALESCE(v_confirmer_participant.attendance_status::TEXT, 'none');
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::INT,
            'CONFIRMER_NOT_ATTENDED'::VARCHAR(50), 'You must have attended status to confirm others'::TEXT;
        RETURN;
    END IF;

    -- Check confirmed user attended
    SELECT * INTO v_confirmed_participant
    FROM activity.participants
    WHERE activity_id = p_activity_id AND user_id = p_confirmed_user_id;

    IF NOT FOUND OR v_confirmed_participant.attendance_status != 'attended' THEN
        RAISE NOTICE 'Confirmed user did not attend: status=%',
            COALESCE(v_confirmed_participant.attendance_status::TEXT, 'none');
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::INT,
            'CONFIRMED_NOT_ATTENDED'::VARCHAR(50), 'User does not have attended status'::TEXT;
        RETURN;
    END IF;

    -- Check if already confirmed
    SELECT EXISTS(
        SELECT 1 FROM activity.attendance_confirmations
        WHERE activity_id = p_activity_id
          AND confirmed_user_id = p_confirmed_user_id
          AND confirmer_user_id = p_confirmer_user_id
    ) INTO v_already_confirmed;

    IF v_already_confirmed THEN
        RAISE NOTICE 'Already confirmed this user';
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::INT,
            'ALREADY_CONFIRMED'::VARCHAR(50), 'You already confirmed this user for this activity'::TEXT;
        RETURN;
    END IF;

    -- Insert confirmation
    RAISE NOTICE 'Creating attendance confirmation';
    INSERT INTO activity.attendance_confirmations (activity_id, confirmed_user_id, confirmer_user_id)
    VALUES (p_activity_id, p_confirmed_user_id, p_confirmer_user_id)
    RETURNING confirmation_id INTO v_new_confirmation_id;

    -- Update user's verification count
    UPDATE activity.users
    SET verification_count = verification_count + 1
    WHERE user_id = p_confirmed_user_id
    RETURNING verification_count INTO v_verification_count;

    RAISE NOTICE 'Attendance confirmed: confirmation_id=%, new_verification_count=%',
        v_new_confirmation_id, v_verification_count;

    RETURN QUERY SELECT TRUE, v_new_confirmation_id, v_verification_count,
        NULL::VARCHAR(50), NULL::TEXT;
    RETURN;
END;
$$;

-- =====================================================
-- 10. sp_get_pending_verifications
-- =====================================================
CREATE OR REPLACE FUNCTION activity.sp_get_pending_verifications(
    p_user_id UUID,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    activity_id UUID,
    title VARCHAR(255),
    scheduled_at TIMESTAMP WITH TIME ZONE,
    participants_to_confirm JSONB,
    total_count BIGINT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE NOTICE 'sp_get_pending_verifications called: user_id=%, limit=%, offset=%',
        p_user_id, p_limit, p_offset;

    RETURN QUERY
    WITH user_attended_activities AS (
        SELECT a.activity_id, a.title, a.scheduled_at
        FROM activity.participants p
        JOIN activity.activities a ON p.activity_id = a.activity_id
        WHERE p.user_id = p_user_id
            AND p.attendance_status = 'attended'
            AND a.scheduled_at <= NOW()
    )
    SELECT
        uaa.activity_id,
        uaa.title,
        uaa.scheduled_at,
        -- Get participants that user hasn't confirmed yet
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'user_id', u.user_id,
                    'username', u.username,
                    'first_name', u.first_name,
                    'profile_photo_url', u.main_photo_url
                )
            )
            FROM activity.participants p2
            JOIN activity.users u ON p2.user_id = u.user_id
            WHERE p2.activity_id = uaa.activity_id
                AND p2.attendance_status = 'attended'
                AND p2.user_id != p_user_id
                AND NOT EXISTS (
                    SELECT 1 FROM activity.attendance_confirmations
                    WHERE activity_id = uaa.activity_id
                        AND confirmed_user_id = p2.user_id
                        AND confirmer_user_id = p_user_id
                )
        ) AS participants_to_confirm,
        COUNT(*) OVER() AS total_count
    FROM user_attended_activities uaa
    WHERE (
        SELECT jsonb_agg(
            jsonb_build_object(
                'user_id', u.user_id,
                'username', u.username,
                'first_name', u.first_name,
                'profile_photo_url', u.main_photo_url
            )
        )
        FROM activity.participants p2
        JOIN activity.users u ON p2.user_id = u.user_id
        WHERE p2.activity_id = uaa.activity_id
            AND p2.attendance_status = 'attended'
            AND p2.user_id != p_user_id
            AND NOT EXISTS (
                SELECT 1 FROM activity.attendance_confirmations
                WHERE activity_id = uaa.activity_id
                    AND confirmed_user_id = p2.user_id
                    AND confirmer_user_id = p_user_id
            )
    ) IS NOT NULL  -- Only activities with unconfirmed participants
    ORDER BY uaa.scheduled_at DESC
    LIMIT p_limit OFFSET p_offset;

    RAISE NOTICE 'Pending verifications returned';
END;
$$;

-- =====================================================
-- 11. sp_send_invitations
-- =====================================================
CREATE OR REPLACE FUNCTION activity.sp_send_invitations(
    p_activity_id UUID,
    p_inviting_user_id UUID,
    p_user_ids UUID[],
    p_message TEXT DEFAULT NULL,
    p_expires_in_hours INT DEFAULT 72
)
RETURNS TABLE (
    success BOOLEAN,
    invited_count INT,
    failed_count INT,
    invitations JSONB,
    failed_invitations JSONB,
    error_code VARCHAR(50),
    error_message TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_activity RECORD;
    v_inviting_participant RECORD;
    v_user_id UUID;
    v_user_exists BOOLEAN;
    v_already_invited BOOLEAN;
    v_already_participant BOOLEAN;
    v_is_blocked BOOLEAN;
    v_invite_count INT := 0;
    v_fail_count INT := 0;
    v_invitations_array JSONB := '[]'::jsonb;
    v_failed_array JSONB := '[]'::jsonb;
    v_new_invitation_id UUID;
    v_expires_at TIMESTAMP WITH TIME ZONE;
BEGIN
    RAISE NOTICE 'sp_send_invitations called: activity_id=%, inviting_user_id=%, user_count=%, expires_in_hours=%',
        p_activity_id, p_inviting_user_id, array_length(p_user_ids, 1), p_expires_in_hours;

    -- Check max invitations
    IF array_length(p_user_ids, 1) > 50 THEN
        RAISE NOTICE 'Too many invitations: count=%', array_length(p_user_ids, 1);
        RETURN QUERY SELECT FALSE, 0, 0, NULL::JSONB, NULL::JSONB,
            'TOO_MANY_INVITATIONS'::VARCHAR(50), 'Maximum 50 invitations per request'::TEXT;
        RETURN;
    END IF;

    -- Get activity details
    SELECT * INTO v_activity
    FROM activity.activities
    WHERE activity_id = p_activity_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'Activity not found: %', p_activity_id;
        RETURN QUERY SELECT FALSE, 0, 0, NULL::JSONB, NULL::JSONB,
            'ACTIVITY_NOT_FOUND'::VARCHAR(50), 'Activity does not exist'::TEXT;
        RETURN;
    END IF;

    -- Check activity is published
    IF v_activity.status != 'published' THEN
        RAISE NOTICE 'Activity not published: status=%', v_activity.status;
        RETURN QUERY SELECT FALSE, 0, 0, NULL::JSONB, NULL::JSONB,
            'ACTIVITY_NOT_FOUND'::VARCHAR(50), 'Activity is not published'::TEXT;
        RETURN;
    END IF;

    -- Check activity is invite_only
    IF v_activity.activity_privacy_level != 'invite_only' THEN
        RAISE NOTICE 'Activity is not invite_only: activity_privacy_level=%', v_activity.activity_privacy_level;
        RETURN QUERY SELECT FALSE, 0, 0, NULL::JSONB, NULL::JSONB,
            'NOT_INVITE_ONLY'::VARCHAR(50), 'Activity is not invite-only'::TEXT;
        RETURN;
    END IF;

    -- Check inviting user is organizer or co-organizer
    SELECT * INTO v_inviting_participant
    FROM activity.participants
    WHERE activity_id = p_activity_id AND user_id = p_inviting_user_id;

    IF NOT FOUND OR (v_inviting_participant.role != 'organizer' AND v_inviting_participant.role != 'co_organizer') THEN
        RAISE NOTICE 'User is not authorized to send invitations: role=%',
            COALESCE(v_inviting_participant.role::TEXT, 'none');
        RETURN QUERY SELECT FALSE, 0, 0, NULL::JSONB, NULL::JSONB,
            'NOT_AUTHORIZED'::VARCHAR(50), 'Only organizer or co-organizer can send invitations'::TEXT;
        RETURN;
    END IF;

    -- Calculate expiry
    v_expires_at := NOW() + (p_expires_in_hours * INTERVAL '1 hour');
    RAISE NOTICE 'Invitations will expire at: %', v_expires_at;

    -- Process each user
    FOREACH v_user_id IN ARRAY p_user_ids
    LOOP
        RAISE NOTICE 'Processing invitation for user: %', v_user_id;

        -- Check user exists
        SELECT EXISTS(SELECT 1 FROM activity.users WHERE user_id = v_user_id) INTO v_user_exists;
        IF NOT v_user_exists THEN
            v_failed_array := v_failed_array || jsonb_build_object(
                'user_id', v_user_id,
                'reason', 'User does not exist'
            );
            v_fail_count := v_fail_count + 1;
            RAISE NOTICE 'User does not exist: %', v_user_id;
            CONTINUE;
        END IF;

        -- Check not already invited
        SELECT EXISTS(
            SELECT 1 FROM activity.activity_invitations
            WHERE activity_id = p_activity_id
              AND user_id = v_user_id
              AND status = 'pending'
        ) INTO v_already_invited;

        IF v_already_invited THEN
            v_failed_array := v_failed_array || jsonb_build_object(
                'user_id', v_user_id,
                'reason', 'Already invited'
            );
            v_fail_count := v_fail_count + 1;
            RAISE NOTICE 'User already invited: %', v_user_id;
            CONTINUE;
        END IF;

        -- Check not already participant
        SELECT EXISTS(
            SELECT 1 FROM activity.participants
            WHERE activity_id = p_activity_id AND user_id = v_user_id
        ) INTO v_already_participant;

        IF v_already_participant THEN
            v_failed_array := v_failed_array || jsonb_build_object(
                'user_id', v_user_id,
                'reason', 'Already a participant'
            );
            v_fail_count := v_fail_count + 1;
            RAISE NOTICE 'User already participant: %', v_user_id;
            CONTINUE;
        END IF;

        -- Check not blocked
        SELECT EXISTS(
            SELECT 1 FROM activity.user_blocks
            WHERE (blocker_user_id = p_inviting_user_id AND blocked_user_id = v_user_id)
               OR (blocker_user_id = v_user_id AND blocked_user_id = p_inviting_user_id)
        ) INTO v_is_blocked;

        IF v_is_blocked THEN
            v_failed_array := v_failed_array || jsonb_build_object(
                'user_id', v_user_id,
                'reason', 'User is blocked'
            );
            v_fail_count := v_fail_count + 1;
            RAISE NOTICE 'User is blocked: %', v_user_id;
            CONTINUE;
        END IF;

        -- Create invitation
        INSERT INTO activity.activity_invitations (
            activity_id, user_id, invited_by_user_id, message, expires_at
        )
        VALUES (
            p_activity_id, v_user_id, p_inviting_user_id, p_message, v_expires_at
        )
        RETURNING invitation_id INTO v_new_invitation_id;

        v_invitations_array := v_invitations_array || jsonb_build_object(
            'invitation_id', v_new_invitation_id,
            'user_id', v_user_id,
            'status', 'pending',
            'invited_at', NOW(),
            'expires_at', v_expires_at
        );
        v_invite_count := v_invite_count + 1;
        RAISE NOTICE 'Invitation created: invitation_id=%', v_new_invitation_id;
    END LOOP;

    RAISE NOTICE 'Invitations processing complete: invited=%, failed=%', v_invite_count, v_fail_count;

    RETURN QUERY SELECT TRUE, v_invite_count, v_fail_count,
        v_invitations_array, v_failed_array,
        NULL::VARCHAR(50), NULL::TEXT;
    RETURN;
END;
$$;

-- =====================================================
-- 12. sp_accept_invitation
-- =====================================================
CREATE OR REPLACE FUNCTION activity.sp_accept_invitation(
    p_invitation_id UUID,
    p_user_id UUID
)
RETURNS TABLE (
    success BOOLEAN,
    activity_id UUID,
    participation_status activity.participation_status,
    waitlist_position INT,
    error_code VARCHAR(50),
    error_message TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_invitation RECORD;
    v_activity RECORD;
    v_current_count INT;
    v_next_position INT;
BEGIN
    RAISE NOTICE 'sp_accept_invitation called: invitation_id=%, user_id=%', p_invitation_id, p_user_id;

    -- Get invitation details
    SELECT * INTO v_invitation
    FROM activity.activity_invitations
    WHERE invitation_id = p_invitation_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'Invitation not found: %', p_invitation_id;
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::activity.participation_status, NULL::INT,
            'INVITATION_NOT_FOUND'::VARCHAR(50), 'Invitation does not exist'::TEXT;
        RETURN;
    END IF;

    RAISE NOTICE 'Invitation found: activity_id=%, user_id=%, status=%',
        v_invitation.activity_id, v_invitation.user_id, v_invitation.status;

    -- Check invitation is for this user
    IF v_invitation.user_id != p_user_id THEN
        RAISE NOTICE 'Invitation is for different user: expected=%, actual=%',
            v_invitation.user_id, p_user_id;
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::activity.participation_status, NULL::INT,
            'NOT_YOUR_INVITATION'::VARCHAR(50), 'This invitation is not for you'::TEXT;
        RETURN;
    END IF;

    -- Check invitation status
    IF v_invitation.status != 'pending' THEN
        RAISE NOTICE 'Invitation already responded: status=%', v_invitation.status;
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::activity.participation_status, NULL::INT,
            'ALREADY_RESPONDED'::VARCHAR(50), 'Invitation already responded to'::TEXT;
        RETURN;
    END IF;

    -- Check invitation not expired
    IF v_invitation.expires_at IS NOT NULL AND v_invitation.expires_at <= NOW() THEN
        RAISE NOTICE 'Invitation expired: expires_at=%', v_invitation.expires_at;
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::activity.participation_status, NULL::INT,
            'INVITATION_EXPIRED'::VARCHAR(50), 'Invitation has expired'::TEXT;
        RETURN;
    END IF;

    -- Get activity details
    SELECT * INTO v_activity
    FROM activity.activities
    WHERE activity_id = v_invitation.activity_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'Activity not found: %', v_invitation.activity_id;
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::activity.participation_status, NULL::INT,
            'INVITATION_NOT_FOUND'::VARCHAR(50), 'Activity does not exist'::TEXT;
        RETURN;
    END IF;

    -- Check activity not in past
    IF v_activity.scheduled_at <= NOW() THEN
        RAISE NOTICE 'Activity is in the past: scheduled_at=%', v_activity.scheduled_at;
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::activity.participation_status, NULL::INT,
            'ACTIVITY_IN_PAST'::VARCHAR(50), 'Activity has already occurred'::TEXT;
        RETURN;
    END IF;

    -- Accept invitation
    RAISE NOTICE 'Accepting invitation';
    UPDATE activity.activity_invitations
    SET status = 'accepted', responded_at = NOW()
    WHERE invitation_id = p_invitation_id;

    -- Join activity (check capacity)
    v_current_count := v_activity.current_participants_count;
    RAISE NOTICE 'Capacity check: current=%, max=%', v_current_count, v_activity.max_participants;

    IF v_current_count >= v_activity.max_participants THEN
        -- Add to waitlist
        RAISE NOTICE 'Activity full - adding to waitlist';

        SELECT COALESCE(MAX(position), 0) + 1 INTO v_next_position
        FROM activity.waitlist_entries
        WHERE activity_id = v_invitation.activity_id;

        INSERT INTO activity.waitlist_entries (activity_id, user_id, position)
        VALUES (v_invitation.activity_id, p_user_id, v_next_position);

        UPDATE activity.activities
        SET waitlist_count = waitlist_count + 1
        WHERE activity_id = v_invitation.activity_id;

        RAISE NOTICE 'Invitation accepted and added to waitlist: position=%', v_next_position;

        RETURN QUERY SELECT TRUE, v_invitation.activity_id,
            'waitlisted'::activity.participation_status, v_next_position,
            NULL::VARCHAR(50), NULL::TEXT;
        RETURN;
    ELSE
        -- Add as participant
        RAISE NOTICE 'Spots available - adding as participant';

        INSERT INTO activity.participants (activity_id, user_id, role, participation_status)
        VALUES (v_invitation.activity_id, p_user_id, 'member', 'registered');

        UPDATE activity.activities
        SET current_participants_count = current_participants_count + 1
        WHERE activity_id = v_invitation.activity_id;

        RAISE NOTICE 'Invitation accepted and joined activity';

        RETURN QUERY SELECT TRUE, v_invitation.activity_id,
            'registered'::activity.participation_status, NULL::INT,
            NULL::VARCHAR(50), NULL::TEXT;
        RETURN;
    END IF;
END;
$$;

-- =====================================================
-- 13. sp_decline_invitation
-- =====================================================
CREATE OR REPLACE FUNCTION activity.sp_decline_invitation(
    p_invitation_id UUID,
    p_user_id UUID
)
RETURNS TABLE (
    success BOOLEAN,
    activity_id UUID,
    error_code VARCHAR(50),
    error_message TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_invitation RECORD;
BEGIN
    RAISE NOTICE 'sp_decline_invitation called: invitation_id=%, user_id=%', p_invitation_id, p_user_id;

    -- Get invitation details
    SELECT * INTO v_invitation
    FROM activity.activity_invitations
    WHERE invitation_id = p_invitation_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'Invitation not found: %', p_invitation_id;
        RETURN QUERY SELECT FALSE, NULL::UUID,
            'INVITATION_NOT_FOUND'::VARCHAR(50), 'Invitation does not exist'::TEXT;
        RETURN;
    END IF;

    RAISE NOTICE 'Invitation found: activity_id=%, user_id=%, status=%',
        v_invitation.activity_id, v_invitation.user_id, v_invitation.status;

    -- Check invitation is for this user
    IF v_invitation.user_id != p_user_id THEN
        RAISE NOTICE 'Invitation is for different user: expected=%, actual=%',
            v_invitation.user_id, p_user_id;
        RETURN QUERY SELECT FALSE, NULL::UUID,
            'NOT_YOUR_INVITATION'::VARCHAR(50), 'This invitation is not for you'::TEXT;
        RETURN;
    END IF;

    -- Check invitation status
    IF v_invitation.status != 'pending' THEN
        RAISE NOTICE 'Invitation already responded: status=%', v_invitation.status;
        RETURN QUERY SELECT FALSE, NULL::UUID,
            'ALREADY_RESPONDED'::VARCHAR(50), 'Invitation already responded to'::TEXT;
        RETURN;
    END IF;

    -- Decline invitation
    RAISE NOTICE 'Declining invitation';
    UPDATE activity.activity_invitations
    SET status = 'declined', responded_at = NOW()
    WHERE invitation_id = p_invitation_id;

    RAISE NOTICE 'Invitation declined successfully';

    RETURN QUERY SELECT TRUE, v_invitation.activity_id,
        NULL::VARCHAR(50), NULL::TEXT;
    RETURN;
END;
$$;

-- =====================================================
-- 14. sp_cancel_invitation
-- =====================================================
CREATE OR REPLACE FUNCTION activity.sp_cancel_invitation(
    p_invitation_id UUID,
    p_cancelling_user_id UUID
)
RETURNS TABLE (
    success BOOLEAN,
    activity_id UUID,
    error_code VARCHAR(50),
    error_message TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_invitation RECORD;
    v_activity RECORD;
    v_participant RECORD;
    v_is_authorized BOOLEAN := FALSE;
BEGIN
    RAISE NOTICE 'sp_cancel_invitation called: invitation_id=%, cancelling_user_id=%',
        p_invitation_id, p_cancelling_user_id;

    -- Get invitation details
    SELECT * INTO v_invitation
    FROM activity.activity_invitations
    WHERE invitation_id = p_invitation_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'Invitation not found: %', p_invitation_id;
        RETURN QUERY SELECT FALSE, NULL::UUID,
            'INVITATION_NOT_FOUND'::VARCHAR(50), 'Invitation does not exist'::TEXT;
        RETURN;
    END IF;

    RAISE NOTICE 'Invitation found: activity_id=%, invited_by_user_id=%, status=%',
        v_invitation.activity_id, v_invitation.invited_by_user_id, v_invitation.status;

    -- Check invitation status
    IF v_invitation.status != 'pending' THEN
        RAISE NOTICE 'Invitation already responded: status=%', v_invitation.status;
        RETURN QUERY SELECT FALSE, NULL::UUID,
            'ALREADY_RESPONDED'::VARCHAR(50), 'Cannot cancel responded invitation'::TEXT;
        RETURN;
    END IF;

    -- Check authorization
    -- Can cancel if: organizer, co-organizer, or the person who sent the invitation
    IF v_invitation.invited_by_user_id = p_cancelling_user_id THEN
        v_is_authorized := TRUE;
        RAISE NOTICE 'User sent this invitation - authorized';
    ELSE
        -- Check if organizer or co-organizer
        SELECT * INTO v_participant
        FROM activity.participants
        WHERE activity_id = v_invitation.activity_id
          AND user_id = p_cancelling_user_id;

        IF FOUND AND (v_participant.role = 'organizer' OR v_participant.role = 'co_organizer') THEN
            v_is_authorized := TRUE;
            RAISE NOTICE 'User is organizer/co-organizer - authorized';
        END IF;
    END IF;

    IF NOT v_is_authorized THEN
        RAISE NOTICE 'User not authorized to cancel invitation';
        RETURN QUERY SELECT FALSE, NULL::UUID,
            'NOT_AUTHORIZED'::VARCHAR(50), 'Not authorized to cancel this invitation'::TEXT;
        RETURN;
    END IF;

    -- Cancel invitation (delete it)
    RAISE NOTICE 'Cancelling invitation';
    DELETE FROM activity.activity_invitations
    WHERE invitation_id = p_invitation_id;

    RAISE NOTICE 'Invitation cancelled successfully';

    RETURN QUERY SELECT TRUE, v_invitation.activity_id,
        NULL::VARCHAR(50), NULL::TEXT;
    RETURN;
END;
$$;

-- =====================================================
-- 15. sp_get_received_invitations
-- =====================================================
CREATE OR REPLACE FUNCTION activity.sp_get_received_invitations(
    p_user_id UUID,
    p_status activity.invitation_status DEFAULT NULL,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    invitation_id UUID,
    activity_id UUID,
    activity_title VARCHAR(255),
    activity_scheduled_at TIMESTAMP WITH TIME ZONE,
    invited_by_user_id UUID,
    invited_by_username VARCHAR(100),
    status activity.invitation_status,
    message TEXT,
    invited_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE,
    responded_at TIMESTAMP WITH TIME ZONE,
    total_count BIGINT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE NOTICE 'sp_get_received_invitations called: user_id=%, status=%, limit=%, offset=%',
        p_user_id, p_status, p_limit, p_offset;

    RETURN QUERY
    SELECT
        i.invitation_id,
        a.activity_id,
        a.title AS activity_title,
        a.scheduled_at AS activity_scheduled_at,
        i.invited_by_user_id,
        u.username AS invited_by_username,
        CASE
            WHEN i.status = 'pending' AND i.expires_at IS NOT NULL AND i.expires_at <= NOW()
            THEN 'expired'::activity.invitation_status
            ELSE i.status
        END AS status,
        i.message,
        i.invited_at,
        i.expires_at,
        i.responded_at,
        COUNT(*) OVER() AS total_count
    FROM activity.activity_invitations i
    JOIN activity.activities a ON i.activity_id = a.activity_id
    JOIN activity.users u ON i.invited_by_user_id = u.user_id
    WHERE i.user_id = p_user_id
        AND (p_status IS NULL OR i.status = p_status)
    ORDER BY i.invited_at DESC
    LIMIT p_limit OFFSET p_offset;

    RAISE NOTICE 'Received invitations returned';
END;
$$;

-- =====================================================
-- 16. sp_get_sent_invitations
-- =====================================================
CREATE OR REPLACE FUNCTION activity.sp_get_sent_invitations(
    p_inviting_user_id UUID,
    p_activity_id UUID DEFAULT NULL,
    p_status activity.invitation_status DEFAULT NULL,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    invitation_id UUID,
    activity_id UUID,
    activity_title VARCHAR(255),
    user_id UUID,
    username VARCHAR(100),
    status activity.invitation_status,
    invited_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE,
    responded_at TIMESTAMP WITH TIME ZONE,
    total_count BIGINT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE NOTICE 'sp_get_sent_invitations called: inviting_user_id=%, activity_id=%, status=%, limit=%, offset=%',
        p_inviting_user_id, p_activity_id, p_status, p_limit, p_offset;

    RETURN QUERY
    SELECT
        i.invitation_id,
        a.activity_id,
        a.title AS activity_title,
        i.user_id,
        u.username,
        CASE
            WHEN i.status = 'pending' AND i.expires_at IS NOT NULL AND i.expires_at <= NOW()
            THEN 'expired'::activity.invitation_status
            ELSE i.status
        END AS status,
        i.invited_at,
        i.expires_at,
        i.responded_at,
        COUNT(*) OVER() AS total_count
    FROM activity.activity_invitations i
    JOIN activity.activities a ON i.activity_id = a.activity_id
    JOIN activity.users u ON i.user_id = u.user_id
    WHERE i.invited_by_user_id = p_inviting_user_id
        AND (p_activity_id IS NULL OR i.activity_id = p_activity_id)
        AND (p_status IS NULL OR i.status = p_status)
    ORDER BY i.invited_at DESC
    LIMIT p_limit OFFSET p_offset;

    RAISE NOTICE 'Sent invitations returned';
END;
$$;

-- =====================================================
-- 17. sp_get_waitlist
-- =====================================================
CREATE OR REPLACE FUNCTION activity.sp_get_waitlist(
    p_activity_id UUID,
    p_requesting_user_id UUID,
    p_limit INT DEFAULT 50,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    waitlist_id UUID,
    user_id UUID,
    username VARCHAR(100),
    first_name VARCHAR(100),
    profile_photo_url VARCHAR(500),
    waitlist_position INT,
    created_at TIMESTAMP WITH TIME ZONE,
    notified_at TIMESTAMP WITH TIME ZONE,
    total_count BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_activity RECORD;
    v_participant RECORD;
BEGIN
    RAISE NOTICE 'sp_get_waitlist called: activity_id=%, requesting_user_id=%, limit=%, offset=%',
        p_activity_id, p_requesting_user_id, p_limit, p_offset;

    -- Get activity details
    SELECT * INTO v_activity
    FROM activity.activities
    WHERE activity_id = p_activity_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'Activity not found: %', p_activity_id;
        RETURN;
    END IF;

    -- Check requesting user is organizer or co-organizer
    SELECT * INTO v_participant
    FROM activity.participants
    WHERE activity_id = p_activity_id AND user_id = p_requesting_user_id;

    IF NOT FOUND OR (v_participant.role != 'organizer' AND v_participant.role != 'co_organizer') THEN
        RAISE NOTICE 'User not authorized to view waitlist: role=%',
            COALESCE(v_participant.role::TEXT, 'none');
        RETURN;
    END IF;

    RAISE NOTICE 'Authorization passed, returning waitlist';

    RETURN QUERY
    SELECT
        w.waitlist_id,
        u.user_id,
        u.username,
        u.first_name,
        u.main_photo_url AS profile_photo_url,
        w."position" AS waitlist_position,
        w.created_at,
        w.notified_at,
        COUNT(*) OVER() AS total_count
    FROM activity.waitlist_entries w
    JOIN activity.users u ON w.user_id = u.user_id
    WHERE w.activity_id = p_activity_id
    ORDER BY w."position" ASC
    LIMIT p_limit OFFSET p_offset;

    RAISE NOTICE 'Waitlist returned';
END;
$$;

-- =====================================================
-- END OF STORED PROCEDURES
-- =====================================================

-- Add helpful comments
COMMENT ON FUNCTION activity.sp_join_activity IS 'Join activity or add to waitlist with comprehensive validation including blocking, privacy, and premium priority checks';
COMMENT ON FUNCTION activity.sp_leave_activity IS 'Leave activity with automatic waitlist promotion';
COMMENT ON FUNCTION activity.sp_cancel_participation IS 'Cancel participation with reason tracking and waitlist promotion';
COMMENT ON FUNCTION activity.sp_list_participants IS 'List participants with blocking enforcement and role-based ordering';
COMMENT ON FUNCTION activity.sp_get_user_activities IS 'Get user activity history with privacy and blocking checks';
COMMENT ON FUNCTION activity.sp_promote_participant IS 'Promote member to co-organizer (organizer only)';
COMMENT ON FUNCTION activity.sp_demote_participant IS 'Demote co-organizer to member (organizer only)';
COMMENT ON FUNCTION activity.sp_mark_attendance IS 'Bulk mark attendance after activity completion (organizer/co-organizer only)';
COMMENT ON FUNCTION activity.sp_confirm_attendance IS 'Peer verification of attendance with verification count increment';
COMMENT ON FUNCTION activity.sp_get_pending_verifications IS 'Get activities with unconfirmed attendances for peer verification';
COMMENT ON FUNCTION activity.sp_send_invitations IS 'Bulk send invitations with validation and blocking checks';
COMMENT ON FUNCTION activity.sp_accept_invitation IS 'Accept invitation and join activity or waitlist';
COMMENT ON FUNCTION activity.sp_decline_invitation IS 'Decline invitation';
COMMENT ON FUNCTION activity.sp_cancel_invitation IS 'Cancel invitation (organizer/co-organizer/sender only)';
COMMENT ON FUNCTION activity.sp_get_received_invitations IS 'Get received invitations with expired status handling';
COMMENT ON FUNCTION activity.sp_get_sent_invitations IS 'Get sent invitations with expired status handling';
COMMENT ON FUNCTION activity.sp_get_waitlist IS 'Get waitlist entries ordered by position (organizer/co-organizer only)';
