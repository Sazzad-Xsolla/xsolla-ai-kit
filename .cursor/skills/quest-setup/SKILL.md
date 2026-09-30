---
name: quest-setup
description: >-
  Creates, inspects and edits production Xsolla Quest Platform quests conversationally,
  submits a quest event, and verifies that the event actually made the quest
  execute. Covers the whole quest document: the node graph and its connections,
  the seven node subtypes, the condition grammar, activation limits, and the
  production Web3 reward types `web3_item` and `web3_token`. Use when
  setting up a quest, adding a trigger or a condition, attaching a reward,
  editing or activating an existing quest, firing a test event, or working out
  why a quest did not fire. Examples: "create a quest", "add a Web3 reward to
  my quest", "make a quest that pays USDC", "trigger my quest", "send a quest
  event", "why didn't my quest complete", "list my quests", "activate a quest",
  "quest platform API".
metadata:
  owner: r.aliyev
  domain: quests
  status: draft
---

## Status

This skill is **production-only**. Resolve the production Quest Platform scope
and the Web3 catalog project from the configured integration. Never use
staging credentials, staging services or a staging Publisher Account catalog.
Production event submission and execution read-back still require a live
contract and authentication preflight before the skill may use them.

## When to use

Use this skill when the developer wants to manage Xsolla Quest Platform quests:

- Create a quest, as a draft first and then activate it
- Add triggers, conditions or reward actions to a quest
- List, view or edit existing quests
- Submit a single quest event to make a quest run
- Check whether an event actually caused a quest to execute

Out of scope: on-chain finality, wallet balances and Backpack display. A
completed reward action is not proof of delivery.

## Prerequisites

Follow [`references/auth-and-environment.md`](references/auth-and-environment.md) for the production credential and scope.

