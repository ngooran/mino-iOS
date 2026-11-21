#!/usr/bin/env python3
"""Updates Mino/Localizable.xcstrings from the strings the compiler found.

Xcode does this by itself when you build in the IDE. From the command line:

    xcodebuild -project Mino.xcodeproj -scheme Mino -sdk iphonesimulator \\
        -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \\
        -derivedDataPath build/DerivedData build
    python3 Scripts/sync_strings.py

It then adds English plural forms for the keys in PLURALS, so "1 page" and
"3 pages" both read correctly. Add a key there when a new counted string
appears in the app.
"""
import glob
import json
import os
import subprocess
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
CATALOG = os.path.join(ROOT, "Mino", "Localizable.xcstrings")
DERIVED = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "DerivedData")

# key -> (text for one, text for other)
PLURALS = {
    "%lld pages": ("%lld page", "%lld pages"),
    "Discard all %lld pages?": ("Discard 1 page?", "Discard all %lld pages?"),
    "%lld photos": ("%lld photo", "%lld photos"),
    "%lld files": ("%lld file", "%lld files"),
    "%lld free actions left today": ("%lld free action left today", "%lld free actions left today"),
    "%lld free actions left today.": ("%lld free action left today.", "%lld free actions left today."),
    "All %lld Pages": ("%lld Page", "All %lld Pages"),
    "Create PDF (%lld pages)": ("Create PDF (%lld page)", "Create PDF (%lld pages)"),
    "Export %lld Images": ("Export %lld Image", "Export %lld Images"),
    "%lld %@ images": ("%lld %@ image", "%lld %@ images"),
    "%lld images saved to Photos.": ("%lld image saved to Photos.", "%lld images saved to Photos."),
    "%lld photos couldn't be loaded.": ("%lld photo couldn't be loaded.", "%lld photos couldn't be loaded."),
    "%lld files aren't images Mino can read, so they were left out.": (
        "%lld file isn't an image Mino can read, so it was left out.",
        "%lld files aren't images Mino can read, so they were left out.",
    ),
    "%lld pages extracted": ("%lld page extracted", "%lld pages extracted"),
    "Split into %lld PDFs": ("Split into %lld PDF", "Split into %lld PDFs"),
    "%lld PDFs created": ("%lld PDF created", "%lld PDFs created"),
    "%lld PDFs": ("%lld PDF", "%lld PDFs"),
    "Save PDF (%lld pages)": ("Save PDF (%lld page)", "Save PDF (%lld pages)"),
    "%lld pages recognized": ("%lld page recognized", "%lld pages recognized"),
    "%lld saved signatures": ("%lld saved signature", "%lld saved signatures"),
    "%lld changes": ("%lld change", "%lld changes"),
    "%lld sheets": ("%lld sheet", "%lld sheets"),
    "%lld slides": ("%lld slide", "%lld slides"),
}


def main():
    if not os.path.exists(CATALOG):
        with open(CATALOG, "w") as handle:
            json.dump({"sourceLanguage": "en", "strings": {}, "version": "1.0"}, handle)

    pattern = os.path.join(DERIVED, "Build", "Intermediates.noindex", "Mino.build", "*", "Mino.build", "Objects-normal", "*", "*.stringsdata")
    data = sorted(glob.glob(pattern))
    if not data:
        sys.exit("No .stringsdata files under %s. Build the app first." % DERIVED)
    command = ["xcrun", "xcstringstool", "sync", CATALOG]
    for path in data:
        command += ["--stringsdata", path]
    subprocess.run(command, check=True)

    with open(CATALOG) as handle:
        catalog = json.load(handle)
    strings = catalog["strings"]
    missing = []
    for key, (one, other) in PLURALS.items():
        if key not in strings:
            missing.append(key)
            continue
        # Only English is set here; the translations of a plural key are kept.
        strings[key].setdefault("localizations", {})["en"] = {
            "variations": {
                "plural": {
                    "one": {"stringUnit": {"state": "translated", "value": one}},
                    "other": {"stringUnit": {"state": "translated", "value": other}},
                }
            }
        }
    with open(CATALOG, "w") as handle:
        json.dump(catalog, handle, ensure_ascii=False, indent=2, sort_keys=True, separators=(",", " : "))
        handle.write("\n")

    stale = [key for key, value in strings.items() if value.get("extractionState") == "stale"]
    print("%d strings in %s" % (len(strings), os.path.relpath(CATALOG, ROOT)))
    if stale:
        print("Stale (no longer in the code): %d" % len(stale))
    if missing:
        print("Plural keys not in the code yet: " + ", ".join(missing))


if __name__ == "__main__":
    main()
