# Field notes: translating a Shop Builder store

The failures specific to a translation pass. General Shop Builder failures are in
`shopbuilder-storefront/references/field-notes.md`; this file does not repeat them except
where a translation pass hits them differently.

## The governing property: every wrong write succeeds

There is no failure signal anywhere in this workflow. `update-block` returns `ok:true` for
a correct patch, a misrouted patch, and a no-op patch alike. The catalog admin API accepts
a locale map that silently drops the locale you meant to keep. `get-structure` returns a
healthy document for a store rendering entirely demo data.

Everything below is a consequence of that. **Verification is not a final step in this
workflow, it is the workflow.**

## Order of operations

- **Enable the language first, before writing a single string.** The project language list
  and the site language toggles are both gates. Write translations into a locale the site
  does not have enabled and every call succeeds while nothing renders. This reads exactly
  like "the translation didn't work" and sends people debugging the wrong layer.
- **Snapshot before writing, every run.** Not once at project start. If a human touched the
  store in Publisher Account between runs, a stale baseline makes the diff wrong in the one
  direction that matters — it hides their change and you overwrite it.

## Writes

- **Block text is not in the block.** `get-structure` gives a field an `L:<uuid>`; the text
  lives in a separate localization store keyed by the slug. Patching `["values","title"]`
  via `update-block` returns `ok:true` and changes nothing. Write with
  `update-many-localization` (batch, one locale per call) or `update-localization` (single).
- **The per-id envelope is `{"translation": …}`, singular.** A bare string, or the keys
  `value` / `text` / `translations`, returns **200 and writes an EMPTY string**. This is the
  nastiest failure in the workflow: a success response, a well-formed request, and the copy
  silently blanked.
- **An `L:` id must be written into its own scope** — the page `_id` it lives under, or
  `common` for shared strings. Resolve scopes from `get-localization` before writing.
- **Catalog locale maps are replaced, not merged.** Sending `{"de-DE": …}` to a field
  holding `{"en-US": …}` leaves German only. Always send the full map. Completely silent,
  and it removes the source language from a live store.
- **The catalog stores `pt-BR` under the key `pt`**, and generally returns two-letter keys
  regardless of what was written. Normalize before diffing or reconciliation reports every
  key as changed.
- **`--landing-id` is the landing's Mongo `_id`, not the slug.** Passing a slug 500s.
  `--slug` is the returned domain (`voidwall-45e0`), not the slug you requested.
- **Never wholesale-replace a block's `values` or `components`.** Copying `L:` references
  with no matching localization 500s the renderer. Translation never needs to — the text is
  not in the block. Use targeted writes.
- **`update-items` replaces the ENTITY, not just the fields you name — PROVEN, not inferred.**
  Probed live: an item created with a price, a group and `is_show_in_store:true`, then
  updated with only `--name` and `--description`, came back
  `prices:[] groups:[] is_show_in_store:false` — and the call returned **`ok:true`**. The
  item silently left the store. Separately, an update with `--name` but no `--description`
  is rejected with **HTTP 422**, so a missing description fails loudly while a missing price
  fails silently. It exposes
  `--prices`, `--groups`, `--is-enabled`, `--is-show-in-store`, `--image-url`, `--is-free`,
  `--vc-prices`. A name/description-only write is how a translation pass drops prices and
  unlists items — `--groups` is documented as "makes it store-visible", so losing it removes
  the item from the store. Reconstruct the whole entity from the baseline on every write.

- **`description` is mandatory and needs at least one character in every locale sent.** An
  item with no description cannot be name-translated without inventing copy. Flag it and let
  a human write the source string; do not fabricate one.

- **Item groups have no CLI update command** in this build, and `update-items` has no
  `--long-description` flag. Both are real gaps: report them, do not pretend they were
  covered.

## Response shapes — three ways to read nothing and think you read something

Every one of these was found by running the pipeline against a real store, and every one of
them produced **zero output and no error**.

1. **The CLI wraps everything in `{"ok":true,"data":{…}}`.** `pages` and `common` are one
   level below where a naive parse looks. Unwrap `.data` before touching a response.
2. **`--all` changes the shape.** Without it, `.data` is `{items:[…]}`; with it, `.data`
   **is** the array. Indexing an array with a string is a jq *error*, not null — and an error
   swallowed by `|| true` becomes an empty result that looks like an empty catalog.
3. **Localization entries nest the locale map under `translations`**, beside a `description`
   holding the dotted source path:

   ```json
   {"description": "blocks.header.values.loginButton",
    "translations": {"en-US": "Log in", "de-DE": "Anmelden"}}
   ```

   Treating that dict as the locale map itself makes every lookup miss. In `walk()` a miss
   hits a *silent early return*, so the entire storefront is skipped without one note.

**Read shape is `translations` (plural, a locale map). Write shape is `translation`
(singular, one string).** They are different keys on purpose and neither accepts the other.

Related: bundles embed their contents' SKUs under `content`, so a recursive SKU sweep over
`list-catalog-bundles` yields virtual-item SKUs and `get-bundles` 404s on them. Take
top-level SKUs only.

## Reads and verification

