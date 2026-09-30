# Bilingual reviewer spot-check — 20-string sample

Per the SB-8790 DoD ask for "a bilingual reviewer spot-check on a 20-string sample." **This
file is the sample sheet for that reviewer, not the review itself** — grading your own
translation output isn't an independent check, so the "Reviewer" columns below are
intentionally blank for a human fluent in the target language to fill in. An AI self-check
pass is included underneath as a preliminary signal only; it does not satisfy this DoD item.

Sampled across all 3 completed target languages (de-DE, ja-JP, es-ES) and stratified across
`kind` (`product` = catalog name, `product-body` = catalog description, `marketing`, `ui`) so
the sample isn't all easy short strings. Pulled from the actual `l10n/work/<locale>/
translated.json` that was sent live, not re-typed by hand.

| # | Locale | Kind | Source (EN) | Target | Reviewer: accurate? | Reviewer: register/tone OK? | Notes |
|---|---|---|---|---|---|---|---|
| 1 | de-DE | product | Victory Emote | Sieges-Emote |  |  |  |
| 2 | de-DE | product | Season 1 Pass | Season-1-Pass |  |  |  |
| 3 | de-DE | product-body | Close out the match with a flourish only the winner gets to use. | Beende das Match mit einer Geste, die nur der Sieger verwenden darf. |  |  |  |
| 4 | de-DE | marketing | Available on | Verfügbar auf |  |  |  |
| 5 | de-DE | marketing | Official store | Offizieller Store |  |  |  |
| 6 | de-DE | ui | Log in | Anmelden |  |  |  |
| 7 | de-DE | ui | Log out | Abmelden |  |  |  |
| 8 | ja-JP | product | Victory Emote | ビクトリーエモート |  |  |  |
| 9 | ja-JP | product | Season 1 Pass | シーズン1パス |  |  |  |
| 10 | ja-JP | product-body | Close out the match with a flourish only the winner gets to use. | 勝者だけが使える華やかな決めポーズで、試合を締めくくろう。 |  |  |  |
| 11 | ja-JP | marketing | Available on | 対応プラットフォーム |  |  |  |
| 12 | ja-JP | marketing | Official store | 公式ストア |  |  |  |
| 13 | ja-JP | ui | Log in | ログイン |  |  |  |
| 14 | ja-JP | ui | Log out | ログアウト |  |  |  |
| 15 | es-ES | product | Victory Emote | Emote de Victoria |  |  |  |
| 16 | es-ES | product-body | Close out the match with a flourish only the winner gets to use. | Cierra la partida con un gesto triunfal que solo el ganador puede usar. |  |  |  |
| 17 | es-ES | marketing | Available on | Disponible en |  |  |  |
| 18 | es-ES | marketing | Official store | Tienda oficial |  |  |  |
| 19 | es-ES | ui | Battle pass | Pase de batalla |  |  |  |
| 20 | es-ES | ui | Log in | Entrar |  |  |  |

## Rubric for the reviewer

- **Accurate?** Does the target mean what the English source means — no added/dropped
  meaning, no false-friend mistranslation?
- **Register/tone OK?** Does it read like a game storefront wrote it (not a machine-literal
  gloss), and is it consistent with the termbase
  (`skills/localization/glossary/termbase.csv`) where a term recurs?
- Flag anything below "good enough to ship," not just outright errors — tone/naturalness
  matters as much as literal correctness for a storefront.

## AI self-check (preliminary only, not the DoD item)

- Row 2 / de-DE: "Season-1-Pass" keeps the hyphenated German compound-noun convention rather
  than the English-order "Season 1 Pass" — matches how the termbase treats similar compounds
  (`Starter Pack` → `Starterpaket`), but a native reviewer should confirm the hyphen placement
  reads naturally rather than looking machine-generated.
- Row 11/12: "Available on" / "Official store" in ja-JP (対応プラットフォーム / 公式ストア)
  render more formally than a literal gloss would; worth reviewer confirmation that this
  matches the rest of the storefront's voice rather than skewing more formal than intended.
- No row here is one flagged as a byte-for-byte machine-literal error by the pipeline's own
  tag-parity/budget checks — those only catch structural issues (missing HTML tags, length),
  not meaning or tone, which is exactly the gap this human pass is meant to cover.
