# Changelog

## Platform upgrade — 2026-09-26

### Backend

- Replaced split increment/insert behavior with tokenized, idempotent seat reservations and recoverable registration states.
- Added safe cancellation, waitlist ordering/promotion, legacy counter reconciliation and idempotent event cancellation compensation.
- Added persistent MongoDB ticket jobs, atomic leases, retry/backoff, continuous expired-lease recovery and idempotent QR generation.
- Strengthened signed QR claims and organizer-scoped, concurrent-safe check-in.
- Scoped event CRUD, registrations, exports and all analytics to the owning organizer.
- Added attendee cancellation, favorites, calendar export and ticket retry APIs.
- Added event end time, waitlist configuration, ticket/check-in analytics fields and richer CSV export.
- Protected organizer signup with an environment-provided invitation code and removed committed demo credentials from documentation.
- Required the private-event invite code again at registration time instead of trusting knowledge of an event identifier.
- Added compound indexes for ownership, waitlists, jobs and favorites; pinned a Redis client compatible with the test fake.

### Flutter

- Separated registration lifecycle data from issued ticket data.
- Added pending, waitlisted, confirmed, ticket-processing, retryable/failed, rejected, cancelled and checked-in presentations.
- Added attendee cancellation, explicit ticket retry and secure offline ticket caching with logout cleanup and authoritative-check-in warnings.
- Updated scanner integration to submit the full signed QR payload; removed raw registration-ID check-in.
- Added persistent favorites, favorites view, card/detail bookmark controls, date filtering and contract-correct pagination.
- Added calendar export, event start/end time editing and waitlist configuration.
- Expanded organizer registration management to pending, confirmed, checked-in, waitlisted and history views with ticket status.
- Expanded organizer analytics with checked-in, waitlisted and cancelled counts sourced from the backend.
- Added organizer invitation-code input and safer deep-link handling for ticket details.
- Wired API `401` responses to clear in-memory authentication and route expired sessions back to login.

### Verification status

- Before the final implementation-only pass, the backend suite reported 10/10 passing and the added reliability/security module reported 6/6 passing.
- `flutter analyze` was run before the final pass: it reported no compile errors, but existing deprecation/info warnings remained.
- Per user instruction, Docker builds, emulator/device runs and final suites were not run after the last implementation changes. Follow `MANUAL_TESTING_GUIDE.md`.
