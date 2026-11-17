import unittest

from extract_release_notes import extract_release_notes


class ExtractReleaseNotesTest(unittest.TestCase):
    def test_returns_only_requested_version_section(self):
        changelog = """# Changelog

## 1.1.3 — 2026-11-17

- Current release change one.
- Current release change two.

## 1.1.2 — 2026-11-16

- Older release change.
"""

        self.assertEqual(
            extract_release_notes(changelog, "1.1.3"),
            "- Current release change one.\n- Current release change two.",
        )

    def test_version_match_is_exact(self):
        changelog = """## 1.1.30 — future

- Future release.

## 1.1.3 — current

- Current release.
"""

        self.assertEqual(
            extract_release_notes(changelog, "1.1.3"), "- Current release."
        )

    def test_missing_or_empty_version_section_fails(self):
        with self.assertRaisesRegex(ValueError, "No changelog section"):
            extract_release_notes("## 1.1.2 — old\n\n- Older release.", "1.1.3")

        with self.assertRaisesRegex(ValueError, "is empty"):
            extract_release_notes("## 1.1.3 — current\n\n## 1.1.2 — old", "1.1.3")


if __name__ == "__main__":
    unittest.main()
