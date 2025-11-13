#!/bin/bash

# test_attendance.sh
# Tests for attendance marking and peer verification

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

# Test activity
ATTENDANCE_ACTIVITY="00000002-0000-0000-0000-000000000005"

# JWT tokens
TOKEN_ORGANIZER=""
TOKEN_FREE1=""
TOKEN_FREE2=""
TOKEN_FREE3=""

generate_tokens() {
    print_step "Generating JWT tokens..."
    TOKEN_ORGANIZER=$(python3 "$TEST_ROOT/generate_test_tokens.py" organizer)
    TOKEN_FREE1=$(python3 "$TEST_ROOT/generate_test_tokens.py" free1)
    TOKEN_FREE2=$(python3 "$TEST_ROOT/generate_test_tokens.py" free2)
    TOKEN_FREE3=$(python3 "$TEST_ROOT/generate_test_tokens.py" free3)
    print_success "JWT tokens generated"
}

cleanup_attendance() {
    db_query "DELETE FROM activity.participants WHERE activity_id = '$ATTENDANCE_ACTIVITY'"
    db_query "DELETE FROM activity.activity_attendance WHERE activity_id = '$ATTENDANCE_ACTIVITY'"
    db_query "DELETE FROM activity.attendance_confirmations WHERE activity_id = '$ATTENDANCE_ACTIVITY'"
    db_query "UPDATE activity.activities SET current_participants_count = 0 WHERE activity_id = '$ATTENDANCE_ACTIVITY'"
}

setup_participants() {
    # Add participants for attendance testing
    api_call "POST" "/activities/$ATTENDANCE_ACTIVITY/join" "$TOKEN_FREE1" "" "200" > /dev/null
    api_call "POST" "/activities/$ATTENDANCE_ACTIVITY/join" "$TOKEN_FREE2" "" "200" > /dev/null
    api_call "POST" "/activities/$ATTENDANCE_ACTIVITY/join" "$TOKEN_FREE3" "" "200" > /dev/null
}

