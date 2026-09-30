# Shop Builder storefront

Reference for the storefront half of the `localization` skill. Paths are relative to
the skill directory. Catalog and LiveOps text go through `scripts/catalog_i18n.py`,
not through this page.

Take a store that exists in one language and render it in another, end to end, without
losing the ability to undo it.

The core problem this skill solves is not translation quality — the model handles that. It
is that a store's text lives in **three separate systems with three separate write paths**,
and a pass that touches only one ships a store that is half-translated in a way nobody
notices until a player does.

## When to use

Trigger keywords: translate the store, localize the shop, add a language, translate item
names, localize storefront copy, "my store is English only", ja-JP / de-DE / pt-BR, i18n,
multi-language store.

Entry conditions: the store exists and renders, the catalog is populated, and the target
locale is on Xsolla's supported list (`references/i18n-support.md`).

Not for: creating the store (`shop-builder-assembly`), building the catalog
(`catalog-design`), or region-specific pricing (that is a catalog change, not a
translation — see "Prices are not text" below).

## The three surfaces

Internalize this before touching anything. Every design decision below follows from it.

| Surface | What it is | Who translates it | Write path |
|---|---|---|---|
| **A — Site chrome** | Cart, buttons, nav, checkout UI | **Xsolla**, for all 26 supported languages | Enable the language. Do not translate |
| **B — Block copy** | Hero, CTAs, section titles, FAQ, footer | **You** | `xsolla shopbuilder update-many-localization` |
| **C — Catalog metadata** | Item / bundle / package / group `name`, `description`, `long_description` | **You** | Store **Admin API** pass-through PUT via `scripts/catalog_i18n.py` (CLI `xsolla catalog` still used for items/bundles/packages name+description only) |

Surface A is free and already done — Xsolla ships default translations, and they are
overridden only by double-clicking the string in the Publisher Account editor. That is a
**human, editor-only** operation and it must never run while this skill is writing (see
"One writer at a time").

Surfaces B and C are the job. They have nothing in common: different transport, different
auth, different payload shape, different verification. Handling only one is the failure
mode this skill exists to prevent.

## Prerequisites

- The store exists and renders (`shop-builder-assembly`), and the catalog is populated
  (`catalog-design`). A translation pass over an empty catalog translates demo data.
- **Auth, and it is two different credentials.** Shop Builder: run `xsolla auth login`
  (OAuth2 + PKCE) — it auto-bootstraps the Shop Builder session. If it errors with
  "audience required", retry with `--audience https://api.xsolla.com`. Fallback for CI:
  `export XSOLLA_SHOPBUILDER_SESSION='pa-v4-token=<value>'` — note the `pa-v4-token=`
  prefix is part of the value, and `ps2[user_session]` 403s. Catalog: **Basic auth** with
  a Store/merchant key — `XSOLLA_API_KEY` plus `--merchant-id`. A 403 on one says nothing
  about the other.
- `XSOLLA_MERCHANT_ID`, `XSOLLA_PROJECT_ID`.
- The **returned domain**, not the slug you asked for. `create-website --slug voidwall`
  produces domain `voidwall-45e0`. Localization commands take that domain as `--slug`.
  Block-structure commands take `--landing-id`, which is the landing's Mongo `_id` from
  `get-structure` — **passing a slug there 500s the backend**.
- The `xsolla` CLI with `shopbuilder get-localization`, `update-many-localization`, and
  `get-block`. `scripts/preflight.sh` checks every command this skill calls.
- **A disposable project.** The catalog has no sandbox, so every catalog call is live. See
  "There is no catalog sandbox". Set `XSOLLA_PRODUCTION_PROJECT_IDS` to every project that
  must never be touched — `apply.sh --commit` refuses catalog writes until you do.

## Steps

### 1. Preflight

```
scripts/preflight.sh
```

Verifies the CLI is present, is the right binary, has the subcommands this skill calls,
and that the session token is set and accepted. It fails loudly rather than letting a
wrong-binary call fail silently three steps later.

### 1b. Do not trust a read to tell you what is translated

