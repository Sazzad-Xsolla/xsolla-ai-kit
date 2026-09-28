# Events

Stage OpenAPI and local runtime snapshots were checked on 2026-09-23; the
event route, its auth and the publisher rule were rechecked on 2026-09-25.
Stage deployments churn and the revision is not pinned here, so revalidate
before writes.

Events go to **qp-events-collector**, not to qp-server. Sending an event to
qp-server produces a 404 that looks like a missing quest.

## Collector route and auth

**Live stage evidence rechecked 2026-09-28:** the collector OpenAPI lists
`POST /api/v2/events` with BasicAuth, plus the service-key and Bearer lanes.
The old `/api/v2/projects/{project_id}/events` route is gone, and there is no
merchant-prefixed event route. Use only `/api/v2/events`.

At bring-up, fetch the collector OpenAPI and confirm that the route and the
BasicAuth scheme are still present. An `OPTIONS` request may answer `405` with
`Allow: POST`; that confirms the route is POST-only, not that the route is
missing. On the fixed stage deployment, a project Basic request with a missing
body field reached validation with HTTP 422, and a matching authorized event
returned HTTP 200 with an `event_id`. Send the project's Basic credential only
after the quest scope and reward wallet preflights pass, with the matching
`publisher` block. Route availability and `event_id` are not execution or
reward proof.

The service-key and Bearer lanes remain explicit alternatives when a valid
credential is supplied, not credentials to guess or silently substitute. If the
live Basic request returns 401, report the exact auth response and stop; do not
use the old project route. A 404 plain text `Cannot POST <path>` follows the
route-missing rule in [`auth-and-environment.md`](auth-and-environment.md).

