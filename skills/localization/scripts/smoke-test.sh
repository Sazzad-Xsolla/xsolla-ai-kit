#!/usr/bin/env bash
# smoke-test.sh — exercise the pipeline against fixtures. No CLI, no network, no store.
#
# Proves the mechanical parts: the allowlist keeps structural fields out, L: ids resolve to
# the right scope, block text is routed to the localization store rather than update-block,
# the {"translation":...} envelope is used, catalog locale maps keep the source locale, and
# the tag-parity gate blocks. It proves nothing about the live API.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/l10n/baseline/fixture" "$TMP/l10n/work/de-DE"
cp "$HERE/fixtures/baseline/"*.json "$TMP/l10n/baseline/fixture/"
cd "$TMP"

pass=0; failn=0
chk(){ if eval "$2" >/dev/null 2>&1; then echo "  ok   $1"; pass=$((pass+1));
       else echo "  FAIL $1"; failn=$((failn+1)); fi; }

echo "== extract =="
bash "$HERE/extract.sh" en-US de-DE l10n/baseline/fixture >/dev/null
T=l10n/work/de-DE/translatable.json
chk "22 units"                        "[ \$(jq '.units|length' $T) -eq 22 ]"
chk "11 catalog / 11 block"            "[ \$(jq '[.units[]|select(.surface==\"catalog\")]|length' $T) -eq 11 ] && [ \$(jq '[.units[]|select(.surface==\"block\")]|length' $T) -eq 11 ]"
chk "L: ids resolved to page scope"   "[ \$(jq '[.units[]|select(.scope==\"page1\")]|length' $T) -eq 10 ]"
chk "asset URLs flagged, not copy"    "jq -e '[.units[]|select(.kind==\"asset\")]|length==2' $T"
chk "every asset unit is a URL"       "jq -e '[.units[]|select(.kind==\"asset\")]|all(.source|startswith(\"http\"))' $T"
# Page-level SEO (title/description) lives under page.seo, a sibling of page.blocks — the
# original block walker never reached it (SB-8790 DoD names SEO fields explicitly).
chk "page SEO title extracted"        "jq -e '.units[]|select(.id==\"seo:page1:title\")|.source==\"Voidwall Store\"' $T"
chk "page SEO title is marketing"     "jq -e '.units[]|select(.id==\"seo:page1:title\")|.kind==\"marketing\"' $T"
chk "page SEO description extracted"  "jq -e '.units[]|select(.id==\"seo:page1:description\")|.kind==\"ui\"' $T"
chk "page SEO og:image is an asset"   "jq -e '.units[]|select(.id==\"seo:page1:ogImage\")|.kind==\"asset\"' $T"
chk "SEO units carry the page's L: ids" "jq -e '[.units[]|select(.id|startswith(\"seo:page1:\"))|.lid]|sort==[\"L:seoDesc\",\"L:seoImg\",\"L:seoTitle\"]' $T"
chk "empty description not extracted" "jq -e '[.units[]|select(.sku==\"no_desc_item\")]|length==1' $T"
chk "common-scope string not dropped" "jq -e '[.units[]|select(.scope==\"common\")]|length==1' $T"
chk "1 legal unit flagged"            "[ \$(jq '[.units[]|select(.kind==\"legal\")]|length' $T) -eq 1 ]"
# list-item-groups returns `name` as a bare string with no locale map at all (PA-only field,
# no CLI read or write path) — confirmed live. Extracting 0 units here is correct, not a miss.
chk "item group names extracted from locale maps" "[ \$(jq '[.units[]|select(.entity_type==\"item_group\")]|length' $T) -eq 2 ]"
chk "item group cosmetics name present"          "jq -e '.units[]|select(.id==\"catalog:item_group:cosmetics:name\")|.source==\"Cosmetics\"' $T"
chk "landing_id captured from _id"    "jq -e '.meta.landing_id==\"landing_mongo_id\"' $T"
for b in cosmetics virtual_good rgba 'cdn\\.x' skin_ember 'L:'; do
  chk "no structural leakage: $b"     "[ \$(jq --arg b '$b' '[.units[]|select(.source|test(\$b))]|length' $T) -eq 0 ]"
