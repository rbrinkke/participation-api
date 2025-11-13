#!/bin/bash

# test_waitlist.sh
# Tests for waitlist functionality and auto-promotion logic

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$(dirname "$SCRIPT_DIR")"

# Source test helpers
source "$TEST_ROOT/test_helpers.sh"

# Test users
ORGANIZER_ID="00000001-0000-0000-0000-000000000001"
FREE1_ID="00000001-0000-0000-0000-000000000003"
FREE2_ID="00000001-0000-0000-0000-000000000004"
FREE3_ID="00000001-0000-0000-0000-000000000005"
FREE4_ID="00000001-0000-0000-0000-000000000006"
FREE5_ID="00000001-0000-0000-0000-000000000007"

# Small activity (max 2 participants - perfect for waitlist testing)
SMALL_ACTIVITY="00000002-0000-0000-0000-000000000002"

# JWT tokens
TOKEN_ORGANIZER=""
TOKEN_FREE1=""
TOKEN_FREE2=""
TOKEN_FREE3=""
TOKEN_FREE4=""
TOKEN_FREE5=""

generate_tokens() {
    print_step "Generating JWT tokens..."
    TOKEN_ORGANIZER=$(python3 "$TEST_ROOT/generate_test_tokens.py" organizer)
    TOKEN_FREE1=$(python3 "$TEST_ROOT/generate_test_tokens.py" free1)
    TOKEN_FREE2=$(python3 "$TEST_ROOT/generate_test_tokens.py" free2)
    TOKEN_FREE3=$(python3 "$TEST_ROOT/generate_test_tokens.py" free3)
    TOKEN_FREE4=$(python3 "$TEST_ROOT/generate_test_tokens.py" free4)
    TOKEN_FREE5=$(python3 "$TEST_ROOT/generate_test_tokens.py" free5)
    print_success "JWT tokens generated"
}

cleanup_small_activity() {
    db_query "DELETE FROM activity.participants WHERE activity_id = '$SMALL_ACTIVITY'"
    db_query "DELETE FROM activity.waitlist_entries WHERE activity_id = '$SMALL_ACTIVITY'"
    db_query "UPDATE activity.activities SET current_participants_count = 0, waitlist_count = 0 WHERE activity_id = '$SMALL_ACTIVITY'"
}

