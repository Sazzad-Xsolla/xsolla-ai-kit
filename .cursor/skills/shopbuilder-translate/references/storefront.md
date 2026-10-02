# Shop Builder page copy

Paths are relative to the skill directory. Catalog and LiveOps text belong to the `localization` skill, not this page.

The model translates. These steps exist so a write can be undone and a silent success is not trusted.

## Surfaces

| Surface | What | Who | Write |
|---|---|---|---|
| A — Site chrome | Cart, buttons, nav, checkout UI | Xsolla, all 26 languages | Enable the language. Do not translate. Overrides are editor-only: double-click in Publisher Account. Never while this skill is writing. |
| B — Block copy | Hero, CTAs, section titles, FAQ, footer, page SEO | This skill | `xsolla shopbuilder update-many-localization` |

Not for creating the store (`shop-builder-assembly`), translating the catalog (`localization`), or prices.

## Prerequisites

- The store renders. An empty page translates demo data.
- Shop Builder auth is `xsolla auth login` (OAuth2 + PKCE) only. On "audience required", retry `--audience https://api.xsolla.com`. Do not pass a session token by hand.
- `XSOLLA_MERCHANT_ID`, `XSOLLA_PROJECT_ID`.
- `XSOLLA_APPROVED_TEST_PROJECTS` is the approved-test-project allowlist. Writes use environment `test`.
- Use the returned domain. `create-website --slug voidwall` yields `voidwall-45e0`. Localization commands take that domain as `--slug`. `--landing-id` is the landing's Mongo `_id` from `get-structure`. A slug there 500s.
- `scripts/preflight.sh` checks `shopbuilder get-localization`, `update-many-localization`, and `get-block`.
- No sandbox. The scripts never pass `--sandbox`.

## Steps

### 1. Preflight

```
scripts/preflight.sh
```

Fails if the CLI is the wrong binary, a subcommand is missing, or the session is unset.

### 2. Enable the language first

Both gates must be open or writes succeed and never render.

1. Project languages: Publisher Account, Project Settings, General Settings.
2. Site language toggles, plus a visible selector in Header and/or Footer.

```
xsolla shopbuilder add-language --merchant-id <m> --project-id <p> --slug <domain> --language de-DE
```

`add-language` appends. It does not change the language the shop opens in.

### 3. Backup

```
python3 ../shop-builder-assembly/scripts/backup_shop.py \
  --merchant-id "$XSOLLA_MERCHANT_ID" --project-id "$XSOLLA_PROJECT_ID" \
  --environment test \
  --approved-test-projects "$XSOLLA_APPROVED_TEST_PROJECTS" \
  --slug <domain> --output-dir l10n/backup/<timestamp>
```

This is `shop-builder-assembly`'s `backup_shop.py`. Identity mode checks the approved-test-project allowlist before it reads the site. A project that is not on the list is not exported and must not be written. Do not keep a production-project denylist.

The export is read-only: structure, localization, landing, and a manifest. Re-run it every time. A Publisher Account edit since the last backup makes the diff a lie.

### 4. Extract

```
scripts/extract.sh <source-locale> <target-locale> [backup-dir]
scripts/extract.sh en-US ja-JP
```

No domain argument. The domain is in the backup. Omit the directory and the newest `l10n/backup/*/` is used.

Writes `l10n/work/<target>/translatable.json`.

Before any translation: does the publisher already have a complete set? If yes, ingest it and do not re-translate.

```
scripts/ingest-user-translations.sh ja-JP ./publisher-ja.json
```

Translatable, and only these:

- Blocks: any field with an `L:` id, including hero, CTAs, section titles, FAQ, and `common`.
- Page SEO: `page.seo.title` and `page.seo.description`. They have `L:` ids and live under `page.seo`, a sibling of `page.blocks`. `page.seo.ogImage` is a URL (`kind: asset`): extracted, never translated.

Never send to translation: SKUs, item and block ids, group keys, `type`, `layout`, prices, currency codes, image URLs, theme colors, `L:` ids, `I:` ids.

### 5. Translate

The model writes `l10n/work/<target>/translated.json`. No machine-translation service.

1. `glossary/do-not-translate.txt` is verbatim. `glossary/termbase.csv` is the one rendering per locale.
2. Keep HTML tags, order, and count.
3. Stay inside the character budget.
4. `kind: marketing` is transcreation. Hero, promo, CTA.
5. Do not skip a string because a target exists. Template landings ship stale translations. `extract.sh` reports `existing_target_present`, not "already translated".
6. Never translate a value starting with `http`. `kind: asset`.
7. Never translate legal or compliance text. `kind: legal`. Flag them.