A client read falls back to the default locale with no marker, so identical text means
"untranslated **or** translated identically" and the two are indistinguishable from outside.
Establish coverage from the admin record (`get-items`), and where it is genuinely ambiguous,
report the ambiguity rather than claiming a percentage.

### 2. Confirm the language is enabled — before authoring anything

Two gates, both of which must be open or translated text is written successfully and then
never rendered:

1. **Project languages** — Publisher Account › Project Settings › General Settings.
2. **Site language toggles** — plus a visible language selector (Header and/or Footer).

```
xsolla shopbuilder add-language --merchant-id <m> --project-id <p> --slug <domain> --language de-DE
```

Doing this last instead of first is the most common way a translation pass appears to have
done nothing at all.

### 3. Snapshot before writing

```
scripts/snapshot.sh <domain>
```

Pulls `get-structure`, `get-localization`, and the catalog into
`l10n/baseline/<timestamp>/` and commits it as a single verbatim commit.

The catalog half **must** come from admin reads (`get-items`, `get-bundles`,
`admin-list-currency-packages`), which return the real locale map. The client reads return a
single resolved string, and `extract.sh` then drops every catalog string without a word —
that is a storefront-only translation pass that reports success. `snapshot.sh` asserts the
shape and aborts rather than committing a baseline like that. Note that
`admin-list-items-by-group` returns **403 with a project-scoped key**, so items and bundles
are walked per SKU instead, which also picks up items belonging to no group. That commit is
the rollback point. Reformatting, if any, goes in a **separate** commit so the diff of
"what the API returned" never mixes with "what we prettified".

Re-snapshot at the start of every run. If a human edited the store in Publisher Account
since the last run, a stale baseline makes the diff a lie.

### 4. Extract translatable text

```
scripts/extract.sh <source-locale> <target-locale> [baseline-dir]
scripts/extract.sh en-US ja-JP                 # newest baseline is used when omitted
```

It takes **no domain** — the domain is already baked into the baseline. Passing one (the
signature this file documented until now) silently treats it as the source locale, matches no
strings, and produces an empty-but-plausible extraction.

Produces `l10n/work/<target>/translatable.json`: a flat list of units, each with a stable
`id`, the source string, its HTML tags, a character budget, and a `kind` marking whether
it is transcreation-sensitive.

**Ask this before translating anything.** Andrey's launch rule: does the publisher already
have a complete set of translations?

1. **Yes — they have copy.** Take a **JSON or TXT** file (do not re-translate). JSON may
   be a full `translated.json`, `{"units":[{"id","target"}]}`, or a flat `{id: text}` map.
   TXT is `id<TAB>target` or `id: target` per line.
   ```
   scripts/ingest-user-translations.sh ja-JP ./publisher-ja.json
   ```
   Then skip the LLM fill. Show the ingest counts (`filled` / `still_empty`) and get
   confirmation before `apply.sh`.
2. **No — they need the model.** Do **not** start filling `translated.json` yet. Show a
   **plan**: target locale, unit counts by surface, overwrite risk (`existing_target_present`),
   legal/asset skips, and that a snapshot already exists. Wait for explicit confirmation.
   Only then translate (step 5).

Snapshot (step 3) is the backup-before-edit. Never skip it because a file was ingested.

**What counts as translatable.** Only these:

- Catalog: `name`, `description`, `long_description`. **Those three fields and no others** —
  nothing else in the catalog is a locale-keyed map.
- Blocks: any field carrying an `L:` id — hero copy, CTAs, store section titles, FAQ
  question/answer pairs, and shared strings in the `common` scope.
- Page SEO: `page.seo.title` / `page.seo.description`. These carry their own `L:` ids and
  resolve through the same localization store as block text, but live under `page.seo`, a
  sibling of `page.blocks` — the block walker alone misses them. `page.seo.ogImage` carries
  an `L:` id too but is a URL (`kind: asset`), so it is extracted for visibility, never sent
  to translation.

**What is structural and must never be sent to translation:** SKUs, item and block ids,
group keys, `type` and `layout` values, prices and currency codes, image URLs and
`mediaValues` keys, theme colors, `blockId` / `host` / `offerChainId` on federated blocks,
and any `L:` or `I:` reference id. The extractor allowlists translatable paths rather than
denylisting structural ones — a denylist silently passes new fields through to the
translator, and a mistranslated SKU is a broken store.