A mixed request (for example, "create the quest, fill it in, then send a test
event") still runs each approved step through its own confirmation. If the
collector route is absent or a Web3 preflight fails, stop before the blocked
mutation, report the exact blocker, and do not claim execution verification.

## Payload

```json
{
  "idempotency_key": "<uuid>",
  "name": "<event_name from the trigger>",
  "client_timestamp": "2026-09-22T10:30:00Z",
  "user_ids": [{"identifier_type": "xsolla_id", "value": "<uuid>"}],
  "quest_id": "<uuid>",
  "scope": "private",
  "publisher": {"publisher_id": "<string>", "project_id": "<string>"},
  "properties": {"any": "string values only"}
}
```

| Field | Required | Rules |
|---|---|---|
| `idempotency_key` | yes | a valid, non-zero UUID. Any version is accepted despite the schema hinting at v4 |
| `name` | yes | must match the `event_name` on the quest's `dynamic_event` trigger |
| `client_timestamp` | yes | RFC3339 |
| `user_ids` | yes | at least one entry |
| `quest_id` | no | a valid UUID when present. Restricts matching to that one quest; without it, every live quest of the project's account with that `event_name` runs |
| `scope` | no | `global`, `private`, `within_project`, `within_quest`, `within_publisher`. Defaults to `private`. It decides which quests' event-count conditions can count this event later, not which quest runs. Keep the default unless the developer asks. The published schema shows a bare string and the older struct hint lists only three values; the server accepts all five |
| `publisher` | always send it | see "The `publisher` block" below |
| `properties` | no | string values only |

`user_ids[].identifier_type` is `xsolla_id`, `gamer_id`, `guest_id` or `email`.
An `xsolla_id` value must parse as a UUID; an `email` value must contain `@`;
`gamer_id` and `guest_id` need only be non-empty.

### The `publisher` block

A quest created on the project route always carries the server-set
`publisher_id` (the merchant id) and `project_id`. The collector does not fill
`publisher` from a route; it keeps whatever you send. Always send

`{"publisher_id": "<XSOLLA_MERCHANT_ID>", "project_id": "<XSOLLA_PROJECT_ID>"}`

with both ids as **strings**, and check that they equal the quest's
`publisher_id` and `project_id` as read back from a single-quest GET (or the
create response), never from the quest list: list items carry `project_id`
but no `publisher_id`. If that read has no `publisher_id`, or its values
differ from the credential's, stop and ask; do not fill anything in.

What the lanes do with the block (from code, collector f63f2b26ce):

- Bearer lane: both ids are required and must be positive-integer strings,
  and they must match the token's project, or the collector answers 401
  `{"error":"Invalid credential"}`.
- API-key lane: the block is optional, but if present `publisher_id` is
  required. The collector does not cross-check it. A value that does not
  match the quest is dropped silently downstream and leaves **no** qp-data
  row, not even `NOT_TRIGGERED` (per team docs; inferred, consumer code not
  read).

Some rewards read the merchant or project from the event, not from the quest,
and fail without the block; see "Event-side requirements" in
[`rewards.md`](rewards.md). The rule above already covers them.

A quest with a `web3_item` or `web3_token` reward needs an `xsolla_id` entry
whose user already has a wallet. Check it before submitting; see
[`rewards.md`](rewards.md).

The account is **not** in the body. On the old project route the collector
took it from the project in the path.

A 200 returns `{"idempotency_key": "...", "event_id": "<uuid>"}`.

The scopeless `POST /api/v2/events` accepts the fixed stage publisher Basic
lane when the body carries matching `publisher_id` and `project_id`; it also
advertises API-key and Publisher Bearer lanes. Use the project Basic lane for
this skill when its live auth check succeeds. Do not guess or substitute an
API key or Bearer token from another account, and never call
`/api/v2/debug/trigger-outbox`.

## Before sending

- **Wait after a quest write.** The pipeline caches quest config for up to 60
  seconds (see [`auth-and-environment.md`](auth-and-environment.md)). After
  creating, activating, pausing or editing a quest, wait about 90 seconds
  before the first event, or the event may be matched against the old config.
  Right after a pause, an event can still run the quest as active; for a quest
  with an `issue_reward`, say so and wait before sending.
- **Check the window.** The quest must be `active` and inside its dates at
  event time; see [`quest-document.md`](quest-document.md).
- **Show the exact payload**, including the `idempotency_key` you generated.
  If the developer changes anything, generate a new key.

## Test events and `load_test`

`properties.load_test` set to exactly `"true"` makes quest-engine drop the
event before it starts a workflow, where the bypass is enabled (see
[`auth-and-environment.md`](auth-and-environment.md)). The collector still
returns 200 with an `event_id`, but the quest never runs and qp-data gets no
row. Report that as the expected outcome, not as unverified.

- Use it only when the developer wants to test acceptance, not execution.
- To verify execution, omit it. Each untagged event that matches a live quest
  starts a billable workflow and runs its actions for real, so say so and get
  the developer's explicit choice. Removing the flag from a test payload turns
  it into a real event and needs the same decision.
- Any value other than the exact string `"true"` does not bypass.

## Idempotency

There are two separate mechanisms and they are easy to confuse:

- the body field `idempotency_key`, which the platform uses as the message key
- a generic HTTP `X-Idempotency-Key` header handled by middleware, which must
  be exactly 36 characters

Use the body field. Generate a fresh UUID per event.

## After an uncertain response

If the request times out or the outcome is otherwise unknown, **stop**. Do not
resend, not with the same key and not with a new one. A timeout is not a
failure: the event may have been accepted and the quest may already be paying
out. Report "result unknown", and use the execution read-back to find out what
really happened.

If the developer later agrees to a new event, use the saved payload or ask
them to paste it again, show it, and get a new yes. Never rebuild it from memory or from a read-back
`eventBody`.

### An event the developer sent, not you

When the developer says their own script or tool sent an event and asks what
happened, you never saw the request or its response. Do not resend it to find
out, and do not treat it as yours. Ask for the exact payload (or at least the
quest id, `name`, `idempotency_key` and user), which user it named, and when
it was sent, and whether they got an `event_id` back. Then verify read-only
as in [`verification.md`](verification.md). A key the developer's script
generated or reused is a developer-supplied key: the match is weaker
identification, so also require the user and a `server_timestamp` close to
the stated send time, and say so in the report.

If the developer reports a timeout, do not infer whether the event was
accepted. The current fixed stage Basic lane can authenticate, but a stale
deployment or wrong credential may still return 401. Ask which route and
header were used, then verify read-only with the supplied event identifiers;
do not resend an uncertain request.
