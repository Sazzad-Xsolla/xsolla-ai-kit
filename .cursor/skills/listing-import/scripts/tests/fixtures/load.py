"""Fixture loading.

Every fixture describes one fictional title, "Example Game" by "Example Studio",
so no third-party listing is needed to run or extend the suite.  The *shapes*
follow the live responses -- ``steam_appdetails.json`` mirrors the public
``appdetails`` envelope, ``appstore_lookup.json`` the iTunes ``lookup`` body,
``play_page.html`` the regions of a Play page the extractor reads, and
``steam_structure.json`` the 13-block spine that ``xsolla shopbuilder
import-listing`` produces on a fresh landing, trimmed to ids and module names.
``steam_listing.json`` is the ``listing.json`` the Steam extractor builds from
the first of those.  A fixture that disagrees with the code is a bug in one of
them; do not adjust it to agree.
"""

from __future__ import annotations

import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name):
    with open(os.path.join(HERE, name), "r", encoding="utf-8") as handle:
        return json.load(handle)


def steam_listing():
    return load("steam_listing.json")


def steam_structure():
    return load("steam_structure.json")


def steam_appdetails():
    """An ``appdetails`` response for the fictional title, keyed by its app id."""
    return load("steam_appdetails.json")


def appstore_lookup():
    """An iTunes ``lookup`` response for the fictional title."""
    return load("appstore_lookup.json")


def play_page():
    """A trimmed Play page for the fictional title.

    Every region the extractor reads, in the markup shape the live page uses --
    the ``og:`` meta tags, the developer and category links, the rating, the
    screenshot URLs, the price range and the whole ``data-g-id="description"``
    subtree.  A full page is over a megabyte, which is not a fixture.
    """
    with open(os.path.join(HERE, "play_page.html"), "r", encoding="utf-8") as handle:
        return handle.read()
