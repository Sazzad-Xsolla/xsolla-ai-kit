"""Tests for turning in-app items into catalog entities."""

from __future__ import annotations

import json
import os
import shlex
import tempfile
import unittest

from xsolla_listing_import import catalog


class TestSkus(unittest.TestCase):

    def test_slug_is_catalog_safe(self):
        self.assertEqual(catalog.slugify("Pocketful of Gems!"), "pocketful_of_gems")
        self.assertEqual(catalog.slugify("1,200 Gems"), "1_200_gems")

    def test_source_prefix(self):
        skus = catalog.build_skus([{"name": "Gems"}], "app_store")
        self.assertTrue(skus[0].startswith("ios_"))

    def test_duplicate_names_are_broken_by_price(self):
        """Real case: the App Store lists Gold Pass at $4.99 and $6.99."""
        items = [{"name": "Gold Pass", "price": {"amount": 4.99, "currency": "USD"}},
                 {"name": "Gold Pass", "price": {"amount": 6.99, "currency": "USD"}}]
        skus = catalog.build_skus(items, "app_store")
        self.assertEqual(len(set(skus)), 2)
        self.assertIn("6_99_usd", skus[1])

    def test_duplicate_names_with_no_price_still_unique(self):
        items = [{"name": "Offer"}, {"name": "Offer"}, {"name": "Offer"}]
        skus = catalog.build_skus(items, "steam")
        self.assertEqual(len(set(skus)), 3)

    def test_skus_are_stable_across_runs(self):
        items = [{"name": "Gold Pass", "price": {"amount": 4.99, "currency": "USD"}}]
        self.assertEqual(catalog.build_skus(items, "app_store"),
                         catalog.build_skus(items, "app_store"))

    def test_an_unnamed_item_still_gets_a_sku(self):
        self.assertTrue(catalog.build_skus([{}], "steam")[0])

    def test_a_long_name_is_truncated_without_a_trailing_underscore(self):
        sku = catalog.build_skus([{"name": "x " * 60}], "steam")[0]
        self.assertFalse(sku.endswith("_"))


class TestOperations(unittest.TestCase):

    def test_everything_is_a_virtual_item(self):
        """Never a currency package or a bundle: no source publishes quantity."""
        ops, _w = catalog.build_operations(
            [{"name": "Pocketful of Gems", "price": {"amount": 0.99,
                                                     "currency": "USD"}}],
            "app_store")
        self.assertEqual(ops[0]["entity"], "virtual_item")
        self.assertNotIn("content", ops[0])

    def test_a_priced_item_is_enabled(self):
        ops, _w = catalog.build_operations(
            [{"name": "Gems", "price": {"amount": 0.99, "currency": "USD"}}], "steam")
        self.assertTrue(ops[0]["is_enabled"])
        self.assertTrue(ops[0]["is_show_in_store"])

    def test_an_unpriced_item_is_created_disabled_and_warned_about(self):
        ops, warnings = catalog.build_operations([{"name": "Mystery Offer"}], "steam")
        self.assertFalse(ops[0]["is_enabled"])
        self.assertEqual(ops[0]["prices"], [])
        self.assertTrue(any("no price" in w for w in warnings))

    def test_every_item_is_flagged_for_review(self):
        ops, _w = catalog.build_operations([{"name": "Gems"}], "steam")
        self.assertTrue(ops[0]["needs_review"])
        self.assertIn("does not publish", ops[0]["review_reason"])

    def test_the_quantity_limitation_is_always_stated(self):
        _ops, warnings = catalog.build_operations([{"name": "Gems"}], "steam")
        self.assertTrue(any("quantity" in w for w in warnings))

    def test_no_items_means_no_operations_and_no_warnings(self):
        self.assertEqual(catalog.build_operations([], "steam"), ([], []))

    def test_price_shape_matches_the_documented_cli_array(self):
        ops, _w = catalog.build_operations(
            [{"name": "Gems", "price": {"amount": 9.99, "currency": "USD"}}], "steam")
        self.assertEqual(ops[0]["prices"], [{"amount": 9.99, "currency": "USD",
                                             "is_default": True,
                                             "is_enabled": True}])


