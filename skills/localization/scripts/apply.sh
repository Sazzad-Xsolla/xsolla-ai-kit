#!/usr/bin/env bash
# apply.sh <domain> <target-locale> [--commit] [--report] [--confirm-overwrites]
#
# Default is a DRY RUN: builds and saves every payload, sends nothing.
#   --commit              actually write, then make the shop open in <target-locale>
#                         so preview opens in that language
#   --report              reconcile the localization store / catalog against translated.json
#   --confirm-overwrites  required on --commit whenever a unit already has a target-locale
#                         value that differs from what is about to be written. Without it,
#                         a run BLOCKS and lists what it would have overwritten.
set -euo pipefail

DOMAIN="${1:?usage: apply.sh <domain> <target-locale> [--commit] [--report] [--confirm-overwrites]}"
TGT="${2:?usage: apply.sh <domain> <target-locale> [--commit] [--report] [--confirm-overwrites]}"; shift 2
COMMIT=0; REPORT=0; CONFIRM_OVERWRITES=0
for a in "$@"; do
  case "$a" in
    --commit) COMMIT=1 ;;
    --report) REPORT=1 ;;
    --confirm-overwrites) CONFIRM_OVERWRITES=1 ;;
    *) echo "unknown flag: $a" >&2; exit 2 ;;
  esac
done

WORK="l10n/work/$TGT/translated.json"
[ -f "$WORK" ] || { echo "missing $WORK — run extract.sh, then translate it" >&2; exit 1; }

# THERE IS NO SANDBOX, ANYWHERE. The CLI says so for both surfaces — "catalog has no Xsolla
# sandbox environment" and "shopbuilder has no Xsolla sandbox environment" — and in both
# cases the request URL is byte-identical with and without the flag. So --sandbox is never
# passed: it would imply a guarantee that does not exist. Every write below is LIVE.
SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN="$DOMAIN" TGT="$TGT" WORK="$WORK" COMMIT="$COMMIT" REPORT="$REPORT" \
CONFIRM_OVERWRITES="$CONFIRM_OVERWRITES" \
SCRIPTDIR="$SCRIPTDIR" python3 <<'PY'
import json, os, re, subprocess, sys, collections
sys.path.insert(0, os.environ['SCRIPTDIR'])
import catalog_i18n as i18n

DOMAIN, TGT, WORK = os.environ['DOMAIN'], os.environ['TGT'], os.environ['WORK']
COMMIT, REPORT = os.environ['COMMIT'] == '1', os.environ['REPORT'] == '1'
CONFIRM_OVERWRITES = os.environ['CONFIRM_OVERWRITES'] == '1'
XS = os.environ.get('XSOLLA_CLI', 'xsolla')
M  = os.environ.get('XSOLLA_MERCHANT_ID', ''); P = os.environ.get('XSOLLA_PROJECT_ID', '')

doc   = json.load(open(WORK))
SRC   = doc['meta']['source_locale']
units = doc['units']

# The catalog update commands REPLACE the entity, they do not patch it. Sending only --name
# and --description drops prices and groups (and --groups is what makes an item store-visible).
# So every write is reconstructed from the baseline the extraction was taken against.
BASE = doc['meta'].get('baseline')

# STALENESS GATE. translated.json is produced from ONE baseline. If a newer snapshot exists,
# these translations describe a store that has since changed — applying them writes copy for
# strings that may no longer be there, and silently misses ones that appeared. Left-over work
# from a previous run is the usual cause, and it is invisible without this check.
try:
    import glob
    snaps = sorted(d for d in glob.glob('l10n/baseline/*/') if os.path.isdir(d))
except Exception:
    snaps = []
if snaps and BASE:
    newest = snaps[-1].rstrip('/')
    if os.path.normpath(BASE) != os.path.normpath(newest):
        print(f"BLOCKED — stale translations.\n"
              f"  translated.json was built from : {os.path.normpath(BASE)}\n"
              f"  newest baseline is            : {newest}\n"
              f"  Re-run extract.sh against the newest baseline and re-translate, or delete\n"
              f"  the stale l10n/work/<locale>/ directory. Applying these would write copy\n"
              f"  for a version of the store that no longer exists.")
        sys.exit(1)
