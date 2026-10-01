# Shop Builder storefront

Storefront half of `localization`. Paths are relative to the skill directory. Catalog and LiveOps text go through `scripts/catalog_i18n.py`, not this page.

A store's text lives in three systems. Translating one of them ships a shop that looks finished and is not. The model translates. These steps exist so a write can be undone and a silent success is not trusted.

## Surfaces

| Surface | What | Who | Write |
|---|---|---|---|
| A — Site chrome | Cart, buttons, nav, checkout UI | Xsolla, all 26 languages | Enable the language. Do not translate. Overrides are editor-only: double-click in Publisher Account. Never while this skill is writing. |
| B — Block copy | Hero, CTAs, section titles, FAQ, footer | This skill | `xsolla shopbuilder update-many-localization` |
| C — Catalog | Item, bundle, package, group `name`, `description`, `long_description` | This skill | Admin PUT via `scripts/catalog_i18n.py`. CLI `xsolla catalog` only for items, bundles, and packages `name` + `description`. |

Not for creating the store (`shop-builder-assembly`), building the catalog (`catalog-design`), or prices (below).

## Prerequisites

- Store renders and catalog is populated. An empty catalog translates demo data.
- Two credentials. Shop Builder: `xsolla auth login` (OAuth2 + PKCE). On "audience required", retry `--audience https://api.xsolla.com`. CI fallback: `export XSOLLA_SHOPBUILDER_SESSION='pa-v4-token=<value>'`. The `pa-v4-token=` prefix is part of the value. `ps2[user_session]` 403s. Catalog: Basic auth, `XSOLLA_API_KEY` plus `--merchant-id`. A 403 on one says nothing about the other.
- `XSOLLA_MERCHANT_ID`, `XSOLLA_PROJECT_ID`.
- Use the returned domain. `create-website --slug voidwall` yields `voidwall-45e0`. Localization commands take that domain as `--slug`. `--landing-id` is the landing's Mongo `_id` from `get-structure`. A slug there 500s.
- `scripts/preflight.sh` checks `shopbuilder get-localization`, `update-many-localization`, `get-block`, and the catalog commands this skill calls.
- No sandbox on either surface. `apply.sh --commit` refuses catalog writes until `XSOLLA_PRODUCTION_PROJECT_IDS` lists every project that must not be touched.

## Steps

### 1. Preflight

```
scripts/preflight.sh
```

Fails if the CLI is the wrong binary, a subcommand is missing, the session is unset, or project targeting is wrong, instead of failing silently three steps later.

A client read falls back to the default locale with no marker. Identical text means untranslated or translated the same. Coverage comes from admin `get-items`. If it is ambiguous, say so. Do not invent a percentage.

### 2. Enable the language first

Both gates must be open or writes succeed and never render. Doing this last is the usual way a pass appears to do nothing.

1. Project languages: Publisher Account, Project Settings, General Settings.
2. Site language toggles, plus a visible selector in Header and/or Footer.

```
xsolla shopbuilder add-language --merchant-id <m> --project-id <p> --slug <domain> --language de-DE
```

### 3. Snapshot

```
scripts/snapshot.sh <domain>
```

Pulls `get-structure`, `get-localization`, and the catalog into `l10n/baseline/<timestamp>/` and commits that tree verbatim. Reformat, if at all, in a later commit so "what the API returned" stays separate from "what we prettified".

Catalog reads must be admin (`get-items`, `get-bundles`, `admin-list-currency-packages`): a locale map. Client reads return one resolved string, then `extract.sh` drops every catalog string and the run looks like a successful storefront-only pass. `snapshot.sh` aborts on that shape. `admin-list-items-by-group` returns 403 with a project-scoped key, so items and bundles are walked per SKU, which also catches items in no group.

Re-snapshot every run. A Publisher Account edit since the last baseline makes the diff a lie.

### 4. Extract

```
scripts/extract.sh <source-locale> <target-locale> [baseline-dir]
scripts/extract.sh en-US ja-JP
```