done

echo "== ingest: publisher JSON/TXT fills translated.json =="
python3 -c 'import json; json.dump({"catalog:item_group:cosmetics:name":"Kosmetik-Datei"}, open("pub.json","w"))'
bash "$HERE/ingest-user-translations.sh" de-DE pub.json >/dev/null
chk "ingest filled the named unit" "jq -e '.units[]|select(.id==\"catalog:item_group:cosmetics:name\")|.target==\"Kosmetik-Datei\"' l10n/work/de-DE/translated.json"
printf '%s\n' 'catalog:item_group:boosters:name	Booster-TXT' > pub.txt
bash "$HERE/ingest-user-translations.sh" de-DE pub.txt >/dev/null
chk "ingest accepts TXT id-tab-target" "jq -e '.units[]|select(.id==\"catalog:item_group:boosters:name\")|.target==\"Booster-TXT\"' l10n/work/de-DE/translated.json"

echo "== catalog_i18n.py offline suite =="
python3 "$HERE/tests/test_catalog_i18n.py" >/tmp/catalog_i18n.out
chk "catalog_i18n suite passed" "grep -q 'passed' /tmp/catalog_i18n.out && ! grep -q 'FAIL' /tmp/catalog_i18n.out"
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
C=$PD/catalog.bundle.starter_pack.cmd.json
chk "block text -> update-many-localization" "grep -q update-many-localization $PD/localization.cmd.json"
chk "block text NOT via update-block"        "! grep -rq update-block $PD/"
chk "locale is the target"                   "jq -e '.locale==\"de-DE\"' $L"
chk "perScopeValues keyed by page and common" "jq -e '.perScopeValues|has(\"page1\") and has(\"common\")' $L"
chk "per-id envelope is {translation:...}"   "jq -e '.perScopeValues.page1[\"L:t1\"]|has(\"translation\")' $L"
chk "legal string not written"               "jq -e '.perScopeValues.page1|has(\"L:t6\")|not' $L"
# --sandbox is NOT a safety property for the catalog: the CLI warns it has no effect there
# and the request URL is identical with or without it. Asserting it would certify nothing.
chk "no call carries --sandbox at all"       "! grep -rq -- '--sandbox' $PD/"
chk "catalog write is announced as LIVE"     "grep -qi 'go LIVE' $PD/../apply.out"
chk "catalog carries --prices"               "jq -e 'index(\"--prices\")!=null' $C"
chk "catalog carries --groups"               "jq -e 'index(\"--groups\")!=null' $C"
# Flag surfaces differ per command. update-items HAS --is-show-in-store/--is-free;
# admin-update-bundles does NOT (sending them is a hard "unknown flag" failure).
V=$PD/catalog.virtual_item.skin_ember.cmd.json
chk "item carries store-visibility flag"     "jq -e 'any(.[]; startswith(\"--is-show-in-store\"))' $V"
chk "item carries --is-free"                 "jq -e 'any(.[]; startswith(\"--is-free\"))' $V"
chk "bundle omits --is-free (unsupported)"   "jq -e 'all(.[]; startswith(\"--is-free\")|not)' $C"
chk "bundle omits --is-show-in-store"        "jq -e 'all(.[]; startswith(\"--is-show-in-store\")|not)' $C"
chk "asset URL never written"                "! grep -rq 'og-image' $PD/"
chk "no-description item blocked"            "grep -q 'no_desc_item' $PD/../apply.out"
# The catalog stores TWO-LETTER keys: a ja-JP write is normalized to ja, and --locale ja-JP
# silently falls back. So the write must carry en/de, not en-US/de-DE.
chk "catalog map uses 2-letter keys"         "jq -e 'index(\"--name\") as \$i | .[\$i+1] | fromjson | has(\"en\") and has(\"de\")' $C"
chk "catalog map keeps the source locale"    "jq -e 'index(\"--name\") as \$i | .[\$i+1] | fromjson | keys|length==2' $C"
# THE destructive case: catalog locale maps are REPLACED, so a de-DE run that sends only
# {en,de} deletes the Spanish an earlier run wrote — ok:true, no warning, the previous
# language silently un-translated. skin_ember carries `es` in the baseline; every locale the
# entity already had has to come back out in the write.
chk "3rd locale from an earlier run survives" "jq -e 'index(\"--name\") as \$i | .[\$i+1] | fromjson | has(\"es\")' $V"
chk "3rd locale survives on description too"  "jq -e 'index(\"--description\") as \$i | .[\$i+1] | fromjson | has(\"es\")' $V"
chk "preserved locales are announced"         "grep -q 'preserving es' l10n/work/de-DE/apply.out"
chk "catalog uses the right sku flag"        "jq -e 'index(\"--bundle-sku\")!=null' $C"
chk "no item_group CLI write attempted"      "[ ! -f $PD/catalog.item_group.cosmetics.cmd.json ]"
chk "item_group Admin PUT body is pass-through" "jq -e '.entity==\"groups\" and .body.name.de==\"Kosmetik\" and .body.external_id==\"cosmetics\"' $PD/catalog.put.item_group.cosmetics.json"
chk "long_description in pass-through PUT"   "jq -e '.body.long_description.de|test(\"kosmetisch\")' $PD/catalog.put.virtual_item.skin_ember.json"
chk "pass-through PUT keeps image_url"       "jq -e '.body.image_url|startswith(\"http\")' $PD/catalog.put.virtual_item.skin_ember.json"

