#!/usr/bin/env bash
# restore.sh <domain> [baseline-dir] [--commit] [--languages <locale,...>]
#
# Replays a baseline back onto the live store. The snapshot commit is only a rollback POINT;
# this is what makes it a rollback. Without it "revertible" is a claim, not a capability.
#
# Restores catalog name/description to exactly what the baseline held — locale maps are
# REPLACED, so any locale added since is removed from the catalog. Storefront strings are
# deliberately NOT reverted: they live per-locale, they are invisible unless that locale is
# selected, and keeping them makes a re-run cheap. Use --languages to control which locales
# the site offers (and therefore which one it opens in).
#
# LIVE. The catalog has no sandbox. Dry run is the default.
set -euo pipefail

DOMAIN="${1:?usage: restore.sh <domain> [baseline-dir] [--commit] [--languages en-US,ja-JP]}"; shift
BASE=""; COMMIT=0; LANGS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --commit) COMMIT=1 ;;
    --languages) LANGS="${2:?--languages needs a value}"; shift ;;
    *) BASE="$1" ;;
  esac; shift
done
[ -n "$BASE" ] || BASE="$(ls -d l10n/baseline/*/ 2>/dev/null | sort | tail -1)"
[ -n "$BASE" ] && [ -d "$BASE" ] || { echo "no baseline found — pass one explicitly" >&2; exit 1; }

XS="${XSOLLA_CLI:-xsolla}"
M="${XSOLLA_MERCHANT_ID:?set XSOLLA_MERCHANT_ID}"
P="${XSOLLA_PROJECT_ID:?set XSOLLA_PROJECT_ID}"
SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "restore from $BASE -> project $P"
[ "$COMMIT" = 1 ] && echo "** LIVE WRITE — the catalog has no sandbox **" || echo "DRY RUN (add --commit to write)"

BASE="$BASE" DOMAIN="$DOMAIN" COMMIT="$COMMIT" M="$M" P="$P" XS="$XS" SCRIPTDIR="$SCRIPTDIR" python3 <<'PY'
import json, os, subprocess, sys
sys.path.insert(0, os.environ['SCRIPTDIR'])
import catalog_i18n as i18n
BASE, COMMIT = os.environ['BASE'], os.environ['COMMIT'] == '1'
XS, M, P = os.environ['XS'], os.environ['M'], os.environ['P']

I18N_FILE = {
    'catalog-virtual-items.json': ('virtual_item', 'items'),
    'catalog-bundles.json': ('bundle', 'bundle'),
    'catalog-currency-packages.json': ('virtual_currency_package', 'vc_package'),
    'catalog-item-groups.json': ('item_group', 'groups'),
}

CMD = {'catalog-virtual-items.json':     ('update-items',                  '--item-sku',
        {'prices','vc_prices','groups','image_url','is_enabled','is_free','is_show_in_store'}),
       'catalog-bundles.json':           ('admin-update-bundles',          '--bundle-sku',
        {'prices','vc_prices','groups','image_url','is_enabled','content'}),
       'catalog-currency-packages.json': ('admin-update-currency-package', '--package-sku',
        {'prices','groups','image_url','is_enabled','is_show_in_store','content'})}