No domain argument. The domain is in the baseline. Omit the directory and the newest baseline is used. A domain in the first position is read as the source locale, matches nothing, and yields an empty extraction that looks plausible.

Writes `l10n/work/<target>/translatable.json`: stable `id`, source, HTML tags, character budget, `kind`.

Andrey's launch rule, before any translation: does the publisher already have a complete set? If yes, ingest it and do not re-translate. JSON may be a full `translated.json`, `{"units":[{"id","target"}]}`, or `{id: text}`. TXT is `id<TAB>target` or `id: target` per line.

```
scripts/ingest-user-translations.sh ja-JP ./publisher-ja.json
```

Show `filled` / `still_empty` and confirm before `apply.sh`. If they need the model, do not fill yet. Show locale, counts by surface, `existing_target_present`, legal and asset skips, and that a snapshot exists. Wait for an explicit yes.

Never skip the snapshot because a file was ingested.

Translatable, and only these:

- Catalog: `name`, `description`, `long_description`. Nothing else in the catalog is a locale-keyed map.
- Blocks: any field with an `L:` id, including hero, CTAs, section titles, FAQ, and `common`.
- Page SEO: `page.seo.title` and `page.seo.description`. They have `L:` ids and live under `page.seo`, a sibling of `page.blocks`. The block walker misses them. `page.seo.ogImage` is an `L:` id but a URL (`kind: asset`): extracted, never translated.

Never send to translation: SKUs, item and block ids, group keys, `type`, `layout`, prices, currency codes, image URLs, `mediaValues` keys, theme colors, `blockId`, `host`, `offerChainId`, `L:` ids, `I:` ids. Allowlist, do not denylist. A denylist sends new fields to the translator. A mistranslated SKU breaks the store. A missed string is caught by reconciliation.

### 5. Translate

The model writes `l10n/work/<target>/translated.json`. No machine-translation service.

1. `glossary/do-not-translate.txt` is verbatim: game title, factions, characters, currency names, "Xsolla", "Pay Station". `glossary/termbase.csv` is the one rendering per locale for recurring nouns. Extend it. Do not invent a second rarity name three cards later.
2. Keep HTML tags, order, and count. `<h1>Hold the Line</h1>` becomes `<h1>Haltet die Stellung</h1>`. A dropped tag is unstyled layout, not a style nit.
3. Stay inside the character budget. German runs 10–35% longer than English, `pt-BR` 15–30%. Japanese is shorter but does not wrap on spaces. Shorten copy that would overflow. Do not ship the overflow.
4. `kind: marketing` is transcreation. Hero, promo, CTA. A literal pun is grammatical and dead.
5. Do not skip a string because a target exists. On one template landing, 52 of 53 block strings already had `de-DE`, across 26 pre-populated locales. Skipping them would translate one string and report success. After the English changes, stock translations go stale. A card reading "Pay as you go" can carry a `ja-JP` value meaning "Official store". `extract.sh` reports `existing_target_present`, not "already translated". Compare to the current source and overwrite.
6. Do not faithfully render broken English. Template copy is often truncated or about another game. Translate the intent and name the source strings that need an English fix.
7. Never translate a value starting with `http`. `kind: asset`. `apply.sh` skips them. A translated URL is a broken image.
8. Never translate legal or compliance text: refund policy, ToS, age-rating, tax disclosure. `kind: legal`. Flag them. Leave them for counsel.

### 6. Write

```
scripts/apply.sh <domain> <target-locale>
scripts/apply.sh <domain> <target-locale> --commit
scripts/apply.sh <domain> <target-locale> --commit --confirm-overwrites
```

Dry run is the default and sends nothing. Read it before `--commit`.

`apply.sh` compares `existing_target` (from extract) with the value about to be sent. If any differ, `--commit` alone blocks and prints each pair. `--commit --confirm-overwrites` proceeds only after a human has read that list. Identical values need no confirmation. The flag is an acknowledgment of that list, not a permanent skip. Read the list again every time it fires. The units change between runs.

