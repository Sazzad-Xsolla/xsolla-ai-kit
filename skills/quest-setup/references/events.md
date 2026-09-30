# Events

This skill sends events only through the production event-ingestion integration.
Confirm its OpenAPI and accepted credential lane before the first production
event. Never use a staging service, internal service key or guessed route as a
fallback.

## Production event gate

Before sending an event:

1. Fetch the production event-ingestion OpenAPI and confirm the event
   operation and authentication lane.
2. Confirm that the event's publisher/project block matches the selected
   production quest scope.
3. If the route or credential lane is not confirmed, stop and report that
   production event execution is not verified.
4. If the quest is inactive or outside its dates, say that an event could not
   run it and offer activation first.

For a mixed request, complete the separately confirmed quest work first. Then
report the event blocker with the quest id, current status and trigger name.
Do not claim the quest was verified.

## Payload

```json
{
  "idempotency_key": "<uuid>",
  "name": "<event_name from the trigger>",
  "client_timestamp": "<RFC3339 timestamp>",
  "user_ids": [{"identifier_type": "xsolla_id", "value": "<uuid>"}],
  "quest_id": "<uuid>",
  "scope": "private",
  "publisher": {"publisher_id": "<string>", "project_id": "<string>"},
  "properties": {"key": "string value"}
}
```

| Field | Required | Rules |
|---|---|---|
| `idempotency_key` | yes | valid, non-zero UUID; generate a fresh one per event |
| `name` | yes | must match the quest trigger's `event_name` |
| `client_timestamp` | yes | RFC3339 |
| `user_ids` | yes | at least one entry |
| `quest_id` | no | valid UUID when present; restricts matching to one quest |
| `scope` | no | use the production contract's default unless the developer asks otherwise |
| `publisher` | yes for this skill | must match the quest's read-back scope |
| `properties` | no | use only values accepted by the live contract; never include secrets |

`user_ids[].identifier_type` is `xsolla_id`, `gamer_id`, `guest_id` or `email`
when supported by the live contract. A Web3 reward requires an `xsolla_id`
whose user already has a wallet. Check it before submitting; see
[`rewards.md`](rewards.md).

A successful response should return an event identifier. Keep it and use it to
correlate the read-only execution result. If the response shape differs from
this reference, follow the live OpenAPI.

## Before sending

- Wait for the production runtime to refresh after a quest write, according to
  the live contract.
- Check that the quest is active and inside its date window.
- Show the exact payload, including the generated `idempotency_key`.
- If the developer changes anything, generate a new key and show the payload
  again.

## Test events and `load_test`

Only use a test bypass when the production contract documents it and the
developer explicitly wants acceptance testing rather than execution. To verify
execution, omit the bypass and warn that matching actions may run for real.

## Idempotency

The body `idempotency_key` identifies the event. Do not confuse it with an
optional HTTP idempotency header unless the live contract requires one. Generate
a fresh UUID per event.

## After an uncertain response

If the request times out or the outcome is otherwise unknown, stop. Do not
resend with the same or a new key. Report "result unknown" and use the
read-only execution check to find out what happened.

If the developer later agrees to a new event, show the saved payload or ask for
it again, generate a new key and get a new yes.

### An event the developer sent, not you

When the developer says their own script or tool sent an event, you never saw
the request or response. Do not resend it. Ask for the payload or, at minimum,
the quest id, name, idempotency key, user and send time. Then verify read-only
as described in [`verification.md`](verification.md).
