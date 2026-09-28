# Eval log — shop-plan

Every run behind the SB-8794 metrics. The decision step is scored on what the agent *did* — which
skill it loaded, what changed on disk, which commands it ran — not on reading its answers.

**50 runs, 50 passed, 0 manual interventions.** Run 2026-09-28 against this branch at `7d66a8c`,
baseline `integration/sb-ai` at `d684e7f`, `claude-opus-5-5`, CLI 2.1.281–2.1.283, two rounds per
intent. Each run gets a throwaway `$TMPDIR` project, the kit's skills installed, and a stub `xsolla`
on `PATH` that refuses and logs any call, so no run can reach a live project.

## Metrics

| Metric | Target | Result |
|---|---|---|
| **Recommendation accuracy** — recorded path matches the known answer | ≥ 9/10 | **20/20** over 10 intents × 2 rounds. Asserted from `.env`, never from prose |
| **Unintended writes before confirmation** | 0 | **0** across 28 gated runs. Checked three ways: a file-hash snapshot of the project, a scan of every tool call, and the stub `xsolla` |
| **Added context size** | report | **+311 tokens** per request (median 19,718 vs 19,407; 5 interleaved probes per side, spread ≤ 4) |
| **Headless skill success — no measurable drop** | no drop | **12/12 on this branch, 10/10 on the base.** Five headless-side intents × 2 rounds, run against both |

## The intents

19 fixed intents, written before the runs and never edited to fit a result.

| Category | Intents | What must happen |
|---|---|---|
| `path` | 10 — five clearly headless, five clearly Shop Builder, each stating all five criteria | `shop-plan` selected, nothing written before the developer confirms, then the confirmed path recorded exactly once and the agent stops rather than building |
| `state` | 4 — build already in flight, path already decided, hand-edited invalid value, conflicting answers | The recorded decision is never discarded or silently rewritten |
| `regression` | 5 — webhook signature, Google Pay, currency packages, login theming, API keys | The headless-side skill still wins the prompt; `shop-plan` never intercepts |

## Runs

**`path` — 20 runs, 20 passed.** Right path every time, recorded exactly once, and no run started a
build after recording it.

**`state` — 8 runs, 8 passed.** Includes the case that matters most: a project holding credentials
but no recorded path. That used to get a one-line "you're on the headless path" confirmation, which
stopped being true once both paths could be built. Credentials now say nothing about the path, so
the five criteria are asked either way.

**`regression` — 22 runs, 22 passed** (12 on the branch, 10 on the base). Each headless-side prompt
reached its own skill; `shop-plan` never intercepted one.

**Live end-to-end, 2026-09-24.** Empty directory with the kit, a 254-line game brief and 38 images,
no credentials. The decision ran first (comparison, five criteria, Shop Builder recommended,
recorded once, stop), then `merchant-setup` asked for the merchant ID, project ID and key, then the
build produced a real catalog — 6 groups, 2 currencies, 5 packages, 21 items, 4 bundles, a
subscription plan — and an unpublished storefront in five locales, read back through the public API
in French and Japanese with local prices. Nothing was published. Recorded as a Loom.

## Failures, and what needed a human

- **0 manual interventions.** No run needed a human to unstick it.
- **18 runs were lost to an account rate limit** mid-suite and are kept in the results as
  `error_kind: infrastructure`. They count as neither a pass nor a skill failure; the affected
  regression intents were re-run in full afterwards.
- **50 approval prompts**, nearly all for `shop-plan`'s own two shell snippets — the step-1
  three-state check and the step-5 recording. Both are compound commands, which Claude Code splits
  and asks about even under `--permission-mode bypassPermissions`. Every run recovered, so no metric
  moved, but a developer sees a prompt at those two moments. Open.
- **Two scorer bugs, fixed in the scorer rather than by re-running:** a rate limit scored as a skill
  failure, and a `--max-turns` cap scored as a crash. Affected runs were re-scored from their saved
  transcripts; results files are append-only.
- **The live run caught what the eval could not.** Its build-in-flight case asserted the old rule, so
  it passed while that rule's premise had expired. Only a real brief exposed it.

## Reproducing

The runner, the 19 intents and the scorer's unit tests are kept outside this repo — it is public and
ships to partners, and the runner drives `claude -p`. Ask the skill owner for
`tests/evals/shop-plan/` to re-run the suite.