baseline_entities = {}
if BASE:
    for fn, etype in (('catalog-virtual-items.json', 'virtual_item'),
                      ('catalog-bundles.json', 'bundle'),
                      ('catalog-currency-packages.json', 'virtual_currency_package'),
                      ('catalog-item-groups.json', 'item_group')):
        try:
            with open(os.path.join(BASE, fn)) as f: d = json.load(f)
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(d, dict) and 'data' in d and set(d) <= {'ok', 'data', 'error'}:
            d = d['data']
        rows = d
        if isinstance(d, dict):
            rows = d['items'] if isinstance(d.get('items'), list) else d.get('groups', d)
        for e in rows or []:
            if not isinstance(e, dict):
                continue
            key = e.get('sku') or e.get('external_id')
            if key:
                baseline_entities[(etype, key)] = e
PAYDIR = os.path.join(os.path.dirname(WORK), 'payloads')
os.makedirs(PAYDIR, exist_ok=True)

def save(name, obj):
    """Persist every payload. Dry-run payloads are reviewable and diffable; commit
    responses sit beside their request so a revert is replaying a file, not
    reconstructing intent from memory."""
    with open(os.path.join(PAYDIR, name), 'w') as f:
        json.dump(obj, f, indent=2, ensure_ascii=False)

def run(args, tag, sandbox=False):
    """No --sandbox: neither surface has a sandbox environment, so the flag is a no-op that
    would misrepresent what this run is doing. Dry run prints and saves without executing."""
    save(f"{tag}.cmd.json", args)
    print("   ", " ".join(a if len(a) < 60 else a[:57] + "..." for a in args))
    if not COMMIT: return
    r = subprocess.run(args, capture_output=True, text=True)
    save(f"{tag}.response.json", {"rc": r.returncode, "stdout": r.stdout, "stderr": r.stderr})
    print(f"    -> rc={r.returncode}" + ("" if r.returncode == 0 else f" {r.stderr[:160]}"))

TAG   = re.compile(r'<\s*([a-zA-Z][a-zA-Z0-9]*)')

# The CATALOG holds two-letter locale keys. Tested: writing "ja-JP" is accepted but stored
# as "ja", and reading with --locale ja-JP falls back to the default silently. So send the
# two-letter form and leave no ambiguity about what is in the store.
# The two Chinese codes are irregular — truncating zh-CN gives "zh", which is not a code the
# catalog knows. Map them explicitly.
IRREGULAR = {'zh-CN': 'cn', 'zh-TW': 'tw'}
def short_locale(loc):
    if loc in IRREGULAR: return IRREGULAR[loc]
    return loc.split('-')[0] if '-' in loc else loc
plain = lambda s: re.sub(r'<[^>]+>', '', s or '').strip()

# --- gate: validate before writing anything ---------------------------------
errors, warns, skipped, ready = [], [], [], []
for u in units:
    t = u.get('target')
    if u['kind'] == 'legal':
        skipped.append((u['id'], 'legal — route to counsel, not translated here')); continue
    if u['kind'] == 'asset':
        # An asset URL that lives in the localization store. Translating it breaks the image.
        skipped.append((u['id'], 'asset URL — not translatable')); continue
    if not t:
        skipped.append((u['id'], 'no target text')); continue
    # Tag parity: a dropped <h1> renders as unstyled plain text and a reviewer reading the
    # target language will not notice it.
    st, tt = sorted(TAG.findall(u['source'])), sorted(TAG.findall(t))
    if st != tt:
        errors.append(f"{u['id']}: HTML tag mismatch source={st} target={tt}"); continue
    # Block text is HTML. A bare string renders unstyled, so refuse to write one where the
    # source had markup.
    if u['surface'] == 'block' and st and not tt:
        errors.append(f"{u['id']}: block text must be HTML"); continue
    b = u.get('budget')
    if b and len(plain(t)) > b:
        warns.append(f"{u['id']}: {len(plain(t))} chars over budget {b} — will overflow buttons/tabs")
    ready.append(u)

if errors:
    print("BLOCKED — fix these before applying:")
    for e in errors: print("  x", e)
    sys.exit(1)
for w in warns: print("  ! ", w)
for i, r in skipped: print(f"  - skip {i}: {r}")

# --- gate: existing translations are not overwritten without confirmation ---
# extract.sh records existing_target from the baseline. A unit with one already has SOME
# value in the target locale — template-prepopulated or from a prior run. Writing over it
# without the operator seeing what is being replaced is exactly the silent-clobber this DoD
# line exists to prevent. Identical old==new is not a real overwrite; skip those.
overwrites = [u for u in ready
              if (u.get('existing_target') or '').strip()
              and (u.get('existing_target') or '').strip() != (u.get('target') or '').strip()]
