# Verification

Verification is production-only. The event must pass the live gate in
[`events.md`](events.md), and the production execution service contract must
be confirmed before any read-back. Never use staging execution data as proof of
a production run.

## Read-back gate

1. Read the quest through the authenticated production Quest Platform scope.
2. Confirm that the quest belongs to that scope.
3. Fetch the production execution service OpenAPI and confirm the query and
   response fields before using them.
4. Query only the developer's own quest, user or event. Never use an unscoped
   query that could return another tenant's data.

The reference below is a candidate shape until the live contract confirms the
route and field names. Do not call a candidate route just because it appears in
this file.

## What comes back

An execution read may include a status, event identifier, quest identifier,
user identifier and action results. Treat unknown fields as opaque and report
them only when they explain the outcome.

| Result | Meaning |
|---|---|
| `COMPLETED` | the execution finished according to the production contract |
| `FAILED` | an action or condition failed; read the returned error |
| `IN_PROGRESS` | the condition or execution is not complete |
| `NOT_TRIGGERED` | the event was received but did not run the quest, when supported |

An `IN_PROGRESS` or missing row is not proof that a reward claim is still
running. Follow the live contract's timing and retry guidance.

## Correlate the submitted event first

Use the exact event identifier returned by event submission and match it to the
execution's event identifier. Also compare the quest id and user identity. If
any of these do not match, report that the event was not proven to execute this
quest.

Do not infer execution from a 200 event response alone. Do not resend an event
after a timeout or unknown response.

## Reading a row with several actions

Read each action result separately. An action absent from the result did not
run. A `COMPLETED` action inside an overall `FAILED` execution did happen and
is not rolled back. Do not resend a reward event merely to finish later nodes.

For a failed action, report the returned error verbatim and stop before any
retry that could create a duplicate external effect.

## Three separate claims

Keep these claims separate:

1. the event was accepted;
2. the quest execution completed;
3. the Web3 reward is visible in the player's Backpack or has reached finality.

This skill can report the first two when the production contracts prove them.
It must not claim the third from an execution row alone.

## When nothing comes back

Use the bounded read policy from the live production contract. If the event
identifier is absent after that policy, report that execution was not found and
do not resend automatically. A condition miss or activation limit may produce
no completed action; do not call it a reward failure without evidence.

## Unknown results

An unknown event or reward outcome is a safety stop. Preserve the original
event id, idempotency key, quest id, user and send time. Escalate with those
values or perform the documented read-only lookup. Never generate a new event
to discover what happened.
