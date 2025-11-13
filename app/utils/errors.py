from fastapi import HTTPException


def map_sp_error(error_code: str, error_message: str) -> HTTPException:
    """
    Map stored procedure error codes to HTTP exceptions.

    Args:
        error_code: Error code from SP (e.g., 'ACTIVITY_NOT_FOUND')
        error_message: Error message from SP

    Returns:
        HTTPException with appropriate status code and detail
    """
    # Error mapping for join_activity
    join_activity_errors = {
        'ACTIVITY_NOT_FOUND': (404, 'Activity not found'),
        'USER_NOT_FOUND': (404, 'User not found'),
        'ALREADY_JOINED': (400, 'Already joined this activity'),
        'BLOCKED_USER': (403, 'Cannot join this activity'),
        'FRIENDS_ONLY': (403, 'Activity is friends only'),
        'INVITE_ONLY': (403, 'Activity is invite only'),
        'PREMIUM_ONLY_PERIOD': (403, 'Activity is currently only open to Premium members'),
        'USER_BANNED': (403, 'Account is banned'),
        'ACTIVITY_IN_PAST': (400, 'Cannot join past activities'),
        'ACTIVITY_NOT_PUBLISHED': (400, 'Activity is not published'),
        'USER_IS_ORGANIZER': (400, 'Organizer cannot join own activity')
    }

    # Error mapping for leave_activity
    leave_activity_errors = {
        'ACTIVITY_NOT_FOUND': (404, 'Activity not found'),
        'NOT_PARTICIPANT': (400, 'Not a participant of this activity'),
        'IS_ORGANIZER': (403, 'Organizer cannot leave activity'),
        'ACTIVITY_IN_PAST': (400, 'Cannot leave past activities')
    }

    # Error mapping for cancel_participation
    cancel_participation_errors = {
        'ACTIVITY_NOT_FOUND': (404, 'Activity not found'),
        'NOT_PARTICIPANT': (400, 'Not a participant of this activity'),
        'ALREADY_CANCELLED': (400, 'Participation already cancelled'),
        'ACTIVITY_IN_PAST': (400, 'Cannot cancel past activities')
    }

    # Error mapping for promote_participant
    promote_errors = {
        'ACTIVITY_NOT_FOUND': (404, 'Activity not found'),
        'NOT_ORGANIZER': (403, 'Only organizer can promote participants'),
        'TARGET_NOT_MEMBER': (400, 'User is not a member participant'),
        'ALREADY_CO_ORGANIZER': (400, 'User is already a co-organizer')
    }

    # Error mapping for demote_participant
    demote_errors = {
        'ACTIVITY_NOT_FOUND': (404, 'Activity not found'),
        'NOT_ORGANIZER': (403, 'Only organizer can demote participants'),
        'NOT_CO_ORGANIZER': (400, 'User is not a co-organizer')
    }

    # Error mapping for mark_attendance
    attendance_errors = {
        'ACTIVITY_NOT_FOUND': (404, 'Activity not found'),
        'NOT_AUTHORIZED': (403, 'Only organizer or co-organizer can mark attendance'),
        'ACTIVITY_NOT_COMPLETED': (400, 'Activity has not yet completed'),
        'TOO_MANY_UPDATES': (400, 'Maximum 100 attendances per request')
    }

    # Error mapping for confirm_attendance
    confirm_errors = {
        'ACTIVITY_NOT_FOUND': (404, 'Activity not found'),
        'ACTIVITY_NOT_COMPLETED': (400, 'Activity has not yet completed'),
        'CONFIRMER_NOT_ATTENDED': (400, 'You must have attended status to confirm others'),
        'CONFIRMED_NOT_ATTENDED': (400, 'User does not have attended status'),
        'SELF_CONFIRMATION': (400, 'Cannot confirm your own attendance'),
        'ALREADY_CONFIRMED': (400, 'You already confirmed this user for this activity')
    }

    # Error mapping for invitations
    invitation_errors = {
        'ACTIVITY_NOT_FOUND': (404, 'Activity not found'),
        'NOT_INVITE_ONLY': (400, 'Activity is not invite-only'),
        'NOT_AUTHORIZED': (403, 'Only organizer or co-organizer can send invitations'),
        'TOO_MANY_INVITATIONS': (400, 'Maximum 50 invitations per request'),
        'INVITATION_NOT_FOUND': (404, 'Invitation not found'),
        'NOT_YOUR_INVITATION': (403, 'This invitation is not for you'),
        'ALREADY_RESPONDED': (400, 'Invitation already responded to'),
        'INVITATION_EXPIRED': (400, 'Invitation has expired'),
        'ACTIVITY_IN_PAST': (400, 'Activity has already occurred')
    }

    # Combine all error maps
    all_errors = {
        **join_activity_errors,
        **leave_activity_errors,
        **cancel_participation_errors,
        **promote_errors,
        **demote_errors,
        **attendance_errors,
        **confirm_errors,
        **invitation_errors
    }

    # Get status code and message
    status_code, detail = all_errors.get(error_code, (400, error_message))

    return HTTPException(status_code=status_code, detail=detail)