if overwrites:
    print(f"\n== {len(overwrites)} unit(s) already have a {TGT} value that this run would replace ==")
    for u in overwrites[:20]:
        print(f"    {u['id']}")
        print(f"      existing: {u['existing_target']!r}")
        print(f"      new     : {u['target']!r}")
    if len(overwrites) > 20:
        print(f"    … and {len(overwrites) - 20} more")
    if COMMIT and not CONFIRM_OVERWRITES:
        print("\n  BLOCKED — re-run with --confirm-overwrites once a human has reviewed the "
              "list above.\n"
              "  This is not optional: a template-derived landing ships pre-translated, and "
              "the existing value may be a stale mistranslation OR the last thing a human set on "
              "purpose. Either way it must be a deliberate choice to replace it, not a side "
              "effect of running this script.")
        sys.exit(1)

# --- blocks (surface B): the localization store, NOT update-block -----------
# Block text is referenced by an "L:" id; the text lives in a separate store keyed by the
# slug. Patching ["values","title"] via update-block returns ok:true and changes nothing.
# update-many-localization writes one locale in a single call, scoped by page id / "common".
blk = [u for u in ready if u['surface'] == 'block']
per_scope = collections.defaultdict(dict)
for u in blk:
    # The per-id value MUST be {"translation": ...}. A bare string, or any other key
    # (value/text/translations), returns 200 and writes an EMPTY string.
    per_scope[u['scope']][u['lid']] = {"translation": u['target']}

print(f"\n== blocks: {len(blk)} strings across {len(per_scope)} scope(s) -> {TGT} ==")
if per_scope:
    payload = {"locale": TGT, "perScopeValues": {k: v for k, v in per_scope.items()}}
    save("localization.request.json", payload)
    for scope, ids in per_scope.items():
        print(f"    scope {scope}: {len(ids)} string(s)")
    run([XS, 'shopbuilder', 'update-many-localization', '--slug', DOMAIN,
         '--data', json.dumps(payload, ensure_ascii=False)], 'localization')

# --- catalog (surface C) ----------------------------------------------------
# TWO replace-semantics traps, both silent:
#   1. Locale maps are REPLACED, not merged: send the full map or the source language is
#      dropped from the store, with a success response.
#   2. The ENTITY is replaced too. update-items exposes --prices, --groups, --is-enabled,
#      --is-show-in-store, --image-url, --is-free, --vc-prices. Omitting them on a
#      name/description write is how a translation pass unlists items and drops prices.
#      Everything below is carried through verbatim from the baseline.
CMD = {'virtual_item':             ('update-items',                  '--item-sku'),
       'bundle':                   ('admin-update-bundles',          '--bundle-sku'),
       'virtual_currency_package': ('admin-update-currency-package', '--package-sku')}
I18N_ENTITY = {
    'virtual_item': 'items',
    'bundle': 'bundle',
    'virtual_currency_package': 'vc_package',
    'item_group': 'groups',
}
cat = [u for u in ready if u['surface'] == 'catalog']
by_sku = collections.defaultdict(dict)
for u in cat: by_sku[(u['entity_type'], u['sku'])][u['field']] = u

def groups_of(e):
    """Baseline groups may be external-id strings or objects. --groups wants external ids."""
    out = []
    for g in e.get('groups') or []:
        if isinstance(g, str): out.append(g)
        elif isinstance(g, dict):
            gid = g.get('external_id') or g.get('externalId') or g.get('id')
            if gid: out.append(gid)
    return out

# The three update commands do NOT share a flag surface. Sending a flag the command does not
# define is a hard "unknown flag" failure; omitting one it DOES define silently drops that
# field, because the entity is replaced. Both directions are bugs, so gate on the real list.
#   update-items                  has --is-free, --is-show-in-store, --vc-prices; no --content
#   admin-update-bundles          has --content, --vc-prices; NO --is-free/--is-show-in-store
#   admin-update-currency-package has --content, --is-show-in-store; no --is-free/--vc-prices
SUPPORTED = {
  'update-items':                  {'prices','vc_prices','groups','image_url','is_enabled','is_free','is_show_in_store'},
  'admin-update-bundles':          {'prices','vc_prices','groups','image_url','is_enabled','content'},
  'admin-update-currency-package': {'prices','groups','image_url','is_enabled','is_show_in_store','content'},
}