### 5. Translate

The agent translates `translatable.json` into
`l10n/work/<target>/translated.json`. This is the step the model does directly; there is no
MT service call.

Rules, in priority order:

1. **Honor the glossary.** `glossary/do-not-translate.txt` is a hard constraint — game
   title, faction and character names, currency names, "Xsolla", "Pay Station". Copy these
   through verbatim. `glossary/termbase.csv` gives one approved rendering per locale for
   recurring game nouns (rarity tiers, item classes); use it and extend it rather than
   inventing a second rendering of the same term three cards later. Inconsistent rarity
   naming is the clearest tell of a rushed game-store localization.
2. **Preserve HTML tags exactly.** Source `<h1>Hold the Line</h1>` becomes
   `<h1>Haltet die Stellung</h1>`. Same tags, same order, same count. Bare strings render
   unstyled, so a dropped `<h1>` is a visible layout bug, not a cosmetic one.
3. **Respect the character budget.** German runs 10–35% longer than English and Brazilian
   Portuguese 15–30%; both overflow buttons and section tabs. Japanese is shorter in
   character count but does not wrap on spaces, so a long unbroken run overflows a card.
   Where a faithful translation blows the budget, shorten the copy — do not let it overflow.
4. **Transcreate, don't translate, anything marked `kind: marketing`.** Hero headlines,
   promo hooks, and CTA labels are commercial copy. A literal translation of a pun is
   grammatical and dead. Write the equivalent line a native copywriter would write.
5. **Never skip a string because it already has a target.** Measured on a real
   template-derived landing: **52 of 53** block strings already carried a `de-DE` value,
   across 26 pre-populated locales. A pass that skipped populated targets would have
   translated one string and reported success. Landings built from a template
   ship with their stock copy pre-translated. The moment the English is edited those values
   are silently wrong — a card reading "Pay as you go" can carry a `ja-JP` value meaning
   "Official store". `extract.sh` reports this as `existing_target_present`, deliberately not
   "already translated". Compare against the *current* source and overwrite.
6. **Do not faithfully render broken English.** Template copy is often truncated mid-sentence
   or describes a different game. Translate the intent, and report which source strings need
   an English fix, rather than propagating the damage into every locale.
7. **Never translate a value starting with `http`.** Asset URLs (SEO `og:image` and friends)
   live in the localization store like ordinary copy. `extract.sh` marks them `kind: asset`
   and `apply.sh` skips them; a translated URL is a broken image.
8. **Never translate legal or compliance text.** Refund policy, ToS, age-rating and tax
   disclosure. Flag these in the report and leave them for counsel. This skill marks them
   `kind: legal` and refuses to fill them.

### 6. Write back

```
scripts/apply.sh <domain> <target-locale>                                   # dry run, prints the payloads
scripts/apply.sh <domain> <target-locale> --commit                          # writes; BLOCKS if step 5 would overwrite an existing translation
scripts/apply.sh <domain> <target-locale> --commit --confirm-overwrites     # writes, having reviewed what gets replaced
```

Dry run is the default and prints every payload without sending it. Read the dry run
before committing.

**Existing translations are not overwritten without confirmation.** Rule 5 above means
this run may be replacing a value that already exists — pre-populated by a template or
written by an earlier run — not just filling a blank. `apply.sh` diffs each unit's
`existing_target` (recorded by `extract.sh`) against what is about to be sent; if any
differ, `--commit` alone **BLOCKS** and prints every existing-vs-new pair. Only
`--commit --confirm-overwrites`, issued after a human has read that list, proceeds.
Identical existing-and-new values need no confirmation — nothing is actually changing.

Two write paths, and they differ in a way that matters.

**Blocks (surface B) — the text is not in the block.** `get-structure` gives each text
field an `L:<uuid>` at `values.<field>.id`; the text itself lives in a separate
localization store keyed by the slug. **Patching `["values","title"]` via `update-block`
returns `ok:true` and changes nothing.** Write through the store instead:

