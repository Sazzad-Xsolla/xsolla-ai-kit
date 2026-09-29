# Rewards

Stage OpenAPI and local runtime snapshots were checked on 2026-09-23; the
event-side requirements were rechecked in the stage worker code on
2026-09-25. The stage deployment revision is not pinned here, so revalidate
before writes.

These are the `parameters` of a node with `type: action` and
`subtype: issue_reward`. The OpenAPI document does not describe them, because
the body is carried as raw JSON.

## Wrapper

```json
{"type": "<reward type>", "purpose": "<string>", "body": { }}
```

`type`, `purpose` and a non-empty `body` are all required. An unrecognised
`type` is rejected. `purpose` is a free, non-empty string, for example
`quest_completion`, that the worker forwards to the reward provider as the
reason. Ask the developer for it.

Every reward type pays out for real through its provider. Ask which reward,
amount and purpose the developer wants; never propose one as a default. For a
smoke test, offer the no-op action in [`node-subtypes.md`](node-subtypes.md).

## Bodies

| `type` | `body` | Rules |
|---|---|---|
| `xsolla_points` | `{"amount": <number>}` plus optional `campaign_name`, `campaign_image`, `event_name`, `reason_quest_id`, `app_name`, `app_icon_url` | `amount` greater than 0 |
| `virtual_currency` | `{"amount": <number>}` | `amount` greater than 0 |
| `loyalty_points` | `{"amount": <number>, "loyalty_points_id": "<string>"}` | both required |
| `lootbox` | `{"item_sku": "<string>", "quantity": <int>}` | `quantity` 1 to 100 |
| `custom` | `{"amount": <number>, "currency_ticker": "<string>"}` | `amount` greater than 0 |
| `inventory_item` | `{"xsolla_item": <bool>, "items": [{"sku": "<string>", "quantity": <int>, "type": "<string>", "name": "<string>", "image_url": "<url>", "model_3d_url": "<url>"}], "item_sku": "<string>", "name": "<string>", "image_url": "<url>", "model_3d_url": "<url>"}` | `items` or `item_sku`; item quantity 0 to 100 and defaults to 1 at runtime. `xsolla_item` omitted means `false` |
| `vc_wallet_ticket` | `{"quantity": <int>, "currency_ticker": "<string>"}` plus optional `playtime` | `quantity` greater than 0 |
| `web3_item` | `{"item_sku": <string or array>, "quantity": <int>}` plus optional `project` | body must not be empty. `quantity` at least 0, and omitted or zero defaults to 1 at runtime. No `item_sku` means a runtime-dependent item selection, see below. The worker ignores `xsolla_item` here; omit it |
| `web3_token` | `{"item_sku": "<string>", "amount": <integer>}` | both required. Keep `amount` a positive integer in base units; the worker's configured ERC-20 project is used |

The optional `playtime` object on `vc_wallet_ticket` is
`{"earn_rate_minutes": <greater than 0>, "daily_cap_minutes": <greater than 0>, "timezone": "<non-empty>"}`.