##############################################################################
# TEST 1: Join Full Activity - Waitlist
##############################################################################
test_waitlist_join() {
    print_test_header "Waitlist Join - Activity Full"
    cleanup_small_activity

    # Fill activity to capacity (max 2)
    print_step "User 1 joins (1/2)"
    api_call "POST" "/activities/$SMALL_ACTIVITY/join" "$TOKEN_FREE1" "" "200" > /dev/null

    print_step "User 2 joins (2/2 - FULL)"
    api_call "POST" "/activities/$SMALL_ACTIVITY/join" "$TOKEN_FREE2" "" "200" > /dev/null

    # Verify activity is full
    verify_activity_counter "$SMALL_ACTIVITY" "2"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # User 3 joins - should be waitlisted
    print_step "User 3 joins (waitlisted)"
    response=$(api_call "POST" "/activities/$SMALL_ACTIVITY/join" "$TOKEN_FREE3" "" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify user 3 is on waitlist at position 1
    verify_waitlist_position "$SMALL_ACTIVITY" "$FREE3_ID" "1"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify activity counter still 2
    verify_activity_counter "$SMALL_ACTIVITY" "2"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 2: Multiple Waitlist Entries
##############################################################################
test_multiple_waitlist() {
    print_test_header "Multiple Waitlist - Sequential Positions"

    # User 4 joins waitlist (position 2)
    print_step "User 4 joins (waitlist position 2)"
    api_call "POST" "/activities/$SMALL_ACTIVITY/join" "$TOKEN_FREE4" "" "200" > /dev/null

    verify_waitlist_position "$SMALL_ACTIVITY" "$FREE4_ID" "2"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # User 5 joins waitlist (position 3)
    print_step "User 5 joins (waitlist position 3)"
    api_call "POST" "/activities/$SMALL_ACTIVITY/join" "$TOKEN_FREE5" "" "200" > /dev/null

    verify_waitlist_position "$SMALL_ACTIVITY" "$FREE5_ID" "3"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify waitlist count in database
    local waitlist_count=$(db_query "SELECT COUNT(*) FROM activity.waitlist_entries WHERE activity_id = '$SMALL_ACTIVITY' AND status = 'waiting'")

    if [ "$waitlist_count" = "3" ]; then
        print_success "Waitlist count: 3 entries"
    else
        print_failure "Waitlist count incorrect: expected 3, got $waitlist_count"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 3: Auto-Promote from Waitlist
##############################################################################
test_autopromote_waitlist() {
    print_test_header "Auto-Promote - First in Line"

    # Current state: User1, User2 are participants; User3, User4, User5 waitlisted
    # User 1 leaves -> User 3 should be auto-promoted

    print_step "User 1 leaves (trigger auto-promote)"
    api_call "DELETE" "/activities/$SMALL_ACTIVITY/leave" "$TOKEN_FREE1" "" "200" > /dev/null

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify User 3 is now a participant
    verify_participant_exists "$SMALL_ACTIVITY" "$FREE3_ID" "registered" "member"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify User 3 removed from waitlist
    local waitlist_status=$(db_query "SELECT status FROM activity.waitlist_entries WHERE activity_id = '$SMALL_ACTIVITY' AND user_id = '$FREE3_ID' ORDER BY created_at DESC LIMIT 1")

    if [ "$waitlist_status" = "promoted" ]; then
        print_success "User 3 waitlist status: promoted"
    else
        print_failure "User 3 waitlist status incorrect: $waitlist_status"
        mark_test_failed
        return 1
    fi

    # Verify activity counter still 2 (User2 + User3)
    verify_activity_counter "$SMALL_ACTIVITY" "2"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify User 4 and 5 still on waitlist with SAME positions
    verify_waitlist_position "$SMALL_ACTIVITY" "$FREE4_ID" "2"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    verify_waitlist_position "$SMALL_ACTIVITY" "$FREE5_ID" "3"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 4: Second Auto-Promote
##############################################################################
test_second_autopromote() {
    print_test_header "Second Auto-Promote - Chain Reaction"

    # User 2 leaves -> User 4 should be promoted
    print_step "User 2 leaves (second promotion)"
    api_call "DELETE" "/activities/$SMALL_ACTIVITY/leave" "$TOKEN_FREE2" "" "200" > /dev/null

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify User 4 promoted
    verify_participant_exists "$SMALL_ACTIVITY" "$FREE4_ID" "registered" "member"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify User 5 still on waitlist at position 3
    verify_waitlist_position "$SMALL_ACTIVITY" "$FREE5_ID" "3"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify activity counter is 2 (User3 + User4)
    verify_activity_counter "$SMALL_ACTIVITY" "2"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 5: View Waitlist (Organizer Only)
##############################################################################
test_view_waitlist() {
    print_test_header "View Waitlist - Organizer Permission"

    # Organizer views waitlist
    print_step "Organizer views waitlist"
    response=$(api_call "GET" "/activities/$SMALL_ACTIVITY/waitlist" "$TOKEN_ORGANIZER" "" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify User 5 is in the waitlist response
    if echo "$response" | grep -q "$FREE5_ID"; then
        print_success "User 5 found in waitlist"
    else
        print_failure "User 5 not found in waitlist response"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 6: Non-Organizer Cannot View Waitlist
##############################################################################
test_waitlist_permission_denied() {
    print_test_header "View Waitlist - Permission Denied"

    # Regular user tries to view waitlist
    print_step "Non-organizer tries to view waitlist"
    response=$(api_call "GET" "/activities/$SMALL_ACTIVITY/waitlist" "$TOKEN_FREE3" "" "403")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify error response
    if echo "$response" | grep -q "INSUFFICIENT_PERMISSIONS\|permission"; then
        print_success "Correct error response received"
    else
        print_failure "Error response missing or incorrect"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 7: Leave from Waitlist
##############################################################################
test_leave_from_waitlist() {
    print_test_header "Leave from Waitlist - Direct Removal"

    # User 5 leaves waitlist before being promoted
    print_step "User leaves waitlist"
    api_call "DELETE" "/activities/$SMALL_ACTIVITY/leave" "$TOKEN_FREE5" "" "200" > /dev/null

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify User 5 waitlist entry updated
    local waitlist_status=$(db_query "SELECT status FROM activity.waitlist_entries WHERE activity_id = '$SMALL_ACTIVITY' AND user_id = '$FREE5_ID' ORDER BY created_at DESC LIMIT 1")

    if [ "$waitlist_status" = "withdrawn" ] || [ "$waitlist_status" = "cancelled" ]; then
        print_success "User 5 removed from waitlist: $waitlist_status"
    else
        print_failure "User 5 waitlist status incorrect: $waitlist_status"
        mark_test_failed
        return 1
    fi

    # Verify no auto-promote happened (activity still at capacity)
    verify_activity_counter "$SMALL_ACTIVITY" "2"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 8: Waitlist Position Integrity
##############################################################################
test_waitlist_position_integrity() {
    print_test_header "Waitlist Position Integrity - No Gaps"
    cleanup_small_activity

    # Setup: Fill activity and create waitlist
    api_call "POST" "/activities/$SMALL_ACTIVITY/join" "$TOKEN_FREE1" "" "200" > /dev/null
    api_call "POST" "/activities/$SMALL_ACTIVITY/join" "$TOKEN_FREE2" "" "200" > /dev/null
    api_call "POST" "/activities/$SMALL_ACTIVITY/join" "$TOKEN_FREE3" "" "200" > /dev/null  # Waitlist pos 1
    api_call "POST" "/activities/$SMALL_ACTIVITY/join" "$TOKEN_FREE4" "" "200" > /dev/null  # Waitlist pos 2
    api_call "POST" "/activities/$SMALL_ACTIVITY/join" "$TOKEN_FREE5" "" "200" > /dev/null  # Waitlist pos 3

    # Verify positions are sequential
    print_step "Verify waitlist positions are sequential"

    local pos3=$(db_query "SELECT position FROM activity.waitlist_entries WHERE activity_id = '$SMALL_ACTIVITY' AND user_id = '$FREE3_ID' AND status = 'waiting'")
    local pos4=$(db_query "SELECT position FROM activity.waitlist_entries WHERE activity_id = '$SMALL_ACTIVITY' AND user_id = '$FREE4_ID' AND status = 'waiting'")
    local pos5=$(db_query "SELECT position FROM activity.waitlist_entries WHERE activity_id = '$SMALL_ACTIVITY' AND user_id = '$FREE5_ID' AND status = 'waiting'")

    if [ "$pos3" = "1" ] && [ "$pos4" = "2" ] && [ "$pos5" = "3" ]; then
        print_success "Waitlist positions sequential: 1, 2, 3"
    else
        print_failure "Waitlist positions incorrect: $pos3, $pos4, $pos5"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# MAIN TEST RUNNER
##############################################################################
main() {
    echo ""
    echo "================================================="
    echo "WAITLIST & AUTO-PROMOTION TEST SUITE"
    echo "================================================="
    echo ""

    generate_tokens

    echo ""
    echo "Running waitlist tests..."
    echo ""

    test_waitlist_join
    test_multiple_waitlist
    test_autopromote_waitlist
    test_second_autopromote
    test_view_waitlist
    test_waitlist_permission_denied
    test_leave_from_waitlist
    test_waitlist_position_integrity

    print_summary

    return $?
}

# Run tests
main