```
xsolla shopbuilder update-many-localization --slug <domain> \
  --data '{"locale":"de-DE","perScopeValues":{
             "<pageId>":{"L:<id>":{"translation":"<h1>Haltet die Stellung</h1>"}},
             "common":{"L:<id2>":{"translation":"<p>…</p>"}}}}'
```

- Scope is the **page `_id`**, or `"common"` for shared strings.
- The per-id value **must** be `{"translation": "<html>"}`. A bare string, or any other
  key (`value`, `text`, `translations`), returns **200 and writes an empty string**.
- One call per locale. Because each locale is written independently, there is no risk of
  dropping the source language here — unlike the catalog.

Because text lives outside the block, the `values`-vs-`components` distinction does **not**
apply to translation. Section titles and FAQ answers are just `L:` ids like any other.
It matters only if you are changing block *structure*, which this skill does not do — and
must not: **never wholesale-replace a block's `values` or `components`**, because copying
`L:` references with no matching localization 500s the renderer.

**Catalog (surface C)** — two write shapes, because the CLI cannot carry every field.

- **Pass-through Admin PUT** (`catalog_i18n.py`, the catalog half of this skill): GET
  state minus server-derived keys, merge locale maps, PUT the whole object. This is how
  **item groups** and **`long_description`** are written. `apply.sh` always saves
  `payloads/catalog.put.<entity>.<id>.json` on dry-run. Live `import --write` / `restore
  --write` are **not** invoked by `apply.sh --commit` — those flags hit the live Store API
  and need an explicit go-ahead.
- **CLI** `xsolla catalog update-items` / `admin-update-bundles` /
  `admin-update-currency-package` still reconstruct `--name`/`--description` plus
  prices/groups/flags from the baseline. There is **no** `--long-description` flag; that
  field lives only in the PUT body above.

```
# No --sandbox: it is a no-op for the catalog. And send the WHOLE entity — update-items
# replaces it, so omitting --prices/--groups drops the price and unlists the item.
xsolla catalog update-items --item-sku <sku> --sku <sku> \
  --merchant-id <m> --project-id <p> \
  --prices '[{"amount":9.99,"currency":"USD","is_default":true,"is_enabled":true}]' \
  --groups '["cosmetics"]' --is-enabled=true --is-show-in-store=true \
  --description '{"en":"...","de":"..."}' \
  --name '{"en":"Starter Pack","de":"Starterpaket"}'
```

`admin-update-bundles` (`--bundle-sku`) and `admin-update-currency-package`
(`--package-sku`) follow the same shape.

Three things here are tested, not assumed (`scripts/probe-locale.sh`):

1. **The whole entity is replaced.** An item created with a price, a group and
   `is_show_in_store:true`, then updated with only `--name` and `--description`, came back
   `prices:[] groups:[] is_show_in_store:false` — with **`ok:true`**. The item left the store
   silently. `apply.sh` reconstructs every field from the baseline for this reason.
2. **`description` is mandatory** — omitting it is rejected with **HTTP 422**. Note the
   asymmetry: a missing description fails loudly, a missing price fails silently.
3. **Use two-letter locale keys.** Writing `ja-JP` is accepted but stored as `ja`, and
   reading `--locale ja-JP` falls back to English without a word. `apply.sh` normalizes,
   mapping the irregular `zh-CN`→`cn` and `zh-TW`→`tw` rather than truncating.

The locale map itself is also replaced, not merged — so a write must carry **every locale
the entity already holds**, not just source and target. Sending `{en, ja}` to an item holding
`{en, es, ja}` leaves `{en, ja}`: the Spanish from last month's run is gone, `rc=0`, no
warning. That is how a store loses a language by gaining one. `apply.sh` seeds the map from
the baseline entity and overlays source + target, and prints `(preserving es, …)` on each
entity so the dry run shows what is being carried through. Check that line before `--commit`.

Two CLI gaps that **catalog_i18n.py** covers via the Admin API (do not intern-patch the CLI):
- **Item groups** — no `xsolla catalog` update command. Tab labels. Pass-through PUT to
  `/admin/items/groups/{external_id}`.
- **`long_description`** — no `--long-description` on `update-items`. Same PUT as the item.