##############################################################################
# TEST 1: Mark Single User as Present
##############################################################################
test_mark_single_present() {
    print_test_header "Mark Single User Present - Organizer Action"
    cleanup_attendance
    setup_participants

    # Organizer marks Free1 as present
    print_step "Organizer marks user as present"
    attendance_data=$(cat <<EOF
{
    "attendance_records": [
        {
            "user_id": "$FREE1_ID",
            "status": "present"
        }
    ]
}
EOF
)

    response=$(api_call "POST" "/activities/$ATTENDANCE_ACTIVITY/attendance" "$TOKEN_ORGANIZER" "$attendance_data" "200")

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

    # Verify marked_by is organizer
    local marked_by=$(db_query "SELECT marked_by FROM activity.activity_attendance WHERE activity_id = '$ATTENDANCE_ACTIVITY' AND user_id = '$FREE1_ID'")
    
    if [ "$marked_by" = "$ORGANIZER_ID" ]; then
        print_success "Attendance marked by organizer"
    else
        print_failure "Attendance marked_by incorrect: $marked_by"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 2: Mark Multiple Users as Present (Bulk)
##############################################################################
test_mark_bulk_present() {
    print_test_header "Mark Bulk Attendance - Multiple Users"

    # Organizer marks Free2 and Free3 as present
    print_step "Organizer marks multiple users present"
    attendance_data=$(cat <<EOF
{
    "attendance_records": [
        {
            "user_id": "$FREE2_ID",
            "status": "present"
        },
        {
            "user_id": "$FREE3_ID",
            "status": "present"
        }
    ]
}
EOF
)

    response=$(api_call "POST" "/activities/$ATTENDANCE_ACTIVITY/attendance" "$TOKEN_ORGANIZER" "$attendance_data" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify both attendance records
    verify_attendance "$ATTENDANCE_ACTIVITY" "$FREE2_ID" "present"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    verify_attendance "$ATTENDANCE_ACTIVITY" "$FREE3_ID" "present"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 3: Mark User as Absent
##############################################################################
test_mark_absent() {
    print_test_header "Mark User Absent - No Show Tracking"
    cleanup_attendance
    setup_participants

    # Organizer marks Free1 as absent
    print_step "Organizer marks user as absent"
    attendance_data=$(cat <<EOF
{
    "attendance_records": [
        {
            "user_id": "$FREE1_ID",
            "status": "absent"
        }
    ]
}
EOF
)

    response=$(api_call "POST" "/activities/$ATTENDANCE_ACTIVITY/attendance" "$TOKEN_ORGANIZER" "$attendance_data" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify attendance status is absent
    verify_attendance "$ATTENDANCE_ACTIVITY" "$FREE1_ID" "absent"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 4: Peer Confirmation of Attendance
##############################################################################
test_peer_confirmation() {
    print_test_header "Peer Confirmation - Verify Attendance"
    cleanup_attendance
    setup_participants

    # Organizer marks both users present
    attendance_data=$(cat <<EOF
{
    "attendance_records": [
        {
            "user_id": "$FREE1_ID",
            "status": "present"
        },
        {
            "user_id": "$FREE2_ID",
            "status": "present"
        }
    ]
}
EOF
)
    api_call "POST" "/activities/$ATTENDANCE_ACTIVITY/attendance" "$TOKEN_ORGANIZER" "$attendance_data" "200" > /dev/null

    # Free1 confirms Free2's attendance
    print_step "Peer confirms attendance"
    confirm_data=$(cat <<EOF
{
    "confirmed_user_id": "$FREE2_ID"
}
EOF
)

    response=$(api_call "POST" "/attendance/confirm" "$TOKEN_FREE1" "$confirm_data" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify confirmation count incremented
    verify_confirmation_count "$ATTENDANCE_ACTIVITY" "$FREE2_ID" "1"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify confirmation record created
    local confirmation=$(db_query "SELECT COUNT(*) FROM activity.attendance_confirmations WHERE activity_id = '$ATTENDANCE_ACTIVITY' AND confirmed_user_id = '$FREE2_ID' AND confirming_user_id = '$FREE1_ID'")
    
    if [ "$confirmation" = "1" ]; then
        print_success "Confirmation record created"
    else
        print_failure "Confirmation record not found"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 5: Second Peer Confirmation Increments Count
##############################################################################
test_multiple_confirmations() {
    print_test_header "Multiple Confirmations - Count Increment"

    # Free2 confirms Free1's attendance
    print_step "Second peer confirms attendance"
    confirm_data="{\"confirmed_user_id\": \"$FREE1_ID\"}"

    response=$(api_call "POST" "/attendance/confirm" "$TOKEN_FREE2" "$confirm_data" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify confirmation count is 1
    verify_confirmation_count "$ATTENDANCE_ACTIVITY" "$FREE1_ID" "1"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Free1 confirms Free2 back (should increment Free2's count to 2)
    print_step "Third confirmation (cross-confirm)"
    confirm_data="{\"confirmed_user_id\": \"$FREE2_ID\"}"

    # Wait a moment to ensure different timestamps
    sleep 1

    # Free3 confirms Free2
    response=$(api_call "POST" "/attendance/confirm" "$TOKEN_FREE3" "$confirm_data" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify Free2's confirmation count is now 2
    verify_confirmation_count "$ATTENDANCE_ACTIVITY" "$FREE2_ID" "2"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 6: Get Pending Verifications
##############################################################################
test_get_pending_verifications() {
    print_test_header "Get Pending Verifications - Unconfirmed List"

    # Free3 has no confirmations yet
    print_step "Get pending verification list"
    response=$(api_call "GET" "/attendance/pending" "$TOKEN_ORGANIZER" "" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify Free3 is in pending list (0 confirmations)
    if echo "$response" | grep -q "$FREE3_ID"; then
        print_success "User with 0 confirmations in pending list"
    else
        print_failure "Pending list doesn't include unconfirmed user"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 7: Non-Organizer Cannot Mark Attendance
##############################################################################
test_non_organizer_cannot_mark() {
    print_test_header "Non-Organizer Cannot Mark - Permission Denied"
    cleanup_attendance
    setup_participants

    # Free1 (regular member) tries to mark attendance
    print_step "Non-organizer tries to mark attendance"
    attendance_data=$(cat <<EOF
{
    "attendance_records": [
        {
            "user_id": "$FREE2_ID",
            "status": "present"
        }
    ]
}
EOF
)

    response=$(api_call "POST" "/activities/$ATTENDANCE_ACTIVITY/attendance" "$TOKEN_FREE1" "$attendance_data" "403")

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

    # Verify no attendance record created
    local count=$(db_query "SELECT COUNT(*) FROM activity.activity_attendance WHERE activity_id = '$ATTENDANCE_ACTIVITY' AND user_id = '$FREE2_ID'")
    
    if [ "$count" = "0" ]; then
        print_success "No attendance record created (correct)"
    else
        print_failure "Attendance record created when it shouldn't"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 8: Bulk Attendance Limit (Max 100)
##############################################################################
test_bulk_attendance_limit() {
    print_test_header "Bulk Attendance Limit - Max 100 Records"

    # Try to mark 3 users (should succeed - under limit)
    print_step "Mark 3 users (under limit)"
    attendance_data=$(cat <<EOF
{
    "attendance_records": [
        {
            "user_id": "$FREE1_ID",
            "status": "present"
        },
        {
            "user_id": "$FREE2_ID",
            "status": "present"
        },
        {
            "user_id": "$FREE3_ID",
            "status": "present"
        }
    ]
}
EOF
)

    response=$(api_call "POST" "/activities/$ATTENDANCE_ACTIVITY/attendance" "$TOKEN_ORGANIZER" "$attendance_data" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify all 3 records created
    local count=$(db_query "SELECT COUNT(*) FROM activity.activity_attendance WHERE activity_id = '$ATTENDANCE_ACTIVITY'")
    
    if [ "$count" = "3" ]; then
        print_success "Bulk attendance records created: 3"
    else
        print_failure "Incorrect number of attendance records: $count"
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
    echo "ATTENDANCE & VERIFICATION TEST SUITE"
    echo "================================================="
    echo ""

    generate_tokens

    echo ""
    echo "Running attendance tests..."
    echo ""

    test_mark_single_present
    test_mark_bulk_present
    test_mark_absent
    test_peer_confirmation
    test_multiple_confirmations
    test_get_pending_verifications
    test_non_organizer_cannot_mark
    test_bulk_attendance_limit

    print_summary

    return $?
}

# Run tests
main
