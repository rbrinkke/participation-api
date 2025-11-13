#!/bin/bash

# test_invitations.sh
# Tests for invitation functionality: send, accept, decline, cancel

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$(dirname "$SCRIPT_DIR")"

# Source test helpers
source "$TEST_ROOT/test_helpers.sh"

# Test users
ORGANIZER_ID="00000001-0000-0000-0000-000000000001"
FREE1_ID="00000001-0000-0000-0000-000000000003"
INVITEE1_ID="00000001-0000-0000-0000-000000000009"
INVITEE2_ID="00000001-0000-0000-0000-000000000010"

# Test activities
PUBLIC_ACTIVITY="00000002-0000-0000-0000-000000000001"
INVITE_ONLY="00000002-0000-0000-0000-000000000004"

# JWT tokens
TOKEN_ORGANIZER=""
TOKEN_FREE1=""
TOKEN_INVITEE1=""
TOKEN_INVITEE2=""

# Store invitation IDs for later tests
INVITATION_ID_1=""
INVITATION_ID_2=""

generate_tokens() {
    print_step "Generating JWT tokens..."
    TOKEN_ORGANIZER=$(python3 "$TEST_ROOT/generate_test_tokens.py" organizer)
    TOKEN_FREE1=$(python3 "$TEST_ROOT/generate_test_tokens.py" free1)
    TOKEN_INVITEE1=$(python3 "$TEST_ROOT/generate_test_tokens.py" invitee1)
    TOKEN_INVITEE2=$(python3 "$TEST_ROOT/generate_test_tokens.py" invitee2)
    print_success "JWT tokens generated"
}

cleanup_invitations() {
    local activity_id=$1
    db_query "DELETE FROM activity.activity_invitations WHERE activity_id = '$activity_id'"
    db_query "DELETE FROM activity.participants WHERE activity_id = '$activity_id'"
    db_query "UPDATE activity.activities SET current_participants_count = 0 WHERE activity_id = '$activity_id'"
}

