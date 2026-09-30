#!/usr/bin/env bash
# snapshot.sh <domain> — capture the pre-change state and commit it as the rollback point.
#
# Run before EVERY translation run, not once per project. A stale baseline hides a human's
# Publisher Account edit and you overwrite it.
#
# CATALOG READS MUST BE ADMIN READS. The CLI has two families and the tell is --locale:
#
#   client (no auth, HAS --locale):  list-catalog-items, get-catalog-item, get-item-by-sku,
#                                    list-all-items, list-item-groups
#                                    -> returns ONE RESOLVED STRING, silently falling back
#                                       to the default locale. Useless as a baseline.
#   admin  (Basic auth, NO --locale): get-items, admin-list-items-by-group,
#                                     admin-list-bundles-by-group, admin-list-currency-packages
#                                    -> returns the real locale MAP {"en": "...", "de": "..."}
#
# extract.sh requires a map. Snapshotting with a client read produces bare strings, and every
# catalog unit is then silently dropped — a pass that translates the storefront only. Hence
# the shape assertion at the bottom: this failure is invisible without it.
set -euo pipefail

DOMAIN="${1:?usage: snapshot.sh <domain>   (the RETURNED domain, e.g. voidwall-45e0, not the requested slug)}"
XS="${XSOLLA_CLI:-xsolla}"
P="${XSOLLA_PROJECT_ID:?set XSOLLA_PROJECT_ID}"
# Admin catalog reads are Basic auth. Without these the catalog half of the baseline is empty
# and the run silently degrades to storefront-only.
M="${XSOLLA_MERCHANT_ID:?set XSOLLA_MERCHANT_ID (admin catalog reads use Basic auth)}"
: "${XSOLLA_API_KEY:?set XSOLLA_API_KEY (admin catalog reads use Basic auth)}"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="l10n/baseline/$TS"
mkdir -p "$OUT"
echo "snapshot -> $OUT"

get() { # <outfile> <cmd...>
  local out="$1"; shift
  if "$@" > "$OUT/$out" 2>"$OUT/.$out.err"; then
    echo "  $out  $(wc -c < "$OUT/$out") bytes"; rm -f "$OUT/.$out.err"
  else
    echo "  $out  FAILED (see .$out.err)"; rm -f "$OUT/$out"; return 1
  fi
}

# --- Shop Builder -----------------------------------------------------------
# Structure gives each text field an "L:" id at values.<field>.id; it does NOT contain the
# text. The localization store is the source of truth for copy — both are required.
# Flag surfaces differ per command and the CLI rejects extras: get-structure takes
# --merchant-id/--project-id, get-localization takes --slug ONLY. No --sandbox on either —
# "shopbuilder has no Xsolla sandbox environment" (verified), so it is warning noise.
get structure.json    "$XS" shopbuilder get-structure --slug "$DOMAIN" \
                          --merchant-id "$M" --project-id "$P" --json
get localization.json "$XS" shopbuilder get-localization --slug "$DOMAIN" --json

# --- Catalog ----------------------------------------------------------------
# NOTE: --sandbox is deliberately absent here. The CLI warns that catalog has no Xsolla
# sandbox environment; passing it is a no-op that only prints noise. See SKILL.md
# "There is no catalog sandbox".
ADMIN=("--merchant-id" "$M" "--project-id" "$P" "--json")

# Groups: needed for their EXTERNAL IDS only. This is a client read (it takes --locale) and
# its name/description are resolved strings, not maps. Acceptable because group text is not
# translatable via the CLI anyway — there is no admin-update-group in this build.
get catalog-item-groups.json "$XS" catalog list-item-groups --project-id "$P" --json

