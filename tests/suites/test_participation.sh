#!/bin/bash

# test_participation.sh
# Tests for participation endpoints: join, leave, cancel, list, get user activities

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$(dirname "$SCRIPT_DIR")"

# Source test helpers
source "$TEST_ROOT/test_helpers.sh"

# Test users (UUIDs match test_setup.sql)
ORGANIZER_ID="00000001-0000-0000-0000-000000000001"
PREMIUM_ID="00000001-0000-0000-0000-000000000002"
FREE1_ID="00000001-0000-0000-0000-000000000003"
FREE2_ID="00000001-0000-0000-0000-000000000004"

# Test activities
PUBLIC_ACTIVITY="00000002-0000-0000-0000-000000000001"
SMALL_ACTIVITY="00000002-0000-0000-0000-000000000002"

# JWT tokens (generated at runtime)
TOKEN_ORGANIZER=""
TOKEN_PREMIUM=""
TOKEN_FREE1=""
TOKEN_FREE2=""

# Generate tokens
generate_tokens() {
    print_step "Generating JWT tokens..."
    TOKEN_ORGANIZER=$(python3 "$TEST_ROOT/generate_test_tokens.py" organizer)
    TOKEN_PREMIUM=$(python3 "$TEST_ROOT/generate_test_tokens.py" premium)
    TOKEN_FREE1=$(python3 "$TEST_ROOT/generate_test_tokens.py" free1)
    TOKEN_FREE2=$(python3 "$TEST_ROOT/generate_test_tokens.py" free2)
    print_success "JWT tokens generated"
}

# Cleanup between tests
cleanup_participants() {
    db_query "DELETE FROM activity.participants WHERE activity_id = '$PUBLIC_ACTIVITY'"
    db_query "DELETE FROM activity.waitlist_entries WHERE activity_id = '$PUBLIC_ACTIVITY'"
    db_query "UPDATE activity.activities SET current_participants_count = 0 WHERE activity_id = '$PUBLIC_ACTIVITY'"
}