`apply.sh` dry-run must show `catalog.put.item_group.*.json` and `long_description` inside
the item PUT body. Check those files before any live import.

### 7. Set the language the shop OPENS in — or the run looks like it did nothing

```
scripts/set-opening-language.sh <domain> <target-locale>
```

**Skipping this is the single most convincing way to conclude the skill failed.** Every string
is written, every read-back verifies, and the shop still renders in the source language,
because a landing has no default-locale field: the **order of `languages` decides**, and
`add-language` only appends. A run that enables `ja-JP` leaves `["en-US","ja-JP"]`, so the shop
opens in English and the Japanese is reachable only through the selector.

The script delete-and-re-adds so the target ends up first. That is safe: `delete-language`
edits the enabled list only — a locale's strings stay in the localization store and return
intact on re-add (verified). The enabled list and the localization store are separate things.

Leaving the source language enabled behind the target is usually right: the selector then
offers it, and nothing is lost.

### 8. Verify — render it, do not trust `ok:true`

Verification is where this skill earns its keep, because **every incorrect write in this
system succeeds**.

```
scripts/verify.sh <domain> <target-locale>          # exits non-zero if anything is missing
scripts/verify.sh <domain> <target-locale> --json   # same findings, machine-readable
```

Everything `apply.sh` checks before sending — blanks, tag parity, length budget — inspects a
file on disk, and passes identically whether or not a single word reached the store. Only
this step asks the store. It reads back and reports, per surface:

1. **Catalog**, via the **admin** reads (`get-items`, `get-bundles`,
   `admin-list-currency-packages`) — never `--locale`. Confirms the target key exists and is
   non-empty for `name` **and** `description`, that the **source locale survived** the write,
   and lists every other locale still present so a dropped language is visible. Tested against
   a live project, the storefront read accepts `ja`, `ja-JP`, `zz` and `not-a-locale` alike,
   returning `ok:true` and identical default-locale text every time — it can prove neither
   that a locale code is valid nor that a translation exists.
2. **Storefront**, via `get-localization`, resolving each `L:` id in its own scope (page
   strings nest one level deeper than `common` ones). `get-structure` will not do: it returns
   `L:` ids, not text.
3. **Languages**, via `get-structure` — is the target enabled at all, and is it *first*, which
   is what the shop opens in.
4. **Prices** — flags any currency carried by some entities and missing on others, because one
   gap de-localizes every price in that market.

`apply.sh --commit --report` runs it automatically after writing. A missing string or a
disabled language exits non-zero; a value that differs from what was sent is reported but not
failed, since a human may have edited the store since.

5. **Render the store and look at it**, in the target locale:
   ```
   xsolla shopbuilder enable-preview --slug <domain>
   ```
   Load `https://preview.xsollasitebuilder.com/<domain>`, switch to the target language,
   **scroll top to bottom before capturing** (card images lazy-load; blanks above the
   capture are an artifact, not a bug), and screenshot.

   `enable-preview` and `preview-link` return **403 `admin_privileges_requred`** on accounts
   without admin rights on the project, and no CLI flag works around it. Preview through the
   Publisher Account UI instead, which does not need that permission — but do not then treat
   the absence of a screenshot as verification. Steps 1–4 are the verification; this is
   confirmation.

   Check for: untranslated stragglers, text overflowing buttons or tabs, and prices — see
   below.

## Prices are not text

Price display keys off the **user's country**, not the UI language. A fully translated
German store still shows USD to a German buyer if no EUR regional price exists.

Worse, there is a whole-catalog fallback: if a country has regional prices on every item
*except one*, the entire catalog reverts to the default currency for that market. One
missed SKU silently de-localizes every price in the market.

This skill does not set prices — that is a catalog change with commercial consequences, and
it needs a human. What it does is **report** the gap: `verify.sh` compares the currencies
carried across the catalog and flags every entity missing one the others have, so translating
a store never quietly implies its pricing was localized too.

## There is no sandbox — on either surface

The CLI says so itself, and the request URL is byte-identical with and without the flag:

```
$ xsolla catalog list-catalog-items --project-id <p> --sandbox --verbose --dry-run
warning: --sandbox has no effect on this command — catalog has no Xsolla sandbox
environment, so this request runs against live project.
URL: https://store.xsolla.com/api/v2/project/<p>/items/virtual_items
```

