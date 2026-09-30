#!/usr/bin/env bash
# A stand-in for the xsolla CLI, so verify.sh can be exercised with no network and no store.
# Serves canned responses from $FAKE_STORE, in the SAME envelope the real CLI uses
# ({"ok":true,"data":…}) — the envelope is itself a trap worth testing against.
set -euo pipefail
STORE="${FAKE_STORE:?FAKE_STORE must point at a fixture store dir}"
GROUP="${1:-}"; CMD="${2:-}"; shift 2 || true

arg() { # arg <flag> — value of a --flag from the remaining args
  local want="$1"; shift || true
  while [ $# -gt 0 ]; do [ "$1" = "$want" ] && { echo "${2:-}"; return 0; }; shift; done
  return 0
}
emit() { [ -f "$1" ] || { echo "not found: $(basename "$1")" >&2; exit 1; }; printf '{"ok":true,"data":%s}' "$(cat "$1")"; }

case "$GROUP $CMD" in
  "catalog get-items")   emit "$STORE/item.$(arg --item-sku "$@").json" ;;
  "catalog get-bundles") emit "$STORE/item.$(arg --bundle-sku "$@").json" ;;
  "catalog admin-list-currency-packages") emit "$STORE/packages.json" ;;
  "shopbuilder get-localization")
      # The real command takes --slug ONLY; --merchant-id is a hard 'unknown flag' that
      # prints plain text. Reproduce that, so the caller is tested against it.
      for a in "$@"; do case "$a" in --merchant-id|--project-id)
        echo "unknown flag: $a" >&2; exit 1 ;; esac; done
      emit "$STORE/localization.json" ;;
  "shopbuilder get-structure") emit "$STORE/structure.json" ;;
  *) echo "fake-xsolla: unhandled '$GROUP $CMD'" >&2; exit 1 ;;
esac
