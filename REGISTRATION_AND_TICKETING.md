# Registration, Capacity and Ticketing

## Registration state machine

```text
                         private event
new ------------------------> pending ----approve----> processing
 |                                |                       |
 | public                         +----reject----> rejected|
 v                                                        v
processing --seat reserved--------------------------> confirmed
    |                                                      |
    | full + waitlist enabled                              +--> checked_in
    v                                                      |
waitlisted --atomic promotion claim--> processing          +--> cancelled
    |                                                      |
    +---------------- cancel ------------------------------> cancelled

pending --attendee/organizer cancel--> cancelled
confirmed --attendee/organizer cancel--> cancelled + release seat + promote next
```

`processing` is an internal recoverable state. API clients normally observe `pending`, `waitlisted`, `confirmed`, `checked_in`, `cancelled` or `rejected`.

At startup, token evidence completes an interrupted reservation, an unreserved private approval returns to `pending`, and an interrupted public request is safely reserved, waitlisted or cancelled according to the current event window and capacity. Confirmed legacy records without valid tickets receive durable jobs before traffic is accepted.

## Capacity invariant

For an active event:

```text
registeredCount == len(confirmedRegistrationIds)
registeredCount <= capacity
```

The registration `_id` is the seat-reservation token. Reserving a seat atomically checks capacity, adds that token and increments the count in one event-document update. If a database response is ambiguous, a retry checks for the same token; it never consumes a second seat.

Registration insertion happens before reservation. A unique `(userId, eventId)` index prevents duplicate registrations. A retry that finds an internal `processing` registration resumes the state machine. It does not perform a read-then-write capacity allocation.

Cancellation conditionally changes the registration, removes only its token and decrements once. Retrying an ambiguous cancellation is safe. Event cancellation closes the event, clears reservations, cancels active registrations and invalidates issued tickets; repeating the operation completes any interrupted compensation.

## Waitlist policy

- Waitlisting is configurable per event with `allowWaitlist`.
- Public registration at capacity receives a monotonically increasing `waitlistSequence`.
- When a confirmed seat is released, the earliest waiting registration is atomically claimed as `processing`.
- The ordinary tokenized seat reservation is then used. Concurrent promotions therefore cannot exceed capacity.
- If the seat cannot be reserved, the claimed registration returns to `waitlisted`.
- Private-event requests remain `pending` for explicit organizer approval; a full event leaves approval pending rather than silently overbooking.

## Ticket status

- `NOT_REQUIRED`: registration is not currently ticket-eligible.
- `PENDING`: durable job exists and generation has not completed.
- `READY`: a valid issued ticket exists.
- `RETRYABLE`: generation failed and remains eligible for automatic/manual retry.
- `FAILED`: retry limit was exhausted; the attendee may explicitly requeue.

Cancelled/rejected registrations cannot fetch a ticket. Cancellation invalidates any previously issued ticket. Checked-in tickets remain visible as history but a second scan is rejected.

## Counts

- `registeredCount`: confirmed plus checked-in seats; pending, waitlisted, cancelled and rejected do not consume capacity.
- Organizer analytics separately expose pending, waitlisted, confirmed (including checked-in capacity), checked-in, rejected and cancelled counts.
- CSV export includes registration state, ticket state and check-in time.