Shop Builder says exactly the same thing:

```
$ xsolla shopbuilder get-structure --slug <domain> --merchant-id <m> --project-id <p> \
    --sandbox --verbose --dry-run
warning: --sandbox has no effect on this command — shopbuilder has no Xsolla sandbox
environment, so this request runs against your live project.
URL: https://sitebuilder.xsolla.com/api/merchant/<m>/project/<p>/landing/<domain>/structure
```

Verified on both surfaces (`list-catalog-items`, `list-item-groups`, `list-catalog-bundles`,
`list-all-items`, `get-structure`). **Every read and write in this skill hits the live
project.** The only control you have is *which project id you point at* — not a flag, not a
mode. The scripts therefore never pass `--sandbox`: it changes nothing and would misrepresent
what a run is doing.

Note a separate, unrelated thing that *is* called sandbox: a landing carries a
`features.isSandboxMode` boolean. That is a property of the site's payment behaviour, not a
routing mode for these API calls, and it does not make writes reversible.

Consequences, none of them optional:

- `apply.sh` prints the target project id and the words "writes go LIVE" before any catalog
  call, and refuses `--commit` unless `XSOLLA_PRODUCTION_PROJECT_IDS` is set, so a run has to
  state positively that it is not aimed at production.
- Use a disposable project. There is no undo beyond the git baseline, and the baseline only
  lets you *replay* the old values — it does not roll the store back on its own.
- Neither surface is safe by virtue of a flag. Both are live, always.

There is nothing to promote *to*: you were always in production, on both surfaces. What that
buys promotion-wise is a discipline, not a mode — named human sign-off per market, a fresh
baseline, and an announced freeze window before a translation run touches a store anyone uses.

## One writer at a time

Never edit the landing in the Publisher Account editor while this skill is running.
Concurrent writers overwrite each other, drop blocks, and leave ghost references that break
the editor with "Block with id … not found".

This has a specific consequence here: surface-A chrome overrides are editor-only. If anyone
is overriding an Xsolla default string by hand, no CLI write may run at the same time.
Schedule chrome overrides as a separate, serialized step.

## Common pitfalls

- **Finishing at `apply --commit` and calling it done.** The shop still opens in the source
  language, because `languages` order decides and `add-language` appends. Everything verifies,
  nothing looks translated, and the natural conclusion is that the skill failed. Run
  `set-opening-language.sh`.
- **Judging the result from the editor.** The editor renders one locale at a time and opens on
  the default. Catalog cards resolve their locale independently, so you can see German item
  names under English headings and conclude the storefront write failed when it did not.
- **Passing a domain to `extract.sh`.** It takes `<source-locale> <target-locale>`. A domain in
  the first position is read as the source locale and yields an empty, plausible-looking
  extraction.
- **Snapshotting the catalog with a client read.** Yields bare strings where a locale map is
  required; every catalog string is then silently skipped.
- **Writing only `--name`/`--description` to the catalog.** Tested: returns `ok:true` and
  leaves `prices:[] groups:[] is_show_in_store:false`. The item vanishes from the store.
- **Sending five-symbol locale codes to the catalog.** `ja-JP` is stored as `ja`, and
  `--locale ja-JP` on a read silently returns the default. Two-letter everywhere on the
  catalog; five-symbol only for the localization store and `add-language`.
- **Verifying a translation with `--locale`.** The storefront read returns `ok:true` and
  default-locale text for *any* string, including `not-a-locale`.
- **Writing block text with `update-block`.** Returns `ok:true`, changes nothing. Block
  text lives in the localization store; use `update-many-localization`.
- **Using a bare string as the per-id value.** `{"L:x": "text"}` returns **200 and writes
  an empty string**. It must be `{"L:x": {"translation": "text"}}` — the key `translation`,
  singular. Any other key does the same silent nothing.
- **Writing translations before enabling the language.** Everything succeeds and nothing
  renders. `add-language --language <locale>` first, at project *and* site level.
