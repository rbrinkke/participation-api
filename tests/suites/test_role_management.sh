#!/bin/bash

# test_role_management.sh
# Tests for role management endpoints: promote/demote co-organizers

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
ATTENDANCE_ACTIVITY="00000002-0000-0000-0000-000000000005"

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
    db_query "DELETE FROM activity.activity_participants WHERE activity_id = '$PUBLIC_ACTIVITY'"
    db_query "DELETE FROM activity.activity_waitlist WHERE activity_id = '$PUBLIC_ACTIVITY'"
    db_query "UPDATE activity.activities SET current_participants_count = 0, waitlist_count = 0 WHERE activity_id = '$PUBLIC_ACTIVITY'"
}

cleanup_attendance_activity() {
    db_query "DELETE FROM activity.activity_participants WHERE activity_id = '$ATTENDANCE_ACTIVITY'"
    db_query "DELETE FROM activity.activity_attendance WHERE activity_id = '$ATTENDANCE_ACTIVITY'"
    db_query "UPDATE activity.activities SET current_participants_count = 0 WHERE activity_id = '$ATTENDANCE_ACTIVITY'"
}

##############################################################################
# TEST 1: Promote User to Co-Organizer (Organizer Only)
##############################################################################
test_promote_to_coorganizer() {
    print_test_header "Promote to Co-Organizer - Organizer Permission"
    cleanup_participants

    # Free user joins activity first
    print_step "Free user joins activity"
    api_call "POST" "/activities/$PUBLIC_ACTIVITY/join" "$TOKEN_FREE1" "" "200" > /dev/null

    # Verify participant exists with member role
    verify_participant_exists "$PUBLIC_ACTIVITY" "$FREE1_ID" "registered" "member"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Organizer promotes free user to co-organizer
    print_step "Organizer promotes user to co-organizer"
    promote_data="{\"user_id\": \"$FREE1_ID\"}"
    response=$(api_call "POST" "/activities/$PUBLIC_ACTIVITY/promote" "$TOKEN_ORGANIZER" "$promote_data" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify participant role updated to co_organizer
    verify_participant_exists "$PUBLIC_ACTIVITY" "$FREE1_ID" "registered" "co_organizer"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 2: Demote Co-Organizer (Organizer Only)
##############################################################################
test_demote_coorganizer() {
    print_test_header "Demote Co-Organizer - Remove Permissions"

    # Free user 1 is co-organizer from previous test
    # Organizer demotes free user back to member
    print_step "Organizer demotes co-organizer to member"
    demote_data="{\"user_id\": \"$FREE1_ID\"}"
    response=$(api_call "POST" "/activities/$PUBLIC_ACTIVITY/demote" "$TOKEN_ORGANIZER" "$demote_data" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify participant role updated to member
    verify_participant_exists "$PUBLIC_ACTIVITY" "$FREE1_ID" "registered" "member"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 3: Non-Organizer Cannot Promote (403 Error)
##############################################################################
test_non_organizer_cannot_promote() {
    print_test_header "Non-Organizer Cannot Promote - Permission Denied"

    # Free user 2 joins
    print_step "Second user joins activity"
    api_call "POST" "/activities/$PUBLIC_ACTIVITY/join" "$TOKEN_FREE2" "" "200" > /dev/null

    # Free user 1 tries to promote free user 2 (should fail)
    print_step "Non-organizer tries to promote another user"
    promote_data="{\"user_id\": \"$FREE2_ID\"}"
    response=$(api_call "POST" "/activities/$PUBLIC_ACTIVITY/promote" "$TOKEN_FREE1" "$promote_data" "403")

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

    # Verify free user 2 still has member role
    verify_participant_exists "$PUBLIC_ACTIVITY" "$FREE2_ID" "registered" "member"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 4: Cannot Promote Self (400 Error)
##############################################################################
test_cannot_promote_self() {
    print_test_header "Cannot Promote Self - Invalid Operation"

    # Organizer tries to promote themselves (should fail)
    print_step "Organizer tries to promote self"
    promote_data="{\"user_id\": \"$ORGANIZER_ID\"}"
    response=$(api_call "POST" "/activities/$PUBLIC_ACTIVITY/promote" "$TOKEN_ORGANIZER" "$promote_data" "400")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify error response
    if echo "$response" | grep -q "CANNOT_PROMOTE_SELF\|cannot promote.*self"; then
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
# TEST 5: Co-Organizer Can Perform Co-Organizer Actions
##############################################################################
test_coorganizer_permissions() {
    print_test_header "Co-Organizer Permissions - Can Mark Attendance"
    cleanup_attendance_activity

    # Premium user joins attendance activity
    print_step "Premium user joins activity"
    api_call "POST" "/activities/$ATTENDANCE_ACTIVITY/join" "$TOKEN_PREMIUM" "" "200" > /dev/null

    # Promote premium user to co-organizer
    print_step "Promote premium user to co-organizer"
    promote_data="{\"user_id\": \"$PREMIUM_ID\"}"
    api_call "POST" "/activities/$ATTENDANCE_ACTIVITY/promote" "$TOKEN_ORGANIZER" "$promote_data" "200" > /dev/null

    verify_participant_exists "$ATTENDANCE_ACTIVITY" "$PREMIUM_ID" "registered" "co_organizer"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Free user joins for attendance marking
    print_step "Free user joins for attendance test"
    api_call "POST" "/activities/$ATTENDANCE_ACTIVITY/join" "$TOKEN_FREE1" "" "200" > /dev/null

    # Co-organizer (premium user) marks attendance (should succeed)
    print_step "Co-organizer marks attendance"
    attendance_data="{\"user_ids\": [\"$FREE1_ID\"], \"status\": \"present\"}"
    response=$(api_call "POST" "/activities/$ATTENDANCE_ACTIVITY/attendance" "$TOKEN_PREMIUM" "$attendance_data" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify attendance record created
    verify_attendance "$ATTENDANCE_ACTIVITY" "$FREE1_ID" "present"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 6: Demoted User Loses Co-Organizer Permissions
##############################################################################
test_demoted_loses_permissions() {
    print_test_header "Demoted User Loses Permissions - Cannot Mark Attendance"

    # Demote premium user back to member
    print_step "Demote premium user to member"
    demote_data="{\"user_id\": \"$PREMIUM_ID\"}"
    api_call "POST" "/activities/$ATTENDANCE_ACTIVITY/demote" "$TOKEN_ORGANIZER" "$demote_data" "200" > /dev/null

    verify_participant_exists "$ATTENDANCE_ACTIVITY" "$PREMIUM_ID" "registered" "member"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Demoted user tries to mark attendance (should fail)
    print_step "Demoted user tries to mark attendance"
    attendance_data="{\"user_ids\": [\"$FREE1_ID\"], \"status\": \"present\"}"
    response=$(api_call "POST" "/activities/$ATTENDANCE_ACTIVITY/attendance" "$TOKEN_PREMIUM" "$attendance_data" "403")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify error response
    if echo "$response" | grep -q "INSUFFICIENT_PERMISSIONS\|permission"; then
        print_success "Correct error response - permissions revoked"
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
    echo "ROLE MANAGEMENT TEST SUITE"
    echo "================================================="
    echo ""

    generate_tokens

    echo ""
    echo "Running role management tests..."
    echo ""

    test_promote_to_coorganizer
    test_demote_coorganizer
    test_non_organizer_cannot_promote
    test_cannot_promote_self
    test_coorganizer_permissions
    test_demoted_loses_permissions

    print_summary

    return $?
}

# Run tests
main
