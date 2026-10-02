#!/usr/bin/env python3
"""Offline stand-in for shop-builder-assembly backup_shop.py. Smoke tests only."""
import json
import sys
from pathlib import Path

args = sys.argv[1:]
env_name = allow = out = ""
i = 0
while i < len(args):
    if args[i] == "--environment" and i + 1 < len(args):
        env_name = args[i + 1]
        i += 2
    elif args[i] == "--approved-test-projects" and i + 1 < len(args):
        allow = args[i + 1]
        i += 2
    elif args[i] == "--output-dir" and i + 1 < len(args):
        out = args[i + 1]
        i += 2
    else:
        i += 1

if env_name != "test":
    print("environment must be test", file=sys.stderr)
    sys.exit(1)
if not allow or not Path(allow).is_file():
    print("allowlist missing", file=sys.stderr)
    sys.exit(1)
if not out:
    print("output-dir required", file=sys.stderr)
    sys.exit(1)
dest = Path(out)
dest.mkdir(parents=True, exist_ok=True)
(dest / "manifest.json").write_text(
    json.dumps({"read_only": True, "environment": "test"}) + "\n", encoding="utf-8"
)
print(dest.resolve())
