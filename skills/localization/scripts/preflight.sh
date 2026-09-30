#!/usr/bin/env bash
# preflight.sh — verify the environment before any translation work. Fails loudly.
set -euo pipefail

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; RST=$'\033[0m'
fail=0
ok()   { printf '%s  ok  %s %s\n' "$GRN" "$RST" "$1"; }
bad()  { printf '%s FAIL %s %s\n' "$RED" "$RST" "$1"; fail=1; }
warn() { printf '%s warn %s %s\n' "$YEL" "$RST" "$1"; }

echo "== xsolla CLI =="
XS="${XSOLLA_CLI:-$(command -v xsolla 2>/dev/null || true)}"
if [ -z "$XS" ]; then
  bad "xsolla CLI not on PATH. Set XSOLLA_CLI=/abs/path/to/xsolla to override."
else
  ok "using $XS ($("$XS" --version 2>/dev/null | head -1))"
fi

if [ -n "$XS" ]; then
  echo "== required subcommands =="
  sb="$("$XS" shopbuilder --help 2>&1 || true)"
  # Block text lives in the localization store, not the block. Without these two the
  # storefront half of this skill cannot run at all.
  for c in get-structure get-localization update-many-localization add-language enable-preview get-block; do
    grep -qE "^\s*$c\b" <<<"$sb" && ok "shopbuilder $c" || bad "shopbuilder $c MISSING"
  done
  cat="$("$XS" catalog --help 2>&1 || true)"
  # get-items / get-bundles are the ADMIN reads the baseline depends on: they return the real
  # locale map, where the client reads return one resolved string.
  for c in list-catalog-items get-items get-bundles admin-list-currency-packages \
           update-items admin-update-bundles admin-update-currency-package; do
    grep -qE "^\s*$c\b" <<<"$cat" && ok "catalog $c" || bad "catalog $c MISSING"
  done
  # Known gap: no update command for item groups in this build. They render as the store's
  # tab labels, so an untranslated group is highly visible.
  grep -qE '^\s*admin-update-group\b' <<<"$cat" \
    && ok "catalog admin-update-group (item groups translatable via CLI)" \
    || warn "no catalog update command for item groups — tab labels must be set in Publisher Account"
fi

echo "== credentials =="
# Preferred: 'xsolla auth login' bootstraps the Shop Builder session automatically.
# 'auth list-account' exits 0 even when no account is stored, so check the output, not
# the exit code — trusting the exit code here reports a false pass.
acct=""; [ -n "$XS" ] && acct="$("$XS" auth list-account 2>&1 || true)"
if [ -n "$acct" ] && ! grep -qi 'no accounts stored' <<<"$acct"; then
  ok "xsolla auth session present (Shop Builder session auto-bootstraps)"
elif [ -n "${XSOLLA_SHOPBUILDER_SESSION:-}" ]; then
  ok "XSOLLA_SHOPBUILDER_SESSION set (fallback path)"
  case "$XSOLLA_SHOPBUILDER_SESSION" in
    pa-v4-token=*) ok "session value has the pa-v4-token= prefix" ;;
    *ps2*|*user_session*) bad "that looks like a legacy ps2[user_session] value — it 403s. Use pa-v4-token." ;;
    *) warn "expected the form 'pa-v4-token=<value>'" ;;
  esac
else
  bad "no auth. Run 'xsolla auth login' (add --audience https://api.xsolla.com if it asks), or export XSOLLA_SHOPBUILDER_SESSION='pa-v4-token=<value>'"
fi
# Catalog uses Basic auth with a Store/merchant API key — a different credential.
[ -n "${XSOLLA_API_KEY:-}" ] && ok "XSOLLA_API_KEY set (catalog Basic auth)" \
  || bad "XSOLLA_API_KEY unset — catalog writes need it"
[ -n "${XSOLLA_PROJECT_ID:-}" ]  && ok "XSOLLA_PROJECT_ID set"  || bad "XSOLLA_PROJECT_ID unset"
[ -n "${XSOLLA_MERCHANT_ID:-}" ] && ok "XSOLLA_MERCHANT_ID set" \
  || bad "XSOLLA_MERCHANT_ID unset — the admin catalog reads snapshot.sh needs are Basic auth"

echo "== project targeting =="
# There is no catalog sandbox. The CLI warns "--sandbox has no effect on this command —
# catalog has no Xsolla sandbox environment, so this request runs against live project", and
# the URL is identical either way. The ONLY control is which project id is targeted, so an
# unset denylist is not a soft warning — it means nothing is checking anything.
echo "  note: catalog reads/writes are LIVE; --sandbox is a no-op for them"
if [ -n "${XSOLLA_PRODUCTION_PROJECT_IDS:-}" ]; then
  hit=0
  for p in ${XSOLLA_PRODUCTION_PROJECT_IDS//,/ }; do
    [ "$p" = "${XSOLLA_PROJECT_ID:-}" ] && { bad "XSOLLA_PROJECT_ID=$p is a listed production project"; hit=1; }
  done
  [ "$hit" = 0 ] && ok "project ${XSOLLA_PROJECT_ID:-?} is not a listed production project"
else
  bad "XSOLLA_PRODUCTION_PROJECT_IDS unset — set it (comma-separated) to every project that
       must never be written to. apply.sh --commit refuses catalog writes without it."
fi

echo "== tooling =="
for t in jq git python3; do command -v "$t" >/dev/null 2>&1 && ok "$t" || bad "$t not installed"; done

echo
if [ "$fail" = 0 ]; then echo "${GRN}preflight passed${RST}"
else echo "${RED}preflight failed — fix the above before snapshot/extract/apply${RST}"; exit 1; fi