echo "== apply: existing translations are not overwritten without confirmation =="
# A unit that already carries a DIFFERENT de-DE value (template-prepopulated, or a prior
# run) must not be silently replaced on --commit. Route --commit through the fake CLI so
# this stays network-free even if the gate has a bug and lets a write through.
export XSOLLA_CLI="$HERE/fixtures/fake-xsolla.sh"
export FAKE_STORE="$HERE/fixtures/store-good"
# Drop the two SKUs the fixture deliberately leaves description-less — --commit blocks on
# those regardless (a separate, already-covered gate), which would mask what this section
# tests. What is being tested here is the overwrite gate, not the description gate.
jq '.units |= map(select(.sku!="coins_1000" and .sku!="no_desc_item"))
    | (.units[]|select(.id=="catalog:virtual_item:skin_ember:name")|.existing_target)="Alter Glut-Skin"' \
  "$HERE/fixtures/translated.de-DE.json" > l10n/work/de-DE/translated.json
set +e
XSOLLA_MERCHANT_ID=1 XSOLLA_PROJECT_ID=2 bash "$HERE/apply.sh" voidwall-45e0 de-DE --commit \
  > overwrite.out 2>&1; orc=$?
set -e
chk "commit without --confirm-overwrites is BLOCKED" "[ $orc -ne 0 ]"
chk "blocked run lists the existing vs. new value" \
  "grep -q 'existing.*Alter Glut-Skin' overwrite.out && grep -q 'new.*Glutwächter-Skin' overwrite.out"
chk "blocked run wrote nothing"                    "[ ! -f l10n/work/de-DE/payloads/catalog.virtual_item.skin_ember.response.json ]"
XSOLLA_MERCHANT_ID=1 XSOLLA_PROJECT_ID=2 bash "$HERE/apply.sh" voidwall-45e0 de-DE \
  --commit --confirm-overwrites > overwrite-confirmed.out 2>&1
