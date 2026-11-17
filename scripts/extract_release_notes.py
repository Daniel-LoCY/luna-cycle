#!/usr/bin/env python3
"""Extract one version's body from the project changelog."""

from __future__ import annotations

import argparse
import pathlib
import re


def extract_release_notes(changelog: str, version: str) -> str:
    heading = re.compile(rf"^##\s+{re.escape(version)}(?:\s|$)")
    lines = changelog.splitlines()
    start = next(
        (index for index, line in enumerate(lines) if heading.match(line)), None
    )
    if start is None:
        raise ValueError(f"No changelog section found for version {version}.")

    end = next(
        (
            index
            for index in range(start + 1, len(lines))
            if lines[index].startswith("## ")
        ),
        len(lines),
    )
    notes = "\n".join(lines[start + 1 : end]).strip()
    if not notes:
        raise ValueError(f"Changelog section for version {version} is empty.")
    return notes


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("changelog", type=pathlib.Path)
    parser.add_argument("version")
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()

    try:
        notes = extract_release_notes(
            args.changelog.read_text(encoding="utf-8"), args.version
        )
    except ValueError as error:
        parser.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(notes + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
