#!/usr/bin/env python3
"""Build a shop-builder-assembly brief from a listing-import result.

The boundary is intentionally narrow: store media and reviews never cross it.
listing-import creates the catalog first; this adapter carries only style tokens,
game name, plain-text description, and verified catalog references into assembly.
"""

from __future__ import annotations

import argparse
import html
from html.parser import HTMLParser
import json
import re
import sys
from pathlib import Path

from validate_shop_brief import validate

SOURCES = {"steam", "google_play", "app_store"}
CATALOG_STATUSES = {"created", "empty"}
STYLE_KEYS = {"colors", "fonts"}
URL_RE = re.compile(r"(?:https?://|data:)", re.IGNORECASE)
BB_IMAGE_RE = re.compile(r"\[img\].*?\[/img\]", re.IGNORECASE | re.DOTALL)
BB_TAG_RE = re.compile(r"\[/?[a-z][^\]]*\]", re.IGNORECASE)


class _TextOnlyParser(HTMLParser):
    """Collect visible text while discarding media and executable content."""

    SKIP_CONTAINERS = {"script", "style", "video", "audio", "picture"}
    SKIP_VOID = {"source", "img"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self.skip_depth = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() in self.SKIP_CONTAINERS:
            self.skip_depth += 1
        elif tag.lower() in self.SKIP_VOID:
            return
        elif not self.skip_depth and tag.lower() in {"p", "br", "li", "h1", "h2", "h3"}:
            self.parts.append("\n")

    def handle_startendtag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        if not self.skip_depth and tag.lower() == "br":
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() in self.SKIP_CONTAINERS and self.skip_depth:
            self.skip_depth -= 1
        elif not self.skip_depth and tag.lower() in {"p", "li", "h1", "h2", "h3"}:
            self.parts.append("\n")

    def handle_data(self, data: str) -> None:
        if not self.skip_depth:
            self.parts.append(data)


def _load(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read valid JSON from {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def _clean_text(value: str, form: str) -> str:
    if form == "html":
        parser = _TextOnlyParser()
        parser.feed(value)
        parser.close()
        text = "".join(parser.parts)
    elif form == "bbcode":
        text = BB_TAG_RE.sub("", BB_IMAGE_RE.sub("", value))
    else:
        text = value
    lines = [" ".join(line.split()) for line in html.unescape(text).splitlines()]
    return "\n\n".join(line for line in lines if line)


def listing_description(fields: dict) -> str | None:
    candidates = (
        ("long_description_text", "text"),
        ("long_description_html", "html"),
        ("long_description_bbcode", "bbcode"),
        ("short_description", "text"),
    )
    for key, form in candidates:
        value = fields.get(key)
        if isinstance(value, str) and value.strip():
            cleaned = _clean_text(value, form)
            if cleaned:
                return cleaned
    return None


def _style(context: dict) -> dict:
    value = context.get("style", {})
    if not isinstance(value, dict):
        raise ValueError("context.style must be an object")
    unknown = sorted(set(value) - STYLE_KEYS)
    if unknown:
        raise ValueError("context.style supports only colors and fonts")
    result: dict = {}
    for key in sorted(STYLE_KEYS):
        tokens = value.get(key)
        if tokens is None:
            continue
        if not isinstance(tokens, dict) or any(
            not isinstance(name, str)
            or not name.strip()
            or not isinstance(token, str)
            or not token.strip()
            or URL_RE.search(token)
            for name, token in tokens.items()
        ):
            raise ValueError(
                f"context.style.{key} must be an object of non-URL string tokens"
            )
        result[key] = dict(sorted(tokens.items()))
    return result


def _catalog(context: dict) -> tuple[list[dict], list[str]]:
    result = context.get("catalog_result")
    if not isinstance(result, dict):
        raise ValueError("context.catalog_result must be an object")
    status = result.get("status")
    if status not in CATALOG_STATUSES:
        raise ValueError("context.catalog_result.status must be created or empty")
    skus = result.get("created_skus", [])
    if not isinstance(skus, list) or any(
        not isinstance(sku, str) or not sku.strip() for sku in skus
    ):
        raise ValueError("context.catalog_result.created_skus must be strings")
    if len(skus) != len(set(skus)):
        raise ValueError("context.catalog_result.created_skus must be unique")
    if status == "empty":
        if skus or result.get("group_external_id"):
            raise ValueError("an empty catalog result cannot contain a group or SKUs")
        return [], []
    group = result.get("group_external_id")
    if not isinstance(group, str) or not group.strip():
        raise ValueError("a created catalog result requires group_external_id")
    return [
        {
            "external_id": group,
            "type": "virtual_good",
            "placement": "primary",
        }
    ], skus


def build_brief(listing: dict, context: dict) -> dict:
    source = listing.get("source")
    if source not in SOURCES:
        raise ValueError("listing.source must be steam, google_play, or app_store")
    if listing.get("rights_confirmed") is not True:
        raise ValueError("listing.rights_confirmed must be true")
    fields = listing.get("fields")
    if not isinstance(fields, dict):
        raise ValueError("listing.fields must be an object")
    title = fields.get("title")
    if not isinstance(title, str) or not title.strip():
        raise ValueError("listing.fields.title is required")

    project = context.get("project")
    site = context.get("site")
    if not isinstance(project, dict) or not isinstance(site, dict):
        raise ValueError("context.project and context.site must be objects")
    project = dict(project)
    if context.get("test_project_acknowledged") is not None:
        project["test_project_acknowledged"] = context["test_project_acknowledged"]
    groups, skus = _catalog(context)
    platforms = ["pc"] if source == "steam" else ["mobile"]
    game_context = context.get("game", {})
    if not isinstance(game_context, dict):
        raise ValueError("context.game must be an object")
    if "platforms" in game_context:
        platforms = game_context["platforms"]

    description = listing_description(fields)
    content = (
        {"description": {"text": description, "status": "imported-store-listing"}}
        if description
        else {}
    )
    brief = {
        "version": 1,
        "project": project,
        "game": {
            "name": title.strip(),
            "platforms": platforms,
            "lifecycle": game_context.get("lifecycle", "evergreen"),
        },
        "site": site,
        "catalog": {"groups": groups, "featured_skus": skus},
        "brand": _style(context),
        "content": content,
        "sources": [
            {
                "kind": "external_store",
                "source": source,
                "url": listing.get("source_url", ""),
            }
        ],
    }
    errors = validate(brief)
    if errors:
        raise ValueError("generated shop brief is invalid: " + "; ".join(errors))

    return brief


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--listing", type=Path, required=True)
    parser.add_argument("--context", type=Path, required=True)
    parser.add_argument(
        "--catalog-result",
        type=Path,
        required=True,
        help="trusted result written by listing-import's catalog step",
    )
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        context = _load(args.context)
        context["catalog_result"] = _load(args.catalog_result)
        brief = build_brief(_load(args.listing), context)
        rendered = json.dumps(brief, indent=2, ensure_ascii=False) + "\n"
        if args.output:
            args.output.write_text(rendered, encoding="utf-8")
        else:
            sys.stdout.write(rendered)
        return 0
    except (OSError, ValueError) as exc:
        print(f"Listing handoff failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
