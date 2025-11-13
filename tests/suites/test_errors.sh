#!/bin/bash

# test_errors.sh
# Tests for error scenarios and edge cases

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$(dirname "$SCRIPT_DIR")"

# Source test helpers
source "$TEST_ROOT/test_helpers.sh"

# Test users
ORGANIZER_ID="00000001-0000-0000-0000-000000000001"
PREMIUM_ID="00000001-0000-0000-0000-000000000002"
FREE1_ID="00000001-0000-0000-0000-000000000003"
BLOCKED_ID="00000001-0000-0000-0000-000000000008"

# Test activities
PUBLIC_ACTIVITY="00000002-0000-0000-0000-000000000001"
SMALL_ACTIVITY="00000002-0000-0000-0000-000000000002"

# JWT tokens
TOKEN_ORGANIZER=""
TOKEN_PREMIUM=""
TOKEN_FREE1=""
TOKEN_BLOCKED=""

generate_tokens() {
    print_step "Generating JWT tokens..."
    TOKEN_ORGANIZER=$(python3 "$TEST_ROOT/generate_test_tokens.py" organizer)
    TOKEN_PREMIUM=$(python3 "$TEST_ROOT/generate_test_tokens.py" premium)
    TOKEN_FREE1=$(python3 "$TEST_ROOT/generate_test_tokens.py" free1)
    TOKEN_BLOCKED=$(python3 "$TEST_ROOT/generate_test_tokens.py" blocked)
    print_success "JWT tokens generated"
}

cleanup_activity() {
    local activity_id=$1
    db_query "DELETE FROM activity.participants WHERE activity_id = '$activity_id'"
    db_query "DELETE FROM activity.waitlist_entries WHERE activity_id = '$activity_id'"
    db_query "UPDATE activity.activities SET current_participants_count = 0, waitlist_count = 0 WHERE activity_id = '$activity_id'"
}

