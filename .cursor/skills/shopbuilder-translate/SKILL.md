---
name: shopbuilder-translate
description: >-
  Translates Shop Builder page copy: hero, CTAs, FAQ, section titles, and page SEO.
  Use when someone says "translate the FAQ", "add a language to Shop Builder",
  "my store is only in English", "translate the hero", or hands over page-copy
  translations. Catalog and LiveOps text belong to the localization skill. Confirm
  before any write. Not for creating the shop (shop-setup) or setting prices
  (catalog-design).
metadata:
  owner: s.hossain
  domain: store
  status: draft
---

# Translate Shop Builder page copy

This skill writes Shop Builder page copy only. Catalog and LiveOps text (items, groups, bundles, currency, promotions, reward chains) belong to the `localization` skill. Do not copy that workflow into this one.

The model does the translation. There is no machine-translation service.

Nothing here publishes the site. `--commit` writes the live project named by `XSOLLA_PROJECT_ID`. There is no Shop Builder sandbox. `--commit` does not change the language the shop opens in.

## Before any write

1. Name the target locale in the user's words (`Japanese` → `ja-JP`). Codes are in [references/i18n-support.md](references/i18n-support.md).
2. Ask whether they already have translations. If yes, `scripts/ingest-user-translations.sh`. If no, the model fills the gaps after they confirm the plan.
3. Show the plan: locale, what will change, what already has a translation. Wait for an explicit yes. Then write.
4. For catalog or LiveOps strings, stop and use the `localization` skill.

## Page copy

After the storefront exists. Silent failures and the script list: [references/storefront.md](references/storefront.md). Field failures: [references/translation-notes.md](references/translation-notes.md).

```
scripts/preflight.sh
python3 ../shop-builder-assembly/scripts/backup_shop.py \
  --merchant-id "$XSOLLA_MERCHANT_ID" --project-id "$XSOLLA_PROJECT_ID" \
  --environment test \
  --approved-test-projects "$XSOLLA_APPROVED_TEST_PROJECTS" \
  --slug <domain> --output-dir l10n/backup/<timestamp>
scripts/extract.sh en-US ja-JP
scripts/apply.sh <domain> ja-JP                 # dry run
scripts/apply.sh <domain> ja-JP --commit --confirm-overwrites
scripts/verify.sh <domain> ja-JP
```

`backup_shop.py` is Krish's script in `shop-builder-assembly`. Call it. Do not copy it. Identity mode (merchant, project, environment) is the mode Sajid added. `--environment test` runs the approved-test-project allowlist before any export. A project that is not on the list gets no backup and no write.

Enable the locale with `xsolla shopbuilder add-language` before writing. `--commit` blocks when it would replace an existing translation until `--confirm-overwrites`. `--commit` runs `backup_shop.py` again, into `l10n/pre-write/`, immediately before the first write.

The shop opens in the first language of the site language list. This skill does not reorder that list and does not call `delete-language`. If the partner wants the shop to open in the new language, they reorder the list in Publisher Account.

## Out of scope

Catalog and LiveOps (`localization`). Prices and regional availability (`catalog-design`). Legal copy. Text baked into images. Publishing the site. Changing the language the shop opens in.