**Blocks.** Text is not in the block. `get-structure` puts `L:<uuid>` at `values.<field>.id`. The string is in a localization store keyed by the slug. `update-block` on `["values","title"]` returns `ok:true` and changes nothing.

```
xsolla shopbuilder update-many-localization --slug <domain> \
  --data '{"locale":"de-DE","perScopeValues":{
             "<pageId>":{"L:<id>":{"translation":"<h1>Haltet die Stellung</h1>"}},
             "common":{"L:<id2>":{"translation":"<p>…</p>"}}}}'
```

Scope is the page `_id`, or `"common"`. The per-id value must be `{"L:x": {"translation": "text"}}`. `{"L:x": "text"}`, or the keys `value` / `text` / `translations`, returns 200 and writes an empty string. The key is `translation`, singular. One call per locale, so the source language is not dropped here. `values` versus `components` does not apply to translation. Never wholesale-replace a block's `values` or `components`. Copying `L:` ids with no localization 500s the renderer.

**Catalog.** CLI cannot carry every field.

- Pass-through Admin PUT (`catalog_i18n.py`): GET, drop server-derived keys, merge locale maps, PUT the object. This is how groups and `long_description` are written. Dry-run saves `payloads/catalog.put.<entity>.<id>.json`. `apply.sh --commit` does not call `import --write` or `restore --write`. Those hit the live Store API and need their own yes.
- CLI `update-items`, `admin-update-bundles` (`--bundle-sku`), `admin-update-currency-package` (`--package-sku`) rebuild `--name` and `--description` plus prices, groups, and flags from the baseline. There is no `--long-description` flag.

```
xsolla catalog update-items --item-sku <sku> --sku <sku> \
  --merchant-id <m> --project-id <p> \
  --prices '[{"amount":9.99,"currency":"USD","is_default":true,"is_enabled":true}]' \
  --groups '["cosmetics"]' --is-enabled=true --is-show-in-store=true \
  --description '{"en":"...","de":"..."}' \
  --name '{"en":"Starter Pack","de":"Starterpaket"}'
```

Do not pass `--sandbox`. It is a no-op, and omitting fields replaces the entity.

Measured by `scripts/probe-locale.sh`:

1. Whole entity is replaced. An item with a price, a group, and `is_show_in_store:true`, updated with only `--name` and `--description`, came back `prices:[] groups:[] is_show_in_store:false` and `ok:true`. The item left the store. `apply.sh` rebuilds every field from the baseline. Flags the CLI exposes: `--prices`, `--groups`, `--is-enabled`, `--is-show-in-store`, `--image-url`, `--is-free`, `--vc-prices`. `--groups` is what makes an item store-visible.
2. `description` is mandatory. Omitting it is HTTP 422. A missing description fails loudly. A missing price fails silently. An item with no description cannot be name-translated by inventing copy. Flag it.
3. Two-letter catalog keys. `ja-JP` is accepted and stored as `ja`. `--locale ja-JP` on a read falls back to English. `apply.sh` maps `zh-CN` to `cn` and `zh-TW` to `tw`. Do not truncate those to `zh`. Five-letter codes are for the localization store and `add-language` only.

The locale map is replaced, not merged. `{en, ja}` sent to an item holding `{en, es, ja}` leaves `{en, ja}`. Spanish is gone, `rc=0`, no warning. `apply.sh` seeds the map from the baseline and overlays source plus target, and prints `(preserving es, …)`. Check that line before `--commit`.

CLI gaps, covered by Admin PUT, not by patching the CLI: item groups (`/admin/items/groups/{external_id}`, the tab labels) and `long_description`. Dry-run must show `catalog.put.item_group.*.json` and `long_description` inside the item body. Currency packages are a different entity from bundles and from virtual currency.

### 7. Opening language

