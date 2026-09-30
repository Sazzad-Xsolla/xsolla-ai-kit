---
name: localization
description: >-
  Translates an Xsolla catalog, LiveOps, and a Shop Builder storefront into another
  language. Use when someone says "localize the shop", "translate the catalog",
  "translate item names", "translate promotions / promo codes / reward chains",
  "add Japanese / German / Portuguese", "my store is only in English", "translate the
  FAQ", "add a language to Shop Builder", "bulk translate", or hands over a translation
  CSV. Catalog and LiveOps go through one reviewable CSV. Shop Builder page copy
  (hero, CTAs, SEO, FAQ) goes through the storefront scripts. Confirm before any write.
  Not for creating the shop (shop-setup) or setting prices (catalog-design).
metadata:
  owner: s.hossain
  domain: catalog
  status: draft
---

# Localize a shop

One skill, two halves. Catalog and LiveOps text, and Shop Builder page copy. Do not
run them as separate skills. A shop that only translates one of them looks finished
and is not.

The model does the translation. There is no machine-translation service. **Catalog
and LiveOps strings are sent to the agent's model** as the CSV batch. Say that
before the first `batch` when the catalog is a real project.

Nothing here publishes the site. Writes hit the live project named by
`XSOLLA_PROJECT_ID`. There is no catalog or Shop Builder sandbox.

Moving `catalog_i18n.py` into `xsolla-cli` as `xsolla catalog localize` is a
follow-up. The script stays in this skill.

## Which half

| Surface | What moves | How |
|---|---|---|
| Catalog and LiveOps | Item, group, bundle, currency, game key, attribute, promotion, and chain text | `scripts/catalog_i18n.py` |
| Shop Builder page copy | Hero, CTAs, FAQ, section titles, page SEO | `scripts/extract.sh` then `scripts/apply.sh` |
| Site chrome | Cart, checkout buttons, Xsolla UI | Enable the language. Do not translate it |

## Before any write

1. Name the target locale in the user's words (`Japanese` → `ja` on the catalog, `ja-JP` on Shop Builder). The code tables are in [references/supported-languages.md](references/supported-languages.md) and [references/i18n-support.md](references/i18n-support.md).
2. Ask whether they already have translations. If yes, `merge` (catalog) or `scripts/ingest-user-translations.sh` (storefront). If no, the model fills the gaps after they confirm the plan.
3. Show the plan: locale, what will change, what already has a translation. Wait for an explicit yes. Then write.

## Catalog and LiveOps

From the skill directory:

```
scripts/catalog_i18n.py discover
scripts/catalog_i18n.py export work.csv ja,de --source en
scripts/catalog_i18n.py batch work.csv --locale ja
# model fills the batch, then:
scripts/catalog_i18n.py fill work.csv --locale ja --from batch.json
scripts/catalog_i18n.py check work.csv
scripts/catalog_i18n.py import work.csv          # preview
scripts/catalog_i18n.py import work.csv --write  # only after approval
```

`de-DE` and `de` are the same column. A locale with no column is an error.
`import` previews unless `--write` is passed. `restore` refuses a snapshot from
another project. Snapshots and backups go in `l10n-snapshots/` and `l10n-backups/`
beside the CSV, not in the repository root.

Load these only when that step needs them:

- [references/translation-csv.md](references/translation-csv.md) — CSV contract and commands
- [references/write-safety.md](references/write-safety.md) — replace semantics, conflicts, rollback
- [references/glossary.md](references/glossary.md) — terminology
- [references/qa.md](references/qa.md) — what `check` decides and what the model must judge
- [references/coverage-matrix.md](references/coverage-matrix.md) — which entities localize

`reward_chain` is on API v2, with promotions on v3. Chains `daily_chain` and
`offer_chain` can be written only while disabled.

## Shop Builder page copy

After the storefront exists. Full procedure, silent failures, and the script list:
[references/storefront.md](references/storefront.md).

```
scripts/preflight.sh
scripts/snapshot.sh <domain>
scripts/extract.sh en-US ja-JP
scripts/apply.sh <domain> ja-JP                 # dry run
scripts/apply.sh <domain> ja-JP --commit --confirm-overwrites
scripts/set-opening-language.sh <domain> ja-JP
scripts/verify.sh <domain> ja-JP
```

Enable the locale with `xsolla shopbuilder add-language` before writing.
`--commit` blocks when it would replace an existing translation until
`--confirm-overwrites`. `scripts/restore.sh` replays a storefront snapshot.

## Out of scope

Prices and regional availability (`catalog-design`). Legal copy. Text baked into
images. Publishing the site.