# Items and bundles: SKUs come from the CLIENT read (a SKU is structural, so a resolved
# response is fine), and the TEXT comes from a per-SKU ADMIN read.
#
# Why not admin-list-items-by-group / admin-list-bundles-by-group? Two reasons, both real:
#   1. They return HTTP 403 with a project-scoped API key (verified against project 314515,
#      while get-items and admin-list-currency-packages on the same key return 200).
#   2. A group walk cannot see an item that belongs to no group, and would drop it silently.
# The per-SKU walk is N+1 calls but has neither problem.
per_sku() { # <outfile> <client-list-cmd> <admin-get-cmd> <admin-sku-flag>
  local out="$1" listcmd="$2" getcmd="$3" skuflag="$4" tmp skus n=0 miss=0
  # TOP-LEVEL skus only. A recursive walk also picks up the SKUs nested inside a bundle's
  # `content`, and calling get-bundles on a virtual item 404s.
  # TOP-LEVEL skus only. A recursive walk also picks up the SKUs nested inside a bundle's
  # `content`, and calling get-bundles on a virtual item 404s.
  # Shape differs by flag: WITHOUT --all, .data is {items:[...]}; WITH --all, .data IS the
  # array. Indexing an array with a string is a jq ERROR, not null, so branch on the type.
  skus="$("$XS" catalog "$listcmd" --project-id "$P" --all --json 2>/dev/null \
          | jq -r '[ (if (.data|type)=="array" then .data
                      elif (.data|type)=="object" then (.data.items // [])
                      else (.items // []) end)[] | .sku ] | unique[]' 2>/dev/null || true)"
  if [ -z "$skus" ]; then echo '{"items":[]}' > "$OUT/$out"; echo "  $out  0 entities"; return 0; fi
  tmp="$(mktemp -d)"
  for k in $skus; do
    if "$XS" catalog "$getcmd" "$skuflag" "$k" "${ADMIN[@]}" > "$tmp/$n.json" 2>"$tmp/$n.err"; then
      n=$((n+1))
    else
      echo "  ! $getcmd $k: $(head -c 120 "$tmp/$n.err")"; rm -f "$tmp/$n.json"; miss=$((miss+1))
    fi
  done
  jq -s '{items: [.[] | (.data // .)]}' "$tmp"/*.json > "$OUT/$out" 2>/dev/null \
    || echo '{"items":[]}' > "$OUT/$out"
  echo "  $out  $n entities$([ "$miss" -gt 0 ] && echo " ($miss unreadable — NOT translated)")"
  rm -rf "$tmp"
}

per_sku catalog-virtual-items.json list-catalog-items   get-items   --item-sku
per_sku catalog-bundles.json       list-catalog-bundles get-bundles --bundle-sku

# Currency packages list fine at the admin level, so no per-SKU walk is needed.
if "$XS" catalog admin-list-currency-packages --all "${ADMIN[@]}" \
     > "$OUT/.pkg.raw" 2>"$OUT/.pkg.err"; then
  jq '{items: ((.data.items // .data // []) | map(.))}' "$OUT/.pkg.raw" \
    > "$OUT/catalog-currency-packages.json" 2>/dev/null || echo '{"items":[]}' > "$OUT/catalog-currency-packages.json"
  echo "  catalog-currency-packages.json  $(jq '.items|length' < "$OUT/catalog-currency-packages.json") entities"
  rm -f "$OUT/.pkg.raw" "$OUT/.pkg.err"
else
  echo "  ! admin-list-currency-packages failed: $(head -c 120 "$OUT/.pkg.err")"
  echo '{"items":[]}' > "$OUT/catalog-currency-packages.json"
fi

# --- Shape assertion --------------------------------------------------------
# The whole class of bug here is a read that looks fine. A client read yields
# "name": "Ember Warden Skin"; an admin read yields "name": {"en": "Ember Warden Skin"}.
# Fail loudly rather than committing a baseline that extract.sh will silently skip.
echo "== shape check =="
shape_fail=0
for f in catalog-virtual-items.json catalog-bundles.json catalog-currency-packages.json; do
  [ -f "$OUT/$f" ] || continue
  bad="$(jq -r '[(.items // .)[]? | select((.name | type) == "string") | .sku] | join(", ")' \
           < "$OUT/$f" 2>/dev/null || true)"
  if [ -n "$bad" ]; then
    echo "  FAIL $f: 'name' is a string, not a locale map, for: $bad"
    echo "       That is a CLIENT read. The baseline must come from an admin read or every"
    echo "       catalog string is silently dropped by extract.sh."
    shape_fail=1
  else
    echo "  ok   $f"
  fi
done
# An empty baseline passes every per-item check by vacuity. Cross-check the counts against
# the storefront so "captured nothing" cannot masquerade as "nothing to capture".
for pair in "catalog-virtual-items.json:list-catalog-items" "catalog-bundles.json:list-catalog-bundles"; do
  f="${pair%%:*}"; lc="${pair##*:}"
  got="$(jq '.items | length' < "$OUT/$f" 2>/dev/null || echo 0)"
  want="$("$XS" catalog "$lc" --project-id "$P" --json 2>/dev/null \
          | jq '[(.data.items // .data // .items // [])[]] | length' 2>/dev/null || echo 0)"
  if [ "$got" -lt "$want" ]; then
    echo "  FAIL $f: captured $got of $want entities the storefront lists"
    echo "       A short baseline silently under-translates. Not committing."
    shape_fail=1
  else
    echo "  ok   $f  $got/$want entities"
  fi
done
[ "$shape_fail" = 0 ] || { echo "aborting — baseline not committed"; exit 1; }

# --- Commit verbatim --------------------------------------------------------
# One commit, unformatted, changing nothing else. That is the rollback point. Reformatting
# goes in a SEPARATE commit so "what the API returned" never mixes with "what we prettified".
git add "$OUT"
git commit -q -m "l10n: baseline snapshot $TS ($DOMAIN)" -- "$OUT"
git tag -f "l10n-baseline-$TS" >/dev/null
echo
echo "committed and tagged l10n-baseline-$TS"
echo "rollback point: git show l10n-baseline-$TS"
