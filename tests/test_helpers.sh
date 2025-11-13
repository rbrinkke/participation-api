#!/bin/bash

# test_helpers.sh
# Shared helper functions for database verification and API testing

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Database connection details
DB_CONTAINER="activity-postgres-db"
DB_USER="postgres"
DB_NAME="activitydb"

# API configuration
API_BASE="http://localhost:8004/api/v1/participation"

# Execute PostgreSQL query
db_query() {
    local query=$1
    docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "$query" 2>/dev/null
}

# Print test header
print_test_header() {
    local test_name=$1
    echo ""
    echo -e "${BLUE}[TEST $((TOTAL_TESTS + 1))]${NC} $test_name"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# Print step
print_step() {
    local message=$1
    echo -e "  ${YELLOW}→${NC} $message"
}

# Print success
print_success() {
    local message=$1
    echo -e "  ${GREEN}✅${NC} $message"
}

# Print failure
print_failure() {
    local message=$1
    echo -e "  ${RED}❌${NC} $message"
    FAILED_TESTS=$((FAILED_TESTS + 1))
}

# Mark test as passed
mark_test_passed() {
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo -e "  ${GREEN}✅ TEST PASSED${NC}"
}

# Mark test as failed
mark_test_failed() {
    echo -e "  ${RED}❌ TEST FAILED${NC}"
}

# Verify participant exists
verify_participant_exists() {
    local activity_id=$1
    local user_id=$2
    local expected_status=$3
    local expected_role=$4

    local result=$(db_query "SELECT status, role, is_deleted FROM activity.activity_participants WHERE activity_id = '$activity_id' AND user_id = '$user_id' ORDER BY joined_at DESC LIMIT 1")

    if [ -z "$result" ]; then
        print_failure "Participant record not found for user $user_id"
        return 1
    fi

    IFS='|' read -r status role is_deleted <<< "$result"

    if [ "$status" != "$expected_status" ]; then
        print_failure "Participant status: expected '$expected_status', got '$status'"
        return 1
    fi

    if [ "$expected_role" != "" ] && [ "$role" != "$expected_role" ]; then
        print_failure "Participant role: expected '$expected_role', got '$role'"
        return 1
    fi

    if [ "$is_deleted" = "t" ]; then
        print_failure "Participant is marked as deleted"
        return 1
    fi

    print_success "Participant exists: status=$status, role=$role"
    return 0
}

# Verify participant deleted
verify_participant_deleted() {
    local activity_id=$1
    local user_id=$2

    local is_deleted=$(db_query "SELECT is_deleted FROM activity.activity_participants WHERE activity_id = '$activity_id' AND user_id = '$user_id' ORDER BY joined_at DESC LIMIT 1")

    if [ "$is_deleted" = "t" ]; then
        print_success "Participant marked as deleted"
        return 0
    else
        print_failure "Participant not marked as deleted"
        return 1
    fi
}

# Verify waitlist position
verify_waitlist_position() {
    local activity_id=$1
    local user_id=$2
    local expected_position=$3

    local result=$(db_query "SELECT position, is_deleted FROM activity.activity_waitlist WHERE activity_id = '$activity_id' AND user_id = '$user_id' ORDER BY joined_waitlist_at DESC LIMIT 1")

    if [ -z "$result" ]; then
        print_failure "Waitlist record not found for user $user_id"
        return 1
    fi

    IFS='|' read -r position is_deleted <<< "$result"

    if [ "$is_deleted" = "t" ]; then
        print_failure "Waitlist record is marked as deleted"
        return 1
    fi

    if [ "$position" != "$expected_position" ]; then
        print_failure "Waitlist position: expected $expected_position, got $position"
        return 1
    fi

    print_success "Waitlist position: $position"
    return 0
}

# Verify waitlist removed
verify_waitlist_removed() {
    local activity_id=$1
    local user_id=$2

    local is_deleted=$(db_query "SELECT is_deleted FROM activity.activity_waitlist WHERE activity_id = '$activity_id' AND user_id = '$user_id' ORDER BY joined_waitlist_at DESC LIMIT 1")

    if [ "$is_deleted" = "t" ]; then
        print_success "Waitlist record marked as deleted"
        return 0
    else
        print_failure "Waitlist record not marked as deleted"
        return 1
    fi
}

# Verify activity counter
verify_activity_counter() {
    local activity_id=$1
    local expected_count=$2

    local counter=$(db_query "SELECT current_participants FROM activity.activities WHERE id = '$activity_id'")

    if [ "$counter" = "$expected_count" ]; then
        print_success "Activity counter: $counter/$expected_count"
        return 0
    else
        print_failure "Activity counter: expected $expected_count, got $counter"
        return 1
    fi
}

# Verify invitation status
verify_invitation_status() {
    local invitation_id=$1
    local expected_status=$2

    local status=$(db_query "SELECT status FROM activity.activity_invitations WHERE id = '$invitation_id'")

    if [ "$status" = "$expected_status" ]; then
        print_success "Invitation status: $status"
        return 0
    else
        print_failure "Invitation status: expected $expected_status, got $status"
        return 1
    fi
}

# Verify attendance record
verify_attendance() {
    local activity_id=$1
    local user_id=$2
    local expected_status=$3

    local status=$(db_query "SELECT status FROM activity.activity_attendance WHERE activity_id = '$activity_id' AND user_id = '$user_id' ORDER BY marked_at DESC LIMIT 1")

    if [ "$status" = "$expected_status" ]; then
        print_success "Attendance status: $status"
        return 0
    else
        print_failure "Attendance status: expected $expected_status, got $status"
        return 1
    fi
}

# Verify attendance confirmation count
verify_confirmation_count() {
    local activity_id=$1
    local user_id=$2
    local expected_count=$3

    local count=$(db_query "SELECT confirmation_count FROM activity.activity_attendance WHERE activity_id = '$activity_id' AND user_id = '$user_id' ORDER BY marked_at DESC LIMIT 1")

    if [ "$count" = "$expected_count" ]; then
        print_success "Confirmation count: $count"
        return 0
    else
        print_failure "Confirmation count: expected $expected_count, got $count"
        return 1
    fi
}

# Verify participant count
verify_participant_count() {
    local activity_id=$1
    local expected_count=$2

    local count=$(db_query "SELECT COUNT(*) FROM activity.activity_participants WHERE activity_id = '$activity_id' AND is_deleted = false")

    if [ "$count" = "$expected_count" ]; then
        print_success "Participant count: $count"
        return 0
    else
        print_failure "Participant count: expected $expected_count, got $count"
        return 1
    fi
}

# Verify no participant record
verify_no_participant() {
    local activity_id=$1
    local user_id=$2

    local count=$(db_query "SELECT COUNT(*) FROM activity.activity_participants WHERE activity_id = '$activity_id' AND user_id = '$user_id' AND is_deleted = false")

    if [ "$count" = "0" ]; then
        print_success "No participant record exists (correct)"
        return 0
    else
        print_failure "Participant record exists when it shouldn't"
        return 1
    fi
}

# Make API call and verify HTTP status
api_call() {
    local method=$1
    local endpoint=$2
    local token=$3
    local data=$4
    local expected_status=$5

    local url="$API_BASE$endpoint"

    if [ "$method" = "GET" ]; then
        response=$(curl -s -w "\n%{http_code}" -X GET "$url" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json")
    elif [ "$method" = "POST" ]; then
        if [ -n "$data" ]; then
            response=$(curl -s -w "\n%{http_code}" -X POST "$url" \
                -H "Authorization: Bearer $token" \
                -H "Content-Type: application/json" \
                -d "$data")
        else
            response=$(curl -s -w "\n%{http_code}" -X POST "$url" \
                -H "Authorization: Bearer $token" \
                -H "Content-Type: application/json")
        fi
    elif [ "$method" = "DELETE" ]; then
        response=$(curl -s -w "\n%{http_code}" -X DELETE "$url" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json")
    fi

    # Split response and status code
    http_code=$(echo "$response" | tail -n1)
    response_body=$(echo "$response" | head -n-1)

    if [ "$http_code" = "$expected_status" ]; then
        print_success "API call: $method $endpoint → HTTP $http_code"
        echo "$response_body"
        return 0
    else
        print_failure "API call: $method $endpoint → HTTP $http_code (expected $expected_status)"
        echo "Response: $response_body" >&2
        return 1
    fi
}

# Print test summary
print_summary() {
    echo ""
    echo "================================================="
    echo -e "${BLUE}TEST SUMMARY${NC}"
    echo "================================================="
    echo "Total tests: $TOTAL_TESTS"
    echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
    echo -e "${RED}Failed: $FAILED_TESTS${NC}"

    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
        echo "================================================="
        return 0
    else
        echo -e "${RED}❌ SOME TESTS FAILED${NC}"
        echo "================================================="
        return 1
    fi
}
