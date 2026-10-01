# localization

Translates an Xsolla catalog, LiveOps text, and Shop Builder page copy into another language.
The model does the translation. The scripts move the data and check the write.

## Prerequisites

- Xsolla CLI authenticated with `xsolla auth login`. Do not pass a session token by hand.
- `XSOLLA_MERCHANT_ID`, `XSOLLA_PROJECT_ID`, and `XSOLLA_API_KEY` for catalog reads and writes.
- `XSOLLA_PRODUCTION_PROJECT_IDS` set to every project that must not be written.
- A store that already renders, and a catalog that is already populated.

## Happy path

1. Say the target language. Confirm whether translations already exist.
2. Catalog and LiveOps: `discover`, `export`, fill, `check`, then `import` as a preview.
3. Shop Builder: `preflight.sh`, `snapshot.sh`, `extract.sh`, then `apply.sh` as a dry run.
4. After an explicit yes, `import --write` and `apply.sh --commit`.
5. `--commit` moves that language first, which is what the shop opens in.
6. `verify.sh` reads the live store back. It fails if the shop would still open in another language.

Nothing is published. There is no sandbox.

## Known limitations

- Prices, legal copy, and text baked into images are out of scope.
- Catalog text is sent to the agent's model. There is no machine-translation service.
- Moving `catalog_i18n.py` into `xsolla catalog localize` is a follow-up.
- Item groups and `long_description` are written by Admin PUT, not a CLI flag.

## Layout

```
SKILL.md                 which half to run, and the commands
README.md                this file
references/              CSV contract, write safety, storefront procedure
scripts/                 catalog_i18n.py and the storefront scripts
scripts/tests/           catalog unit tests
glossary/                terms to keep and terms to render one way
```