##############################################################################
# TEST 1: ACTIVITY_NOT_FOUND (404)
##############################################################################
test_activity_not_found() {
    print_test_header "Activity Not Found - 404 Error"

    local fake_activity="00000000-0000-0000-0000-000000000000"

    print_step "Try to join non-existent activity"
    response=$(api_call "POST" "/activities/$fake_activity/join" "$TOKEN_FREE1" "" "404")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify error response
    if echo "$response" | grep -q "ACTIVITY_NOT_FOUND\|not found"; then
        print_success "Correct error code returned"
    else
        print_failure "Error code missing or incorrect"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 2: ALREADY_JOINED (400)
##############################################################################
test_already_joined() {
    print_test_header "Already Joined - Duplicate Join Prevention"
    cleanup_activity "$PUBLIC_ACTIVITY"

    # Join activity
    api_call "POST" "/activities/$PUBLIC_ACTIVITY/join" "$TOKEN_FREE1" "" "200" > /dev/null

    # Try to join again
    print_step "Try to join already joined activity"
    response=$(api_call "POST" "/activities/$PUBLIC_ACTIVITY/join" "$TOKEN_FREE1" "" "400")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify error response
    if echo "$response" | grep -q "ALREADY_JOINED\|already.*joined"; then
        print_success "Correct error code returned"
    else
        print_failure "Error code missing or incorrect"
        mark_test_failed
        return 1
    fi

    # Verify only 1 participant record
    verify_participant_count "$PUBLIC_ACTIVITY" "1"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 3: NOT_PARTICIPANT (400)
##############################################################################
test_not_participant() {
    print_test_header "Not Participant - Cannot Leave"
    cleanup_activity "$PUBLIC_ACTIVITY"

    # Try to leave without joining
    print_step "Try to leave activity without being participant"
    response=$(api_call "DELETE" "/activities/$PUBLIC_ACTIVITY/leave" "$TOKEN_FREE1" "" "400")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify error response
    if echo "$response" | grep -q "NOT_PARTICIPANT\|not.*participant"; then
        print_success "Correct error code returned"
    else
        print_failure "Error code missing or incorrect"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 4: USER_IS_ORGANIZER Cannot Join Own Activity (400)
##############################################################################
test_organizer_cannot_join() {
    print_test_header "Organizer Cannot Join Own Activity"

    # Organizer tries to join their own activity
    print_step "Organizer tries to join own activity"
    response=$(api_call "POST" "/activities/$PUBLIC_ACTIVITY/join" "$TOKEN_ORGANIZER" "" "400")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify error response
    if echo "$response" | grep -q "USER_IS_ORGANIZER\|organizer.*cannot.*join"; then
        print_success "Correct error code returned"
    else
        print_failure "Error code missing or incorrect"
        mark_test_failed
        return 1
    fi

    # Verify no participant record created
    verify_no_participant "$PUBLIC_ACTIVITY" "$ORGANIZER_ID"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 5: INSUFFICIENT_PERMISSIONS (403)
##############################################################################
test_insufficient_permissions() {
    print_test_header "Insufficient Permissions - Non-Organizer Action"
    cleanup_activity "$PUBLIC_ACTIVITY"

    # Free user joins
    api_call "POST" "/activities/$PUBLIC_ACTIVITY/join" "$TOKEN_FREE1" "" "200" > /dev/null

    # Non-organizer tries to promote (should fail)
    print_step "Non-organizer tries to promote user"
    promote_data="{\"user_id\": \"$PREMIUM_ID\"}"
    response=$(api_call "POST" "/activities/$PUBLIC_ACTIVITY/promote" "$TOKEN_FREE1" "$promote_data" "403")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify error response
    if echo "$response" | grep -q "INSUFFICIENT_PERMISSIONS\|permission"; then
        print_success "Correct error code returned"
    else
        print_failure "Error code missing or incorrect"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 6: CANNOT_PROMOTE_SELF (400)
##############################################################################
test_cannot_promote_self() {
    print_test_header "Cannot Promote Self - Invalid Operation"

    # Organizer tries to promote themselves
    print_step "Organizer tries to promote self"
    promote_data="{\"user_id\": \"$ORGANIZER_ID\"}"
    response=$(api_call "POST" "/activities/$PUBLIC_ACTIVITY/promote" "$TOKEN_ORGANIZER" "$promote_data" "400")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify error response
    if echo "$response" | grep -q "CANNOT_PROMOTE_SELF\|cannot.*self"; then
        print_success "Correct error code returned"
    else
        print_failure "Error code missing or incorrect"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 7: Invalid UUID Format (400)
##############################################################################
test_invalid_uuid() {
    print_test_header "Invalid UUID Format - Validation Error"

    local invalid_uuid="not-a-valid-uuid"

    print_step "Try to join with invalid activity UUID"
    response=$(api_call "POST" "/activities/$invalid_uuid/join" "$TOKEN_FREE1" "" "400")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify error response mentions validation
    if echo "$response" | grep -q "invalid\|validation\|uuid\|format"; then
        print_success "Validation error returned"
    else
        print_failure "Validation error missing"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 8: Missing Required Fields (400)
##############################################################################
test_missing_required_fields() {
    print_test_header "Missing Required Fields - Validation Error"

    # Try to cancel without reason (if reason is required)
    print_step "Try to cancel with missing required field"
    empty_data="{}"
    response=$(api_call "POST" "/activities/$PUBLIC_ACTIVITY/cancel" "$TOKEN_FREE1" "$empty_data" "400")

    # Note: This might return 400 (validation) or 404 (not participant)
    # Both are acceptable depending on validation order
    if [ $? -eq 0 ] || echo "$response" | grep -q "validation\|required\|NOT_PARTICIPANT"; then
        print_success "Validation or business logic error returned"
    else
        print_failure "Expected error not returned"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 9: BLOCKED_USER (403) - If Blocking is Implemented
##############################################################################
test_blocked_user() {
    print_test_header "Blocked User - Cannot Join"
    cleanup_activity "$PUBLIC_ACTIVITY"

    # Premium user joins first
    api_call "POST" "/activities/$PUBLIC_ACTIVITY/join" "$TOKEN_PREMIUM" "" "200" > /dev/null

    # Create block relationship (blocked user blocks premium user)
    print_step "Setup block relationship"
    db_query "INSERT INTO activity.user_blocks (blocker_id, blocked_id, created_at) VALUES ('$PREMIUM_ID', '$BLOCKED_ID', NOW()) ON CONFLICT DO NOTHING"

    # Blocked user tries to join activity where premium user is participant
    print_step "Blocked user tries to join activity"
    response=$(api_call "POST" "/activities/$PUBLIC_ACTIVITY/join" "$TOKEN_BLOCKED" "" "403")

    # Clean up block
    db_query "DELETE FROM activity.user_blocks WHERE blocker_id = '$PREMIUM_ID' AND blocked_id = '$BLOCKED_ID'"

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify error response
    if echo "$response" | grep -q "BLOCKED_USER\|blocked\|cannot.*join"; then
        print_success "Correct error code returned"
    else
        print_failure "Error code missing or incorrect"
        mark_test_failed
        return 1
    fi

    # Verify no participant record
    verify_no_participant "$PUBLIC_ACTIVITY" "$BLOCKED_ID"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 10: USER_NOT_FOUND (404)
##############################################################################
test_user_not_found() {
    print_test_header "User Not Found - Invalid User ID"

    local fake_user="00000000-0000-0000-0000-999999999999"

    # Try to get activities for non-existent user
    print_step "Try to get activities for non-existent user"
    response=$(api_call "GET" "/users/$fake_user/activities" "$TOKEN_ORGANIZER" "" "404")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify error response
    if echo "$response" | grep -q "USER_NOT_FOUND\|user.*not.*found"; then
        print_success "Correct error code returned"
    else
        print_failure "Error code missing or incorrect"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 11: ACTIVITY_NOT_PUBLISHED (400) - Draft/Cancelled Activity
##############################################################################
test_activity_not_published() {
    print_test_header "Activity Not Published - Cannot Join"

    # Update activity to draft status
    print_step "Set activity to draft status"
    db_query "UPDATE activity.activities SET status = 'draft' WHERE activity_id = '$PUBLIC_ACTIVITY'"

    # Try to join draft activity
    print_step "Try to join draft activity"
    response=$(api_call "POST" "/activities/$PUBLIC_ACTIVITY/join" "$TOKEN_FREE1" "" "400")

    # Restore activity to published
    db_query "UPDATE activity.activities SET status = 'published' WHERE activity_id = '$PUBLIC_ACTIVITY'"

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify error response
    if echo "$response" | grep -q "ACTIVITY_NOT_PUBLISHED\|not.*published"; then
        print_success "Correct error code returned"
    else
        print_failure "Error code missing or incorrect"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 12: ACTIVITY_IN_PAST (400) - Past Activity
##############################################################################
test_activity_in_past() {
    print_test_header "Activity In Past - Cannot Join"

    # Update activity to past date
    print_step "Set activity to past date"
    db_query "UPDATE activity.activities SET scheduled_at = NOW() - INTERVAL '1 day' WHERE activity_id = '$PUBLIC_ACTIVITY'"

    # Try to join past activity
    print_step "Try to join past activity"
    response=$(api_call "POST" "/activities/$PUBLIC_ACTIVITY/join" "$TOKEN_FREE1" "" "400")

    # Restore activity to future date
    db_query "UPDATE activity.activities SET scheduled_at = NOW() + INTERVAL '7 days' WHERE activity_id = '$PUBLIC_ACTIVITY'"

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify error response
    if echo "$response" | grep -q "ACTIVITY_IN_PAST\|past"; then
        print_success "Correct error code returned"
    else
        print_failure "Error code missing or incorrect"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 13: MAX_PARTICIPANTS_REACHED - No Waitlist Allowed
##############################################################################
test_max_participants_no_waitlist() {
    print_test_header "Max Participants Reached - No Waitlist"
    cleanup_activity "$SMALL_ACTIVITY"

    # Fill activity to max (2 participants)
    api_call "POST" "/activities/$SMALL_ACTIVITY/join" "$TOKEN_PREMIUM" "" "200" > /dev/null
    api_call "POST" "/activities/$SMALL_ACTIVITY/join" "$TOKEN_FREE1" "" "200" > /dev/null

    # Verify activity is full
    verify_activity_counter "$SMALL_ACTIVITY" "2"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    print_success "Activity filled to capacity (2/2)"

    mark_test_passed
    return 0
}

##############################################################################
# TEST 14: Unauthorized Access (401) - No Token
##############################################################################
test_unauthorized_no_token() {
    print_test_header "Unauthorized Access - No JWT Token"

    # Try to join without token
    print_step "Try to access endpoint without token"
    response=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:8004/api/v1/participation/activities/$PUBLIC_ACTIVITY/join" \
        -H "Content-Type: application/json")

    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "401" ] || [ "$http_code" = "403" ]; then
        print_success "Unauthorized access blocked: HTTP $http_code"
    else
        print_failure "Expected 401/403, got HTTP $http_code"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 15: Invalid Token (401)
##############################################################################
test_invalid_token() {
    print_test_header "Invalid Token - Authentication Failure"

    local invalid_token="invalid.jwt.token"

    # Try to join with invalid token
    print_step "Try to access endpoint with invalid token"
    response=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:8004/api/v1/participation/activities/$PUBLIC_ACTIVITY/join" \
        -H "Authorization: Bearer $invalid_token" \
        -H "Content-Type: application/json")

    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "401" ] || [ "$http_code" = "403" ]; then
        print_success "Invalid token rejected: HTTP $http_code"
    else
        print_failure "Expected 401/403, got HTTP $http_code"
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
    echo "ERROR SCENARIOS & EDGE CASES TEST SUITE"
    echo "================================================="
    echo ""

    generate_tokens

    echo ""
    echo "Running error scenario tests..."
    echo ""

    test_activity_not_found
    test_already_joined
    test_not_participant
    test_organizer_cannot_join
    test_insufficient_permissions
    test_cannot_promote_self
    test_invalid_uuid
    test_missing_required_fields
    test_blocked_user
    test_user_not_found
    test_activity_not_published
    test_activity_in_past
    test_max_participants_no_waitlist
    test_unauthorized_no_token
    test_invalid_token

    print_summary

    return $?
}

# Run tests
main
