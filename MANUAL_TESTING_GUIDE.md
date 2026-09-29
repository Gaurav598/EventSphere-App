# Manual Testing Guide

These scenarios are awaiting user execution. They are not recorded as passed by this document.

## Environment and accounts

1. Copy `.env.example` to `.env`; set a private `JWT_SECRET` and `ORGANIZER_SIGNUP_CODE` (at least 12 characters).
2. Start MongoDB, Redis, FastAPI and Flutter using your preferred local workflow.
3. Create Organizer A and Organizer B with the organizer invitation code. Create Attendee A, Attendee B and Attendee C without it.
4. Grant camera permission for the organizer device/browser when testing QR scanning. Keep network access enabled for authoritative check-in.

## 1. Public registration and ticket

Setup: Organizer A creates a public event in the future with capacity 2, end time after start and waitlist enabled.

Actions: Attendee A browses/searches, opens details, registers, opens My registrations and refreshes the ticket.

Expected: capacity becomes 1/2; registration is `confirmed`; ticket progresses `PENDING` to `READY`; QR contains a signed payload rather than a plain registration ID.

Failure symptoms: count changes twice, registration says ready without QR, QR contains only an identifier, or refresh creates multiple tickets.

## 2. Private approval and rejection

Setup: Organizer A creates a private event and shares its invite code. Attendees A and B submit requests.

Actions: Organizer approves A and rejects B.

Expected: both initially show `pending`; A becomes `confirmed` and receives a ticket; B becomes `rejected` and cannot display a QR; only A consumes capacity.

Failure symptoms: pending users consume seats, rejected user retains a ticket, or another organizer can act on the requests.

## 3. Capacity race

Setup: public event capacity 1, waitlist disabled.

Actions: submit A and B registrations as close together as possible from separate clients.

Expected: exactly one confirmation, one `EVENT_FULL`, count 1/1.

Failure symptoms: two confirmations or registered count greater than capacity. A real MongoDB concurrency run is required; mock tests are not a substitute.

## 4. Cancellation and waitlist

Setup: capacity 1, waitlist enabled. A registers; B then C join waitlist.

Actions: A cancels, then refresh all three clients and organizer registrations.

Expected: A is cancelled and QR is unavailable; B (earliest sequence) is confirmed and ticket generation begins; C remains waitlisted; count stays 1/1.

Failure symptoms: count reaches 0 or 2, C jumps B, A's QR remains fetchable, or multiple attendees are promoted.

## 5. Organizer isolation

Setup: Organizer A and B each own an event with registrations.

Actions: while authenticated as B, attempt A's edit, registration list/export, status update, analytics inference and check-in URLs.

Expected: A's event is not found/accessible; B's analytics include only B's events.

Failure symptoms: any A attendee identity, export, count or mutation is visible to B.

## 6. QR validation

Setup: obtain A's ready ticket and Organizer A's scanner.

Actions: scan normally, scan again, alter one QR character, scan it for another event, cancel a different ticket then scan it.

Expected: first scan succeeds and state becomes `checked_in`; repeat reports already used; tampered reports invalid; wrong event reports wrong event; cancelled ticket is rejected.

Failure symptoms: raw registration ID works, duplicate succeeds, or another organizer/event accepts the ticket.

## 7. Ticket retry and process interruption

Setup: confirmed registration with a pending job.

Actions: interrupt the API process after the registration response but before QR completion, restart it, and observe status. Separately induce a generator failure if you have a development fault hook, then use Retry.

Expected: persisted job survives restart; expired lease is reclaimed; status moves through `RETRYABLE`/`PENDING` to `READY`; only one ticket exists.

Failure symptoms: job remains processing forever, ticket is permanently lost, or duplicate QR records appear.

## 8. Event cancellation

Setup: event with confirmed, pending and waitlisted registrations plus issued tickets.

Actions: Organizer cancels/deletes the event; repeat the request if simulating an ambiguous timeout.

Expected: event disappears from discovery/favorites, unconsumed active registrations become cancelled, checked-in records remain as attendance history, count becomes zero and every ticket fails further server validation. Repeating completes safely.

Failure symptoms: active registrations or valid tickets remain, favorites crash, or count stays nonzero.

## 9. Favorites, filters and calendar

Actions: favorite events across different pages, restart the app, show Favorites, remove one, search with a date filter, paginate results and export an event to calendar.

Expected: server-backed favorites persist and deleted events disappear; search/date/page state remains coherent; calendar title, location, UTC start and end match the event.

Failure symptoms: favorites exist only in memory/current page, pagination drops the search, or calendar time/end is wrong.

## 10. Offline ticket display

Actions: open a ready ticket online once, disconnect network, reopen it, then reconnect and scan with the organizer.

Expected: attendee sees a clear “offline copy” warning; scanner still requires backend validation. Logging out removes cached tickets.

Failure symptoms: offline display marks attendance, a cancelled ticket is shown after a server rejection, or one user's cached ticket is visible after logout.