##############################################################################
# TEST 1: Join Public Activity - Success
##############################################################################
test_join_public_activity() {
    print_test_header "Join Public Activity - Direct Join"
    cleanup_participants

    # Free user 1 joins public activity
    print_step "Free user joins public activity"
    response=$(api_call "POST" "/activities/$PUBLIC_ACTIVITY/join" "$TOKEN_FREE1" "" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify participant record exists
    verify_participant_exists "$PUBLIC_ACTIVITY" "$FREE1_ID" "registered" "member"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify activity counter incremented
    verify_activity_counter "$PUBLIC_ACTIVITY" "1"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 2: Already Joined Error
##############################################################################
test_already_joined_error() {
    print_test_header "Already Joined - Error Handling"

    # Free user 1 is already joined from previous test
    print_step "Same user tries to join again"
    response=$(api_call "POST" "/activities/$PUBLIC_ACTIVITY/join" "$TOKEN_FREE1" "" "400")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify response contains error
    if echo "$response" | grep -q "ALREADY_JOINED\|already joined"; then
        print_success "Correct error response received"
    else
        print_failure "Error response missing or incorrect"
        mark_test_failed
        return 1
    fi

    # Verify only 1 participant record (not duplicated)
    verify_participant_count "$PUBLIC_ACTIVITY" "1"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 3: List Participants
##############################################################################
test_list_participants() {
    print_test_header "List Participants - Verify Visibility"

    # Another user joins
    print_step "Second user joins activity"
    api_call "POST" "/activities/$PUBLIC_ACTIVITY/join" "$TOKEN_FREE2" "" "200" > /dev/null

    # Verify second participant
    verify_participant_exists "$PUBLIC_ACTIVITY" "$FREE2_ID" "registered" "member"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # List participants
    print_step "List all participants"
    response=$(api_call "GET" "/activities/$PUBLIC_ACTIVITY/participants" "$TOKEN_PREMIUM" "" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Check if response contains both users
    if echo "$response" | grep -q "$FREE1_ID"; then
        print_success "First participant in list"
    else
        print_failure "First participant missing from list"
        mark_test_failed
        return 1
    fi

    if echo "$response" | grep -q "$FREE2_ID"; then
        print_success "Second participant in list"
    else
        print_failure "Second participant missing from list"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 4: Leave Activity - Success
##############################################################################
test_leave_activity() {
    print_test_header "Leave Activity - Successful Departure"

    # Free user 1 leaves activity
    print_step "User leaves activity"
    api_call "DELETE" "/activities/$PUBLIC_ACTIVITY/leave" "$TOKEN_FREE1" "" "200" > /dev/null

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify participant no longer active (participation_status changed)
    local result=$(db_query "SELECT participation_status FROM activity.participants WHERE activity_id = '$PUBLIC_ACTIVITY' AND user_id = '$FREE1_ID'")

    if [ "$result" = "withdrawn" ] || [ "$result" = "cancelled" ]; then
        print_success "Participant status updated: $result"
    else
        print_failure "Participant status incorrect: $result"
        mark_test_failed
        return 1
    fi

    # Verify activity counter decremented
    verify_activity_counter "$PUBLIC_ACTIVITY" "1"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 5: Rejoin After Leaving
##############################################################################
test_rejoin_after_leaving() {
    print_test_header "Rejoin After Leaving - Allow Re-entry"

    # Free user 1 rejoins after leaving
    print_step "User rejoins activity"
    api_call "POST" "/activities/$PUBLIC_ACTIVITY/join" "$TOKEN_FREE1" "" "200" > /dev/null

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify new participant record
    verify_participant_exists "$PUBLIC_ACTIVITY" "$FREE1_ID" "registered" "member"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify counter is 2 (free1 + free2)
    verify_activity_counter "$PUBLIC_ACTIVITY" "2"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 6: Get User Activities
##############################################################################
test_get_user_activities() {
    print_test_header "Get User Activities - Activity History"

    # Get activities for free user 1
    print_step "Retrieve user's activity list"
    response=$(api_call "GET" "/users/$FREE1_ID/activities" "$TOKEN_FREE1" "" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify response contains the public activity
    if echo "$response" | grep -q "$PUBLIC_ACTIVITY"; then
        print_success "User's activity found in history"
    else
        print_failure "User's activity missing from history"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 7: Cancel Participation with Reason
##############################################################################
test_cancel_participation() {
    print_test_header "Cancel Participation - With Reason"
    cleanup_participants

    # Free user joins first
    api_call "POST" "/activities/$PUBLIC_ACTIVITY/join" "$TOKEN_FREE1" "" "200" > /dev/null

    # Cancel with reason
    print_step "Cancel participation with reason"
    cancel_data='{"reason": "Test cancellation reason"}'
    api_call "POST" "/activities/$PUBLIC_ACTIVITY/cancel" "$TOKEN_FREE1" "$cancel_data" "200" > /dev/null

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify participation status is cancelled
    local status=$(db_query "SELECT participation_status FROM activity.participants WHERE activity_id = '$PUBLIC_ACTIVITY' AND user_id = '$FREE1_ID'")

    if [ "$status" = "cancelled" ]; then
        print_success "Participation status: cancelled"
    else
        print_failure "Participation status not cancelled: $status"
        mark_test_failed
        return 1
    fi

    # Verify counter decremented
    verify_activity_counter "$PUBLIC_ACTIVITY" "0"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 8: Activity Not Found Error
##############################################################################
test_activity_not_found() {
    print_test_header "Activity Not Found - Error Handling"

    local fake_activity="00000000-0000-0000-0000-000000000000"

    print_step "Try to join non-existent activity"
    response=$(api_call "POST" "/activities/$fake_activity/join" "$TOKEN_FREE1" "" "404")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify error response
    if echo "$response" | grep -q "ACTIVITY_NOT_FOUND\|not found"; then
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
# TEST 9: Premium User Can Join
##############################################################################
test_premium_user_join() {
    print_test_header "Premium User Join - Subscription Level"
    cleanup_participants

    # Premium user joins
    print_step "Premium user joins public activity"
    api_call "POST" "/activities/$PUBLIC_ACTIVITY/join" "$TOKEN_PREMIUM" "" "200" > /dev/null

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify participant record
    verify_participant_exists "$PUBLIC_ACTIVITY" "$PREMIUM_ID" "registered" "member"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 10: Not Participant Error on Leave
##############################################################################
test_not_participant_error() {
    print_test_header "Not Participant - Cannot Leave"

    # Free user 1 is not joined, tries to leave
    print_step "Non-participant tries to leave"
    response=$(api_call "DELETE" "/activities/$PUBLIC_ACTIVITY/leave" "$TOKEN_FREE1" "" "400")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify error response
    if echo "$response" | grep -q "NOT_PARTICIPANT\|not.*participant"; then
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
# MAIN TEST RUNNER
##############################################################################
main() {
    echo ""
    echo "================================================="
    echo "PARTICIPATION API TEST SUITE"
    echo "================================================="
    echo ""

    generate_tokens

    echo ""
    echo "Running participation tests..."
    echo ""

    test_join_public_activity
    test_already_joined_error
    test_list_participants
    test_leave_activity
    test_rejoin_after_leaving
    test_get_user_activities
    test_cancel_participation
    test_activity_not_found
    test_premium_user_join
    test_not_participant_error

    print_summary

    return $?
}

# Run tests
main
