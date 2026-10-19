#!/usr/bin/env python3
"""Fail when any language file is missing keys from English.xml, carries extra or duplicate ones,
or changes the placeholders, key symbols, "Esc" or "Rote" that English uses."""
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "languages"
FILES = ["French", "German", "Spanish", "Japanese", "Korean", "Portuguese", "Chinese"]
PLACEHOLDER = re.compile(r"%[1-9]")
ESC = re.compile(r"(?<![A-Za-z])Esc(?![A-Za-z])")
SYMBOLS = "⌘⌥⌃⇧"


def keys(name: str) -> tuple[dict[str, str], list[str]]:
    """The file's strings by key, and one problem line per duplicate key or <string> without a key."""
    tree = ET.parse(ROOT / f"{name}.xml")
    strings: dict[str, str] = {}
    problems: list[str] = []
    for node in tree.getroot().iter("string"):
        key = node.get("key")
        if key is None:
            problems.append(f"{name}: <string> without a key attribute: {node.text!r}")
        elif key in strings:
            problems.append(f"{name}: duplicate key {key}")
        else:
            strings[key] = node.text or ""
    return strings, problems


def token_problems(english: str, other: str) -> list[str]:
    """What the translation changed among the parts that must be copied as written."""
    problems = []
    if Counter(PLACEHOLDER.findall(english)) != Counter(PLACEHOLDER.findall(other)):
        problems.append("placeholders %1-%9")
    if [c for c in english if c in SYMBOLS] != [c for c in other if c in SYMBOLS]:
        problems.append("key symbols ⌘ ⌥ ⌃ ⇧")
    if len(ESC.findall(english)) != len(ESC.findall(other)):
        problems.append("Esc")
    # German repeats the name where English says "it", so only a missing "Rote" is an error.
    if other.count("Rote") < english.count("Rote"):
        problems.append("Rote")
    return problems


def main() -> int:
    english, problems = keys("English")
    status = 0
    for problem in problems:
        print(problem)
        status = 1
    for name in FILES:
        path = ROOT / f"{name}.xml"
        if not path.exists():
            print(f"MISSING FILE {path.name}")
            status = 1
            continue
        other, problems = keys(name)
        for problem in problems:
            print(problem)
            status = 1
        missing = sorted(set(english) - set(other))
        extra = sorted(set(other) - set(english))
        untranslated = sorted(k for k in english if k in other and other[k] == english[k] and k not in ("app.name",))
        for key in english:
            if key in other:
                if not other[key].strip():
                    print(f"{name}: empty value for {key}")
                    status = 1
                for token in token_problems(english[key], other[key]):
                    print(f"{name}: {token} mismatch in {key}")
                    status = 1
        if missing or extra:
            status = 1
        print(f"{name}: {len(other)} keys, missing {len(missing)}, extra {len(extra)}, identical-to-English {len(untranslated)}")
        for key in missing:
            print(f"  missing  {key}")
        for key in extra:
            print(f"  extra    {key}")
    return status


if __name__ == "__main__":
    sys.exit(main())
