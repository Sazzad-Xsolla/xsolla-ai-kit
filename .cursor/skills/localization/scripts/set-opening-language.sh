#!/usr/bin/env bash
# set-opening-language.sh <domain> <locale> — make <locale> the language the shop OPENS in.
#
# A landing has no default-locale field. The ORDER of `languages` decides, and add-language
# only appends, so the sole lever is delete + re-add in the order you want.
#
# This is safe: delete-language edits the ENABLED LIST only. Verified — a locale's strings
# remain in the localization store after its removal and come back intact on re-add. The
# enabled list and the localization store are separate things.
#
# Without this step a translation run "does nothing": every string is written correctly, the
# shop opens in its original language, and it looks like the run failed.
set -euo pipefail

DOMAIN="${1:?usage: set-opening-language.sh <domain> <locale>   e.g. voidwall-45e0 ja-JP}"
TARGET="${2:?usage: set-opening-language.sh <domain> <locale>}"
XS="${XSOLLA_CLI:-xsolla}"
M="${XSOLLA_MERCHANT_ID:?set XSOLLA_MERCHANT_ID}"
P="${XSOLLA_PROJECT_ID:?set XSOLLA_PROJECT_ID}"
A=(--merchant-id "$M" --project-id "$P" --json)

cur="$("$XS" shopbuilder get-structure --slug "$DOMAIN" "${A[@]}" 2>/dev/null \
       | jq -r '.data.languages[]' || true)"
[ -n "$cur" ] || { echo "could not read languages for $DOMAIN" >&2; exit 1; }
echo "current: $(echo $cur | tr '\n' ' ')"

if [ "$(echo "$cur" | head -1)" = "$TARGET" ]; then
  echo "$TARGET is already first — nothing to do"; exit 0
fi

# Target first, then everything else in its existing relative order.
order="$TARGET$(printf '\n%s' $(echo "$cur" | grep -vx "$TARGET") )"

# Remove all but one: a landing cannot have zero languages, so keep the target present
# throughout by adding it first, then stripping the rest, then re-adding in order.
"$XS" shopbuilder add-language --slug "$DOMAIN" --language "$TARGET" "${A[@]}" >/dev/null 2>&1 || true
for l in $cur; do
  [ "$l" = "$TARGET" ] && continue
  "$XS" shopbuilder delete-language --slug "$DOMAIN" --language "$l" "${A[@]}" >/dev/null 2>&1 \
    || echo "  ! could not remove $l"
done
# Re-add the others so they stay available behind the selector.
for l in $(echo "$order" | tail -n +2); do
  "$XS" shopbuilder add-language --slug "$DOMAIN" --language "$l" "${A[@]}" >/dev/null 2>&1 \
    || echo "  ! could not restore $l"
done

final="$("$XS" shopbuilder get-structure --slug "$DOMAIN" "${A[@]}" 2>/dev/null | jq -c '.data.languages')"
echo "now:     $final"
case "$final" in
  "[\"$TARGET\""*) echo "OK — the shop now opens in $TARGET" ;;
  *) echo "WARNING: $TARGET is not first; the shop will still open in another language" >&2; exit 1 ;;
esac