def carry(e, args, sku, warns_out, cmd='update-items'):
    """Re-send every replaceable field from the baseline. A field we cannot reconstruct is a
    BLOCKING error, not a warning: omitting it is precisely the destructive case."""
    ok = SUPPORTED.get(cmd, SUPPORTED['update-items'])
    prices = e.get('prices')
    if prices is None and isinstance(e.get('price'), dict):
        warns_out.append(f"{sku}: baseline has the CLIENT 'price' shape, not admin 'prices' — "
                         f"re-run snapshot.sh; refusing to write")
        return False
    if prices is not None and 'prices' in ok:
        args += ['--prices', json.dumps(prices, ensure_ascii=False)]
    vc = e.get('vc_prices') or e.get('virtual_prices')
    if vc and 'vc_prices' in ok: args += ['--vc-prices', json.dumps(vc, ensure_ascii=False)]
    g = groups_of(e)
    if g and 'groups' in ok: args += ['--groups', json.dumps(g, ensure_ascii=False)]
    if e.get('image_url') and 'image_url' in ok: args += ['--image-url', e['image_url']]
    # A bundle's contents are part of the entity it replaces. Not re-sending them on a
    # bundle/package update risks emptying the bundle.
    if 'content' in ok:
        c = e.get('content')
        if c:
            # READ shape != WRITE shape. get-bundles returns full nested entries
            # (name/description/item_id/type/...); --content accepts only {sku, quantity},
            # and sending the read shape back is rejected HTTP 422.
            slim = [{'sku': i['sku'], 'quantity': i.get('quantity', 1)}
                    for i in c if isinstance(i, dict) and i.get('sku')]
            if slim: args += ['--content', json.dumps(slim, ensure_ascii=False)]
        else:
            warns_out.append(f"{sku}: no 'content' in the baseline for a {cmd} write")
    # Booleans are sent explicitly as --flag=value; bare --flag cannot express false.
    for key, flag in (('is_enabled', '--is-enabled'), ('is_free', '--is-free'),
                      ('is_show_in_store', '--is-show-in-store')):
        if key in e and key in ok: args += [f"{flag}={'true' if e[key] else 'false'}"]
    return True

print(f"\n== catalog: {len(by_sku)} entities, {len(cat)} fields ==")
if by_sku:
    # These writes are live. Say so once, plainly, naming the project.
    prod = {x for x in os.environ.get('XSOLLA_PRODUCTION_PROJECT_IDS', '').replace(',', ' ').split() if x}
    print(f"  ** catalog has no sandbox — these writes go LIVE to project {P or '<unset>'} **")
    if P and P in prod:
        print("  BLOCKED: that project id is listed in XSOLLA_PRODUCTION_PROJECT_IDS")
        sys.exit(1)
    if COMMIT and not prod:
        print("  BLOCKED: set XSOLLA_PRODUCTION_PROJECT_IDS (comma-separated) before --commit")
        print("           so this run can prove it is not writing to a production catalog.")
        sys.exit(1)