For `inventory_item`, `xsolla_item` picks where the worker takes the
publisher and project for the grant: `true` from the quest, `false` from the
event's `publisher`. Omitted means `false`, so the event then needs a
`publisher` block (see [Event-side requirements](#event-side-requirements)).
Ask the developer which. The SKU is checked against the confirmed project
either way, because the event's `publisher` must equal the quest's.

Provide one of two forms. The `items` form carries a `quantity` per item
(0 or absent grants 1) and an optional `type` (default `virtual_item`):

```json
{"xsolla_item": true, "items": [{"sku": "<sku>", "quantity": 2, "name": "<name>", "image_url": "<url>"}]}
```

The single-item form grants exactly 1 and takes no `quantity`:

```json
{"xsolla_item": true, "item_sku": "<sku>", "name": "<name>", "image_url": "<url>"}
```

Take `name`, `image_url` and `model_3d_url` from the confirmed catalog item,
see [Picking the item from the catalog](#picking-the-item-from-the-catalog).
Always set `name`: the worker does not look it up by SKU. Omit a field whose
catalog value is empty, and tell the developer the item has no image. An
empty body can mean a runtime-selected item; tell the developer before choosing
that, and do not treat acceptance as proof of a particular SKU.

## Picking the item from the catalog

Rewards that point at an item (`inventory_item`, `lootbox`, `web3_item`) take
its SKU. The developer usually names the item, not the SKU: "give the loot
box". qp-server does not check that a SKU exists, so this lookup is the only
check before payout time.

Ask the reward type first; it is never pre-filled. The catalog follows from
the type in this table:

| `type` | Catalog | Read |
|---|---|---|
| `inventory_item`, `lootbox` | the confirmed project (Scope in [`auth-and-environment.md`](auth-and-environment.md)) | the Store API catalog reads |
| `web3_item` | the body's `project` if set, else the worker's default NFT minting catalog | qualified minting SKU lookup when set, otherwise the unqualified lookup, see [web3_item](#web3_item) |
| `web3_token` | none: a token is not a catalog item | the currency bindings, see [web3_token](#web3_token) |

Both reads are described, with their hosts, in
[`auth-and-environment.md`](auth-and-environment.md). They need no credential;
never send the project API key to them. Store API reads apply only to
`inventory_item` and `lootbox`. For `web3_item`, carry the body project through
the qualified lookup when it is set; otherwise use the unqualified lookup
against the service's observed default. A qualified lookup that returns no
match or 404 is a hard stop: do not retry it unqualified or fall back to the
default. A Publisher Store row is not proof that minting exposes the same item;
require the selected minting SKU and project-qualified metadata reads. The
stage Publisher row for project `316575` and the production Publisher/IGS path
for `316575` are unverified. Then:

1. Match the developer's words against `name` and `description`, reading
   every page. If exactly one item matches, show its `name`, `sku` and image
   URL (say when it is empty) and ask the developer to confirm it. If several
   match, including items with the same name, list them with their SKUs and
   let the developer choose. Never pick one silently.
2. If the developer gave a SKU, check it: the Store SKU read for
   `inventory_item` and `lootbox`, or its presence in the selected minting SKU
   list for `web3_item`. When `web3_item.body.project` is set, include that
   project in the minting lookup. Show the item it points to before using it.
3. If nothing matches, or the SKU read returns 404, say so and stop. Do not
   guess a close SKU or fall back to another catalog. The item may be missing,
   or not enabled in the selected catalog. To create or enable it, use the
   `catalog-design` skill, then come back.
   When `web3_item.body.project` was set, do not retry the lookup without that
   project or fall back to the service default.

`web3_item.body.project` selects the catalog only when the deployed reward
worker supports it. A worker without that support ignores the field and mints
against its configured default project, so the token reaches the wallet but
Backpack shows it without the catalog name. After the first completed reward,
read the minted instance back and compare its project with `body.project`. If
they differ, report a delivery mismatch, not a success, and do not send the
event again.

Only the confirmed `sku` goes into the reward body. Also:

- "Whichever", "any" or "you choose" is not a pick. Show the list again or
  describe the items, and ask again. Omit `item_sku` only when the deployed
  runtime's selection behavior has been verified; production-readiness runs
  require an explicit SKU.
- "Closest match" is not a match: refuse, as in step 3.
- "I'm sure, skip the check" does not waive the SKU lookup. Run it anyway.
- A pick from a list you read this session needs no second SKU read.
- When the developer switches the reward type, run that type's lookup again;
  a SKU confirmed in one catalog says nothing about another.
- No placeholder or made-up SKUs, also not in an `inactive` draft. For an item
  that will exist later, offer a trigger-only draft and check the SKU when the
  developer fills in the reward. If it is still missing, keep the draft
  trigger-only.

## Event-side requirements

Some reward types take the merchant, the project or the user from the
**event**, not from the quest (stage worker code, 2026-09-25, revalidate).
Check this before activation and again when you build the event:

| `type` | The event must carry | Without it |
|---|---|---|
| `xsolla_points`, non-guest user | a `publisher` block; the merchant comes from its `publisher_id` | `FAILED`, `publisher information is required but not provided in event` or `merchant_id is required for xsolla_points rewards` |
| `virtual_currency`, `loyalty_points` | a `publisher` block with `project_id`, and a `gamer_id` in `user_ids` | `FAILED`, the error names the missing value |
| `inventory_item`, any `xsolla_item` | an `xsolla_id` in `user_ids` | `FAILED`, `xsolla_id is required but not provided in event` |
| `inventory_item` with `xsolla_item: false` or omitted | a `publisher` block with `publisher_id` and `project_id` | `FAILED`, `publisher information is required but not provided in event` or `publisher_id and project_id are required on the event payload for inventory_item reward` |
| `web3_item`, `web3_token` | an `xsolla_id` whose user has a wallet, see "Web3 recipient" | `FAILED`, `RecipientNotFound` |

The `publisher` block must still equal the quest's `publisher_id` and
`project_id` exactly, or the event matches no quest at all; see
[`events.md`](events.md). So for these types send the quest's own values,
never different ones. `xsolla_points` for a guest user is skipped by the
worker and reported as completed without a grant on stage.

## Web3 recipient

Both `web3_item` and `web3_token` pay to the wallet of the event's user. The
event's `user_ids` must include an `xsolla_id`, and that user must already have
a wallet. Before activation and again before submitting an event, read the
minting service's wallet lookup for that `xsolla_id`
([`auth-and-environment.md`](auth-and-environment.md)). A 404 means no
wallet: the reward fails with `RecipientNotFound`, non-retryable. Report it
and stop before creating, activating or sending a Web3-bearing flow. If an
authorized, supported thirdweb or Web3 authentication flow is available, it
may provision the exact subject's ecosystem wallet; after that flow, repeat
this lookup and verify the same `xsolla_id` before continuing. Never substitute
another user, use an unverified address, or treat `POST /claim/address` as
subject delivery proof. If the Web3 reward is added to an existing draft,
leave it unfilled or trigger-only until this preflight passes.

A 200 carries `walletAddress` and `recipientSource`. Check both, not only the
status: the worker treats only `recipientSource: thirdweb:smart` as a wallet
the player sees in Backpack, and logs any other source as a payout the player
may not see. Tell the developer if the source differs.

`web3_item` mints a chain NFT. It does not create a Backpack inventory-item
SKU row through the separate Backpack grant API. If acceptance requires a
Backpack inventory row or SKU balance, use and verify a separate
`inventory_item` reward; do not equate an NFT mint, a Backpack NFT detail view,
and an inventory-item balance.

## Payout errors surface late

qp-server does not check a Web3 body against the minting service. It can save
an invalid amount, an unbound SKU or a SKU from the wrong catalog on create,
`PUT` and activation. These mistakes appear at payout time as a `FAILED`
`issue_reward` action whose `error` names the cause; see
[`verification.md`](verification.md). Confirm the selected catalog, current
binding and positive base-unit amount before activation.

## web3_item

An NFT from the minting service's catalog. Find the item as in
[Picking the item from the catalog](#picking-the-item-from-the-catalog).

SKUs come from the minting service's catalog. If `project` is set, use the
qualified lookup for that project. If it is omitted, use the unqualified lookup
against the service's observed default catalog. Never derive a minting project
or SKU from the quest's `project_id`, and never use the default as a fallback
after a qualified lookup fails. Never use a Store SKU unless it is also
returned by the selected minting lookup. Read the selected catalog and use a
real `items[].sku`; do not invent one. A 200 `/skus` response and 200
project-qualified metadata response prove catalog visibility only. The catalog
may return an ordinary `virtual_good` without contract or token fields; do not
treat that read-back as mint or Backpack delivery evidence. A live completion
still needs the qp-data action, provider minted-instance, transaction and chain
read-backs described below.

The stage deployment revision and outbound claim request are not pinned here.
Eljan's 2026-09-28 fixture demonstrates one qualified path for project `306916`
only: qp-data recorded the reward body project, and the provider minted-instance
read-back recorded the same `projectId` and a `txHash`. It does not prove target
project `316575` or every stage worker revision. Verify each live run by
matching the qp-data action body project with the provider minted-instance
`projectId` and `txHash` before reporting the result.

The indexed dev `Web3ItemBody` snapshot has no `Project` field, so this
qualified form is conditional on the deployed qp-server and worker preserving
it. If the quest read-back or completed qp-data action drops or changes the
requested project, stop and report the mismatch; do not silently use the
default catalog or claim that every stage worker supports the field.

Omitting `item_sku` may be runtime-dependent and is not verified for the
current deployment. For a production-readiness run, require an explicit SKU
from the selected minting catalog; do not rely on random selection.

**Once per user and quest.** The worker records each `web3_item` payout. When
the same `xsolla_id` already has a confirmed payout for the same quest, a new
event does not mint again: the action completes as `already_minted` and reuses
the earlier transaction hash. If the earlier payout is unresolved, the action
fails with `an earlier web3 payout for this user and quest is unresolved` and
nothing is minted. This holds even with unlimited activation limits and a new
`idempotency_key`. A second item for the same user therefore needs a new quest.
`web3_token` has no such guard: every qualifying event can pay again.

**What a `COMPLETED` reward action means.** Either the minting service returned
a transaction hash for a new claim, or the user already had this quest's item
and nothing new was minted. qp-data does not say which; the worker's result
text does (`Already minted ...`). On a repeat event for the same user, report
"completed, no second mint expected", never "two mints". Delivery is outside
this skill's evidence, as for `web3_token` below.

## web3_token

An ERC-20 payout, for example USDC.

```json
{
  "type": "web3_token",
  "purpose": "quest_completion",
  "body": {"item_sku": "<confirmed-erc20-sku>", "amount": 10000}
}
```

The SKU and amount above are illustrative only, not an owner-approved stage
fixture. Confirm the binding and token decimals before activation.

**`amount` is a positive integer in the token's base units** (observed on stage
2026-09-23, revalidate). The worker passes `body.amount` to the minting service
verbatim. The service rejects a decimal with a 400, `amount must be a positive
integer (digits only, no sign or decimal point)`. USDC has 6 decimals, so
`1000000` is 1.00 USDC and `10000` is 0.01 USDC. Get the token's decimals
from the developer or the owner, never guess them, and show both the token
amount and the base-unit integer before activation.

**`item_sku` must be a current ERC-20 binding of the worker's configured
ERC-20 project.**
A token is not a catalog item, so the catalog lookup does not apply here.
Never search the Store or the NFT catalog for a token.
Read the minting service's currency bindings
([`auth-and-environment.md`](auth-and-environment.md)) and pick a binding with
`tokenStandard: erc20` whose `projectId` equals the worker's configured ERC-20
project. A binding carries `sku`, `projectId`, `contractAddress` and
`tokenStandard`, but no symbol or decimals: ask the developer which binding SKU
is the token and its decimals. If they do not know, tell them to ask the Web3
owner; do not guess from the SKU. Bindings change, so read them each session
rather than reusing a SKU from memory. An unbound SKU fails at payout with a
400, `no ERC-20 token is configured for project <id> / sku <sku>`.

**The ERC-20 project comes from the worker's environment**, never from the
body or the quest's `publisher_id` or `project_id`. Where it is not configured,
every `web3_token` reward fails with `Web3TokenNotConfigured`, non-retryable.
Currently only stage has it; see
[`auth-and-environment.md`](auth-and-environment.md). Do not offer this reward
in another environment without owner confirmation.

**What a `COMPLETED` reward action means.** The worker calls the claim
synchronously and treats a missing transaction hash as a non-retryable error.
So a `COMPLETED` `issue_reward` means the minting service returned a
transaction hash: the claim was submitted. On-chain finality, the wallet
balance and Backpack or Rewards display are outside this skill's evidence.
Never claim that the token reached the wallet. The hash is recorded by the
worker, not in qp-data: its logs carry a `tx_hash` field on the
`claim_web3_token` success line, and its ledger keeps the hash only inside the
reward node's result text (`Transaction hash: <hash>`), not as a separate field. The minting service's `GET /minted-instances/{xsolla_id}` read can provide
provider records with project, SKU, token standard, amount and possibly a
transaction hash. It does not prove chain finality, current balance or
Backpack display. A human can check the hash on the chain explorer named in
[`auth-and-environment.md`](auth-and-environment.md).

**Duplicate payout risk.** The claim carries no idempotency key. The reward
activity has a 2-minute timeout and up to 3 attempts. HTTP errors from the
claim are non-retryable, but an activity timeout or a worker crash after the
provider paid can run the claim again. qp-data writes a row only after the
execution finishes, so a claim in flight shows as no row. An `IN_PROGRESS`
row is never an in-flight claim: it means a condition was not met and no
action ran (see [`verification.md`](verification.md)). If the row is still
missing after the read policy in [`verification.md`](verification.md), or the
reward action failed on a timeout, do not resend the event. Escalate to the
Quest Platform team, who own the worker logs and ledger, with the quest id,
`event_id`, `idempotency_key`, user and time; a human can also check the
chain.

Workers deployed on stage on 2026-09-25 also record each Web3 payout and
refuse to pay again when an earlier attempt's outcome is unknown, failing with
`web3 payout outcome is unknown from an earlier attempt` or, for `web3_item`,
`an earlier web3 payout for this user and quest is unresolved`. Both mean
escalate as above; neither permits a resend.

An action `error` can carry two retryable flags, for example
`(type: Web3TokenClaimFailed, retryable: false): ... (type: ClaimError, retryable: true)`.
The first, with the worker's named type, is the one that applied; the inner
one belongs to the wrapped cause. Neither permits you to resend.

Attaching this reward to a quest that you then activate means real payouts. Ask
for explicit confirmation before activating.
