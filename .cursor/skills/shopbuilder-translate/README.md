# shopbuilder-translate

Translates Shop Builder page copy (hero, CTAs, FAQ, section titles, page SEO).
The model does the translation. The scripts move the data and check the write.

Catalog and LiveOps text belong to the `localization` skill.

## Prerequisites

- Xsolla CLI authenticated with `xsolla auth login`. Do not pass a session token by hand.
- `XSOLLA_MERCHANT_ID` and `XSOLLA_PROJECT_ID`.
- `XSOLLA_APPROVED_TEST_PROJECTS` pointing at the approved-test-project allowlist. Writes use environment `test`. There is no production denylist.
- `shop-builder-assembly` `scripts/backup_shop.py`, including the merchant, project, and environment mode.
- A store that already renders.

## Happy path

1. Say the target language. Confirm whether translations already exist.
2. `preflight.sh`, then `backup_shop.py` into `l10n/backup/<timestamp>`.
3. `extract.sh`, then `apply.sh` as a dry run.
4. After an explicit yes, `apply.sh --commit`. That runs the allowlist backup again before the first write.
5. `verify.sh` reads the live store back. It checks that the language is enabled and that the strings came back. It does not fail because the shop still opens in another language.

Nothing is published. There is no sandbox. `--commit` does not change the language the shop opens in. The partner sets that in Publisher Account by reordering the site language list.

## Known limitations

- Prices, legal copy, and text baked into images are out of scope.
- `backup_shop.py` is a read-only export. This skill does not replay it.
- Catalog text is not extracted or written here.

## Layout

```
SKILL.md                 the commands
README.md                this file
references/              storefront procedure and field notes
scripts/                 extract, apply, verify
glossary/                terms to keep and terms to render one way
```
