#!/usr/bin/env python3
"""Update appcast.xml with a new Sparkle release entry.

Usage:
    python3 scripts/update_appcast.py \
        --version 1.2.0 \
        --build 42 \
        --signature "BASE64_ED_SIGNATURE" \
        --length 12345678 \
        --min-os 26.0
"""

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

APPCAST_PATH = "appcast.xml"
GITHUB_REPO = "bitwize-ai/Logue"

# Register Sparkle namespace so it's preserved in output
SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC_NS = "http://purl.org/dc/elements/1.1/"
ET.register_namespace("sparkle", SPARKLE_NS)
ET.register_namespace("dc", DC_NS)

VERSION_PATTERN = re.compile(r"^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Add a Sparkle release to appcast.xml")
    parser.add_argument("--version", required=True, help="Marketing version (e.g. 1.2.0)")
    parser.add_argument("--build", required=True, help="Build number")
    parser.add_argument("--signature", required=True, help="EdDSA signature from sign_update")
    parser.add_argument("--length", required=True, type=int, help="ZIP file size in bytes")
    parser.add_argument("--min-os", default="26.0", help="Minimum macOS version")
    parser.add_argument("--notes", default="", help="Release notes (plain text)")
    return parser.parse_args()


def validate_args(args: argparse.Namespace) -> None:
    """Validate inputs before modifying the appcast."""
    if not VERSION_PATTERN.match(args.version):
        print(f"Error: invalid version format '{args.version}'. Expected: X.Y.Z or X.Y.Z-beta.1", file=sys.stderr)
        sys.exit(1)
    if not args.signature or not args.signature.strip():
        print("Error: --signature must not be empty", file=sys.stderr)
        sys.exit(1)
    if args.length <= 0:
        print(f"Error: --length must be positive, got {args.length}", file=sys.stderr)
        sys.exit(1)


def remove_existing_version(channel: ET.Element, version: str) -> bool:
    """Remove any existing <item> with the same shortVersionString. Returns True if one was removed."""
    removed = False
    for item in list(channel.findall("item")):
        enclosure = item.find("enclosure")
        if enclosure is not None:
            existing_version = enclosure.get(f"{{{SPARKLE_NS}}}shortVersionString")
            if existing_version == version:
                channel.remove(item)
                removed = True
    return removed


def find_insert_position(channel: ET.Element) -> int:
    """Find the index after <title> and <link> to insert new items at the top."""
    insert_idx = 0
    for idx, child in enumerate(channel):
        if child.tag in ("title", "link", "description", "language"):
            insert_idx = idx + 1
        else:
            break
    return insert_idx


def main() -> None:
    args = parse_args()
    validate_args(args)

    tree = ET.parse(APPCAST_PATH)
    root = tree.getroot()
    channel = root.find("channel")
    if channel is None:
        raise SystemExit("Error: <channel> not found in appcast.xml")

    # Remove duplicate if this version already exists (idempotent re-runs)
    if remove_existing_version(channel, args.version):
        print(f"Replaced existing entry for v{args.version}")

    # Build the download URL pointing directly at the GitHub Release asset.
    # The release (with the uploaded ZIP) must exist before this runs — see release.yml.
    tag = f"v{args.version}"
    filename = f"Logue-{args.version}.zip"
    download_url = f"https://github.com/{GITHUB_REPO}/releases/download/{tag}/{filename}"

    # RFC 2822 date for pubDate
    pub_date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S %z")

    # Build <item>
    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {args.version}"
    if args.notes:
        ET.SubElement(item, "description").text = args.notes
    ET.SubElement(item, "pubDate").text = pub_date

    enclosure = ET.SubElement(item, "enclosure")
    enclosure.set("url", download_url)
    enclosure.set("length", str(args.length))
    enclosure.set("type", "application/octet-stream")
    enclosure.set(f"{{{SPARKLE_NS}}}edSignature", args.signature)
    enclosure.set(f"{{{SPARKLE_NS}}}version", args.build)
    enclosure.set(f"{{{SPARKLE_NS}}}shortVersionString", args.version)
    enclosure.set(f"{{{SPARKLE_NS}}}minimumSystemVersion", args.min_os)

    # Insert at top of channel (after metadata elements) so newest version appears first
    insert_idx = find_insert_position(channel)
    channel.insert(insert_idx, item)

    # Write back with XML declaration
    ET.indent(tree, space="  ")
    tree.write(APPCAST_PATH, encoding="utf-8", xml_declaration=True)

    # Append trailing newline
    with open(APPCAST_PATH, "a") as f:
        f.write("\n")

    print(f"appcast.xml updated: v{args.version} (build {args.build})")


if __name__ == "__main__":
    main()
