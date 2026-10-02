#!/usr/bin/env bash
# smoke-test.sh — exercise the Shop Builder page-copy pipeline against fixtures.
# No CLI, no network, no store. Catalog and LiveOps are not this skill.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/l10n/backup/fixture" "$TMP/l10n/work/de-DE"
cp "$HERE/fixtures/baseline/"*.json "$TMP/l10n/backup/fixture/"
cd "$TMP"

pass=0; failn=0
chk(){ if eval "$2" >/dev/null 2>&1; then echo "  ok   $1"; pass=$((pass+1));
       else echo "  FAIL $1"; failn=$((failn+1)); fi; }

echo "== extract =="
bash "$HERE/extract.sh" en-US de-DE l10n/backup/fixture >/dev/null
T=l10n/work/de-DE/translatable.json
chk "11 block units, no catalog"      "[ \$(jq '.units|length' $T) -eq 11 ] && [ \$(jq '[.units[]|select(.surface==\"catalog\")]|length' $T) -eq 0 ]"
chk "L: ids resolved to page scope"   "[ \$(jq '[.units[]|select(.scope==\"page1\")]|length' $T) -eq 10 ]"
chk "asset URLs flagged, not copy"    "jq -e '[.units[]|select(.kind==\"asset\")]|length==2' $T"
chk "every asset unit is a URL"       "jq -e '[.units[]|select(.kind==\"asset\")]|all(.source|startswith(\"http\"))' $T"
chk "page SEO title extracted"        "jq -e '.units[]|select(.id==\"seo:page1:title\")|.source==\"Voidwall Store\"' $T"
chk "page SEO title is marketing"     "jq -e '.units[]|select(.id==\"seo:page1:title\")|.kind==\"marketing\"' $T"
chk "page SEO description extracted"  "jq -e '.units[]|select(.id==\"seo:page1:description\")|.kind==\"ui\"' $T"
chk "page SEO og:image is an asset"   "jq -e '.units[]|select(.id==\"seo:page1:ogImage\")|.kind==\"asset\"' $T"
chk "SEO units carry the page's L: ids" "jq -e '[.units[]|select(.id|startswith(\"seo:page1:\"))|.lid]|sort==[\"L:seoDesc\",\"L:seoImg\",\"L:seoTitle\"]' $T"
chk "common-scope string not dropped" "jq -e '[.units[]|select(.scope==\"common\")]|length==1' $T"
chk "1 legal unit flagged"            "[ \$(jq '[.units[]|select(.kind==\"legal\")]|length' $T) -eq 1 ]"
chk "landing_id captured from _id"    "jq -e '.meta.landing_id==\"landing_mongo_id\"' $T"
for b in cosmetics virtual_good rgba 'cdn\\.x' skin_ember 'L:'; do
  chk "no structural leakage: $b"     "[ \$(jq --arg b '$b' '[.units[]|select(.source|test(\$b))]|length' $T) -eq 0 ]"
done

echo "== ingest: publisher JSON/TXT fills translated.json =="
python3 -c 'import json; json.dump({"block:blk_hero:values.title":"<h1>Aus Datei</h1>"}, open("pub.json","w"))'
bash "$HERE/ingest-user-translations.sh" de-DE pub.json >/dev/null
chk "ingest filled the named unit" "jq -e '.units[]|select(.id==\"block:blk_hero:values.title\")|.target==\"<h1>Aus Datei</h1>\"' l10n/work/de-DE/translated.json"
printf '%s\n' 'block:common:L:c1	<p>Aus TXT</p>' > pub.txt
bash "$HERE/ingest-user-translations.sh" de-DE pub.txt >/dev/null
chk "ingest accepts TXT id-tab-target" "jq -e '.units[]|select(.id==\"block:common:L:c1\")|.target==\"<p>Aus TXT</p>\"' l10n/work/de-DE/translated.json"

echo "== apply: tag parity blocks a bad translation =="
jq '(.units[]|select(.id=="block:blk_hero:values.title")|.target)="Haltet die Stellung"' \
  "$HERE/fixtures/translated.de-DE.json" > l10n/work/de-DE/translated.json
set +e
XSOLLA_MERCHANT_ID=1 XSOLLA_PROJECT_ID=2 bash "$HERE/apply.sh" d de-DE >/dev/null 2>&1; rc=$?
set -e
chk "tag-parity gate exits non-zero"  "[ $rc -ne 0 ]"

echo "== apply: clean dry run =="
cp "$HERE/fixtures/translated.de-DE.json" l10n/work/de-DE/translated.json
XSOLLA_MERCHANT_ID=1 XSOLLA_PROJECT_ID=2 bash "$HERE/apply.sh" voidwall-45e0 de-DE \
  > l10n/work/de-DE/apply.out 2>&1
