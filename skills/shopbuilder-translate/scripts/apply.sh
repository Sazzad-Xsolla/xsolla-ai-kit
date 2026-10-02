#!/usr/bin/env bash
# apply.sh <domain> <target-locale> [--commit] [--report] [--confirm-overwrites]
#
# Shop Builder page copy only. Catalog and LiveOps belong to the localization skill.
# Default is a DRY RUN: builds and saves every payload, sends nothing.
#   --commit              write page copy. Does not change the language the shop opens in.
#                         Before the first write, runs shop-builder-assembly backup_shop.py
#                         in identity mode (merchant, project, environment=test), which
#                         checks the approved-test-project allowlist first.
#   --report              reconcile the localization store against translated.json
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
import json, os, re, subprocess, sys, collections, time

DOMAIN, TGT, WORK = os.environ['DOMAIN'], os.environ['TGT'], os.environ['WORK']
COMMIT, REPORT = os.environ['COMMIT'] == '1', os.environ['REPORT'] == '1'
CONFIRM_OVERWRITES = os.environ['CONFIRM_OVERWRITES'] == '1'
XS = os.environ.get('XSOLLA_CLI', 'xsolla')
M  = os.environ.get('XSOLLA_MERCHANT_ID', ''); P = os.environ.get('XSOLLA_PROJECT_ID', '')

doc   = json.load(open(WORK))
SRC   = doc['meta']['source_locale']
units = doc['units']

# STALENESS GATE. translated.json is produced from ONE backup. If a newer backup exists
# under l10n/backup, these translations describe a store that has since changed.
BASE = doc['meta'].get('baseline')
try:
    import glob
    snaps = sorted(d for d in glob.glob('l10n/backup/*/') if os.path.isdir(d))
except Exception:
    snaps = []
if snaps and BASE:
    newest = snaps[-1].rstrip('/')
    if os.path.normpath(BASE) != os.path.normpath(newest):
        print(f"BLOCKED — stale translations.\n"
              f"  translated.json was built from : {os.path.normpath(BASE)}\n"
              f"  newest backup is              : {newest}\n"
              f"  Re-run extract.sh against the newest backup and re-translate, or delete\n"
              f"  the stale l10n/work/<locale>/ directory. Applying these would write copy\n"
              f"  for a version of the store that no longer exists.")
        sys.exit(1)
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

def backup_before_write():
    """Allowlist, then a read-only backup, before the first write. Not a production denylist."""
    if not COMMIT:
        return
    allow = os.environ.get('XSOLLA_APPROVED_TEST_PROJECTS', '').strip()
    if not allow or not os.path.isfile(allow):
        print("BLOCKED — set XSOLLA_APPROVED_TEST_PROJECTS to the approved-test-project "
              "allowlist JSON before any write. A production denylist is not a substitute. "
              "Nothing was written.")
        sys.exit(1)
    if not M or not P:
        print("BLOCKED — XSOLLA_MERCHANT_ID and XSOLLA_PROJECT_ID are required before a write.")
        sys.exit(1)
    script = os.environ.get('L10N_BACKUP_SHOP') or os.path.normpath(os.path.join(
        os.environ['SCRIPTDIR'], '..', '..', 'shop-builder-assembly', 'scripts', 'backup_shop.py'))
    if not os.path.isfile(script):
        print(f"BLOCKED — shop-builder-assembly backup_shop.py not found at {script}. "
              "Nothing was written.")
        sys.exit(1)
    out = os.path.abspath(os.path.join('l10n', 'pre-write', time.strftime('%Y%m%d-%H%M%S')))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    cmd = [sys.executable, script,
           '--merchant-id', str(M), '--project-id', str(P),
           '--environment', 'test',
           '--approved-test-projects', allow,
           '--slug', DOMAIN, '--output-dir', out]
    print("\n== backup before write (approved-test-project allowlist) ==")
    print("   ", " ".join(cmd))
    r = subprocess.run(cmd)
    if r.returncode != 0:
        print("BLOCKED — backup_shop.py failed the allowlist or the export. Nothing was written.")
        sys.exit(r.returncode or 1)
    print(f"  backup -> {out}")

backup_before_write()

# --- blocks (surface B): the localization store, NOT update-block -----------
# Block text is referenced by an "L:" id; the text lives in a separate store keyed by the
# slug. update-block on ["values","title"] deletes that string and every translation of it,
# and the call still returns 200. It does not leave the block unchanged.
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
    print("DRY RUN — nothing was sent. --commit writes the copy and does not change the language the shop opens in.")
    print("Review the payloads, then re-run with --commit.")
else:
    print("\nCopy was written. This run did not change the language the shop opens in.")
    print("The shop opens in the first language of the site language list.")
    print("To open in another language, reorder that list in Publisher Account.")
    print("A write returning ok:true proves nothing. Read it back:")
    print(f"    scripts/verify.sh {DOMAIN} {TGT}")
sys.exit(rc)
PY
