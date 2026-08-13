#!/usr/bin/env python3
"""Tests for extract_release_notes.py.

This script feeds both the Sparkle update dialog and the GitHub Release body, and
its output is only ever seen after a release has been signed, notarised and
published — so a mistake here is discovered by users. Two of the cases below are
regressions it actually shipped with: a double-escaped query string, and a code
span that swallowed the span after it.

Run: python3 scripts/test_extract_release_notes.py
"""

from __future__ import annotations

import unittest

from extract_release_notes import (
    find_section,
    inline_html,
    strip_link_definitions,
    to_html,
)
import re


class InlineHTML(unittest.TestCase):
    def test_escapes_markup(self):
        self.assertEqual(inline_html("angle <b> & amp"), "angle &lt;b&gt; &amp; amp")

    def test_bold(self):
        self.assertEqual(inline_html("**loud**"), "<b>loud</b>")

    def test_code_span(self):
        self.assertEqual(inline_html("a `code` b"), "a <code>code</code> b")

    def test_link(self):
        self.assertEqual(
            inline_html("[docs](https://example.com/x)"),
            '<a href="https://example.com/x">docs</a>',
        )

    def test_query_string_is_escaped_once(self):
        # Regression: the URL was escaped a second time inside the attribute, so the
        # `&amp;` left by the initial pass became `&amp;amp;` and the browser followed
        # a URL containing a literal "&amp;".
        self.assertEqual(
            inline_html("[docs](https://example.com/a?b=1&c=2)"),
            '<a href="https://example.com/a?b=1&amp;c=2">docs</a>',
        )

    def test_quotes_in_url_cannot_close_the_attribute(self):
        # html.escape(quote=False) leaves quotes alone, so this is the one bit of
        # escaping the link rule still has to do itself.
        self.assertEqual(
            inline_html('[x](https://example.com/a"b)'),
            '<a href="https://example.com/a&quot;b">x</a>',
        )

    def test_non_http_scheme_is_not_linked(self):
        # A javascript: target must never become a link in Sparkle's web view.
        rendered = inline_html("[click](javascript:alert(1))")
        self.assertNotIn("<a href", rendered)

    def test_backtick_run_closes_on_equal_run(self):
        self.assertEqual(
            inline_html("Fence: ```mermaid``` and `code`."),
            "Fence: <code>mermaid</code> and <code>code</code>.",
        )

    def test_span_may_contain_a_longer_run(self):
        # The changelog's own line. A 1-backtick span holding a ``` run: pairing single
        # backticks closed it on the first of the three, leaving a loose delimiter and
        # pulling the following well-formed span out of position.
        self.assertEqual(
            inline_html("through ` ```mermaid ` and `$$` fences."),
            "through <code>```mermaid</code> and <code>$$</code> fences.",
        )

    def test_unclosed_backtick_is_left_alone(self):
        self.assertEqual(inline_html("unclosed ` backtick"), "unclosed ` backtick")

    def test_padding_spaces_are_stripped_only_when_symmetric(self):
        self.assertEqual(inline_html("`` ` ``"), "<code>`</code>")
        self.assertEqual(inline_html("` x`"), "<code> x</code>")


class ToHTML(unittest.TestCase):
    def test_bullets_become_one_list(self):
        self.assertEqual(to_html("- one\n- two"), "<ul><li>one</li><li>two</li></ul>")

    def test_heading(self):
        self.assertEqual(to_html("### Added"), "<h3>Added</h3>")

    def test_paragraph(self):
        self.assertEqual(to_html("Some prose."), "<p>Some prose.</p>")

    def test_indented_line_continues_its_bullet(self):
        self.assertEqual(
            to_html("- first line\n  second line"),
            "<ul><li>first line second line</li></ul>",
        )

    def test_blank_line_closes_the_list(self):
        self.assertEqual(
            to_html("- one\n\nprose"),
            "<ul><li>one</li></ul>\n<p>prose</p>",
        )

    def test_heading_closes_an_open_list(self):
        self.assertEqual(
            to_html("- one\n### Fixed\n- two"),
            "<ul><li>one</li></ul>\n<h3>Fixed</h3>\n<ul><li>two</li></ul>",
        )


CHANGELOG = """# Changelog

## [Unreleased]

- pending thing

## [1.1.0] - 2026-08-01

### Added

- a feature

## [1.0.0] - 2026-07-22

- first

[Unreleased]: https://example.com/compare
"""


def section_for(version: str, text: str = CHANGELOG):
    return find_section(
        text, re.compile(rf"^##\s+\[?v?{re.escape(version)}\]?(\s|$)", re.IGNORECASE)
    )


class FindSection(unittest.TestCase):
    def test_finds_a_version(self):
        self.assertEqual(section_for("1.1.0"), "### Added\n\n- a feature")

    def test_stops_at_the_next_release(self):
        self.assertNotIn("first", section_for("1.1.0"))

    def test_missing_version_is_none(self):
        self.assertIsNone(section_for("9.9.9"))

    def test_unreleased_heading(self):
        self.assertIn("pending thing", section_for("Unreleased"))

    def test_bare_and_v_prefixed_headings(self):
        self.assertIn("x", section_for("2.0.0", "## 2.0.0\n\n- x\n"))
        self.assertIn("x", section_for("2.0.0", "## v2.0.0 — Big\n\n- x\n"))


class StripLinkDefinitions(unittest.TestCase):
    def test_drops_definitions_keeps_prose(self):
        self.assertEqual(
            strip_link_definitions("- a thing\n[1.1.0]: https://example.com/x"),
            "- a thing",
        )

    def test_keeps_inline_links(self):
        self.assertIn("[docs](https://example.com)", strip_link_definitions("see [docs](https://example.com)"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