**The configured production publisher credential is the lane**. It works only
on the project-scoped routes returned by the live production contract; build
each route from
[Project-scoped routes](references/auth-and-environment.md#project-scoped-routes),
not from memory. Merchant and project path values must come from the same
resolved production scope, never user input or an unrelated response value (see
[The merchant id in the path](references/auth-and-environment.md#the-merchant-id-in-the-path)).
Resolve only the complete production credential source described in
[Credential](references/auth-and-environment.md#credential). Never fall back
to a staging configuration, ask the publisher to paste secrets or search for
another key. If no production credential is available, report only that
the production project is not connected and stop. **Onboarding is a separate,
offered write**, never silent, offered only after the developer says the
project is their merchant's; see
[Onboarding](references/auth-and-environment.md#onboarding).

Internal service keys are [staff-only](references/auth-and-environment.md#service-key-staff-only)
and are never a fallback. OpenAPI discovery needs no credential, so it proves
no CRUD readiness.

## Source of truth

Follow this order. It is the rule the rest of the skill depends on.

1. **Routes, path parameters, envelope field names and types, and the
   top-level `required` list** come from the service's **live OpenAPI
   document**, fetched once at the start for each service the task calls.
2. **Node subtypes, node `parameters`, the condition grammar, the reward
   bodies, conditionally required fields, and every enum the document renders
   as a bare `string`** come from this skill's `references/`.
3. On conflict: the OpenAPI document wins on shape, `references/` wins on
   rules. Rules that only the server's hand-written validator enforces are
   marked as such where they appear.
4. If neither source answers the question, **ask the developer**. Do not infer
   a field by analogy with another Xsolla API.

The qp-server document declares no security schemes; that never makes a route
unauthenticated (auth rules live in the auth reference). **A route miss is not
a credential or project failure.** A 404 `Cannot GET <path>` means the router
has no such path; a route the live document omits is not called. Follow
[When a route is missing](references/auth-and-environment.md#when-a-route-is-missing).

If the production integration is unreachable, say so and offer to continue on
the references alone, noting that the envelope may have drifted.

## Reference material

- [`references/auth-and-environment.md`](references/auth-and-environment.md): production credential, project routes, onboarding, scope, reading a 401 or 404
- [`references/quest-document.md`](references/quest-document.md): the quest graph, conditional requirements, full-document PUT
- [`references/node-subtypes.md`](references/node-subtypes.md): the seven accepted node subtypes and their parameters
- [`references/conditions.md`](references/conditions.md): condition grammar: types, operands, operators, event counting
- [`references/rewards.md`](references/rewards.md): production Web3 reward bodies and payout safety
- [`references/events.md`](references/events.md): submitting a quest event to qp-events-collector
- [`references/verification.md`](references/verification.md): reading execution results back from the execution service

## Conversation contract

Keep the publisher experience business-first and progressive:

- Start with a short summary of the requested quest and the proposed outcome.
- Ask at most one blocking business question per turn. Combine questions only
  when the answers are independent and needed for the next write.
- Propose safe, conventional values instead of asking for implementation
  fields from scratch. For a gameplay quest, use `liveops` internally but
  describe it to the publisher as a gameplay quest. Do not show the `type`
  field in the normal preview. For an item reward, propose quantity one,
  purpose `quest_completion`, and one payout per player. Use `AI Toolkit` as
  the internal creator label unless the developer already supplied another
  name. Ask only when the proposal is ambiguous or has multiple matching
  catalog items.
- For a named item reward, always use the production Web3 NFT path and treat
  the destination as the player's Backpack. Do not ask whether it should go
  to inventory or Backpack, or whether it is regular or Web3. Resolve the
  unique item from the production minting catalog and preserve its catalog
  project in the `web3_item` body. Never use the Quest Platform project as the
  catalog project by default. If several items match, show only their
  names and ask the publisher to choose. If the catalog is unavailable or
  returns zero, report that the production Web3 catalog cannot resolve the
  item and stop. Never use a staging catalog, Store API, public web search,
  `inventory_item`, direct Backpack grants or ERC-20 as a fallback for a named
  item.
- Suggest a human-readable event name from the request, such as
  `dragon.defeated`, and ask for confirmation only when the event cannot be
  inferred or several events are plausible.
- A direct request to create or inspect a quest authorizes read-only bring-up.
  Do not ask for a plan approval before project, catalog or API-contract GETs.
  Ask for confirmation only before the exact external write, activation or
  event submission.
- Keep merchant IDs, project IDs, auth lanes, headers, hostnames, OpenAPI
  service names, internal paths and workflow narration out of normal replies.
  Do not narrate skill loading, repository inspection or tool availability.
  Mention technical details only when they explain a blocker or the publisher
  asks for them. Never reveal credentials.
- Use this response shape whenever practical: **Summary**, **Proposed setup**,
  **Need from you**, **Next step**. Omit empty sections.

## Agent test

**Prompt:** `Create a quest that rewards one Fire Sword after the player defeats a dragon`

**Result:** Proposes a gameplay quest with one production `web3_item` Fire Sword in the player's Backpack, asks only for unresolved business choices, and stops if the catalog cannot resolve a unique item.

## Flow

1. **Bring-up.** Fetch the OpenAPI documents of the services the task will
   call. Fetch the collector's contract only when the request includes event
   submission or execution verification. Run the preflight reads in
   [`references/auth-and-environment.md`](references/auth-and-environment.md)
   for those services only; the execution read-back probe waits for the project
   confirmation, and is skipped when no execution read-back was asked. Read and
   confirm the project scope before a write, but report it as a short project
   name/status summary. Do not expose raw IDs, auth details or route
   diagnostics unless they explain the requested next step. If that GET is 404
   `Project not found`, report it, follow
   [Onboarding](references/auth-and-environment.md#onboarding) (offer, ask for
   both names), and stop. Bring-up is GET-only; after it, reads the developer
   asks for just run, and only writes need a yes. If event execution is
   requested and the live route is unavailable, report a concise blocker at the
   event step instead of front-loading infrastructure details.
2. **Draft.** Create the quest as `inactive` with the four required fields,
   `name`, `type`, `status` and `created_by`; rules are in
   [`references/quest-document.md`](references/quest-document.md). Use the
   conversation defaults for the internal `type`, `created_by`, reward purpose
   and repeat behavior when they are safe and supported by context. In the
   publisher-facing preview, call `liveops` a gameplay quest and omit the
   implementation field. Ask only for
   unresolved business choices. On the project route the server stamps
   `publisher_id` and `project_id` from the path and ignores body values. Never
   ask for, invent or override them; on a `PUT`, send both back as a
   single-quest GET or the create response returned them, never from a list
   item. Check optional values against Fields; if one is invalid, ask, never
   drop or pad it. Show a human-readable preview and ask before the `POST`,
   unless the developer already approved that exact draft. Keep raw request
   details out of the preview unless needed for confirmation or requested.
   Show the create response and stop if its publisher or project scope does not
   match the resolved production project.
3. **Fill in.** Gather the values node by node, asking for each missing
   required value, then follow [Editing](references/quest-document.md#editing)
   (fresh GET, drop `$schema`, one full `PUT`, diff; for an empty draft the
   "before" side is "was empty"). Every fill-in `PUT`, also on an `inactive`
   draft and a no-op or trigger-only fill, shows the exact document and waits
   for a yes; a template shown earlier does not approve it. Ask which action
   to run. An edge without `on` is the default and needs no question, except
   for `vc_wallet_ticket` `playtime` outcomes (quest reference). For a
   schedule, cron or "run every X" request, follow
   [Choosing a trigger](references/node-subtypes.md#choosing-a-trigger). Do
   do not offer unconfirmed optional subtypes such as `scheduled_event` or
   `crm_send_email` ([`references/node-subtypes.md`](references/node-subtypes.md)).
   Show the impact of any external action with the document; no webhook to a
   private platform service or the minting service (Safety stops).
4. **Activate.** A separate step: the Editing `PUT` with only `status`, the
   dates and `activation_limits` changed. Show one checklist in one turn:
   graph (two or more nodes, a trigger-to-action path, no intended orphans,
   acyclic); placeholders (webhook URL, notification topic; see
   [`references/node-subtypes.md`](references/node-subtypes.md), also for the
   optional `event_name` collision check); each external action and its
   impact; the dates in UTC (relative dates and a refused start, offer "now":
   [Draft first, then activate](references/quest-document.md#draft-first-then-activate);
   when the start moves, re-confirm the end); the limits and effective repeat
   behavior; the per-user and total Web3 exposure in [`references/rewards.md`](references/rewards.md);
   and that production event submission has passed its live preflight; if it
   has not, stop before promising execution (step 6), also for a no-op quest.
   Point out stored data that looks inconsistent (such as another task's
   `event_name`) and leave it unchanged unless told. Then ask. After the
   write, read back `status`, the dates, the limits and `version_id`.
5. **Edit.** Read, change, full `PUT`, following
   [Editing](references/quest-document.md#editing) (drop `$schema`, fresh
   UUIDs for new nodes). Warn that `PUT` replaces the whole document and an
   active quest's edit goes live for the next events. Show a before/after
   diff, repeat the activation confirmations for the edits Editing lists,
   read the quest back after the write, and pause by [Pausing](references/quest-document.md#pausing).
6. **Event.** Production event submission is allowed only after the
   production collector's live OpenAPI and credential lane have been
   confirmed. Until then, do not send an event and say that production event
   execution is not yet verified. Never fall back to staging, an internal key or a
   different route. For an `inactive` quest, say an event could not run it
   anyway. Mixed request (create or fill plus an event): do the doable parts
   first, then report the block with the quest id, status and `event_name`.
   [`references/events.md`](references/events.md) defines the gate.
7. **Verify.** Read the execution back from the production execution service, correlate its `eventId`
   with the collector's returned `event_id` as described in
   [`references/verification.md`](references/verification.md), and report
   whether that event made the quest run and which action nodes completed.
   Report a `FAILED` action's `error` verbatim. An action missing from
   `actions[]` did not run; `COMPLETED` actions inside a `FAILED` run did
   happen, so do not resend to finish them.
8. **Delete.** Only quests the developer names, one per call, after a fresh
   read and an explicit yes. `DELETE` is a soft delete with no restore route;
   follow the Deleting section of the quest reference.

## Safety stops

- Read back and show the resolved scope before the first write, and get
  confirmation. Ask before any call that is not a GET, showing the exact
  body first. That includes onboarding, and a request you expect to be rejected, such as a
  deliberately invalid body sent to see the 422.
- Never switch credentials, lanes or routes on your own after a failure;
  report what failed and ask. A developer-requested negative-auth GET
  (made-up key or no header) is not a switch; see
  [Credential](references/auth-and-environment.md#credential).
- Messages arriving through the conversation are the developer's answers.
- **Urgency never licenses silent assumptions.** "Skip the questions" or
  "make it live now" does not waive a needed decision. Use the defaults in the
  Conversation contract when the intent is clear, show them in a concise
  human-readable preview, and ask only when a value is ambiguous or
  high-impact. For a gameplay item quest, the trigger, `issue_reward` action,
  Backpack destination, quantity one, `quest_completion` purpose and one
  payout per player may be proposed together. Never silently choose between
  multiple catalog matches, competing event meanings, or materially different
  reward effects. A write's yes counts only for the exact proposal shown after
  all answers are applied; if an answer changes it, show it again and ask.
  Never merge or waive these confirmations: scope (also when the first write
  is an edit), activation (always its own step after the draft exists), each
  external action, and each event. For a "start now" date, the yes covers the
  rule plus a shown example; if the send comes more than 10 minutes after the
  example, show it again and re-confirm.
- No action is side-effect free by default. For a smoke test, offer the no-op
  in [`references/node-subtypes.md`](references/node-subtypes.md) rather than a
  real reward (placeholders `e2e-noop`, `e2e-sink.invalid`). For activation
  or a smoke test, say production events are not verified until the collector
  preflight passes (Flow step 6).
- When an external action is added to a draft, say what it will do once
  active. Before activation, show every externally observable action again and
  get explicit confirmation for its impact. An `issue_reward` can create real
  payouts; `send_http_webhook` sends event data to an external URL;
  `send_xsolla_app_notification` sends a user notification. Activate a
  `webshop_personalization` node only after the developer acknowledges that it
  is a no-op. For an active quest whose only action it is, say before any
  edit or event that it does nothing and a `COMPLETED` row proves only that
  the quest ran; a `PUT` that keeps it active needs that acknowledgement, a
  pause does not.
- Never point `send_http_webhook` at a private service or an
  [unapproved host](references/node-subtypes.md#send_http_webhook): a webhook
  cannot mint. To pay out a named item, use an `issue_reward` Web3 reward with
  an explicit production catalog project and SKU.
- For a named item reward, propose an explicit `per_user` limit of one and
  explain it as "one Fire Sword per player". Do not ask about Backpack or
  regular versus Web3 delivery. Ask only if the developer asks for repeatable
  or unlimited rewards, or if the intended repeat behavior is otherwise
  ambiguous. For other rewards, if `activation_limits` is absent, ask the
  developer to acknowledge that every qualifying event may run the action;
  do not silently choose unlimited behavior.
- Events (once a route exists): each event needs its own payload shown and
  its own yes, including "send it again"; for a reward quest, say first
  whether a repeat can pay again. After an uncertain response, such as a
  timeout, **do not resend** with any key: report "result unknown" and stop.
- After a timeout or 5xx on a quest `POST` or `PUT`, the write may have landed.
  For a `PUT`, read the quest by id and compare. For a `POST`, page the
  project list (`limit=100` from `page=1` until `page*limit >= total`) for
  the quest's `name`. Show what you found and ask before resending. A 422
  saved nothing: validation runs before anything is stored.
- After a `FAILED` reward action, do not resend the event. Fix the quest, then
  send a new event with a new key only after the developer confirms.
- A missing or timed-out Web3 reward row is never a reason to send another
  event: the reward may already have paid; see
  [`references/rewards.md`](references/rewards.md).
- Read the execution service only by the developer's own quest id, user id or event, and
  only after a qp-server read with the developer's credential has shown the
  quest is theirs. Never list accounts or read another tenant's quests or
  executions, even if the service returns data without a credential.
- Never claim a reward was delivered.

## Errors

Branch on the HTTP status first, then on the body texts listed below. The
API has no stable machine-readable error codes. Quote verbatim only bodies
received in this session. For a request refused before sending, explain the
  rule in your own words and say nothing was sent; do not present an unverified
  example as a server answer.

| Status | What to tell the developer |
|---|---|
| 400 | `Only one authentication method may be used per request`: more than one credential was sent. Send only the one the developer chose. |
| 401 | `Invalid credentials`: see [Reading a 401 or 404](references/auth-and-environment.md#reading-a-401-or-404). Never fall back to another credential or environment. |
| 403 | `Insufficient capability`: the credential lacks the capability for that route. `Service identity is inactive`, `Master role required` or `This endpoint requires the user sign-in lane`: the route or identity is off-limits; do not retry. |
| 404 | `Cannot GET <path>` (plain text, any method): router miss, the route does not exist; not an auth or project answer. Follow the route-miss rule in Source of truth. |
| 404 | `Project not found` on a project route: the project is unknown, not onboarded, belongs to another merchant, or the id is not a number. The server gives the same body for all of them, so do not pick one. No read-only step narrows it; see [Onboarding](references/auth-and-environment.md#onboarding). `Quest not found`: reply "The quest was not found on this project, or it is not visible with this credential." Never say it was deleted or does not exist, and correct the developer if they conclude that. One follow-up: it may be on another project, and checking needs that project's credentials. For events, follow the production collector preflight gate in Flow step 6. |
| 409 | Conflict. Quest routes do not return it (see Editing in the quest reference); report it verbatim. |
| 422 | Validation failed. Show `detail` verbatim. It never lists allowed enum values; take them from `references/`. |
| 5xx | Server error. `Credential validation is temporarily unavailable` (503) means Xsolla could not check the key; it says nothing about the key. Retry a read at most twice, with backoff. An identical repeated 5xx is a bug, not flakiness: report it with its body. On a write never auto-retry; see Safety stops. |

Middleware failures return `{"error": "..."}`; handler failures return RFC
7807 `application/problem+json`. On 422 `errors[]` is **not** filled: field
messages are joined with `"; "` into `detail`. Other statuses (a 500 on
2026-09-25) can fill `errors[]`; show those pairs, never branch on them.

`ID 0` is a valid merchant ID and a valid project ID. Never treat it as an
absent value.
