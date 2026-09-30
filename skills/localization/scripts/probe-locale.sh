#!/usr/bin/env bash
# probe-locale.sh — settle two questions that no amount of reading can settle, by writing to
# a throwaway SKU and reading it back:
#
#   Q1  Are short (`ja`) and five-symbol (`ja-JP`) locale codes interchangeable on the
#       CATALOG? SKILL.md says both are accepted; the shop-translation draft says a
#       five-symbol code "fails quietly". A client read cannot tell you — it returns
#       ok:true and default-locale text for ANY string, including "not-a-locale".
#   Q2  Does update-items really REPLACE the entity, dropping prices/groups when they are
#       not re-sent?
#
# THIS WRITES TO A LIVE CATALOG. The Xsolla catalog has no sandbox. It creates its own
# throwaway SKU and deletes it at the end; it never touches an existing item.
set -euo pipefail

XS="${XSOLLA_CLI:-xsolla}"
P="${XSOLLA_PROJECT_ID:?set XSOLLA_PROJECT_ID}"
M="${XSOLLA_MERCHANT_ID:?set XSOLLA_MERCHANT_ID}"
: "${XSOLLA_API_KEY:?set XSOLLA_API_KEY}"

for p in ${XSOLLA_PRODUCTION_PROJECT_IDS:-}; do
  [ "$p" = "$P" ] && { echo "REFUSING: $P is listed in XSOLLA_PRODUCTION_PROJECT_IDS" >&2; exit 1; }
done

SKU="l10n-probe-$(date -u +%Y%m%d%H%M%S)"
A=(--merchant-id "$M" --project-id "$P" --json)
PRICES='[{"amount":1.99,"currency":"USD","is_default":true,"is_enabled":true}]'
GROUP="$($XS catalog list-item-groups --project-id "$P" --json 2>/dev/null \
        | jq -r '[.. | objects | (.external_id // empty)][0] // empty')"

echo "probe SKU: $SKU   project: $P   group: ${GROUP:-<none>}"
echo "NOTE: this is a LIVE write. Ctrl-C now if that is not intended."; sleep 3

cleanup() { echo "-- deleting $SKU"; $XS catalog delete-items --item-sku "$SKU" --force "${A[@]}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

name_keys() { $XS catalog get-items --item-sku "$SKU" "${A[@]}" 2>/dev/null | jq -c '.data.name'; }
client_name() { $XS catalog get-catalog-item --item-sku "$SKU" --project-id "$P" --locale "$1" --json 2>/dev/null | jq -r '.data.name // .name // "?"'; }

create() { # <name-json>
  $XS catalog create-items --sku "$SKU" --name "$1" \
      --description '{"en":"probe"}' --prices "$PRICES" \
      ${GROUP:+--groups "[\"$GROUP\"]"} --is-enabled=true --is-show-in-store=true "${A[@]}" >/dev/null
}

echo; echo "== Q1a: write five-symbol ja-JP =="
create '{"en":"Probe","ja-JP":"テスト"}'
echo "  admin name map : $(name_keys)"
echo "  client ja      : $(client_name ja)"
echo "  client ja-JP   : $(client_name ja-JP)"

echo; echo "== Q2: update with --name ONLY, then check prices/groups survived =="
$XS catalog update-items --item-sku "$SKU" --sku "$SKU" \
    --name '{"en":"Probe2","ja-JP":"テスト2"}' "${A[@]}" >/dev/null 2>&1 \
  && echo "  (name-only update accepted)" || echo "  (name-only update REJECTED — see below)"
$XS catalog get-items --item-sku "$SKU" "${A[@]}" 2>/dev/null \
  | jq -c '{prices, groups: [.groups[]?.external_id], is_show_in_store, description}'
echo "  ^ if prices is [] or groups is [], update-items REPLACES the entity:"
echo "    a name-only translation write silently drops price and store visibility."

cleanup; trap - EXIT

echo; echo "== Q1b: write short code ja =="
create '{"en":"Probe","ja":"テスト"}'
echo "  admin name map : $(name_keys)"
echo "  client ja      : $(client_name ja)"
cleanup; trap - EXIT

cat <<'INTERP'

Interpretation
  Q1  admin map shows key "ja" after a ja-JP write   -> accepted and normalized (SKILL.md right)
      admin map shows "ja-JP" AND client ja is JP    -> both forms work verbatim
      admin map shows "ja-JP" but client ja is EN    -> the draft is right: five-symbol
                                                        stores but does not resolve
  Q2  prices/groups empty after a name-only update   -> entity is REPLACED; always re-send
                                                        the full body (apply.sh does)

Record the outcome in references/i18n-support.md and delete the UNRESOLVED box there.
INTERP
