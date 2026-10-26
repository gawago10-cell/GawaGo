"""The barangay list, skill catalog and city boundary exist once per layer:
the backend validates against its copy, the web and mobile apps render
theirs. They drifted before (31 barangays everywhere, three different
"inside Tayabas" checks), so these tests read the client source files and
fail when any copy differs from the backend's."""

import re
from pathlib import Path
from unittest import skipUnless

from django.conf import settings
from django.test import SimpleTestCase

from apps.common.barangays import BARANGAY_CENTERS
from apps.common.skills import OTHER_SKILL_CHOICE, SKILL_CATALOG
from apps.common.tayabas_boundary import TAYABAS_CITY_BOUNDARY, TAYABAS_TOWN_CENTER, is_inside_tayabas

REPO_ROOT = Path(settings.BASE_DIR)
WEB_CONSTANTS = REPO_ROOT / "frontend" / "src" / "constants" / "appConstants.js"
WEB_BOUNDARY = REPO_ROOT / "frontend" / "src" / "data" / "tayabasCityBoundary.js"
MOBILE_OPTIONS = REPO_ROOT / "mobile" / "lib" / "src" / "shared" / "constants" / "gawago_options.dart"
NUMBER = r"-?\d+(?:\.\d+)?"


def _block(source, start_pattern):
    match = re.search(start_pattern + r"(.*?)\n[\]}];", source, flags=re.S)
    if not match:
        raise AssertionError(f"Could not find {start_pattern!r}")
    return match.group(1)


def _strings(block):
    return re.findall(r"[\"']([^\"']+)[\"']", block)


@skipUnless(WEB_CONSTANTS.exists() and WEB_BOUNDARY.exists(), "web sources not checked out")
class WebReferenceDataTests(SimpleTestCase):
    def setUp(self):
        self.constants = WEB_CONSTANTS.read_text(encoding="utf-8")

    def test_barangays_match(self):
        web = _strings(_block(self.constants, r"export const BARANGAYS = \["))
        self.assertEqual(web, list(BARANGAY_CENTERS))

    def test_barangay_centres_match(self):
        block = _block(self.constants, r"export const BARANGAY_CENTERS = \{")
        rows = re.findall(
            rf"^\s*\"?([^\":\n]+?)\"?: \{{ latitude: ({NUMBER}), longitude: ({NUMBER}) \}},?$",
            block,
            flags=re.M,
        )
        web = {name: (float(lat), float(lng)) for name, lat, lng in rows}
        backend = {name: (point["latitude"], point["longitude"]) for name, point in BARANGAY_CENTERS.items()}
        self.assertEqual(web, backend)

    def test_skill_catalog_matches(self):
        block = _block(self.constants, r"export const SKILLS = \[")
        self.assertEqual(_strings(block), SKILL_CATALOG)
        self.assertRegex(block, r"OTHER_SKILL,\s*$")
        self.assertIn(f'export const OTHER_SKILL = "{OTHER_SKILL_CHOICE}";', self.constants)

    def test_town_centre_matches(self):
        match = re.search(
            rf"export const TAYABAS_CITY_CENTER = \{{ latitude: ({NUMBER}), longitude: ({NUMBER}) \}};",
            self.constants,
        )
        self.assertIsNotNone(match)
        self.assertEqual((float(match.group(1)), float(match.group(2))), TAYABAS_TOWN_CENTER)

    def test_boundary_matches(self):
        source = WEB_BOUNDARY.read_text(encoding="utf-8")
        points = [(float(lat), float(lng)) for lat, lng in re.findall(rf"\[({NUMBER}), ({NUMBER})\]", source)]
        self.assertEqual(points, [tuple(point) for point in TAYABAS_CITY_BOUNDARY])


@skipUnless(MOBILE_OPTIONS.exists(), "mobile sources not checked out")
class MobileReferenceDataTests(SimpleTestCase):
    def setUp(self):
        self.options = MOBILE_OPTIONS.read_text(encoding="utf-8")

    def test_barangays_match(self):
        mobile = _strings(_block(self.options, r"const List<String> gawagoBarangays = \["))
        self.assertEqual(mobile, list(BARANGAY_CENTERS))

    def test_barangay_centres_match(self):
        block = _block(self.options, r"gawagoBarangayCenters = \{")
        # dart format wraps the longer entries over several lines.
        rows = re.findall(
            rf"'([^']+)':\s*\(\s*latitude:\s*({NUMBER}),\s*longitude:\s*({NUMBER}),?\s*\),",
            block,
        )
        mobile = {name: (float(lat), float(lng)) for name, lat, lng in rows}
        backend = {name: (point["latitude"], point["longitude"]) for name, point in BARANGAY_CENTERS.items()}
        self.assertEqual(mobile, backend)

    def test_skill_catalog_matches(self):
        block = _block(self.options, r"const List<String> gawagoSkills = \[")
        self.assertEqual(_strings(block), SKILL_CATALOG)
        self.assertRegex(block, r"gawagoOtherSkill,\s*$")
        self.assertIn(f"const String gawagoOtherSkill = '{OTHER_SKILL_CHOICE}';", self.options)


class BoundaryTests(SimpleTestCase):
    def test_every_barangay_centre_is_inside_the_city(self):
        outside = [
            name
            for name, point in BARANGAY_CENTERS.items()
            if not is_inside_tayabas(point["latitude"], point["longitude"])
        ]
        self.assertEqual(outside, [])

    def test_barangay_centres_are_distinct(self):
        points = [(point["latitude"], point["longitude"]) for point in BARANGAY_CENTERS.values()]
        self.assertEqual(len(points), len(set(points)))

    def test_neighbouring_towns_are_outside(self):
        for town, (latitude, longitude) in {
            "Lucena City": (13.9373, 121.6170),
            "Lucban": (14.1131, 121.5566),
            "Sariaya": (13.9634, 121.5262),
            "Pagbilao": (13.9718, 121.6866),
        }.items():
            self.assertFalse(is_inside_tayabas(latitude, longitude), town)

    def test_town_centre_is_inside(self):
        self.assertTrue(is_inside_tayabas(*TAYABAS_TOWN_CENTER))

    def test_bad_input_is_outside(self):
        for latitude, longitude in ((None, None), ("", ""), ("abc", 121.6), (float("nan"), 121.6)):
            self.assertFalse(is_inside_tayabas(latitude, longitude))
