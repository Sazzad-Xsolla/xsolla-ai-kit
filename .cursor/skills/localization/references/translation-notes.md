# Field notes: translating a Shop Builder store

Failures specific to a translation pass. General Shop Builder failures live in `shopbuilder-storefront/references/field-notes.md` and are not repeated here. That skill is not in this kit. The procedure is [storefront.md](storefront.md). This page is the failure catalog.

Every wrong write succeeds. `update-block` returns `ok:true` for a correct patch, a misrouted patch, and a no-op. The catalog admin API accepts a locale map that drops the locale you meant to keep. `get-structure` is healthy for a store that is still demo data. Verification is the workflow.

## Order

- Enable the language before any string. Project language list and site toggles are both gates. Writes into a disabled locale succeed and render nothing.
- Snapshot every run, not once. A Publisher Account edit since the last baseline hides their change and you overwrite it.

## Writes

- Block text is not in the block. `get-structure` stores `L:<uuid>`. The string is in a localization store keyed by the slug. Patching `["values","title"]` with `update-block` returns `ok:true` and changes nothing. Use `update-many-localization` (one locale per call) or `update-localization` (one string).
- The per-id envelope is `{"translation": …}`, singular. A bare string, or `value` / `text` / `translations`, returns 200 and writes an empty string.
- Write an `L:` id into its own scope: the page `_id`, or `common`. Resolve scopes from `get-localization` first.
- Catalog locale maps are replaced, not merged. `{"de-DE": …}` sent to a field holding `{"en-US": …}` leaves German only. Send the full map.
- The catalog stores `pt-BR` as `pt`, and generally returns two-letter keys. Normalize before diffing or every key looks changed.
- `--landing-id` is the landing's Mongo `_id`. A slug 500s. `--slug` is the returned domain (`voidwall-45e0`), not the slug you asked for.
- Never wholesale-replace `values` or `components`. `L:` ids with no localization 500 the renderer. Translation does not need that.
- `update-items` replaces the entity. Proven: an item with a price, a group, and `is_show_in_store:true`, updated with only `--name` and `--description`, came back `prices:[] groups:[] is_show_in_store:false` and `ok:true`. `--name` without `--description` is HTTP 422. A missing description fails loudly. A missing price fails silently. Rebuild from the baseline. Flags: `--prices`, `--groups`, `--is-enabled`, `--is-show-in-store`, `--image-url`, `--is-free`, `--vc-prices`. Losing `--groups` unlists the item.
- `description` needs at least one character in every locale sent. Do not invent a description to unlock a name translation. Flag it.
- Item groups have no CLI update. `update-items` has no `--long-description`. Both go through Admin PUT in `catalog_i18n.py`.

## Response shapes

Each of these produced zero output and no error on a real store.

1. The CLI wraps responses in `{"ok":true,"data":{…}}`. `pages` and `common` are under `.data`. Unwrap before parsing.
2. `--all` changes the shape. Without it, `.data` is `{items:[…]}`. With it, `.data` is the array. Indexing an array with a string is a jq error. `|| true` turns that into an empty catalog.
3. Localization entries nest the locale map under `translations`, beside `description` (the dotted source path):

```json
{"description": "blocks.header.values.loginButton",
 "translations": {"en-US": "Log in", "de-DE": "Anmelden"}}
```

Treating that object as the locale map makes every lookup miss. In `walk()` a miss returns early and the storefront is skipped with no note.

Read key is `translations` (plural, a map). Write key is `translation` (singular, one string). Neither accepts the other.

Bundles embed content SKUs under `content`. A recursive SKU sweep of `list-catalog-bundles` then 404s `get-bundles` on those virtual-item SKUs. Take top-level SKUs only.

## Reads

| Family | Auth | `--locale`? | Returns | Commands |
|---|---|---|---|---|
| client | none | yes | one resolved string | `list-catalog-items`, `get-catalog-item`, `get-item-by-sku`, `list-all-items`, `list-item-groups` |
| admin | Basic | no | the locale map | `get-items`, `admin-list-items-by-group`, `admin-list-bundles-by-group`, `admin-list-currency-packages` |

A client baseline yields `"name": "Vanguard Skin"` where `extract.sh` expects `{"en": "Vanguard Skin"}`. Every catalog string is dropped and the run reports a successful storefront-only pass. `snapshot.sh` asserts the shape.

On project 314515, `ja`, `ja-JP`, `zz`, and `not-a-locale` all returned `ok:true` and the same default-locale text. A client read proves neither that a code is valid nor that a translation exists. Verify the catalog with `get-items`, never `--locale`.

- `get-structure` returns `L:` ids, not text.
- `get-block --slug <domain> --block-id <id>` inlines the localized strings. Use it to confirm a write.
- `get-localization --slug <domain>` is the whole store: `common."L:<id>"` and `pages.<pageId>.texts."L:<id>"`, each id mapping locale to HTML.
- Re-run `enable-preview` and hard-refresh. Preview is a snapshot. A stale one looks like a failed write.
- Scroll the target locale before a screenshot. Checks pass on demo data. Card images lazy-load. Blanks above the capture are an artifact.

## Content

- Dropped HTML renders unstyled. Tag parity is a correctness check. A reviewer of the German will not notice a missing `<h1>`.
- German and Brazilian Portuguese overflow buttons and tabs. Japanese does not wrap on spaces. This shows up in a screenshot, not in the JSON.
- Missing keys fall back to the source language and look fine. There is no visual signal for 80% coverage. Only the reconciliation diff catches it.
- A populated target is not a good translation. Template landings ship pre-translated. After the English changes, those values are stale. "Pay as you go" can carry a `ja-JP` value meaning "Official store". `extract.sh` counts this as `existing_target_present`, not "already translated". Compare to the current source and overwrite.
- Asset URLs sit in the localization store like copy. SEO `og:image` is one. `^https?://` is `kind: asset` and is never translated. A translated URL is a broken image.
- Broken source English propagates. Template copy is often truncated or about another game. Translate the intent and name the strings that need an English fix.
- The same rarity rendered three ways is the tell of a rushed job. The glossary has to exist before the first translation.

## Structural fields

Never send SKUs, group keys, `type`, `layout`, `L:` or `I:` ids, image URLs, or theme colors to translation. A translated SKU breaks the store. A translated group key empties a section.

Allowlist. Block text is an `L:` id. Catalog text is exactly three fields. A denylist sends every new field to the translator. A missed string is caught by reconciliation. A corrupted store is not.

## Scope

- Item groups are the tab labels, a different entity from the items in them.
- Currency packages are not virtual currency and not bundles. Items-and-bundles leaves the top-up section in English.
- Prices follow country, not UI language. One missing regional price de-localizes the catalog for that market. Report it. Do not set it.
- There is no per-locale image slot. Text in art needs new art. Flag it. Do not substitute other art.

## Concurrency

One writer. Do not run the CLI while the landing is open in Publisher Account. Concurrent writers drop blocks and leave "Block with id … not found". Overriding an Xsolla default string is editor-only, so that step stays separate from every CLI write.
