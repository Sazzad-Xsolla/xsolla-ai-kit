---
name: quest-setup
description: >-
  Creates, inspects, edits and activates Xsolla Quest Platform quests
  conversationally, and submits a quest event to make a quest run. Covers the
  whole quest document: the node graph and its connections, all seven node
  subtypes, the condition grammar, activation limits, and all nine reward types
  including web3_item and web3_token ERC-20 payouts. Use when setting up a
  quest, adding a trigger or a condition, attaching a reward, editing or
  activating an existing quest, or firing a test event, including "create a
  quest", "add a Web3 reward to my quest", "make a quest that pays USDC",
  "trigger my quest", "send a quest event", "list my quests", "activate a
  quest", "quest platform API".
metadata:
  owner: r.aliyev
  domain: quests
  status: draft
---

## Status

This skill is a **draft**. On stage the publisher Basic credential works on
merchant-scoped project routes, and the fixed collector accepts
`POST /api/v2/events` with matching publisher fields (rechecked 2026-09-28).
Production is not checked. An accepted `event_id` is not execution or delivery
proof; verify qp-data, provider settlement and Backpack or chain read-backs.

## When to use

Use this skill when the developer wants to manage quests on the Xsolla Quest
Platform:

- Create a quest, as a draft first and then activate it
- Add triggers, conditions or reward actions to a quest
- List, view or edit existing quests
- Submit a single quest event to make a quest run

Out of scope: reading back whether a quest executed, on-chain finality, wallet
balances and Backpack display. This skill configures quests and submits
events. It reports that an event was accepted and never states that a reward
was delivered.

## Prerequisites

Follow [`references/auth-and-environment.md`](references/auth-and-environment.md)
for the credential, hosts, merchant-scoped routes, onboarding and scope. The
publisher Basic credential is the merchant id plus the project's API key. Do
not search for another credential when a value is missing. Onboarding is a
separate offered write and requires the developer to confirm the project is
their merchant's.

## Source of truth

1. Routes, path parameters, envelopes and top-level required fields come from
   the live OpenAPI document fetched for the services the task calls.
2. Node subtypes, parameters, conditions, rewards and rules come from this
   skill's references.
3. On conflict, OpenAPI wins on shape and the references win on rules. If
   neither source answers, ask the developer rather than guessing.

The qp-server document declares no security schemes; that does not make a
route unauthenticated. A plain-text `Cannot GET <path>` or `Cannot POST
<path>` is a router miss, not an auth or project failure.

## Reference material

- [`references/auth-and-environment.md`](references/auth-and-environment.md): host, credential, routes, access check and scope
- [`references/quest-document.md`](references/quest-document.md): the quest graph, conditional requirements, full-document PUT
- [`references/node-subtypes.md`](references/node-subtypes.md): the seven accepted node subtypes and their parameters
- [`references/conditions.md`](references/conditions.md): condition types, operands, operators and event counting
- [`references/rewards.md`](references/rewards.md): the nine reward types and their bodies, including Web3 rewards
- [`references/events.md`](references/events.md): submitting a quest event

## Flow

1. **Bring-up.** Fetch the OpenAPI documents for the services the task calls,
   run the scoped project and quest-list reads, show the merchant id,
   `project_id`, `name` and `status`, and get confirmation before a write.
2. **Draft.** Create the quest as `inactive` with `name`, `type`, `status` and
   `created_by`; the project route stamps `publisher_id` and `project_id` from
   the path. Show the body and get approval before `POST`.
3. **Fill in.** Gather required node values and connections, then follow the
   full-document PUT recipe in [`references/quest-document.md`](references/quest-document.md).
   Show the assembled document and the impact of any external action before
   sending it. Do not silently invent a trigger, action or reward value.
4. **Activate.** Use a separate PUT after checking the graph has at least two
   nodes, a trigger-to-action path, no intended orphan nodes and no cycle.
   Confirm dates and activation limits. For a Web3 reward, follow
   [`references/rewards.md`](references/rewards.md), confirm the SKU, amount
   and recipient wallet, and get approval before activation.
5. **Edit.** Read the quest, change the full document and warn that `PUT`
   replaces everything omitted from the body. Show a before/after diff and
   read the quest back after the approved write. Pause or delete only after a
   fresh read and explicit approval.
6. **Event.** Fetch the collector OpenAPI and confirm `POST /api/v2/events`
   still lists BasicAuth. Build the payload, generate a fresh UUID
   `idempotency_key`, set an RFC3339 `client_timestamp`, show the exact body
   and a copy-paste `curl` example using the project's Basic credential,
   confirm with the developer, and submit it only after the quest is active
   and its Web3 wallet preflight passes. Do not use the removed project route
   or switch credentials automatically. If the route or BasicAuth is absent,
   stop and report the blocker.
7. **Report.** On success, report "event accepted, `event_id=<id>`" and read
   the execution back from qp-data. Report the completed action and provider
   transaction hash when present. A collector `event_id` alone is not
   execution or delivery proof; never claim a reward was delivered without
   the required chain or Backpack read-back.

## Safety stops

- Read back and show the resolved scope before the first write, and get
  confirmation. Ask before every non-GET call and show its exact body.
- Before activation, show every externally observable action and get explicit
  confirmation for its impact. An `issue_reward` can create real payouts;
  `send_http_webhook` sends event data to an external URL;
  `send_xsolla_app_notification` sends a user notification. Do not activate a
  `webshop_personalization` node as if it were a working personalization action.
- Urgency never supplies missing values. Ask for `type`, `created_by`, trigger,
  action, dates and activation limits, and use one approval for the exact body
  shown after all answers are applied.
- If `activation_limits` is absent, ask the developer to explicitly choose
  unlimited repeat behavior and acknowledge that every qualifying event may run
  the action. Do not silently choose a limit or omit this decision.
- Ask for confirmation before submitting an event.
- After an uncertain event response, such as a timeout, **do not resend**:
  not with the same idempotency key and not with a new one. A timeout is not a
  failure. Report "result unknown" and stop.
- If the developer reports that a reward did not arrive, do not resend the
  event to retry it. Fix the quest first, then send a new event with a new key
  only after the developer confirms.
- Never resend an event to retry a Web3 reward. The Web3 claim is not
  idempotent and may already have paid.
- Never claim a reward was delivered.

## Errors

Branch on the HTTP status. The only body check is on a 404: a plain-text body
and a JSON body mean different things. The API has no stable machine-readable
error codes.

| Status | What to tell the developer |
|---|---|
| 401 | Credential missing or rejected. Read the body and never switch credentials automatically. |
| 403 | The lane lacks capability or is not allowed on this route; do not retry. |
| 404, plain text | Router miss. Do not report it as an auth or project answer. |
| 404, JSON body | Project or quest is not visible with this credential; do not guess which cause applies. |
| 409 | Conflict. Report it verbatim. |
| 422 | Validation failed. Show `detail` verbatim. |
| 5xx | Retry reads with backoff only. Never auto-retry a write. |

A JSON 404 looks the same for an unknown project, a project that is not
onboarded, and a project the key has no access to. This is deliberate, so the
API cannot be used to find out which projects use Quest Platform.

Two JSON body shapes exist. Failures before the request reaches a quest
operation, such as authentication, return `{"error": "..."}`. Failures inside
the operation return RFC 7807 `application/problem+json`. On 422 the `errors[]` array is
**not** filled in: per-field messages are flattened into one `detail` string
joined with `"; "`. Those `location: message` pairs may be shown to a human,
never parsed for control flow.

`ID 0` is a valid merchant ID and a valid project ID. Never treat it as an
absent value.
