# Eval log — shop-plan

Every run behind the SB-8794 metrics. The decision step is scored on what the agent *did* — which
skill it loaded, what changed on disk, which commands it ran — not on reading its answers.

**50 agent runs, 50 passed, 0 manual interventions.** `claude-opus-5-5`, CLI 2.1.281, two rounds per
intent. Each run: a throwaway `$TMPDIR` project, all kit skills installed, and a stub `xsolla` on
`PATH` that refuses and logs any call, so no run could reach a live project. Baseline for the
comparison rows: `origin/main` @ `4126ae0`.

## Metrics

| Metric | Target | Result |
|---|---|---|
| **Recommendation accuracy** — recorded path matches the known answer | ≥ 9/10 | **20/20** over 10 intents × 2 rounds. Asserted from `.env`, never from prose |
| **Unintended writes before confirmation** | 0 | **0** across 28 gated runs. Checked three ways: file-hash snapshot of the project, a scan of every tool call, and the stub `xsolla` |
| **Added context size** | report | **+1,645 tokens** per request (median 21,042 vs 19,397, 5 interleaved probes per side) |
| **Headless skill success — no measurable drop** | no drop | **10/10 on this branch, 10/10 on `main`.** Five headless-side intents × 2 rounds, run against both |

## The intents

19 fixed intents, written before the runs and never edited to fit a result.

| Category | Intents | What must happen |
|---|---|---|
| `path` | 10 — five clearly headless, five clearly Shop Builder, each stating all five criteria | `shop-plan` selected, nothing written before the developer confirms, then the confirmed path recorded exactly once and the agent stops rather than building |
| `state` | 4 — build already in flight, path already decided, hand-edited invalid value, conflicting answers | The recorded decision is never discarded or silently rewritten |
| `regression` | 5 — webhook signature, Google Pay, currency packages, login theming, API keys | The headless-side skill still wins the prompt; `shop-plan` never intercepts |

## Runs

**2026-09-23 — 48 runs, all passed.** 20 `path` (20/20 correct, 0 premature writes), 8 `state`
(8/8), 20 `regression` (10 on the branch, 10 on `main`, 10/10 both). Three runs ended at the case's
turn cap with the correct skill already selected; a turn cap is scored on what the agent did, not
treated as a crash.

**2026-09-24 — 2 runs, both passed.** `state-build-in-flight` re-run after a spec fix: a project
holding credentials but no recorded path used to get a one-line "you're on the headless path"
confirmation. That premise died once both paths became buildable, so credentials no longer imply a
path and the five criteria are asked either way. The case now encodes the new rule.

**Live end-to-end, 2026-09-24.** Empty directory with the kit, a 254-line game brief and 38 images,
no credentials. The decision ran first (comparison, five criteria, Shop Builder recommended,
recorded once, stop), then `merchant-setup` asked for the merchant ID, project ID and key, then the
build produced a real catalog — 6 groups, 2 currencies, 5 packages, 21 items, 4 bundles, a
subscription plan — and an unpublished storefront in five locales, read back through the public API
in French and Japanese with local prices. Nothing was published. Recorded as a Loom.

## Failures and things a human had to decide

- **0 manual interventions** across the 50 runs: no run needed a human to unstick it.
- **57 approval prompts** (53 on 09-23, 4 on 09-24), 46 of them for `shop-plan`'s own two shell
  snippets — the step-1 three-state check and the step-5 recording. Both are compound commands, which
  Claude Code splits and asks about, even under `--permission-mode bypassPermissions`. Every run
  recovered, so no metric moved, but a developer sees a prompt at those two moments. Open.
- **Two runner bugs, fixed in the scorer rather than by re-running:** a rate limit scored as a skill
  failure, and a turn cap scored as a crash. Affected runs were re-scored from their saved
  transcripts; results files are append-only.
- **The live run surfaced what the eval could not.** Its `state-build-in-flight` case asserted the
  old rule, so it passed while the rule's premise had expired. Only a real brief exposed it.

## Reproducing

The runner, the 19 intents and the scorer's unit tests are kept outside this repo — it is public and
ships to partners, and the runner drives `claude -p`. Ask the skill owner for
`tests/evals/shop-plan/` if you want to re-run the suite.
