#!/usr/bin/env python3
"""Fail when any language file is missing keys from English.xml or carries extra ones."""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "languages"
FILES = ["French", "German", "Spanish", "Japanese", "Korean", "Portuguese", "Chinese"]


def keys(name: str) -> dict[str, str]:
    tree = ET.parse(ROOT / f"{name}.xml")
    return {node.get("key"): (node.text or "") for node in tree.getroot().iter("string")}


def main() -> int:
    english = keys("English")
    status = 0
    for name in FILES:
        path = ROOT / f"{name}.xml"
        if not path.exists():
            print(f"MISSING FILE {path.name}")
            status = 1
            continue
        other = keys(name)
        missing = sorted(set(english) - set(other))
        extra = sorted(set(other) - set(english))
        untranslated = sorted(k for k in english if k in other and other[k] == english[k] and k not in ("app.name",))
        for key in english:
            if key in other:
                if not other[key].strip():
                    print(f"{name}: empty value for {key}")
                    status = 1
                for token in ("%1", "%2"):
                    if (token in english[key]) != (token in other[key]):
                        print(f"{name}: placeholder {token} mismatch in {key}")
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
