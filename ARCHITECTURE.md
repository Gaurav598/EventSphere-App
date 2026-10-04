# EventSphere Upgrade Architecture

## Runtime components

- Flutter uses feature-scoped services and `ChangeNotifier` providers. Tokens and downloaded tickets are stored with `flutter_secure_storage`.
- FastAPI routers validate transport input and delegate lifecycle rules to services.
- MongoDB is authoritative for users, events, registrations, favorites, tickets and durable `ticket_jobs`.
- Redis is optional for event-list caching, rate limiting and best-effort Pub/Sub. Registration and ticket correctness do not depend on Pub/Sub delivery.
- A lightweight ticket worker starts with FastAPI. Multiple replicas may run it because jobs are atomically leased.

## Data ownership

`events.createdBy` is the organizer boundary. Every organizer mutation, registration list/export, check-in and analytics query resolves events through that boundary. An `admin` role alone does not grant access to another organizer's event.

Public event discovery excludes private and deleted events. Private events are resolved by their cryptographically random invite code, and the code is verified again when registration is submitted so knowing an event ObjectId is insufficient. Public and attendee DTOs never echo that organizer-only secret. Invite uniqueness uses a partial index over string values so public events with a null code do not conflict. Favorites use a unique `(userId, eventId)` index and omit deleted events when read.

## Durable ticket flow

```text
confirmed registration
        |
        v
upsert ticket_jobs(registrationId, pending)  -- persisted before API success
        |
        v
atomic lease: pending/retryable -> processing
        |
        +---- success ----> unique ticket insert -> registration.ticketStatus=READY
        |
        +---- failure ----> retryable + backoff -> FAILED after max attempts
                              |
                              +-> attendee may explicitly requeue
```

Expired processing leases are reclaimed continuously. Ticket generation is idempotent through unique indexes on `tickets.registrationId` and `ticket_jobs.registrationId`.

## QR trust boundary

QR data is an HMAC-SHA256 signed canonical payload containing registration, event and user identifiers, issue time, payload type and version. Check-in verifies the signature, exact issued ticket record, ticket validity, claimed user/event association, organizer ownership and registration status. The final `confirmed -> checked_in` update is conditional, so concurrent scans have one winner.

An offline QR display is only a cached presentation. It never changes registration state and cannot bypass authoritative server check-in.

## Startup reconciliation

Before accepting traffic, the backend creates required indexes, recovers interrupted `processing` registrations according to event type and reservation-token evidence, backfills missing durable ticket jobs, and rebuilds each event's reservation-token array and `registeredCount` from confirmed/checked-in registrations. This backfills legacy v1 data for the new idempotent capacity model. On very large deployments this reconciliation should become an explicit migration rather than startup work.

## Operational boundaries

- Redis failure degrades caching, rate limiting and realtime hints; MongoDB-backed lifecycle work remains available.
- MongoDB availability is required for API readiness.
- The in-process worker is intentionally lightweight. A separate worker deployment can be introduced later without changing the persisted job schema.
- No email, push-notification, payment or offline check-in delivery is claimed by this upgrade.