n = fail = 0
for fname, (cmd, skuflag, ok) in CMD.items():
    path = os.path.join(BASE, fname)
    if not os.path.exists(path): continue
    for e in (json.load(open(path)).get('items') or []):
        sku = e.get('sku')
        if not sku: continue
        args = [XS, 'catalog', cmd, skuflag, sku, '--sku', sku,
                '--merchant-id', M, '--project-id', P]
        # Send the entity whole: these commands REPLACE, so a partial write drops fields.
        if e.get('prices') is not None and 'prices' in ok:
            args += ['--prices', json.dumps(e['prices'], ensure_ascii=False)]
        if e.get('vc_prices') and 'vc_prices' in ok:
            args += ['--vc-prices', json.dumps(e['vc_prices'], ensure_ascii=False)]
        g = [x['external_id'] if isinstance(x, dict) else x
             for x in (e.get('groups') or []) if x]
        g = [x for x in g if isinstance(x, str)]
        if g and 'groups' in ok: args += ['--groups', json.dumps(g, ensure_ascii=False)]
        if e.get('image_url') and 'image_url' in ok: args += ['--image-url', e['image_url']]
        if 'content' in ok and e.get('content'):
            slim = [{'sku': i['sku'], 'quantity': i.get('quantity', 1)}
                    for i in e['content'] if isinstance(i, dict) and i.get('sku')]
            if slim: args += ['--content', json.dumps(slim, ensure_ascii=False)]
        for key, flag in (('is_enabled','--is-enabled'), ('is_free','--is-free'),
                          ('is_show_in_store','--is-show-in-store')):
            if key in e and key in ok: args += [f"{flag}={'true' if e[key] else 'false'}"]
        for f in ('name','description'):
            if isinstance(e.get(f), dict) and e[f]:
                args += [f'--{f}', json.dumps(e[f], ensure_ascii=False)]
        locales = ','.join(sorted((e.get('name') or {}).keys()))
        print(f"  {sku:28} -> locales [{locales}]")
        if COMMIT:
            r = subprocess.run(args, capture_output=True, text=True)
            if r.returncode: fail += 1; print(f"     FAILED rc={r.returncode} {r.stderr[:120]}")
            else: n += 1
print(f"\nrestored {n} entities" + (f", {fail} FAILED" if fail else "") if COMMIT else "\n(dry run)")

# Pass-through Admin PUT bodies (groups + long_description). Preview only unless
# catalog_i18n restore --write is used later — apply/restore --commit still uses CLI
# for items/bundles/packages and never calls Store HTTP from this script.
putn = 0
outdir = os.path.join('l10n', 'work', 'restore-put')
os.makedirs(outdir, exist_ok=True)
for fname, (etype, ikey) in I18N_FILE.items():
    path = os.path.join(BASE, fname)
    if not os.path.exists(path):
        continue
    d = json.load(open(path))
    if isinstance(d, dict) and 'data' in d and set(d) <= {'ok', 'data', 'error'}:
        d = d['data']
    rows = d.get('items') if isinstance(d, dict) and isinstance(d.get('items'), list) else (
        d.get('groups') if isinstance(d, dict) else d)
    for e in rows or []:
        if not isinstance(e, dict):
            continue
        oid = e.get('sku') or e.get('external_id')
        if not oid:
            continue
        merged = {f: e[f] for f in ('name', 'description', 'long_description')
                  if isinstance(e.get(f), dict)}
        body = i18n._put_body(i18n.ENTITIES[ikey], dict(e), merged, allow_field_loss=False)
        out = os.path.join(outdir, f"restore.put.{etype}.{oid}.json")
        json.dump({"entity": ikey, "id": oid, "body": body}, open(out, "w"), indent=2, ensure_ascii=False)
        putn += 1
        print(f"  PUT preview {etype:24} {oid}")
print(f"pass-through PUT previews: {putn} (catalog_i18n restore --write is the live rollback)")
sys.exit(1 if fail else 0)
PY

if [ -n "$LANGS" ] && [ "$COMMIT" = 1 ]; then
  echo; echo "setting site languages -> $LANGS"
  want="$(echo "$LANGS" | tr ',' ' ')"; first="$(echo $want | awk '{print $1}')"
  cur="$("$XS" shopbuilder get-structure --slug "$DOMAIN" --merchant-id "$M" --project-id "$P" --json 2>/dev/null | jq -r '.data.languages[]')"
  "$XS" shopbuilder add-language --slug "$DOMAIN" --language "$first" --merchant-id "$M" --project-id "$P" >/dev/null 2>&1 || true
  for l in $cur; do
    echo " $want " | grep -q " $l " && continue
    "$XS" shopbuilder delete-language --slug "$DOMAIN" --language "$l" --merchant-id "$M" --project-id "$P" >/dev/null 2>&1 || true
  done
  for l in $want; do
    [ "$l" = "$first" ] && continue
    "$XS" shopbuilder add-language --slug "$DOMAIN" --language "$l" --merchant-id "$M" --project-id "$P" >/dev/null 2>&1 || true
  done
  echo "languages now: $("$XS" shopbuilder get-structure --slug "$DOMAIN" --merchant-id "$M" --project-id "$P" --json 2>/dev/null | jq -c '.data.languages')"
fi
