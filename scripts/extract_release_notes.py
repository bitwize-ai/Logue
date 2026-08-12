#!/usr/bin/env python3
"""Extract one release's section from CHANGELOG.md.

Feeds two things at release time: Sparkle's <description>, so the update dialog says
what changed before the user commits to downloading it, and the GitHub Release body.
Both used to be empty, which meant the only place a user could learn what an update
contained was the commit log.

Usage:
    python3 scripts/extract_release_notes.py --version 1.1.0 --format html
    python3 scripts/extract_release_notes.py --version 1.1.0 --format markdown

Falls back to the [Unreleased] section when no section is named for the version, and
exits 0 with no output when there is nothing to say — a missing changelog entry should
not fail a release that is otherwise built, signed and notarised.
"""

# Postpones annotation evaluation so `str | None` parses on the Python 3.9 that ships
# with macOS, not just the newer one on the CI runner.
from __future__ import annotations

import argparse
import html
import re
import sys
from pathlib import Path


def find_section(text: str, heading: re.Pattern) -> str | None:
    """Return the body under the first heading matching `heading`, up to the next `## `."""
    lines = text.splitlines()
    start = None
    for index, line in enumerate(lines):
        if heading.match(line):
            start = index + 1
            break
    if start is None:
        return None

    body = []
    for line in lines[start:]:
        if re.match(r"^##\s", line):
            break
        body.append(line)
    return "\n".join(body).strip("\n")


def strip_link_definitions(markdown: str) -> str:
    """Drop `[Unreleased]: https://…` reference definitions — they are file plumbing."""
    return "\n".join(
        line for line in markdown.splitlines()
        if not re.match(r"^\[[^\]]+\]:\s*\S+", line)
    )


# A code span opens on a run of backticks and closes on a run of the *same* length,
# per CommonMark. The lookarounds are what enforce "same length": without them a
# 1-backtick opener happily closes on the first backtick of a ``` run, which left a
# loose delimiter behind and swallowed the next well-formed span into a <code> of its
# own — the changelog's own `` ` ```mermaid ` `` line rendered that way.
#
# Single-line by design. A fenced block spanning lines is not a code span, and the
# converter above treats one as a paragraph; the changelog does not contain any.
CODE_SPAN = re.compile(r"(?<!`)(`+)(?!`)(.+?)(?<!`)\1(?!`)")


def _code_span_text(content: str) -> str:
    """Strip the one padding space each side that lets a span hold a backtick run."""
    if len(content) > 1 and content.startswith(" ") and content.endswith(" ") and content.strip():
        return content[1:-1]
    return content


def inline_html(text: str) -> str:
    """Escape, then re-introduce the few inline marks the changelog actually uses."""
    escaped = html.escape(text, quote=False)
    escaped = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", escaped)
    escaped = CODE_SPAN.sub(lambda m: "<code>{}</code>".format(_code_span_text(m.group(2))), escaped)
    # Attribution links are all over the changelog; without this they reach Sparkle's
    # pane as literal "[@name](https://…)". Only http(s) targets become links, so a
    # javascript: URL in a changelog cannot execute in the update dialog's web view.
    #
    # The URL is already escaped by the pass above — escaping it again would turn the
    # `&amp;` of a query string into `&amp;amp;`, which a browser resolves back to a
    # literal "&amp;" and follows to the wrong address. Quotes survive that pass
    # (quote=False), so closing the attribute is the only escaping left to do.
    escaped = re.sub(
        r"\[([^\]]+)\]\((https?://[^)\s]+)\)",
        lambda m: '<a href="{}">{}</a>'.format(m.group(2).replace('"', "&quot;"), m.group(1)),
        escaped,
    )
    return escaped


def to_html(markdown: str) -> str:
    """Convert the Keep-a-Changelog subset to the HTML Sparkle renders.

    Deliberately not a general Markdown implementation: the input shape is fixed by
    the changelog format, so a handful of rules beats taking on a dependency.
    """
    blocks: list[str] = []
    bullets: list[str] = []
    paragraph: list[str] = []

    def flush_bullets() -> None:
        if bullets:
            items = "".join(f"<li>{inline_html(item)}</li>" for item in bullets)
            blocks.append(f"<ul>{items}</ul>")
            bullets.clear()

    def flush_paragraph() -> None:
        if paragraph:
            blocks.append(f"<p>{inline_html(' '.join(paragraph))}</p>")
            paragraph.clear()

    for raw in markdown.splitlines():
        stripped = raw.strip()

        if not stripped:
            flush_bullets()
            flush_paragraph()
            continue

        heading = re.match(r"^#{2,4}\s+(.*)$", stripped)
        if heading:
            flush_bullets()
            flush_paragraph()
            blocks.append(f"<h3>{inline_html(heading.group(1))}</h3>")
            continue

        bullet = re.match(r"^[-*]\s+(.*)$", stripped)
        if bullet:
            flush_paragraph()
            bullets.append(bullet.group(1))
            continue

        # An indented line under a bullet is that bullet wrapping, not a new block.
        if bullets and raw[:1].isspace():
            bullets[-1] += " " + stripped
            continue

        flush_bullets()
        paragraph.append(stripped)

    flush_bullets()
    flush_paragraph()
    return "\n".join(blocks)


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract a release's notes from CHANGELOG.md")
    parser.add_argument("--version", required=True, help="Marketing version (e.g. 1.1.0)")
    parser.add_argument("--format", choices=["html", "markdown"], default="markdown")
    parser.add_argument("--changelog", default="CHANGELOG.md")
    args = parser.parse_args()

    path = Path(args.changelog)
    if not path.is_file():
        print(f"warning: {path} not found; emitting no release notes", file=sys.stderr)
        return

    text = path.read_text(encoding="utf-8")
    version = args.version.lstrip("v")

    section = find_section(
        text,
        re.compile(rf"^##\s+\[?v?{re.escape(version)}\]?(\s|$)", re.IGNORECASE),
    )
    if section is None:
        # Tagging without moving [Unreleased] into a versioned section is the likely
        # slip, and its content is what is shipping. Say so loudly, then use it.
        print(
            f"warning: no '## [{version}]' section in {path}; falling back to [Unreleased]",
            file=sys.stderr,
        )
        section = find_section(text, re.compile(r"^##\s+\[?Unreleased\]?(\s|$)", re.IGNORECASE))

    if section is None:
        print(f"warning: no [Unreleased] section in {path} either; emitting nothing", file=sys.stderr)
        return

    section = strip_link_definitions(section).strip()
    if not section:
        return

    sys.stdout.write(to_html(section) if args.format == "html" else section)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