- **Sending only source + target to the catalog.** Locale maps are replaced, not merged, so
  this deletes every OTHER language the entity holds — a second-language pass silently
  un-translates the first, with a success response. Send the whole map; check the dry run's
  `(preserving …)` line.
- **Treating `ok:true`, or `apply.sh`'s pre-send checks, as verification.** They inspect a
  file on disk and pass whether or not anything reached the store. Run `verify.sh`.
- **Re-running `--commit --confirm-overwrites` out of habit.** The flag is a one-time
  acknowledgment of the specific list printed on the blocked run, not a blanket "skip this
  check" switch — re-read the existing-vs-new list every time the gate fires, since the
  units it names can differ run to run.
- **Passing a slug as `--landing-id`.** It 500s. `--landing-id` is the landing's Mongo
  `_id` from `get-structure`; `--slug` is the returned domain.
- **Wholesale-replacing a block's `values` or `components`.** Copying `L:` references with
  no matching localization 500s the renderer. Translation never needs this — the text is
  not in the block.
- **Confirming copy with `get-structure`.** It returns `L:` ids, not text. Read it back
  with `get-localization` or `get-block`.
- **Translating a SKU, group key, or `type` value.** The extractor allowlists fields
  carrying an `L:` id and the three catalog fields, for exactly this reason.
- **Dropping HTML tags in translation.** Block text is HTML; a bare string renders
  unstyled. Tag parity is a correctness check, not a style preference.
- **Assuming images are localized.** There is no per-locale image slot. Text baked into
  art stays in the source language unless the art is replaced.
- **Forgetting item groups and currency packages.** Groups are the store's tab labels.
  The CLI cannot update them; `apply.sh` emits an Admin PUT body via `catalog_i18n.py`.
  Packages are a distinct entity from bundles. A pass covering only item CLI flags leaves
  groups, `long_description`, and packages in the source language.

## Scripts

| Script | Does |
|---|---|
| `preflight.sh` | Verifies CLI, subcommands, both credentials, and project targeting. Fails loudly |
| `snapshot.sh <domain>` | Baseline via **admin** catalog reads + git commit. The rollback point |
| `extract.sh <src> <tgt> [baseline]` | Baseline → `translatable.json`. **No domain argument** |
| `apply.sh <domain> <tgt> [--commit] [--report] [--confirm-overwrites]` | Writes both surfaces. Dry run by default. Blocks on `--commit` if any unit already has a different target-locale value, until `--confirm-overwrites` is added. `--report` = file coverage, then `verify.sh` |
| `verify.sh <domain> <tgt> [--json]` | **Reads the live store back** and diffs it against what was sent. The only real check |
| `set-opening-language.sh <domain> <locale>` | Makes the shop **open** in that locale. Not optional |
| `restore.sh <domain> [baseline] [--commit] [--languages …]` | Replays a baseline. The actual rollback |
| `probe-locale.sh` | Settles locale-code and replace-semantics behaviour against a live throwaway SKU |
| `ingest-user-translations.sh <locale> <file>` | Merge publisher JSON/TXT into `translated.json`. No store writes |
| `catalog_i18n.py` | Catalog and LiveOps CSV round-trip. Preview default; `--write` is live |

A run is `preflight → snapshot → extract → translate → apply --commit →
set-opening-language → verify.sh`. Dropping the second-to-last step produces a shop that is
fully translated and still renders in the source language; dropping the last one produces a
run that reports success without evidence.

## Rolling back

The snapshot commit is a rollback *point*; `restore.sh` is what makes it a rollback:

```
scripts/restore.sh <domain>                                   # dry run
scripts/restore.sh <domain> --commit --languages en-US        # replay + reset what the site offers
```

It re-sends whole entities, so a restore cannot itself drop prices or unlist items. Storefront
strings are deliberately **not** reverted — they are per-locale and invisible unless that
locale is offered, so leaving them makes a re-run cheap. Use `--languages` to control what the
site offers, and therefore what it opens in.

## Reference

- `references/i18n-support.md` — supported locales, code formats, and exactly what is and
  is not localizable.
- `references/translation-notes.md` — the silent-failure catalog for this workflow.
- `README-poc.md` — PoC scope, what is deferred, and open questions for review.
