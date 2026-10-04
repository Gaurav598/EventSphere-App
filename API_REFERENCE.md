# Upgrade API Reference

All JSON endpoints use `/api/v1`. Protected routes require `Authorization: Bearer <JWT>`. Success responses use `{success, data, message}`; domain failures use `{success:false,error:{code,message}}`.

## Authentication

| Method | Path | Purpose |
|---|---|---|
| POST | `/auth/register` | Create attendee or invited organizer. Organizer role requires `organizerCode` matching `ORGANIZER_SIGNUP_CODE`. |
| POST | `/auth/login` | Issue access token. Unknown email and wrong password both return generic invalid credentials. |
| GET/PUT | `/auth/me` | Read or update the authenticated profile. |

## Discovery and attendee actions

| Method | Path | Purpose |
|---|---|---|
| GET | `/events` | Paginated public events; supports category, location, date range and availability. |
| GET | `/events/search` | Paginated text search with date and availability filters. |
| GET | `/events/{id}` | Event details. Organizer invite secrets are not returned. |
| GET | `/events/invite/{code}` | Resolve a private invite without echoing the invite code. |
| GET | `/events/{id}/calendar` | Standards-compatible iCalendar download with UTC start/end. Missing end falls back to one hour. |
| POST | `/events/{id}/register` | Create pending, confirmed or waitlisted registration. Private events require their `inviteCode` in the request body. |
| GET | `/registrations/me` | Registration history with event, waitlist and ticket status. |
| DELETE | `/registrations/{id}` | Idempotently cancel an eligible registration. |
| GET | `/registrations/{id}/ticket` | Return an owned, valid issued ticket only. |
| POST | `/registrations/{id}/ticket/retry` | Requeue an eligible failed/retryable ticket job. |
| GET | `/favorites` | Current user's accessible favorite events. |
| POST/DELETE | `/events/{id}/favorite` | Idempotently add/remove favorite. |

Registration response example:

```json
{
  "registrationId": "...",
  "status": "confirmed",
  "ticketStatus": "PENDING"
}
```

## Organizer actions

Every route below is scoped to `events.createdBy == current organizer`.

| Method | Path | Purpose |
|---|---|---|
| GET/POST | `/admin/events` | List owned events or create one. |
| PUT/DELETE | `/admin/events/{id}` | Edit or cancel an owned event. |
| PATCH | `/admin/events/{id}/close-registration` | Close new registration. |
| GET | `/admin/events/{id}/registrations` | All registration lifecycle states and ticket status. |
| GET | `/admin/events/{id}/registrations/export` | Authorized CSV export. |
| PUT | `/admin/registrations/{id}/status` | `confirmed`, `rejected` or `cancelled`; transitions are constrained by current state. |
| POST | `/admin/events/{id}/checkin` | Validate `ticketPayload` and atomically check in. Raw registration IDs are not accepted. |
| GET | `/admin/analytics/summary` | Owned-event status and attendance counts. |
| GET | `/admin/analytics/top-events` | Owned-event ranking using real confirmed/checked-in registrations. |
| GET | `/admin/analytics/category-wise` | Owned-event category counts. |
| GET | `/admin/analytics/monthly-trend` | Owned-event registration trend. |

Important check-in error codes include `INVALID_TICKET`, `WRONG_EVENT`, `INVALID_TICKET_OWNER`, `ALREADY_CHECKED_IN`, `TICKET_EXPIRED`, `INVALID_STATUS` and `CHECKIN_CONFLICT`.