`apply.sh --commit` runs this after the write. The publisher does not.

```
scripts/set-opening-language.sh <domain> <target-locale>
```

There is no default-locale field. Order of `languages` decides, and preview uses that same first entry. `add-language` only appends, so enabling `de-DE` on a site that opens in `it-IT` leaves Italian first. The German copy is in the selector. The preview still opens in Italian, and a read-back of the strings still passes.

The script deletes and re-adds so the target is first. `delete-language` edits the enabled list only. Strings stay in the store and return on re-add. The languages that were already enabled stay behind the target, so the selector still offers them.

### 8. Verify

```
scripts/verify.sh <domain> <target-locale>
scripts/verify.sh <domain> <target-locale> --json
```

Every incorrect write in this system returns success. `apply.sh` checks blanks, tag parity, and length against a file on disk. That passes whether or not a word reached the store. `verify.sh` asks the store. Exit non-zero if something is missing. A value that differs from what was sent is reported, not failed, because a person may have edited the store since.

1. Catalog, admin reads only (`get-items`, `get-bundles`, `admin-list-currency-packages`), never `--locale`. Target key non-empty for `name` and `description`, source locale still present, other locales listed. On project 314515 the storefront read returned `ok:true` and default-locale text for `ja`, `ja-JP`, `zz`, and `not-a-locale`. It proves neither that a code is valid nor that a translation exists.
2. Storefront via `get-localization`. Each `L:` id in its own scope. Page strings nest one level deeper than `common`. `get-structure` returns ids, not text. `get-block --slug <domain> --block-id <id>` is the read that inlines localized strings.
3. Languages via `get-structure`: target enabled, and first, which is what the shop opens in.
4. Prices: a currency on some entities and missing on others. One gap de-localizes every price in that market.

`apply.sh --commit --report` runs `verify.sh` after the write. File coverage alone is not verification.

Then render:

```
xsolla shopbuilder enable-preview --slug <domain>
```

Open `https://preview.xsollasitebuilder.com/<domain>`, switch language, scroll top to bottom before capturing. Card images lazy-load. Blanks above the capture are an artifact. Re-run `enable-preview` and hard-refresh. Preview is a snapshot, so a stale preview looks like a failed write.

`enable-preview` and `preview-link` return 403 `admin_privileges_requred` without admin rights. No CLI flag fixes that. Use Publisher Account. Steps 1–4 are the verification. The screenshot is confirmation. Look for untranslated strings, overflow, and prices.

## Prices are not text

Price follows the buyer's country, not the UI language. A German store with no EUR price shows USD. If every item but one has a regional price, the whole catalog falls back to the default currency for that market. This skill reports the gap in `verify.sh`. It does not set prices.

## No sandbox

`--sandbox` does not change the URL. Catalog:

```
xsolla catalog list-catalog-items --project-id <p> --sandbox --verbose --dry-run
```

warns `--sandbox has no effect on this command — catalog has no Xsolla sandbox` and requests `https://store.xsolla.com/api/v2/project/<p>/items/virtual_items`. Shop Builder `get-structure --sandbox` warns the same (`shopbuilder has no Xsolla sandbox`) and requests `https://sitebuilder.xsolla.com/api/merchant/<m>/project/<p>/landing/<domain>/structure`. Also checked: `list-catalog-items`, `list-item-groups`, `list-catalog-bundles`, `list-all-items`. Reads and writes are live. The scripts never pass `--sandbox`.

`features.isSandboxMode` on a landing is payment behaviour, not a routing mode, and it does not make writes reversible.

`apply.sh` prints the project id and "writes go LIVE" before a catalog call, and refuses `--commit` unless `XSOLLA_PRODUCTION_PROJECT_IDS` is set. Use a disposable project. The git baseline lets you replay old values. It does not roll the store back by itself. `restore.sh` does. There is nothing to promote to. Sign-off per market, a fresh baseline, and a freeze window are the discipline.

## One writer

