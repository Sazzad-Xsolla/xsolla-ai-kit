# What Xsolla localizes, and what it does not

Source: [supported languages](https://developers.xsolla.com/dev-resources/references/supported-languages/),
[catalog API › Localization](https://developers.xsolla.com/api/catalog#section/Localization),
[web-shop › localization](https://developers.xsolla.com/solutions/web-shop/create-web-shop/localization/).

## Supported locales

26 languages. Item name and description localize into these and only these:

| Language | 2-letter | 5-symbol | | Language | 2-letter | 5-symbol |
|---|---|---|---|---|---|---|
| English (US) | `en` | `en-US` | | Khmer | `km` | `km-KH` |
| Arabic | `ar` | `ar-AE` | | Korean | `ko` | `ko-KR` |
| Bulgarian | `bg` | `bg-BG` | | Lao | `lo` | `lo-LA` |
| Burmese | `my` | `my-MM` | | Nepali | `ne` | `ne-NP` |
| Chinese simplified | `cn` | `zh-CN` | | Polish | `pl` | `pl-PL` |
| Chinese traditional | `tw` | `zh-TW` | | Portuguese (Brazil) | `pt` | `pt-BR` |
| Czech | `cs` | `cs-CZ` | | Romanian | `ro` | `ro-RO` |
| Filipino | `ph` | `ph-PH` | | Russian | `ru` | `ru-RU` |
| French | `fr` | `fr-FR` | | Spanish (Spain) | `es` | `es-ES` |
| German | `de` | `de-DE` | | Thai | `th` | `th-TH` |
| Hebrew | `he` | `he-IL` | | Turkish | `tr` | `tr-TR` |
| Indonesian | `id` | `id-ID` | | Vietnamese | `vi` | `vi-VN` |
| Italian | `it` | `it-IT` | | | | |
| Japanese | `ja` | `ja-JP` | | | | |

**Notable absences**, worth knowing before anyone promises a market: no Dutch, no
Swedish / Norwegian / Danish / Finnish, no Hindi, no Ukrainian, no Greek. `pt` is
Brazilian Portuguese — there is no European Portuguese. `es` is Castilian — there is no
Latin American Spanish.

Note the two Chinese codes are irregular: the two-letter forms are `cn` / `tw`, but the
five-symbol forms are `zh-CN` / `zh-TW`. Do not derive one from the other by truncation.

## Code format

### Locale codes on the catalog — SETTLED BY TEST

Probed against a live project with a throwaway SKU (`scripts/probe-locale.sh`). Both source
documents were half right, and the split is on the **read** side, not the write side:

| Action | Code used | Result |
|---|---|---|
| write `name` map | `ja-JP` | accepted, **stored normalized as `ja`** |
| write `name` map | `ja` | accepted, stored as `ja` |
| read `--locale` | `ja` | resolves — returns 「テスト」 |
| read `--locale` | `ja-JP` | **falls back to English, silently** |

So: writing `{"en":"Probe","ja-JP":"テスト"}` produces the admin map `{"en":"Probe","ja":"テスト"}`.
The five-symbol form is accepted and folded down on input, which is why SKILL.md's "both
forms accepted" held — but a five-symbol code passed to `--locale` on a **read** resolves to
nothing and quietly serves the default, which is the "fails quietly" the draft described.

**Rule: use the two-letter form everywhere on the catalog.** It is what the store actually
holds, what reads resolve, and what admin responses return. Reserve the five-symbol form for
the localization store and `add-language`, which genuinely require it.

### What a client read can and cannot tell you (tested)

Against a live project, the storefront read accepts **any** locale string and returns
`ok: true` with the default-locale text. Tested on a live project, five items:

```
--locale en           Vanguard Skin | Season 1 Pass | Obsidian Skin | ...
--locale ja           Vanguard Skin | Season 1 Pass | Obsidian Skin | ...   (identical)
--locale ja-JP        Vanguard Skin | ...                                   (identical)
--locale zz           Vanguard Skin | ...                                   (identical)
--locale not-a-locale Vanguard Skin | ...                                   (identical)
```

There is no 400, no warning, no marker. **A client read therefore cannot distinguish a valid
locale code from a typo, nor a translation from a fallback.** Any verification step built on
`list-catalog-items --locale <target>` proves nothing. Only the admin read (`get-items`,
which has no `--locale` and returns the raw locale map) shows which key was actually stored.

This is also why the locale-code question above cannot be settled by reading the storefront.

### Both forms are documented as accepted on input:

```json
{ "name": { "en-US": "Starter Pack", "de-DE": "Premium-Paket" } }
{ "name": { "en":    "Starter Pack", "de":    "Premium-Paket" } }
```

Two constraints that follow:

- **Catalog admin responses return the two-letter form** regardless of what you sent.
  Round-tripping a five-symbol write through a read gives you two-letter keys back. The
  reconciliation step must normalize before diffing or every key looks changed.
- **If both `en` and `en-US` are sent for the same language, the last one wins.** Sending
  both is not additive, it is a race. Pick one form and hold it across the whole project.

This skill uses the **five-symbol** form throughout, because the localization store and
`add-language` use it (`en-US`, `de-DE`, `ja-JP`, `pt-BR`), and normalizes catalog reads up
to it.

## Localizable fields

### Catalog — exactly three fields

`name`, `description`, `long_description`. Nothing else in a catalog entity is a
locale-keyed map. Applies to virtual items, bundles, virtual currency, virtual currency
packages, item groups, and game key packages.

**Item groups are the most-forgotten entity.** They render as the store's tab labels, so
an untranslated group is highly visible while every card under it is correctly translated.

### Blocks — an `L:` id, and the text lives elsewhere

Block text is **not stored in the block**. `get-structure` gives each text field a
reference:

```json
{"values": {"title": {"id": "L:9f2c…"}}}
```

The text lives in a separate localization store keyed by the slug, read with
`get-localization --slug <domain> --json`:

```json
{"common": {"L:c1": {"en-US": "<p>…</p>"}},
 "pages":  {"<pageId>": {"texts": {"L:t1": {"en-US": "<h1>Hold the Line</h1>",
                                            "de-DE": "<h1>Haltet die Stellung</h1>"}}}}}
```

Two namespaces: `common` for shared strings, and one per page `_id`. An `L:` id must be
written back into the scope it lives in.

Writes:

| Command | Use |
|---|---|
| `update-localization` | one id, one locale |
| `update-many-localization` | **one locale, many ids, one call** — the batch path |

```
update-many-localization --slug <domain> \
  --data '{"locale":"de-DE","perScopeValues":{"<pageId>":{"L:t1":{"translation":"<h1>…</h1>"}}}}'
```

The per-id value **must** be the object `{"translation": …}`. A bare string, or the keys
`value` / `text` / `translations`, returns **200 and writes an empty string**.

Block text is **HTML** — wrap copy in `<h1>` / `<h2>` / `<p>`; a bare string renders
unstyled.

`get-block --slug <domain> --block-id <id>` is the only read that returns a block with its
localized strings already resolved. `get-structure` shows references only.

**Consequence for translation:** the `values`-vs-`components` distinction is irrelevant
here. Section titles and FAQ answers are `L:` ids like any other, and translating them
touches no block structure. That distinction matters only for structural edits — and those
carry their own rule: **never wholesale-replace `values` or `components`**, because copying
`L:` references with no matching localization 500s the renderer.

## Not localizable

| Thing | Status | Consequence |
|---|---|---|
| **Images** | No per-locale slot exists | Text baked into art stays in the source language. The documented workaround is custom HTML. Best answer: do not put text in images |
| **Any catalog field except the three above** | Single-value | SKU, type, prices, image URL are global |
| **Item group name, via CLI** | No update command | Use `catalog_i18n.py` Admin PUT (`groups`). CLI list may still return a bare string |
| **`long_description`, via `update-items`** | No CLI flag | Carried in `catalog.put.*.json` / `catalog_i18n.py` PUT, not `--long-description` |
| **Federated block content** (offer chain, daily reward, offerwall) | **Unverified** | Content lives under `values.internalBlockValues` and references a liveops entity created outside the storefront. Whether its labels carry `L:` ids that appear in the localization store is not documented and was not confirmed. Treat as an open spike |
| **Custom React blocks** | Only if authored for it | You own the i18n |
| **Header nav chrome** (Store / Daily gifts / Rewards / Redeem code) | Xsolla-owned | Xsolla translates it. It is also not in the landing structure and cannot be removed or edited via CLI |

## Prices are a separate axis

Price display keys off the user's **country** (explicit `country` param or IP), never the
UI language. From Xsolla's own worked example: with a USD default and EUR regional prices,
a user in Japan sees *7 USD* — "the currency of Japan is not specified, so the price is
displayed in the default currency."

And the fallback is catalog-wide, not per-item: if regional prices exist for a country on
every item *except one*, prices for **the entire catalog** in that country fall back to the
default currency. Price coverage is all-or-nothing per market and must be audited as a set.

Source: [pricing policy › country determination](https://developers.xsolla.com/items-catalog/catalog-features/pricing-policy/).

## Length expansion

Budget for it at translation time, not at QA time.

| Locale | Expansion vs. English | Specific risk |
|---|---|---|
| `de-DE` | +10–35% | Button labels, section tabs |
| `pt-BR` | +15–30% | CTAs, tabs |
| `ja-JP` | Fewer characters, taller line-height | **Does not wrap on spaces** — long unbroken runs overflow cards |

## Formatting conventions

| | `de-DE` | `ja-JP` | `pt-BR` |
|---|---|---|---|
| Decimal | `1.234,56` | `1,234.56` | `1.234,56` |
| Currency | `9,99 €` (symbol after) | `¥1,200` (**no decimals**) | `R$ 9,99` |
| Date | `31.08.2026` | `2026年8月31日` | `31/08/2026` |

Currency rendering itself is Xsolla-side and follows the price object. What matters for a
translation pass is that **no copy hardcodes a formatted number or price** — hardcoded
prices in hero or FAQ text are a frequent and embarrassing miss.