### 6. Write

```
scripts/apply.sh <domain> <target-locale>
scripts/apply.sh <domain> <target-locale> --commit
scripts/apply.sh <domain> <target-locale> --commit --confirm-overwrites
```

Dry run is the default and sends nothing. Read it before `--commit`.

If any unit already has a different target-locale value, `--commit` alone blocks and prints each pair. `--commit --confirm-overwrites` proceeds only after a human has read that list.

`--commit` calls `backup_shop.py` again, into `l10n/pre-write/<timestamp>/`, before the first write. If the allowlist check fails, nothing is written.

**Blocks.** Text is not in the block. `get-structure` puts `L:<uuid>` at `values.<field>.id`. The string is in a localization store keyed by the slug. `update-block` on `["values","title"]` deletes that string and every translation of it, and the call still returns 200. It does not leave the block unchanged. Write through the localization store.

```
xsolla shopbuilder update-many-localization --slug <domain> \
  --data '{"locale":"de-DE","perScopeValues":{
             "<pageId>":{"L:<id>":{"translation":"<h1>Haltet die Stellung</h1>"}},
             "common":{"L:<id2>":{"translation":"<p>…</p>"}}}}'
```

Scope is the page `_id`, or `"common"`. The per-id value must be `{"translation": "text"}`. A bare string, or the keys `value` / `text` / `translations`, returns 200 and writes an empty string. One call per locale. Never wholesale-replace a block's `values` or `components`. Copying `L:` ids with no localization 500s the renderer.

### 7. Opening language

This skill does not change it. There is no default-locale field. The first entry of `languages` is what the shop opens in, and `add-language` only appends. Enabling `de-DE` on a site that opens in English leaves English first. The German copy is in the selector.

To open the shop in the new language, the partner reorders the site language list in Publisher Account so the new language is first. Do not call `delete-language`.

### 8. Verify

```
scripts/verify.sh <domain> <target-locale>
scripts/verify.sh <domain> <target-locale> --json
```

`verify.sh` asks the store. Exit non-zero if a written string is missing or the language is not enabled. It reports which language is first. It does not fail because the new language is not first.

`get-structure` returns ids, not text. `get-localization` is the read-back. `get-block --slug <domain> --block-id <id>` inlines localized strings.

## No sandbox

`--sandbox` does not change the URL. Shop Builder `get-structure --sandbox` warns `shopbuilder has no Xsolla sandbox` and still requests the live site. The scripts never pass `--sandbox`. The allowlist is the control: environment `test`, and the project must be on the approved-test-project list.

## One writer

Do not edit the landing in Publisher Account while this skill runs. Concurrent writers overwrite each other and drop blocks.

## Pitfalls

- Treating a shop that still opens in English as a failed translation. The copy can be correct and the first language unchanged. Say which language is first, and how to reorder it in Publisher Account.
- `update-block` on `["values","title"]`. Returns 200 and deletes the string and all of its translations. Use `update-many-localization`.
- Bare per-id string, or any key but `translation`. HTTP 200, empty string written.
- Writing before `add-language`. Succeeds, renders nothing.
- Domain passed to `extract.sh`. First argument is the source locale.
- Trusting `ok:true`. Run `verify.sh`.
- Slug as `--landing-id`. 500.
- Replacing `values` or `components`. Renderer 500.
- Confirming copy with `get-structure`. Ids, not text.
- Dropped HTML. Unstyled text.
- Assuming images localize. No per-locale image slot.

## Scripts

| Script | Does |
|---|---|
| `preflight.sh` | CLI, Shop Builder subcommands, auth, merchant and project |
| `backup_shop.py` | `shop-builder-assembly`. Allowlist, then a read-only export. Not copied into this skill |
| `extract.sh <src> <tgt> [backup]` | `translatable.json`. No domain argument |
| `apply.sh <domain> <tgt> [--commit] [--report] [--confirm-overwrites]` | Page copy only. Dry run default. `--commit` backs up, then writes. It does not change the opening language |
| `verify.sh <domain> <tgt> [--json]` | Live read-back |
| `ingest-user-translations.sh <locale> <file>` | Publisher JSON or TXT into `translated.json`. No store write |

Order: `preflight`, `backup_shop.py`, `extract`, translate, `apply --commit`, `verify.sh`.

## Also read

- [i18n-support.md](i18n-support.md) — locale codes.
- [translation-notes.md](translation-notes.md) — the same failures, as a field catalog.