chk "--confirm-overwrites lets the same run through" "grep -q 'go LIVE' overwrite-confirmed.out"
# Identical existing==new is not a real overwrite and must not require the flag.
jq '.units |= map(select(.sku!="coins_1000" and .sku!="no_desc_item"))
    | (.units[]|select(.id=="catalog:virtual_item:skin_ember:name")|.existing_target)="Glutwächter-Skin"' \
  "$HERE/fixtures/translated.de-DE.json" > l10n/work/de-DE/translated.json
XSOLLA_MERCHANT_ID=1 XSOLLA_PROJECT_ID=2 bash "$HERE/apply.sh" voidwall-45e0 de-DE --commit \
  > noop-overwrite.out 2>&1
chk "identical existing value needs no confirmation" "grep -q 'go LIVE' noop-overwrite.out"
unset XSOLLA_CLI FAKE_STORE
cp "$HERE/fixtures/translated.de-DE.json" l10n/work/de-DE/translated.json

echo "== client-shape baseline is rejected, not silently skipped =="
# The original bug: snapshot.sh used client reads, extract.sh required a locale map, and every
# catalog string vanished without a word. A fixture that can only pass is not a test.
mkdir -p l10n/baseline/client l10n/work/xx
cp "$HERE/fixtures/baseline-client/"*.json l10n/baseline/client/
bash "$HERE/extract.sh" en-US xx l10n/baseline/client > client.out 2>&1 || true
chk "client shape is reported, not ignored" "grep -qi 'CLIENT read' client.out"
chk "client shape yields no catalog units"  "[ \$(jq '[.units[]|select(.surface==\"catalog\")]|length' l10n/work/xx/translatable.json) -eq 0 ]"

echo "== verify: reads the STORE back, not the file =="
# Everything above checks payloads we built. This checks the half that was documented but
# never implemented: after writing, ask the store what it actually holds. Driven by a fake
# CLI serving the real {"ok":true,"data":…} envelope, so no network and no store are needed.
export XSOLLA_CLI="$HERE/fixtures/fake-xsolla.sh"
export XSOLLA_MERCHANT_ID=1 XSOLLA_PROJECT_ID=2
cp "$HERE/fixtures/translated.de-DE.json" l10n/work/de-DE/translated.json

FAKE_STORE="$HERE/fixtures/store-good" bash "$HERE/verify.sh" voidwall-45e0 de-DE \
  > good.out 2>&1; grc=$?
chk "landed run passes"                      "[ $grc -eq 0 ]"
chk "counts catalog names and descriptions"  "grep -q 'catalog names        5' good.out && grep -q 'catalog descriptions 3' good.out"
chk "counts storefront strings"              "grep -q 'storefront strings   6' good.out"
chk "reports which language it opens in"     "grep -q 'opens in de-DE' good.out"
chk "legal/asset units not demanded"         "! grep -q 'blk_foot\|blk_seo' good.out"
chk "CLI cannot carry long_description flag" "grep -q 'no CLI flag' $PD/../apply.out"

set +e
FAKE_STORE="$HERE/fixtures/store-broken" bash "$HERE/verify.sh" voidwall-45e0 de-DE \
  > bad.out 2>&1; brc=$?
set -e
chk "a store that did not take FAILS"        "[ $brc -ne 0 ]"
chk "catches a missing description"          "grep -q 'boost_xp.description: no de value' bad.out"
chk "catches a WIPED source locale"          "grep -q 'starter_pack.name: SOURCE locale en is GONE' bad.out"
chk "catches a blanked block string"         "grep -q 'blk_hero:values.subtitle: no de-DE value' bad.out"
chk "catches a language that is not enabled" "grep -q 'de-DE: NOT enabled' bad.out"
chk "catches a price gap in one market"      "grep -q 'skin_ember: no price in EUR' bad.out"
chk "reports other locales still present"    "grep -q 'other locales still present: es' bad.out"

echo; echo "$pass passed, $failn failed"; [ "$failn" -eq 0 ]
