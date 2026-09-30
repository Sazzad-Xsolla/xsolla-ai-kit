# Web3 rewards

This skill supports the production Web3 reward path only. A named item always
uses `web3_item` and is delivered to the player's Backpack. Do not offer
`inventory_item`, Store API grants, direct Backpack grants, ERC-20 claim
endpoints or a provider-default catalog as fallbacks.

These are the `parameters` of a node with `type: action` and
`subtype: issue_reward`:

```json
{
  "type": "web3_item",
  "purpose": "quest_completion",
  "body": {
    "project": "<catalog project returned with the item>",
    "item_sku": "<catalog SKU>",
    "quantity": 1
  }
}
```

The wrapper needs a supported `type`, a non-empty `purpose` and a non-empty
`body`. Use `quest_completion` for a named item unless the developer requests a
different reason.

## Named item behavior

When the developer names an item, such as `Fire Sword`:

- resolve the human-readable item in the production Publisher Account catalog;
- validate the exact `(catalog project, SKU)` pair in the production minting
  catalog;
- preserve the catalog project returned by that lookup in the `web3_item`
  body;
- default quantity to one and show it in the concise preview;
- if multiple items match, show only their names and ask which one to use;
- if the item is missing or the minting catalog cannot resolve it, stop before
  a write or activation.

Never guess an SKU, use a staging catalog or ask whether the destination is
Backpack. If the lookup returns zero, explain that the production Web3 catalog
could not resolve the item.

## `web3_item`

An NFT from the production minting catalog:

```json
{
  "type": "web3_item",
  "purpose": "quest_completion",
  "body": {
    "project": "<catalog project>",
    "item_sku": "<string or array>",
    "quantity": 1
  }
}
```

`quantity` must be a non-negative integer. For a named item, use a real SKU
returned by the catalog lookup. Omitting `item_sku` lets the provider choose an
item and is not allowed for a named reward.

The production runtime must enforce the once-per-user-per-quest rule. When a
confirmed payout already exists for the same user and quest, a repeat event
must not mint a second item. If the earlier payout is unresolved, stop and
escalate rather than resend the event.

## `web3_token`

An ERC-20 payout, only when the production token binding and runtime contract
are confirmed:

```json
{
  "type": "web3_token",
  "purpose": "quest_completion",
  "body": {
    "project": "<token project>",
    "item_sku": "<bound token SKU>",
    "amount": 10000
  }
}
```

`amount` must be a positive integer in the token's base units and within the
production contract's limit. Confirm the token decimals and binding with the
production owner. Never guess them.

## Recipient

Both Web3 reward types need an `xsolla_id` in the event and a production wallet
for that user. Check the wallet before activation and again before the event.
A missing wallet is a non-retryable blocker. Confirm the wallet source is the
Backpack-compatible managed wallet required by the production integration.

## Payout exposure before activation

Show three bounds in the activation preview:

- **Per event and user:** `web3_item` is `quantity × selected SKU count`;
  for a named Fire Sword this is one NFT. `web3_token` is `amount`.
- **Per user for the quest:** apply the effective activation limit to the
  per-event quantity. For a confirmed once-per-user named item this is one NFT
  per user and quest; for quantity greater than one or multiple SKUs, multiply
  by `quantity × selected SKU count`. For `web3_token`, multiply `amount` by
  the maximum qualifying events for that user.
- **Total quest exposure:** multiply the per-user bound by the maximum number
  of eligible users. If the user population, event count, activation limit or
  date window is not finite, report the total as **unbounded**.

Do not activate a repeatable Web3 reward without showing these calculations and
getting explicit confirmation for any unbounded total.

## Completion evidence

An execution marked `COMPLETED` proves only that the reward action completed
according to the production execution contract. It does not by itself prove a
Backpack display, wallet balance or on-chain finality. Report only the evidence
returned by the production read-back and never resend an event after an
uncertain result.

Attaching either reward type to an activated quest can create a real payout.
Show the reward and its exposure and get explicit confirmation before
activation.
