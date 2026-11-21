# Mino screenshot plan

Written 21 Nov 2026 with ShotKit (`appdev/Private/iOS/ShotKit`, `prompts/new-set.md`). Status: **waiting for the owner's yes.** Nothing is captured, rendered or uploaded yet.

## What this set sells

The listing this set is for: everything on `main`, 2.0 plus the tools of 2.1 to 2.4, under the name **"Mino - PDF Scanner & Converter"** and the subtitle "Sign, Fill, Compress & Merge" (AppStoreMetadata.md, 2.4). If the releases ship one by one instead, the set is cut down per release (see "If the tools ship one by one").

- English only (the app and the listing are English only).
- Sets: iPhone 6.3", iPhone 6.9" (the same page, scaled), iPad 13", iPhone Duo. Ten frames each.
- What Mino has that the big ones don't: **everything runs on the device**. No upload, no account. That is frame 1's message.
- What the search page shows: the first three frames. They carry the three biggest reasons to install: every tool (1), scanning (2), signing (3).

## Rules this set follows (ShotKit `docs/rules.md`)

- **No price words.** No price, no "free", no "subscription", no "one purchase", no paywall screen. The Mino Pro screen (`07-paywall`) stays the reviewer screenshot only.
  - The app itself prints "3 free actions left today" on Home and on the free tools. Captures need a DEBUG seam that hides that line (see "Captures").
- **Pro frames carry a small Pro mark** on the frame (Guideline 2.3.2). Free frames carry none.
- **Real UI only**, from the current build, through the `-demoScreen` seams with the sandbox store (`-demoSandbox`). No retouching.
- **The app's own words**: the tool names are the titles in `Tool` (Scan to PDF, Fill & Sign, Photos to PDF, Office to PDF, Compress, Edit & Annotate, Organize Pages, Recognize Text, PDF to Images).
- **No overclaiming.** Never "PDF to Word" or "editable Word" (ROADMAP section 11). "Sign" is a drawn signature, so no "legally binding" or "e-signature". Compression figures only as the capture shows them.
- **No layout family next to itself**: lists, grids and documents alternate.

## The ten frames

`§` marks where the accent starts; `|` is a line break.

| # | Slot name | Headline | Proof line | Capture (`-demoScreen`) | Pro |
|---|---|---|---|---|---|
| 1 | hero | Every PDF tool. §Offline. | Scan, sign, convert and compress. Your files never leave your device. | `home` (Home with tools by category) | – |
| 2 | scan | Scan paper | §into clean PDFs | Edges found, pages straightened, color or black and white. | `scan` (review screen, 4 pages) | – |
| 3 | sign | Fill and sign | §in seconds | Type into form fields, then add your signature and the date. | `sign` (rental agreement, filled and signed) | Pro |
| 4 | photos | Photos | §to PDF | JPG, PNG and HEIC, in the order you choose. | `photos` (photo grid) | – |
| 5 | office | Word, Excel, | PowerPoint §to PDF | Every sheet and every slide, converted on your device. | `office` (file + paper size) | Pro |
| 6 | compress | Shrink big PDFs | §to send them | See the size of each setting before you compress. | `compress` (quality presets with size estimates) | – |
| 7 | edit | Highlight, draw | §and add text | Mark up any PDF with your finger or Apple Pencil. | `edit` (house rules with highlight, drawing, note) | Pro |
| 8 | organize | Rotate, delete, | §reorder pages | Drag pages into place, or add pages from another PDF. | `organize` (page grid) | – |
| 9 | ocr | Make scans | §searchable | Text is recognized on your device, ready to copy. | `ocr -demoRun` (result with the recognized text) | Pro |
| 10 | images | PDF pages | §to images | Every page as JPG or PNG, saved to Photos. | `images` (page picker + format) | – |

Why this order:
- **1 hero:** the whole toolkit in one look, with the differentiator (offline) in the headline. Real UI (Home), the biggest phone of the set. Not repeated later: no other frame shows Home.
- **2 scan, 3 sign:** the two highest-intent reasons people install a PDF app. Scanner apps are the largest PDF category on iOS (1.4 to 2.0M ratings each for the top three); signing has the weakest field past the giants (ROADMAP section 2). Message match for the new name, "PDF Scanner".
- **4 photos, 10 images:** "jpg to pdf" (4.8M searches) and "pdf to jpg" (3.4M) are the top two web searches in the roadmap's evidence.
- **5 office:** "word to pdf" (2.6M). Only Office to PDF, never the other direction.
- **6 compress:** what Mino was; still 1.6M searches. The size estimates are a real, visible difference.
- **7, 8, 9:** depth: editing (the top use case in competitors' reviews), organizing, text recognition.
- Free and Pro alternate, so the set shows both what anyone can do and what Pro adds.

Left out, and why: Merge and Split (Home shows them, and they are older, plainer screens), Protect & Unlock (low search demand), PDF to Text (the honest caveat "best for text documents" doesn't fit a headline), Files and Settings (no benefit to sell), the paywall (rule above).

## iPad and iPhone Duo

- iPad: the same ten frames from iPad captures (sidebar and two columns), not enlarged iPhone screens.
- Duo (open, 2853 × 2007): the Duo's two-column layout. Frames 3 and 7 (the editor) show the document in the detail column next to the tool list, which is what the Duo does.

## Captures (step 4, after the yes)

- Simulators only: iPhone 18 Pro Max, iPad Pro 13-inch, iPhone Duo (open, `hinge`). Light appearance, 9:41 status bar, `-demoSandbox -demoAppearance light`.
- Free frames: `-demoFree` plus a new DEBUG seam, `-demoHideAllowance`, that hides the "free actions left today" line so no frame says "free". Pro badges on Home stay, because they are honest.
- Pro frames: `-demoPro`, so the feature itself shows, not the paywall.
- The new app icon doesn't appear in these frames (Home shows no icon). In the store it sits next to the set, so the directions use its teal.

## If the tools ship one by one

- 2.0 alone: frames 1 (Home without the new tools), 6 compress, plus Merge and Split. The current raw shots in `Screenshots/raw/` already cover this.
- 2.1 to 2.4: each release adds its frames from the table above, led by its own tool (AppStoreMetadata.md says which).

## Next steps

1. Owner's yes on this plan (or changes).
2. `shotkit new screenshots/story --app "Mino"`, the capture script, English captures on the three simulators.
3. Two or three directions (theme and composition) for the owner to pick from, as local HTML and contact sheets.
4. Check, export, contact sheets, owner's yes, then upload with `shotkit upload --approved`.