PD=l10n/work/de-DE/payloads
L=$PD/localization.request.json
chk "block text -> update-many-localization" "grep -q update-many-localization $PD/localization.cmd.json"
chk "block text NOT via update-block"        "! grep -rq update-block $PD/"
chk "locale is the target"                   "jq -e '.locale==\"de-DE\"' $L"
chk "perScopeValues keyed by page and common" "jq -e '.perScopeValues|has(\"page1\") and has(\"common\")' $L"
chk "per-id envelope is {translation:...}"   "jq -e '.perScopeValues.page1[\"L:t1\"]|has(\"translation\")' $L"
chk "legal string not written"               "jq -e '.perScopeValues.page1|has(\"L:t6\")|not' $L"
chk "dry run does not change the opening language" "grep -q 'does not change the language' l10n/work/de-DE/apply.out"
chk "no call carries --sandbox at all"       "! grep -rq -- '--sandbox' $PD/"
chk "asset URL never written"                "! grep -rq 'og-image' $PD/"
chk "no catalog payload"                     "! ls $PD/catalog.* >/dev/null 2>&1"

echo "== apply: existing translations are not overwritten without confirmation =="
export XSOLLA_CLI="$HERE/fixtures/fake-xsolla.sh"
export FAKE_STORE="$HERE/fixtures/store-good"
export L10N_BACKUP_SHOP="$HERE/fixtures/fake-backup.py"
export XSOLLA_APPROVED_TEST_PROJECTS="$HERE/fixtures/approved-test-projects.json"
jq '(.units[]|select(.id=="block:blk_hero:values.title")|.existing_target)="<h1>Alter Titel</h1>"' \
  "$HERE/fixtures/translated.de-DE.json" > l10n/work/de-DE/translated.json
set +e
XSOLLA_MERCHANT_ID=1 XSOLLA_PROJECT_ID=2 bash "$HERE/apply.sh" voidwall-45e0 de-DE --commit \
  > overwrite.out 2>&1; orc=$?
set -e
chk "commit without --confirm-overwrites is BLOCKED" "[ $orc -ne 0 ]"
chk "blocked run lists the existing vs. new value" \
  "grep -q 'existing.*Alter Titel' overwrite.out && grep -q 'new.*Haltet die Stellung' overwrite.out"
chk "blocked run wrote nothing"                    "[ ! -f l10n/work/de-DE/payloads/localization.response.json ]"
XSOLLA_MERCHANT_ID=1 XSOLLA_PROJECT_ID=2 bash "$HERE/apply.sh" voidwall-45e0 de-DE \
  --commit --confirm-overwrites > overwrite-confirmed.out 2>&1
chk "--confirm-overwrites lets the same run through" "grep -q 'Copy was written' overwrite-confirmed.out"
chk "commit does not move the opening language" "! grep -q 'set-opening-language\\|delete-language' overwrite-confirmed.out"
jq '(.units[]|select(.id=="block:blk_hero:values.title")|.existing_target)="<h1>Haltet die Stellung</h1>"' \
  "$HERE/fixtures/translated.de-DE.json" > l10n/work/de-DE/translated.json
XSOLLA_MERCHANT_ID=1 XSOLLA_PROJECT_ID=2 bash "$HERE/apply.sh" voidwall-45e0 de-DE --commit \
  > noop-overwrite.out 2>&1
chk "identical existing value needs no confirmation" "grep -q 'Copy was written' noop-overwrite.out"
unset XSOLLA_CLI FAKE_STORE
cp "$HERE/fixtures/translated.de-DE.json" l10n/work/de-DE/translated.json

echo "== verify: reads the STORE back, not the file =="
export XSOLLA_CLI="$HERE/fixtures/fake-xsolla.sh"
export XSOLLA_MERCHANT_ID=1 XSOLLA_PROJECT_ID=2
cp "$HERE/fixtures/translated.de-DE.json" l10n/work/de-DE/translated.json

FAKE_STORE="$HERE/fixtures/store-good" bash "$HERE/verify.sh" voidwall-45e0 de-DE \
  > good.out 2>&1; grc=$?
chk "landed run passes"                      "[ $grc -eq 0 ]"
chk "counts storefront strings"              "grep -q 'storefront strings   6' good.out"
chk "reports which language it opens in"     "grep -q 'opens in de-DE' good.out"
chk "legal/asset units not demanded"         "! grep -q 'blk_foot\|blk_seo' good.out"

echo "== opening language is reported, not changed =="
echo '["it-IT","de-DE","en-US"]' > "$TMP/langs.json"
FAKE_STORE="$HERE/fixtures/store-good" FAKE_LANG_FILE="$TMP/langs.json" \
  bash "$HERE/verify.sh" voidwall-45e0 de-DE > italian.out 2>&1; irc=$?
chk "opens in another language still passes" "[ $irc -eq 0 ]"
chk "names the language the shop opens in"   "grep -q 'opens in it-IT' italian.out"
chk "points at Publisher Account"            "grep -q 'Publisher Account' italian.out"

set +e
FAKE_STORE="$HERE/fixtures/store-broken" bash "$HERE/verify.sh" voidwall-45e0 de-DE \
  > bad.out 2>&1; brc=$?
set -e
chk "a store that did not take FAILS"        "[ $brc -ne 0 ]"
chk "catches a blanked block string"         "grep -q 'blk_hero:values.subtitle: no de-DE value' bad.out"
chk "catches a language that is not enabled" "grep -q 'de-DE: NOT enabled' bad.out"

echo; echo "$pass passed, $failn failed"; [ "$failn" -eq 0 ]
