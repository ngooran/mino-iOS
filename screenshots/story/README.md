# Mino store screenshots

This folder is the set: `set.js` (frames, English copy, composition), `i18n.js` (translations),
`theme.css` (the look), `art/` (generated art, with its brief and manifest), `shotkit.json`
(frame count, sets, locales, the App Store app id). The engine and the tools are ShotKit.

    open index.html                    the gallery: device and locale picker
    shotkit check --all                fail on a headline that does not fit or a missing image
    shotkit export --final --all       the upload set, with contact sheets
    shotkit upload --approved --version X.Y      only after the owner has seen every contact sheet
    shotkit verify --version X.Y       read every set back

Raw captures are not in git. The capture script and what it needs are in this app's own docs;
the techniques are in ShotKit's docs/capture.md.