cat_errors = []
for (etype, sku), fields in sorted(by_sku.items()):
    e = baseline_entities.get((etype, sku))
    if e is None:
        cat_errors.append(f"{etype} {sku}: absent from the baseline — cannot rebuild the full "
                          f"entity, and a partial write would drop prices/groups")
        continue
    # description is mandatory on item/bundle/package PUTs. Groups have no long_description
    # and often no description — do not invent one.
    if etype != 'item_group':
        d = fields.get('description')
        if not (d and d.get('source', '').strip() and d.get('target', '').strip()):
            cat_errors.append(f"{etype} {sku}: description is mandatory in every locale sent, and "
                              f"is missing/empty. Author an English description first — this "
                              f"script will not invent one")
            continue

    obj = dict(e)
    merged = {}
    kept = set()
    for f, u in sorted(fields.items()):
        if f not in ('name', 'description', 'long_description'):
            print(f"  ! {sku}.{f}: not a localizable catalog field; skipped")
            continue
        cur = obj.get(f) if isinstance(obj.get(f), dict) else {}
        m = {short_locale(k): v for k, v in cur.items()
             if isinstance(v, str) and v.strip()}
        kept |= set(m) - {short_locale(SRC), short_locale(TGT)}
        m[short_locale(SRC)] = u['source']
        m[short_locale(TGT)] = u['target']
        obj[f] = merged[f] = m

    ikey = I18N_ENTITY.get(etype)
    if ikey:
        body = i18n._put_body(i18n.ENTITIES[ikey], obj, merged, allow_field_loss=False)
        dropped = i18n._dropped(i18n.ENTITIES[ikey], obj, False)
        save(f"catalog.put.{etype}.{sku}.json",
             {"entity": ikey, "id": sku, "dropped": dropped, "body": body})
        ld = "long_description" in merged
        print(f"  PUT {etype} {sku} via catalog_i18n pass-through"
              + (" +long_description" if ld else "")
              + (f"  (preserving {', '.join(sorted(kept))})" if kept else "")
              + (f"  !! would drop {dropped}" if dropped else ""))

    if etype not in CMD:
        # CLI cannot write item groups; the Admin PUT body above is the write path.
        # apply.sh --commit still does not call Store HTTP (no live writes from this
        # script). Live group writes: catalog_i18n.py import --write after preview.
        print(f"  {etype} {sku}: no CLI update command — Admin PUT body saved; "
              f"do not import --write unless live catalog writes are explicitly allowed")
        continue

    cmd, skuflag = CMD[etype]
    args = [XS, 'catalog', cmd, skuflag, sku, '--sku', sku]
    if M: args += ['--merchant-id', M]
    if P: args += ['--project-id', P]
    w = []
    if not carry(e, args, sku, w, cmd):
        cat_errors.extend(w); continue
    for f in ('name', 'description'):
        if f in merged:
            args += [f'--{f}', json.dumps(merged[f], ensure_ascii=False)]
    if 'long_description' in merged:
        print(f"  {sku}.long_description: no CLI flag; carried in catalog.put.*.json only")
    print(f"  {etype} {sku}" + (f"  (preserving {', '.join(sorted(kept))})" if kept else ""))
    run(args, f"catalog.{etype}.{sku}", sandbox=False)

if cat_errors:
    print("\n  BLOCKED — catalog writes not attempted:")
    for e in cat_errors: print("    x", e)
    if COMMIT: sys.exit(1)

# --- reconciliation ---------------------------------------------------------
rc = 0
if REPORT:
    print("\n== coverage of the translation FILE ==")
    missing = [u['id'] for u in units if u['kind'] != 'legal' and not u.get('target')]
    print(f"  units without a translation: {len(missing)}")
    for m in missing[:20]: print("    -", m)
    if len(missing) > 20: print(f"    … and {len(missing)-20} more")
    # Everything above inspects a file on disk. It passes identically whether or not a
    # single word reached the store, so it is NOT verification — every incorrect write in
    # this system returns success. Hand off to the script that asks the store itself.
    if COMMIT:
        print("\n== reading the store back ==")
        rc = subprocess.run(['bash', os.path.join(os.environ['SCRIPTDIR'], 'verify.sh'),
                             DOMAIN, TGT]).returncode
    else:
        print(f"\n  dry run — nothing was written, so there is nothing to read back.")
        print(f"  After --commit, verify against the live store:")
        print(f"    scripts/verify.sh {DOMAIN} {TGT}")

print(f"\npayloads -> {PAYDIR}")
if not COMMIT:
    print(f"DRY RUN — nothing was sent. On --commit the shop will open in {TGT}, preview included.")
    print("Review the payloads, then re-run with --commit.")
else:
    # The landing has no default-locale field. Preview opens in languages[0], and
    # add-language only appends, so a finished translation still opens in whatever
    # was already first (Italian, English, …) until this runs.
    print(f"\n== opening language: the shop, and preview, will open in {TGT} ==")
    opened = subprocess.run(
        ['bash', os.path.join(os.environ['SCRIPTDIR'], 'set-opening-language.sh'), DOMAIN, TGT])
    if opened.returncode != 0:
        print(f"FAILED — copy may be written, but preview will not open in {TGT}.")
        sys.exit(opened.returncode or 1)
    print(f"NOT DONE YET — a write returning ok:true proves nothing here. Read it back:")
    print(f"    scripts/verify.sh {DOMAIN} {TGT}")
    print(f"  Do not tell the publisher it worked unless that report says the shop opens in {TGT}.")
sys.exit(rc)
PY
