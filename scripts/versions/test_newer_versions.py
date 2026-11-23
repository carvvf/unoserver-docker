"""Offline tests of the newer-release decision; no Docker or network needed.

Run from the repository root: python3 -m unittest scripts.versions.test_newer_versions
"""

import json
import unittest

from scripts.versions.newer_versions import (
    CheckError,
    describe_apk_upgrades,
    parse_apk_upgradable,
    parse_base_image,
    parse_pip_report,
    parse_unoserver_requirement,
    stale_base_platforms,
)

DOCKERFILE = """FROM eclipse-temurin:27-jre-alpine-3.24

ARG UID=worker
ARG UNOSERVER_MAJOR=3
"""


class DockerfileTest(unittest.TestCase):
    def test_base_image_is_the_first_from(self):
        self.assertEqual(parse_base_image(DOCKERFILE), "eclipse-temurin:27-jre-alpine-3.24")

    def test_base_image_ignores_a_platform_flag(self):
        self.assertEqual(parse_base_image("FROM --platform=$BUILDPLATFORM alpine:3.24 AS x\n"), "alpine:3.24")

    def test_missing_from_is_an_error(self):
        with self.assertRaises(CheckError):
            parse_base_image("ARG X=1\n")

    def test_requirement_follows_the_major(self):
        self.assertEqual(parse_unoserver_requirement(DOCKERFILE), "unoserver==3.*")

    def test_missing_major_is_an_error(self):
        with self.assertRaises(CheckError):
            parse_unoserver_requirement("FROM alpine:3.24\n")


class BaseLayersTest(unittest.TestCase):
    BASE = {"linux/amd64": ["a1", "a2"], "linux/arm64": ["b1", "b2"]}

    def test_current_base_is_not_stale(self):
        image = {"linux/amd64": ["a1", "a2", "x"], "linux/arm64": ["b1", "b2", "y"]}
        self.assertEqual(stale_base_platforms(self.BASE, image), [])

    def test_changed_base_layer_is_stale(self):
        image = {"linux/amd64": ["a1", "old", "x"], "linux/arm64": ["b1", "b2", "y"]}
        self.assertEqual(stale_base_platforms(self.BASE, image), ["linux/amd64"])

    def test_platform_missing_from_base_is_an_error(self):
        with self.assertRaises(CheckError):
            stale_base_platforms({"linux/amd64": ["a1"]}, {"linux/arm64": ["b1"]})

    def test_image_without_platforms_is_an_error(self):
        with self.assertRaises(CheckError):
            stale_base_platforms(self.BASE, {})


class PipReportTest(unittest.TestCase):
    def report(self, *items):
        return json.dumps({"install": [{"metadata": {"name": n, "version": v}} for n, v in items]})

    def test_resolved_version(self):
        self.assertEqual(parse_pip_report(self.report(("unoserver", "3.8"))), "3.8")

    def test_name_is_case_insensitive(self):
        self.assertEqual(parse_pip_report(self.report(("Unoserver", "3.8"))), "3.8")

    def test_no_resolution_is_an_error(self):
        with self.assertRaises(CheckError):
            parse_pip_report(self.report())

    def test_malformed_report_is_an_error(self):
        with self.assertRaises(CheckError):
            parse_pip_report("not json")


class ApkTest(unittest.TestCase):
    LINE = (
        "font-noto-2026.11.01-r0 x86_64 {font-noto} (OFL-1.1) "
        "[upgradable from: font-noto-2026.06.01-r0]"
    )

    def test_no_upgrades(self):
        self.assertEqual(parse_apk_upgradable("\n"), [])

    def test_upgrade_line(self):
        self.assertEqual(
            parse_apk_upgradable(self.LINE + "\n"),
            [("font-noto-2026.06.01-r0", "font-noto-2026.11.01-r0")],
        )

    def test_unexpected_line_is_an_error(self):
        with self.assertRaises(CheckError):
            parse_apk_upgradable("WARNING: something changed\n")

    def test_description_lists_the_first_upgrades_and_counts_the_rest(self):
        upgrades = [(f"p-{n}-r0", f"p-{n}-r1") for n in range(7)]
        text = describe_apk_upgrades(upgrades)
        self.assertTrue(text.startswith("7 Alpine package upgrades: p-0-r0 -> p-0-r1"))
        self.assertTrue(text.endswith("and 2 more"))


if __name__ == "__main__":
    unittest.main()
