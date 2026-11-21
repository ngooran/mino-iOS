#!/usr/bin/env python3
"""Puts translations into Mino/Localizable.xcstrings.

    python3 Scripts/import_translations.py de.json es.json fr.json

Each file is named after its language and maps every catalog key to its translation: a string,
or for a plural key an object of plural forms ({"one": ..., "other": ...}; Spanish and French
also "many"). Nothing is written unless every file passes: every key present, and every format
specifier (%@, %lld, %1$@ ...) the same as in the English, so a translation can't crash a
String(format:) or show the wrong number.
"""
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CATALOG = os.path.join(ROOT, "Mino", "Localizable.xcstrings")
SPEC = re.compile(r"%(?:(\d+)\$)?[-+ 0#]*\d*(?:\.\d+)?(lld|ld|d|@|f|lf|s|u|llu|lu|%)")


def specifiers(text):
    """The format specifiers of a string, as a sorted list of (position, type)."""
    found, plain = [], 0
    for match in SPEC.finditer(text):
        position, kind = match.group(1), match.group(2)
        if kind == "%":
            continue
        if position is None:
            plain += 1
            position = str(plain)
        found.append((position, kind))
    return sorted(found)


def english_forms(entry):
    en = entry.get("localizations", {}).get("en")
    if en and "variations" in en:
        return {form: unit["stringUnit"]["value"] for form, unit in en["variations"]["plural"].items()}
    return None


def main(paths):
    catalog = json.load(open(CATALOG))
    strings = catalog["strings"]
    problems, imported = [], {}
    for path in paths:
        lang = os.path.splitext(os.path.basename(path))[0]
        data = json.load(open(path))
        for key, entry in strings.items():
            if key not in data:
                problems.append(f"{lang}: missing {key!r}")
                continue
            value = data[key]
            forms = english_forms(entry)
            english = (forms or {}).get("other") or entry.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value", key)
            if forms:
                if not isinstance(value, dict) or "one" not in value or "other" not in value:
                    problems.append(f"{lang}: {key!r} needs plural forms")
                    continue
                for form, text in value.items():
                    want = specifiers(forms.get(form, forms["other"]))
                    if specifiers(text) != want:
                        problems.append(f"{lang}: {key!r} ({form}) has {specifiers(text)}, English has {want}")
            else:
                if not isinstance(value, str):
                    problems.append(f"{lang}: {key!r} should be a string")
                    continue
                if specifiers(value) != specifiers(english):
                    problems.append(f"{lang}: {key!r} has {specifiers(value)}, English has {specifiers(english)}")
        extra = set(data) - set(strings)
        if extra:
            print(f"{lang}: {len(extra)} keys not in the catalog are ignored")
        imported[lang] = data
    if problems:
        print("\n".join(problems))
        sys.exit(f"{len(problems)} problem(s); nothing written")

    for lang, data in imported.items():
        for key, entry in strings.items():
            value = data[key]
            if isinstance(value, dict):
                unit = {"variations": {"plural": {f: {"stringUnit": {"state": "translated", "value": t}} for f, t in value.items()}}}
            else:
                unit = {"stringUnit": {"state": "translated", "value": value}}
            entry.setdefault("localizations", {})[lang] = unit
    with open(CATALOG, "w") as handle:
        json.dump(catalog, handle, ensure_ascii=False, indent=2, sort_keys=True, separators=(",", " : "))
        handle.write("\n")
    print(f"{len(strings)} strings, translated into {', '.join(sorted(imported))}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