Do not edit the landing in Publisher Account while this skill runs. Concurrent writers overwrite each other, drop blocks, and leave "Block with id … not found". Chrome overrides are editor-only, so they are a separate step, not interleaved with CLI writes.

## Pitfalls

- Stopping before `--commit` has moved the target language first. Preview opens in `languages[0]`. German copy with Italian still first looks like the translation did not work. `verify.sh` fails that run. Do not report it as passed.
- Judging from the editor. It opens on the default locale. German item names under English headings do not mean the storefront write failed.
- Domain passed to `extract.sh`. First argument is the source locale.
- Client-read snapshot. Bare strings. Every catalog string skipped.
- `--name` and `--description` only. `ok:true`, prices and groups gone, item unlisted.
- Five-letter codes on the catalog. Stored as two letters. Reads with `--locale ja-JP` return the default.
- Verifying with `--locale`. `ok:true` and default text for any string, including `not-a-locale`.
- `update-block` for copy. `ok:true`, no change. Use `update-many-localization`.
- Bare per-id string, or any key but `translation`. HTTP 200, empty string written.
- Writing before `add-language`, at project and site. Succeeds, renders nothing.
- Sending only source and target. Deletes every other locale on that entity.
- Trusting `ok:true` or pre-send checks. Run `verify.sh`.
- Slug as `--landing-id`. 500. `_id` from `get-structure` versus returned domain as `--slug`.
- Replacing `values` or `components`. Renderer 500. Translation never needs this.
- Confirming copy with `get-structure`. Ids, not text. Use `get-localization` or `get-block`.
- Translating a SKU, group key, or `type`. Allowlist exists to stop this.
- Dropped HTML. Unstyled text.
- Assuming images localize. No per-locale image slot. Text in art stays until the art is replaced.
- Forgetting groups, packages, and `long_description`. Items-only CLI leaves tabs, top-ups, and long copy in the source language.

## Scripts

| Script | Does |
|---|---|
| `preflight.sh` | CLI, subcommands, both credentials, project targeting |
| `snapshot.sh <domain>` | Admin catalog reads plus git commit. Rollback point |
| `extract.sh <src> <tgt> [baseline]` | `translatable.json`. No domain argument |
| `apply.sh <domain> <tgt> [--commit] [--report] [--confirm-overwrites]` | Both surfaces. Dry run default. `--commit` blocks on a different existing value until `--confirm-overwrites`, then moves `<tgt>` first so preview opens in it. `--report` is file coverage, then `verify.sh` |
| `verify.sh <domain> <tgt> [--json]` | Live read-back. The only real check |
| `set-opening-language.sh <domain> <locale>` | Shop opens in that locale |
| `restore.sh <domain> [baseline] [--commit] [--languages …]` | Replays a baseline |
| `probe-locale.sh` | Locale codes and replace semantics on a throwaway SKU |
| `ingest-user-translations.sh <locale> <file>` | Publisher JSON or TXT into `translated.json`. No store write |
| `catalog_i18n.py` | Catalog and LiveOps CSV. Preview unless `--write` |

Order: `preflight`, `snapshot`, `extract`, translate, `apply --commit`, `verify.sh`. `--commit` includes the opening language. Drop verify and the run reports success with no evidence. A verify report that does not say the shop opens in the target language is a failed run.

## Rollback

```
scripts/restore.sh <domain>
scripts/restore.sh <domain> --commit --languages en-US
```

Re-sends whole entities, so a restore cannot drop prices or unlist items. Storefront strings are left in place. They are invisible unless that locale is offered, and leaving them makes a re-run cheap. `--languages` sets what the site offers, and therefore what it opens in.

## Also read

- [i18n-support.md](i18n-support.md) — locales, code formats, what is localizable.
- [translation-notes.md](translation-notes.md) — the same failures, as a field catalog, including CLI response shapes.
- `evals/localization/EVAL-LOG.md` — live runs and what the definition of done still lacks.
