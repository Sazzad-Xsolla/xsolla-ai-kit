from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location(
    "build_listing_brief", SCRIPTS / "build_listing_brief.py"
)
assert spec and spec.loader
handoff = importlib.util.module_from_spec(spec)
spec.loader.exec_module(handoff)


def listing() -> dict:
    return {
        "source": "steam",
        "source_url": "https://store.steampowered.com/app/123/",
        "rights_confirmed": True,
        "fields": {
            "title": "Example Game",
            "long_description_html": (
                "<h2>Explore</h2><p>A large world.</p>"
                "<img src='https://media.invalid/key-art.jpg'>"
                "<script>steal()</script><p>Keep playing.</p>"
            ),
            "icon": "https://media.invalid/icon.jpg",
            "key_art": "https://media.invalid/key-art.jpg",
            "screenshots": ["https://media.invalid/shot.jpg"],
            "reviews": "4.8/5",
            "user_reviews": [{"quote": "Great", "attribution": "A player"}],
            "iap_items": [{"name": "Pack"}],
        },
    }


def context() -> dict:
    return {
        "project": {
            "merchant_id": 123,
            "project_id": 456,
            "environment": "sandbox",
        },
        "site": {
            "name": "Example Game Shop",
            "slug": "example-game-shop",
            "preset": "auto",
            "primary_locale": "en-US",
            "locales": ["en-US"],
        },
        "catalog_result": {
            "status": "created",
            "group_external_id": "imported_listing",
            "created_skus": ["steam_pack"],
        },
        "style": {
            "colors": {"primary": "#112233", "background": "#ffffff"},
            "fonts": {"heading": "Inter", "body": "Arial"},
        },
    }


class ListingHandoffTests(unittest.TestCase):
    def test_only_approved_listing_data_crosses_the_boundary(self) -> None:
        brief = handoff.build_brief(listing(), context())
        rendered = json.dumps(brief)
        self.assertEqual("Example Game", brief["game"]["name"])
        self.assertEqual(["pc"], brief["game"]["platforms"])
        self.assertEqual(context()["style"], brief["brand"])
        self.assertEqual(
            "Explore\n\nA large world.\n\nKeep playing.",
            brief["content"]["description"]["text"],
        )
        self.assertNotIn("media.invalid", rendered)
        self.assertNotIn("Great", rendered)
        self.assertNotIn("4.8/5", rendered)

    def test_catalog_result_becomes_group_and_featured_skus(self) -> None:
        brief = handoff.build_brief(listing(), context())
        self.assertEqual(
            [
                {
                    "external_id": "imported_listing",
                    "type": "virtual_good",
                    "placement": "primary",
                }
            ],
            brief["catalog"]["groups"],
        )
        self.assertEqual(["steam_pack"], brief["catalog"]["featured_skus"])

    def test_empty_catalog_result_omits_store_catalog_links(self) -> None:
        value = context()
        value["catalog_result"] = {"status": "empty", "created_skus": []}
        brief = handoff.build_brief(listing(), value)
        self.assertEqual([], brief["catalog"]["groups"])
        self.assertEqual([], brief["catalog"]["featured_skus"])

    def test_mobile_sources_choose_mobile(self) -> None:
        value = listing()
        value["source"] = "app_store"
        value["source_url"] = "https://apps.apple.com/app/id123"
        self.assertEqual(
            ["mobile"], handoff.build_brief(value, context())["game"]["platforms"]
        )

    def test_explicit_platform_and_lifecycle_override_safe_defaults(self) -> None:
        value = context()
        value["game"] = {"platforms": ["console"], "lifecycle": "launch"}
        brief = handoff.build_brief(listing(), value)
        self.assertEqual(["console"], brief["game"]["platforms"])
        self.assertEqual("launch", brief["game"]["lifecycle"])

    def test_dedicated_test_acknowledgement_crosses_the_boundary(self) -> None:
        value = context()
        value["project"]["environment"] = "test"
        value["test_project_acknowledged"] = True
        brief = handoff.build_brief(listing(), value)
        self.assertTrue(brief["project"]["test_project_acknowledged"])

    def test_equal_review_and_title_do_not_create_a_false_leak_failure(self) -> None:
        value = listing()
        value["fields"]["user_reviews"] = [{"quote": "Example Game"}]
        brief = handoff.build_brief(value, context())
        self.assertEqual("Example Game", brief["game"]["name"])

    def test_rights_are_required(self) -> None:
        value = listing()
        value["rights_confirmed"] = False
        with self.assertRaisesRegex(ValueError, "rights_confirmed"):
            handoff.build_brief(value, context())

    def test_catalog_must_have_completed_before_handoff(self) -> None:
        value = context()
        value["catalog_result"]["status"] = "planned"
        with self.assertRaisesRegex(ValueError, "created or empty"):
            handoff.build_brief(listing(), value)

    def test_created_catalog_requires_a_group(self) -> None:
        value = context()
        del value["catalog_result"]["group_external_id"]
        with self.assertRaisesRegex(ValueError, "group_external_id"):
            handoff.build_brief(listing(), value)

    def test_style_rejects_media_urls(self) -> None:
        value = context()
        value["style"]["colors"]["primary"] = "https://media.invalid/a.png"
        with self.assertRaisesRegex(ValueError, "non-URL"):
            handoff.build_brief(listing(), value)

    def test_style_rejects_unapproved_keys(self) -> None:
        value = context()
        value["style"]["logo"] = "anything"
        with self.assertRaisesRegex(ValueError, "only colors and fonts"):
            handoff.build_brief(listing(), value)

    def test_output_changes_when_catalog_result_changes(self) -> None:
        first = handoff.build_brief(listing(), context())
        changed = copy.deepcopy(context())
        changed["catalog_result"]["created_skus"].append("steam_pack_2")
        second = handoff.build_brief(listing(), changed)
        self.assertNotEqual(first, second)


if __name__ == "__main__":
    unittest.main()