- **Two catalog read families, and the tell is `--locale`.** Getting this wrong is silent in
  both directions.

  | Family | Auth | `--locale`? | Returns | Commands |
  |---|---|---|---|---|
  | client | none | yes | one **resolved** string | `list-catalog-items`, `get-catalog-item`, `get-item-by-sku`, `list-all-items`, `list-item-groups` |
  | admin | Basic | no | the real **locale map** | `get-items`, `admin-list-items-by-group`, `admin-list-bundles-by-group`, `admin-list-currency-packages` |

  A baseline taken with a client read yields `"name": "Vanguard Skin"` where `extract.sh`
  expects `{"en": "Vanguard Skin"}`, and every catalog string is dropped without a word. The
  run then translates the storefront only and reports success. `snapshot.sh` asserts the
  shape for this reason.

- **The client read accepts any locale string at all** — `ja`, `ja-JP`, `zz`,
  `not-a-locale` all return `ok:true` with identical default-locale text (tested, project
  314515). So a client read can prove neither that a locale code is valid nor that a
  translation exists. **Verify the catalog with `get-items`, never with `--locale`.**

- **`get-structure` does not return text.** It returns `L:` ids. It is the source of truth
  for structure and useless for confirming copy.
- **`get-block --slug <domain> --block-id <id>` is the one read that resolves text**,
  returning the block with its localized strings inlined. Use it to confirm a write landed.
- **`get-localization --slug <domain>`** returns the whole store — `common."L:<id>"` plus
  `pages.<pageId>.texts."L:<id>"`, each id mapping locale to HTML. This is the
  reconciliation source.
- **Re-run `enable-preview` after changes**, then hard-refresh — the preview serves a
  snapshot, so a stale preview looks like a failed write.
- **Render, in the target locale, scrolled.** Structural checks pass on a store showing
  demo data. Card images lazy-load; blanks above the capture point are an artifact.

## Translation content

- **Dropped HTML tags render as unstyled plain text.** Tag parity between source and target
  is a correctness check, not a style preference. Enforce it mechanically — a human
  reviewing German copy will not notice a missing `<h1>`.
- **Length expansion breaks layout, not text.** German and Brazilian Portuguese overflow
  buttons and tabs. Japanese does not wrap on spaces. This surfaces only in a rendered
  screenshot, never in a review of the JSON, which is why per-locale visual QA is not
  optional.
- **A partially-translated store looks fine.** Missing keys fall back to the source
  language and render cleanly. There is no visual signal for 80% coverage. Only the
  reconciliation diff catches it.
- **A populated target locale is not evidence of a good translation.** Landings created from
  a template ship with stock copy already translated. The moment anyone edits the English,
  those values are silently wrong — a card reading "Pay as you go" can carry a `ja-JP` value
  meaning "Official store". Never skip a string because it already has a target; compare it
  against the *current* source and overwrite. `extract.sh` reports this count as
  `existing_target_present`, deliberately not "already translated".

- **Asset URLs live in the localization store like copy.** SEO `og:image` and similar resolve
  as ordinary localized strings. A translated URL is a broken image. Anything matching
  `^https?://` is classified `kind: asset` and never sent to translation.

- **Broken source English propagates.** Template copy is frequently truncated mid-sentence or
  describes a different game. Translating it faithfully renders the damage into every locale.
  Translate the intent and report which source strings need an English fix.

- **Terminology drift is the tell of a rushed job.** The same rarity tier rendered three
  ways across three cards reads as machine output even when each individual string is
  correct. The glossary is what prevents this, and it has to exist before the first
  translation, not after the first review.

## Structural fields

- **Never send structural values to translation.** SKUs, group keys, `type` and `layout`
  values, `L:` and `I:` reference ids, image URLs, theme colors. A translated SKU is a
  broken store; a translated group key silently empties a store section.
- **Allowlist, do not denylist.** Block text is identified by carrying an `L:` id, and
  catalog text by being one of exactly three fields. A denylist passes every newly-added
  field through to the translator by default. The failure mode of an allowlist is a missed
  translation, which reconciliation catches; of a denylist, a corrupted store, which
  nothing catches.

## Scope traps

- **Item groups are forgotten constantly.** They are the store's tab labels — highly
  visible, and easy to miss because they are a different entity type from the items in them.
- **Currency packages are a distinct entity** from virtual currency and from bundles. A
  pass that translates items and bundles leaves the top-up section in English.
- **Prices are not text.** A fully translated store with no regional price for the market
  shows foreign currency, and one missing SKU price de-localizes the entire catalog for
  that country. Report the gap; do not silently imply translation covered it.
- **Images cannot be translated.** Text baked into art needs new art, which is an art
  budget line, not a localization one. Flag them; never substitute unrelated art.

## Concurrency

- **One writer at a time.** Never run the CLI while someone has the landing open in the
  Publisher Account editor. Concurrent writers overwrite each other, drop blocks, and leave
  ghost references that break the editor with "Block with id … not found".
- **Surface-A chrome overrides are editor-only**, so overriding an Xsolla default string is
  by definition a human in the editor. That work must be serialized against every CLI write
  in this skill, not interleaved with it.
