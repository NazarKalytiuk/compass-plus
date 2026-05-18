#!/usr/bin/env python3
"""Append a new <item> entry to appcast.xml for a Sparkle release.

The script is invoked by the GitHub Actions release workflow with the values
that the surrounding steps already gathered (signature, file length, release
URL, release notes). It keeps existing entries intact and inserts the new
release at the top of the channel feed.

We work with the appcast as plain text rather than parsing it as XML — that
way the description's CDATA section can hold raw HTML without ElementTree
double-escaping `<`, `>`, `&` inside it.
"""
from __future__ import annotations

import argparse
import re
import sys
from html import escape as xml_escape


ITEM_TEMPLATE = """        <item>
            <title>Version {short_version}</title>
            <link>{release_url}</link>
            <sparkle:version>{version}</sparkle:version>
            <sparkle:shortVersionString>{short_version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>{min_system}</sparkle:minimumSystemVersion>
            <pubDate>{pub_date}</pubDate>
            <description><![CDATA[
                {description}
            ]]></description>
            <enclosure url="{url}"
                       length="{length}"
                       type="application/octet-stream"
                       sparkle:edSignature="{signature}" />
        </item>
"""


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--appcast", required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--short-version", required=True)
    p.add_argument("--pub-date", required=True)
    p.add_argument("--url", required=True)
    p.add_argument("--release-url", required=True)
    p.add_argument("--length", required=True)
    p.add_argument("--signature", required=True)
    p.add_argument("--description", default="")
    p.add_argument("--min-system-version", default="14.0")
    args = p.parse_args()

    with open(args.appcast, "r", encoding="utf-8") as fp:
        contents = fp.read()

    # Skip if an entry with the same sparkle:version already exists. Match the
    # tag with surrounding whitespace so we don't confuse e.g. "0.4.0" with
    # "0.4.10" later on.
    pattern = re.compile(
        rf"<sparkle:version>\s*{re.escape(args.version)}\s*</sparkle:version>"
    )
    if pattern.search(contents):
        print(f"appcast already contains version {args.version} — nothing to do.")
        return 0

    # Close `]]>` from the user input must be neutralized so we don't end the
    # CDATA prematurely. (Practically never appears in release notes, but
    # cheap to guard against.)
    safe_description = (args.description or "").replace("]]>", "]]&gt;")

    # Attributes — escape carefully. URLs/sig are safe-ish but we still escape
    # XML-significant characters.
    new_item = ITEM_TEMPLATE.format(
        short_version=xml_escape(args.short_version),
        version=xml_escape(args.version),
        release_url=xml_escape(args.release_url, quote=True),
        url=xml_escape(args.url, quote=True),
        length=xml_escape(args.length, quote=True),
        signature=xml_escape(args.signature, quote=True),
        pub_date=xml_escape(args.pub_date),
        min_system=xml_escape(args.min_system_version),
        description=safe_description,
    )

    # Insert the new <item> right before the first existing <item>. Falls back
    # to inserting before </channel> if the feed has none yet.
    first_item = re.search(r"^\s*<item>", contents, re.MULTILINE)
    if first_item is not None:
        insertion_at = first_item.start()
        contents = contents[:insertion_at] + new_item + contents[insertion_at:]
    else:
        close = contents.find("</channel>")
        if close == -1:
            print("appcast.xml has no <channel> — cannot insert.", file=sys.stderr)
            return 1
        contents = contents[:close] + new_item + contents[close:]

    with open(args.appcast, "w", encoding="utf-8") as fp:
        fp.write(contents)

    print(f"Appcast updated with v{args.short_version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