##############################################################################
# TEST 1: Send Single Invitation
##############################################################################
test_send_single_invitation() {
    print_test_header "Send Single Invitation - Organizer Action"
    cleanup_invitations "$PUBLIC_ACTIVITY"

    # Organizer sends invitation to Invitee1
    print_step "Organizer sends invitation"
    invitation_data=$(cat <<EOF
{
    "invitee_ids": ["$INVITEE1_ID"]
}
EOF
)

    response=$(api_call "POST" "/activities/$PUBLIC_ACTIVITY/invitations" "$TOKEN_ORGANIZER" "$invitation_data" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Extract invitation ID from response
    INVITATION_ID_1=$(echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -z "$INVITATION_ID_1" ]; then
        # Try alternative format
        INVITATION_ID_1=$(db_query "SELECT id FROM activity.activity_invitations WHERE activity_id = '$PUBLIC_ACTIVITY' AND invitee_id = '$INVITEE1_ID' ORDER BY invited_at DESC LIMIT 1")
    fi

    print_success "Invitation created: $INVITATION_ID_1"

    # Verify invitation in database
    verify_invitation_status "$INVITATION_ID_1" "pending"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 2: Send Bulk Invitations (Max 50)
##############################################################################
test_send_bulk_invitations() {
    print_test_header "Send Bulk Invitations - Multiple Recipients"

    # Organizer sends invitations to both invitees
    print_step "Organizer sends bulk invitations"
    invitation_data=$(cat <<EOF
{
    "invitee_ids": ["$INVITEE1_ID", "$INVITEE2_ID"]
}
EOF
)

    response=$(api_call "POST" "/activities/$PUBLIC_ACTIVITY/invitations" "$TOKEN_ORGANIZER" "$invitation_data" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify both invitations created
    local inv_count=$(db_query "SELECT COUNT(*) FROM activity.activity_invitations WHERE activity_id = '$PUBLIC_ACTIVITY' AND status = 'pending'")

    if [ "$inv_count" -ge "2" ]; then
        print_success "Bulk invitations created: $inv_count"
    else
        print_failure "Incorrect invitation count: $inv_count"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 3: Get Received Invitations
##############################################################################
test_get_received_invitations() {
    print_test_header "Get Received Invitations - User View"

    # Invitee1 gets their received invitations
    print_step "User retrieves received invitations"
    response=$(api_call "GET" "/invitations/received" "$TOKEN_INVITEE1" "" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify response contains invitation for public activity
    if echo "$response" | grep -q "$PUBLIC_ACTIVITY"; then
        print_success "Received invitation found in list"
    else
        print_failure "Invitation missing from received list"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 4: Accept Invitation - Auto-Join Activity
##############################################################################
test_accept_invitation() {
    print_test_header "Accept Invitation - Auto-Join Activity"

    # Get invitation ID for Invitee1
    if [ -z "$INVITATION_ID_1" ]; then
        INVITATION_ID_1=$(db_query "SELECT id FROM activity.activity_invitations WHERE activity_id = '$PUBLIC_ACTIVITY' AND invitee_id = '$INVITEE1_ID' AND status = 'pending' LIMIT 1")
    fi

    # Invitee1 accepts invitation
    print_step "User accepts invitation"
    response=$(api_call "POST" "/invitations/$INVITATION_ID_1/accept" "$TOKEN_INVITEE1" "" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify invitation status changed to accepted
    verify_invitation_status "$INVITATION_ID_1" "accepted"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify participant record created (auto-join)
    verify_participant_exists "$PUBLIC_ACTIVITY" "$INVITEE1_ID" "registered" "member"
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
# TEST 5: Decline Invitation
##############################################################################
test_decline_invitation() {
    print_test_header "Decline Invitation - No Join"

    # Get invitation ID for Invitee2
    INVITATION_ID_2=$(db_query "SELECT id FROM activity.activity_invitations WHERE activity_id = '$PUBLIC_ACTIVITY' AND invitee_id = '$INVITEE2_ID' AND status = 'pending' LIMIT 1")

    if [ -z "$INVITATION_ID_2" ]; then
        print_failure "No pending invitation found for Invitee2"
        mark_test_failed
        return 1
    fi

    # Invitee2 declines invitation
    print_step "User declines invitation"
    response=$(api_call "POST" "/invitations/$INVITATION_ID_2/decline" "$TOKEN_INVITEE2" "" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify invitation status changed to declined
    verify_invitation_status "$INVITATION_ID_2" "declined"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify NO participant record created
    verify_no_participant "$PUBLIC_ACTIVITY" "$INVITEE2_ID"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify activity counter unchanged (still 1)
    verify_activity_counter "$PUBLIC_ACTIVITY" "1"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 6: Get Sent Invitations (Organizer)
##############################################################################
test_get_sent_invitations() {
    print_test_header "Get Sent Invitations - Organizer View"

    # Organizer gets sent invitations
    print_step "Organizer retrieves sent invitations"
    response=$(api_call "GET" "/invitations/sent" "$TOKEN_ORGANIZER" "" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify response contains both invitees
    if echo "$response" | grep -q "$INVITEE1_ID"; then
        print_success "Invitee1 found in sent list"
    else
        print_failure "Invitee1 missing from sent list"
        mark_test_failed
        return 1
    fi

    if echo "$response" | grep -q "$INVITEE2_ID"; then
        print_success "Invitee2 found in sent list"
    else
        print_failure "Invitee2 missing from sent list"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 7: Cancel Sent Invitation (Organizer Only)
##############################################################################
test_cancel_invitation() {
    print_test_header "Cancel Sent Invitation - Organizer Action"
    cleanup_invitations "$PUBLIC_ACTIVITY"

    # Create new invitation
    invitation_data="{\"invitee_ids\": [\"$INVITEE1_ID\"]}"
    api_call "POST" "/activities/$PUBLIC_ACTIVITY/invitations" "$TOKEN_ORGANIZER" "$invitation_data" "200" > /dev/null

    # Get new invitation ID
    local new_inv_id=$(db_query "SELECT id FROM activity.activity_invitations WHERE activity_id = '$PUBLIC_ACTIVITY' AND invitee_id = '$INVITEE1_ID' AND status = 'pending' LIMIT 1")

    # Organizer cancels invitation
    print_step "Organizer cancels invitation"
    response=$(api_call "DELETE" "/invitations/$new_inv_id" "$TOKEN_ORGANIZER" "" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify invitation status changed to cancelled
    verify_invitation_status "$new_inv_id" "cancelled"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 8: Already Invited Error
##############################################################################
test_already_invited_error() {
    print_test_header "Already Invited Error - Duplicate Prevention"

    # Send invitation to Invitee1
    invitation_data="{\"invitee_ids\": [\"$INVITEE1_ID\"]}"
    api_call "POST" "/activities/$PUBLIC_ACTIVITY/invitations" "$TOKEN_ORGANIZER" "$invitation_data" "200" > /dev/null

    # Try to send another invitation to same user
    print_step "Try to send duplicate invitation"
    response=$(api_call "POST" "/activities/$PUBLIC_ACTIVITY/invitations" "$TOKEN_ORGANIZER" "$invitation_data" "400")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify error response
    if echo "$response" | grep -q "ALREADY_INVITED\|already.*invited"; then
        print_success "Correct error response received"
    else
        print_failure "Error response missing or incorrect"
        mark_test_failed
        return 1
    fi

    # Verify only 1 invitation exists (not duplicated)
    local inv_count=$(db_query "SELECT COUNT(*) FROM activity.activity_invitations WHERE activity_id = '$PUBLIC_ACTIVITY' AND invitee_id = '$INVITEE1_ID' AND status = 'pending'")

    if [ "$inv_count" = "1" ]; then
        print_success "No duplicate invitation created"
    else
        print_failure "Duplicate invitations found: $inv_count"
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 9: Invitation to Invite-Only Activity
##############################################################################
test_invite_only_activity() {
    print_test_header "Invite-Only Activity - Invitation Required"
    cleanup_invitations "$INVITE_ONLY"

    # Send invitation to invite-only activity
    print_step "Send invitation to invite-only activity"
    invitation_data="{\"invitee_ids\": [\"$INVITEE1_ID\"]}"
    response=$(api_call "POST" "/activities/$INVITE_ONLY/invitations" "$TOKEN_ORGANIZER" "$invitation_data" "200")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Get invitation ID
    local inv_id=$(db_query "SELECT id FROM activity.activity_invitations WHERE activity_id = '$INVITE_ONLY' AND invitee_id = '$INVITEE1_ID' AND status = 'pending' LIMIT 1")

    # Verify invitation created
    verify_invitation_status "$inv_id" "pending"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Accept invitation
    print_step "Accept invitation to invite-only activity"
    api_call "POST" "/invitations/$inv_id/accept" "$TOKEN_INVITEE1" "" "200" > /dev/null

    # Verify participant joined
    verify_participant_exists "$INVITE_ONLY" "$INVITEE1_ID" "registered" "member"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    mark_test_passed
    return 0
}

##############################################################################
# TEST 10: Non-Organizer Cannot Send Invitations
##############################################################################
test_non_organizer_cannot_invite() {
    print_test_header "Non-Organizer Cannot Invite - Permission Denied"

    # Regular user tries to send invitation
    print_step "Non-organizer tries to send invitation"
    invitation_data="{\"invitee_ids\": [\"$INVITEE2_ID\"]}"
    response=$(api_call "POST" "/activities/$PUBLIC_ACTIVITY/invitations" "$TOKEN_FREE1" "$invitation_data" "403")

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
# TEST 11: Cannot Accept Already Accepted Invitation
##############################################################################
test_cannot_accept_twice() {
    print_test_header "Cannot Accept Twice - Already Processed"

    # Try to accept already accepted invitation
    if [ -z "$INVITATION_ID_1" ]; then
        INVITATION_ID_1=$(db_query "SELECT id FROM activity.activity_invitations WHERE activity_id = '$PUBLIC_ACTIVITY' AND invitee_id = '$INVITEE1_ID' AND status = 'accepted' LIMIT 1")
    fi

    print_step "Try to accept already accepted invitation"
    response=$(api_call "POST" "/invitations/$INVITATION_ID_1/accept" "$TOKEN_INVITEE1" "" "400")

    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify error response
    if echo "$response" | grep -q "ALREADY_ACCEPTED\|already.*accepted\|INVALID_STATUS"; then
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
# TEST 12: Invitation Status Transitions
##############################################################################
test_invitation_status_transitions() {
    print_test_header "Invitation Status Transitions - Lifecycle"
    cleanup_invitations "$PUBLIC_ACTIVITY"

    # Create invitation
    print_step "Create invitation (pending)"
    invitation_data="{\"invitee_ids\": [\"$INVITEE1_ID\"]}"
    api_call "POST" "/activities/$PUBLIC_ACTIVITY/invitations" "$TOKEN_ORGANIZER" "$invitation_data" "200" > /dev/null

    local inv_id=$(db_query "SELECT id FROM activity.activity_invitations WHERE activity_id = '$PUBLIC_ACTIVITY' AND invitee_id = '$INVITEE1_ID' AND status = 'pending' LIMIT 1")

    # Verify pending status
    verify_invitation_status "$inv_id" "pending"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Accept invitation
    print_step "Accept invitation (pending → accepted)"
    api_call "POST" "/invitations/$inv_id/accept" "$TOKEN_INVITEE1" "" "200" > /dev/null

    # Verify accepted status
    verify_invitation_status "$inv_id" "accepted"
    if [ $? -ne 0 ]; then
        mark_test_failed
        return 1
    fi

    # Verify timestamps
    local responded_at=$(db_query "SELECT responded_at FROM activity.activity_invitations WHERE id = '$inv_id'")

    if [ -n "$responded_at" ] && [ "$responded_at" != "" ]; then
        print_success "Responded timestamp set: $responded_at"
    else
        print_failure "Responded timestamp not set"
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
    echo "INVITATION MANAGEMENT TEST SUITE"
    echo "================================================="
    echo ""

    generate_tokens

    echo ""
    echo "Running invitation tests..."
    echo ""

    test_send_single_invitation
    test_send_bulk_invitations
    test_get_received_invitations
    test_accept_invitation
    test_decline_invitation
    test_get_sent_invitations
    test_cancel_invitation
    test_already_invited_error
    test_invite_only_activity
    test_non_organizer_cannot_invite
    test_cannot_accept_twice
    test_invitation_status_transitions

    print_summary

    return $?
}

# Run tests
main