class TestRenderedCommands(unittest.TestCase):

    def _render(self, name):
        ops, _w = catalog.build_operations(
            [{"name": name, "price": {"amount": 59.99, "currency": "EUR"}}], "steam")
        return catalog.render_commands(ops)

    def test_the_group_is_created_before_the_items(self):
        text = self._render("Gems")
        self.assertLess(text.index("admin-create-group"), text.index("create-items"))

    def test_an_apostrophe_in_a_title_does_not_break_the_quoting(self):
        """A title with an apostrophe is the common case, not an edge case."""
        text = self._render("Example Studio's Game - Standard Edition")
        command = text.split("\n\n")[1].replace("\\\n", " ")
        tokens = shlex.split(command)
        payload = json.loads(tokens[tokens.index("--name") + 1])
        self.assertEqual(payload["en"], "Example Studio's Game - Standard Edition")

    def test_a_double_quote_in_a_title_survives_too(self):
        text = self._render('The "Best" Game')
        command = text.split("\n\n")[1].replace("\\\n", " ")
        tokens = shlex.split(command)
        payload = json.loads(tokens[tokens.index("--name") + 1])
        self.assertEqual(payload["en"], 'The "Best" Game')

    def test_non_ascii_is_not_escaped_into_mojibake(self):
        text = self._render("Example Game®")
        self.assertIn("®", text)

    def test_an_unpriced_item_renders_without_the_prices_flag(self):
        ops, _w = catalog.build_operations([{"name": "Mystery"}], "steam")
        item = catalog.render_commands(ops).split("\n\n")[1]
        self.assertNotIn("--prices", item)
        self.assertIn("--is-enabled=false", item)
        self.assertIn("--is-show-in-store=false", item)


class FakeCatalogCli:
    def __init__(self, answers=None):
        self.calls = []
        self.answers = answers or {}

    def __call__(self, action, args):
        self.calls.append((action, list(args)))
        answer = self.answers.get(action)
        if isinstance(answer, list):
            return answer.pop(0)
        return answer or {"code": 0, "stdout": "{}", "stderr": ""}


class TestCatalogExecution(unittest.TestCase):

    def operations(self, count=1, priced=True):
        items = []
        for index in range(count):
            item = {"name": "Pack %d" % index}
            if priced:
                item["price"] = {"amount": 1.99, "currency": "USD"}
            items.append(item)
        return catalog.build_operations(items, "steam")[0]

    def test_rehearsal_calls_nothing(self):
        cli = FakeCatalogCli()
        outcome = catalog.apply_operations(self.operations(), 1, 2, call=cli)
        self.assertEqual([], cli.calls)
        self.assertEqual("planned", outcome["status"])
        self.assertIsNone(outcome["catalog_result"])

    def test_success_creates_group_then_items_and_builds_result(self):
        cli = FakeCatalogCli()
        outcome = catalog.apply_operations(
            self.operations(2), 1, 2, confirmed=True, call=cli
        )
        self.assertEqual(["admin-create-group", "create-items", "create-items"],
                         [call[0] for call in cli.calls])
        self.assertEqual("created", outcome["catalog_result"]["status"])
        self.assertEqual(2, len(outcome["catalog_result"]["created_skus"]))

    def test_false_item_flags_are_explicit(self):
        cli = FakeCatalogCli()
        catalog.apply_operations(
            self.operations(priced=False), 1, 2, confirmed=True, call=cli
        )
        args = [args for action, args in cli.calls if action == "create-items"][0]
        self.assertIn("--is-enabled=false", args)
        self.assertIn("--is-show-in-store=false", args)

    def test_sku_422_stops_and_produces_no_result(self):
        exists = {
            "code": 1,
            "stdout": "",
            "stderr": '{"code":"http_422","message":"SKU already exists"}',
        }
        cli = FakeCatalogCli({
            "create-items": [exists, {"code": 0, "stdout": "{}", "stderr": ""}]
        })
        outcome = catalog.apply_operations(
            self.operations(2), 1, 2, confirmed=True, call=cli
        )
        self.assertEqual(1, [call[0] for call in cli.calls].count("create-items"))
        self.assertEqual("failed", outcome["status"])
        self.assertIsNone(outcome["catalog_result"])
        self.assertIn("without reusing", outcome["failed"][0]["reason"])

    def test_empty_catalog_has_a_trusted_empty_result(self):
        outcome = catalog.apply_operations([], None, None, confirmed=True)
        self.assertEqual({"status": "empty", "created_skus": []},
                         outcome["catalog_result"])

    def test_result_writer_replaces_the_target(self):
        result = {"status": "created", "group_external_id": "g",
                  "created_skus": ["one"]}
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "catalog-result.json")
            catalog.write_result(path, result)
            with open(path, encoding="utf-8") as handle:
                self.assertEqual(result, json.load(handle))
            self.assertFalse(os.path.exists(path + ".tmp"))


if __name__ == "__main__":
    unittest.main()
