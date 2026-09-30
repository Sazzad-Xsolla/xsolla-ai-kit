# Eval log — `localization` (SB-8790)

Structured record of every live run of the Shop Builder half of the `localization`
skill (runs 1–6 predate the merge with the catalog CSV workflow and were made under
the skill's earlier name, `shopbuilder-translate`). Per the SB-8790 DoD ask for "a
structured eval log across runs (result / manual interventions / failures)". All runs
are against merchant 935479 / project 314515. A second project has not been exercised:
the only API key available is scoped to 314515, and the merchant-level project
endpoints return 401 for it.

**Status: 7 of the DoD's ≥10 runs.** Padding this table with repeat or synthetic runs to
hit the number would defeat its purpose. New rows should only be added for genuinely new
live runs.

## Coverage / integrity / manual-intervention / quality metrics

| # | Date | Landing | Locale | Storefront (written/extractable) | Catalog fields | Verify result | Manual interventions | Failures found this run |
|---|---|---|---|---|---|---|---|---|
| 1 | 2026-09-01 | test-sandbox-355b | ja-JP | 51/53 (2 legal, deliberately skipped) | 10/10 | 51/51 admin read-back match, 0 empty writes | None | None |
| 2 | 2026-09-01 | test-sandbox-355b | es-ES | 51/53 (2 legal) | 10/10 (en+es+ja) | Not captured (pre-`verify.sh`) | Re-sent catalog as a full-entity write after realizing the locale map is *replaced* not merged, to avoid dropping the ja-JP written in run 1 | Discovered: whole-entity/whole-locale-map replacement semantics (catalog + blocks) |
| 3 | 2026-09-02 | test-sandbox-355b | ja-JP (refresh) | 53/53 refreshed | 10/10 (en/es/ja) | Not captured (pre-`verify.sh`) | Fixed a stale template hero title that no longer matched the (edited) English source | Discovered: template-derived pre-translated content can silently drift from current English |
| 4 | 2026-09-02 | test-sandbox-765d (new landing) | ja-JP | 59/61 (38 page + 21 common; 2 legal) | 10/10 | Byte-for-byte read-back match | Fixed 4 stale/wrong template ja values ("Featured"→仮想アイテム, one section untranslated, placeholder user-ID string, "Claim"→請求/billing) | Confirmed: template pre-population makes coverage numbers alone meaningless — each value needs checking against current English, not just presence |
| 5 | 2026-09-08 | test-sandbox-765d | de-DE | 61/63 (40 page + 21 common; 2 legal) | 10/10 (10 genuinely new fields — no prior de) | `verify.sh`: 0 missing, 0 differing, 1 expected WARN (de-DE enabled but not first — intentional, see below) | `--confirm-overwrites` reviewed and accepted for 36 pre-existing template de-DE values that were stale/wrong (e.g. "Featured"→"Virtuelle Gegenstände" on one section, untranslated on another; "Shop"/"Store" inconsistent); tightened 11 strings that exceeded button/tab character budgets, accepted 2 residual 1-char overflows as unavoidable; used `add-language` directly instead of `set-opening-language.sh` to enable de-DE without moving the shop's opening language off ja-JP | Fixed two real, previously-undetected extractor bugs: page-level SEO (`page.seo.title`/`.description`) was never walked; catalog item-groups shape-unwrap only checked for an `items` key, not the real API's `groups` key |
| 6 | 2026-09-08 | test-sandbox-765d | pt-BR | 61/63 (40 page + 21 common; 2 legal) | 10/10 (10 genuinely new fields — no prior pt) | `verify.sh`: 0 missing, 0 differing, 1 expected WARN (pt-BR enabled but not first — intentional) | `--confirm-overwrites` reviewed and accepted for 15 pre-existing template pt-BR values that were stale/wrong; tightened 1 string missing its `<p>` tag on the fix; accepted 7 residual 1-char overflows plus one unavoidable ("Add"→"Adicionar"); used `add-language` directly, same as de-DE, to keep ja-JP as the opening language | Found two translation-quality bugs in the pre-existing template baseline (not extractor bugs — the extractor worked correctly): a semantic negation flip ("does the store support" mistranslated as "does NOT support" — reverses the actual meaning), and a truncated string missing its closing quote mark, dropping content mid-sentence. Also found the recurring "Featured" mistranslation/left-untranslated pattern seen in every prior locale, and one item→game noun-substitution error ("itens" mistranslated as "jogos") |
| 7 | 2026-09-18 | test-sandbox-765d | fr-FR | 61/63 (40 page + 21 common; 2 legal) — landed on the **second** attempt, after replaying the saved `payloads/localization.cmd.json` (`modified: true`) | items+bundles `fr` 14/14 via CLI `update-*` rc=0; **groups** 3/3 via `catalog_i18n.py import --write` PUT 204, confirmed live by `catalog_i18n.py export --entity groups` (3 rows, 0 empty cells) | `verify.sh`: **0 missing, 0 differing**, 4 WARN (3 = item groups unreadable via CLI `list-item-groups`, closed out by the Admin export above; 1 = fr-FR enabled but not first, intentional) | `--confirm-overwrites` reviewed (template fr-FR vs new copy); corrected a stale `meta.baseline` path in `translated.json` after a false "stale translations" block; mapped `XSOLLA_PROJECT_API_KEY`→catalog auth; re-login + rate-limit wait; replayed the storefront call; did **not** run `set-opening-language` (keep ja-JP first) | Found **three** infrastructure failures, none in the translation logic: (a) `xsolla catalog` admin reads 401 with `XSOLLA_API_KEY` while `catalog_i18n.py` using `XSOLLA_PROJECT_API_KEY` from `.env` succeeds — two different auth schemes for one product; (b) the Shop Builder OAuth→`pa-v4-token` bootstrap expires mid-run and `apply.sh` has no resume, so a late failure would normally force a full re-run; (c) the bootstrap endpoint returns **HTTP 429** under the pipeline's own call volume and its error text misreports this as a missing cookie. **wall_clock ~18.5 min total** (11:19:15Z extract start → 11:37:49Z storefront write), of which ~6 min was auth recovery; **~12.5 min** of actual pipeline time |

## Reading this table

- **"Storefront (written/extractable)"** excludes `kind: legal` units by design — those are
  never auto-translated (see SKILL.md). It is not a raw coverage percentage against every
  string on the page.
- **Runs 2–3 predate `verify.sh`** doing a live read-back; those runs were checked by spot
  reading the API response at the time, not re-verified independently after the fact.
- **"Manual interventions"** means a human (or the agent, under human review) had to look at
  something and make a judgment call beyond running the pipeline — confirming an overwrite,
  shortening a translation, or fixing a stale value. Zero interventions (run 1) means the
  pipeline's automatic checks were sufficient.
- Bugs discovered during a run were fixed in the skill before being counted as closed — see
  `skills/localization/references/translation-notes.md` and the git history of
  `skills/localization/scripts/extract.sh` for the fixes themselves.

## Cross-run rollup (SB-8790 metrics)

DoD targets: coverage ≥95% of translatable strings/catalog items; 0 broken placeholders/markup;
≤1 manual intervention per run (the confirmation step); ≥90% acceptable on a 20-string
bilingual spot-check; wall-clock per shop as a baseline.

| Metric | DoD | 7-run result | Notes |
|---|---|---|---|
| Catalog fields written / extractable | ≥95% | **100%** — 10/10 on runs 1–6, **17/17 on run 7** | Same catalog (project 314515) every time. Run 7 is larger because `catalog_i18n.py` reaches bundles and item groups the CLI path could not: 14 item+bundle fields + 3 group names |
| Storefront written / extractable non-legal | ≥95% | **100%** on runs 1–7 | Legal units excluded by design (2 per landing). Raw “has a target locale” is not quality — see template drift. Run 7 needed a retry to get there |
| Broken placeholders / HTML tag mismatch | 0 | **0 shipped** | `apply.sh` blocks tag-parity failures before write. Residual issue is length overflow (1-char), not markup |
| Manual interventions / run | ≤1 (confirmation) | **1 of 7 runs meet the letter of the DoD** | Rubric below. Run 7's extra steps were auth/infrastructure, not translation judgment |
| Bilingual 20-string ≥90% acceptable | ≥90% | **Not measured** | Sheet: `evals/localization/bilingual-review-sample.md`. Reviewer columns blank; AI self-check is not this item |
| Wall-clock per shop | report baseline | **~12.5 min pipeline / ~18.5 min incl. auth recovery** (run 7, 5 SKUs + 2 bundles + 3 groups + 63 storefront strings) | First captured baseline. Only run 7 was timed; treat as n=1. Split is extract 11:19→11:29, translate→11:30, apply+verify→11:32, storefront retry→11:37 |
| Distinct projects | ≥2 shops | **1** (314515; two landings) | Shop 2 `315201` / `test2-33a3` still not in this log — the one DoD item with no progress |
| Distinct target languages | JA + ≥2 more | **ja-JP, es-ES, de-DE, pt-BR, fr-FR** (5) | Language count is met; shop count is not |

### Manual-intervention rubric (so “≤1” is countable)

Count **1** if the only extra human step was the required overwrite confirmation
(`--confirm-overwrites`). Count **each additional** judgment: stale-template rewrite,
length trim, re-send after a semantics bug, choosing `add-language` vs opening language.

| # | Confirmation only? | Extra judgments | Meets ≤1? |
|---|---|---|---|
| 1 ja-JP | n/a (none) | 0 | **Yes** (0) |
| 2 es-ES | n/a | 1 (full-entity catalog re-send) | No |
| 3 ja-JP refresh | n/a | 1 (stale hero vs current English) | No |
| 4 ja-JP 765d | n/a | 4 stale/wrong template ja strings | No |
| 5 de-DE | Yes (36 pairs) | +11 length trims, +2 overflow accepts, +opening-language exception | No |
| 6 pt-BR | Yes (15 pairs) | +1 missing `<p>`, +7 overflow accepts, +opening-language exception | No |
| 7 fr-FR | Yes | +stale `meta.baseline` fix, +catalog auth var swap, +re-login/429 wait, +storefront replay | No — but all 4 are **infrastructure**, not copy judgment |

Once the confirmation gate exists, a “happy” DoD run is: confirm the overwrite list, no
copy edits. Runs 5–6 show template landings almost never look like that.

### Integrity detail

- **Source locale:** English left intact on every run that was read back (1, 4, 5, 6).
  Runs 2–3 were not independently re-verified after `verify.sh` existed.
- **Locale-map replace:** run 2 found it; later runs reconstruct the full map (and now
  emit `catalog.put.*.json` pass-through bodies for groups / `long_description`).
- **Verify.sh:** runs 5–7: 0 missing, 0 differing vs sent copy. Expected WARN when the
  new locale is enabled but not first.
- **Item groups are a verify blind spot:** `verify.sh` can only WARN on them, because CLI
  `list-item-groups` returns a bare string, not a locale map. Run 7 closed the gap out of
  band with `catalog_i18n.py export --entity groups`. Folding that read into `verify.sh`
  would turn 3 standing WARNs into a real assertion.

### How to log run 7+

Add a row to the table above **and** fill:

```
wall_clock_s: <preflight through verify, excluding human think time if you can split it>
coverage_storefront: written/extractable_non_legal
coverage_catalog: fields_written/fields_extractable
tag_parity_failures: 0
interventions: confirm=Y/N extra=<n>
project_id: 
```

Do not add a row for a dry-run.
