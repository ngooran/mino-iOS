# Mino Toolkit Roadmap

The plan to grow Mino from a compressor into the reference PDF toolkit: 10 new tools in four releases after 2.0, chosen for sales impact. Written 15 Nov 2026.

- Interactive prototype of the result: https://claude.ai/artifact/29puk3ndvpZ4NaUkAjiUPS (private to the owner; share it from the page to let others open it).
- 2.0 release steps: [RELEASE-2.0.md](RELEASE-2.0.md). Ship 2.0 first; nothing here should delay it.

---

## 1. Goal and Principles

**Goal:** when someone needs to do something to a PDF on an iPhone, iPad or iPhone Duo, Mino has the tool, and it works offline.

Principles that decide every trade-off:
1. **Offline and private.** Every tool runs on the device. No uploads, no account. This is the one thing the big competitors can't claim.
2. **Pay once.** No subscription. Scanner and editor apps charge weekly or yearly; Mino Pro stays a single purchase.
3. **Native and simple.** One clear screen per tool: choose, adjust, done. System controls, both appearances, iPad and Duo layouts.
4. **Demand first.** Tools are ordered by evidence of demand, then by how cheaply the existing engine can deliver them.

---

## 2. The 10 Tools

Mino 2.0 has Compress (single and batch), Merge and Split. These are added:

| # | Tool | What it does | Access | Release | Effort (working days, rough) |
|---|---|---|---|---|---|
| 1 | Scan to PDF | Camera scan with edge detection, multi-page, filters | Free allowance | 2.2 | 4–5 |
| 2 | Photos to PDF | JPG, PNG, HEIC from Photos or Files into one PDF | Free allowance | 2.1 | 2–3 |
| 3 | Fill & Sign | Fill form fields, add signature, date, checkmarks | Pro | 2.3 | 7–10 |
| 4 | PDF to Images | Export pages as JPG or PNG | Free allowance | 2.1 | 2 |
| 5 | Organize Pages | Rotate, delete, reorder, duplicate, insert | Free allowance | 2.1 | 3–4 |
| 6 | Edit & Annotate | Add text, highlight, draw, white-out, images | Pro | 2.3 | 6–8 |
| 7 | Protect & Unlock | Add or remove a password (AES-256) | Pro | 2.1 | 2–3 |
| 8 | Recognize Text (OCR) | Make scans searchable; copy or export the text | Pro | 2.2 | 5–7 |
| 9 | Office to PDF | Word, Excel, PowerPoint to PDF | Pro | 2.4 | 4–6 |
| 10 | PDF to Word | Editable .docx, or plain text | Pro | 2.4 | 2–3 prototype, then 5–8 |

The effort numbers are estimates for one developer and have not been validated. Total: roughly 46–65 working days, plus 4–6 days for the shared foundation in 2.1.

### Why these ten (evidence)

| Signal | Value | Source |
|---|---|---|
| "jpg to pdf" web searches per month | 4.8M | Ahrefs, India, Oct 2026 |
| "pdf to word" | 4.0M | same |
| "pdf to jpg" | 3.4M | same |
| "word to pdf" | 2.6M | same |
| "compress pdf" (what Mino does today) | 1.6M | same |
| "delete page in pdf" | 301K | third-party keyword estimate |
| Top three scanner apps | 1.4–2.0M App Store ratings each | Apple search API, US, Nov 2026 |
| Scanner revenue | CamScanner about $1M+/month, Genius Scan about $200K+/month | AppGoblin estimates |
| "PDF editor" as the top use case | 66% of iLovePDF reviewers, 53% of Smallpdf reviewers | Software Advice |
| Median ratings of the top 10 apps for "sign pdf" | 49 (weak field past the giants) | Apple search API |
| Same for "pdf password" / "unlock pdf" | 5–6 | Apple search API |
| Same for "pdf to word" | 77 | Apple search API |

Limits of this evidence: no paid App Store keyword tool was used; the web volumes are for India; rating counts are a proxy for demand, not a measurement; revenue figures are third-party estimates. Validate the keyword choices with an ASO tool before each release.

Apple's free Preview app (iOS 26) scans, fills, signs, password-protects and merges. Those tools therefore don't differentiate on their own. They are still in the plan because scanner apps kept earning through years of built-in scanning, and a toolkit without them is not a reference app.

### Left out for now
Watermark and page numbers, redaction, web page to PDF (small demand signals); AI summaries or chat (no evidence gathered, and quality on-device is unproven); true text editing of existing PDF text; certified digital signatures; cloud sync or accounts.

---

## 3. Releases

Each release is useful on its own and changes the App Store listing.

### 2.1 "Toolkit" — foundation + four quick tools
Foundation (4–6 days):
- **Tool registry** (`Mino/App/Tools.swift`): one `Tool` enum with title, subtitle, symbol, color, category, access (free allowance or Pro) and accepted input (PDF, images, camera, Office). Home, search, the tool picker, the paywall and the Share Extension read from it. Replaces the hard-coded Merge and Split tiles.
- **New Home:** search field, two entry points ("Scan" arrives in 2.2; "Open PDF" from day one), then tools grouped by category: Create, Reduce & Organize, Sign & Edit, Convert, Protect. Recent files below.
- **File-first flow:** open any PDF, then pick a tool from a "What do you want to do?" sheet. The same sheet appears from the Files tab, after a result ("Continue with another tool") and from the Share Extension.
- **Free allowance becomes "3 free actions a day"**, shared by the free tools (`FreeUsage` already counts per day).
- **Password prompt on import:** any tool that opens an encrypted PDF asks for its password once.
- **Files tab:** the segmented filter becomes a filter menu (more kinds than fit in a segmented control); `FileItem.Kind` gains scanned, converted, edited, protected.
- **String Catalog:** move all UI text into a `.xcstrings` file now, before the number of strings triples. English only for the moment.

Tools: Photos to PDF, PDF to Images, Organize Pages, Protect & Unlock.

### 2.2 "Scanner" — Scan to PDF + Recognize Text
The release that changes what Mino is in the store: rename to "Mino - PDF Scanner & Converter".

### 2.3 "Sign" — Fill & Sign + Edit & Annotate
Both tools share one page editor built on PDFKit annotations.

### 2.4 "Office" — Office to PDF + PDF to Word
PDF to Word ships only if it passes the quality gate in section 4. If it fails, ship "PDF to Text" alone.

---

## 4. Tool Specifications

All tools follow the existing pattern: a session object in `Mino/App/Sessions.swift`, a `Route` case, a flow view in `Mino/UI/Tasks/` (configure → progress → result), and a service in `Mino/Features/`. Results are `FileItem`s and get the shared result screen: Share, Save to Files, Preview, Continue with another tool.

### 1. Scan to PDF (2.2)
- **Flow:** camera with live edge detection and auto-capture → add pages → review (reorder, delete, retake, filter: Color / Grayscale / Black & White) → Save PDF.
- **Build:** VisionKit `VNDocumentCameraViewController` for capture and perspective correction. Assemble pages with MuPDF (`pdf_add_image`), JPEG-compressed using the existing quality presets. Optional "Make text searchable" runs tool 8 (Pro).
- **Needs:** `NSCameraUsageDescription`. The document camera does not run in the simulator, so `-demoScreen scan` must use sample pages, and the real camera needs one test on a device.
- **Done when:** a 10-page scan produces a PDF under 3 MB at Balanced quality; works on iPad and on the Duo's outer and inner cameras.

### 2. Photos to PDF (2.1)
- **Flow:** pick photos (Photos picker, Files, drag and drop) → reorder → page size (Fit to photo / A4 / Letter), margins → Create PDF.
- **Build:** `PhotosPicker` (needs no permission). JPEGs are embedded as-is with `pdf_add_image`, so there is no quality loss; HEIC and PNG are transcoded with ImageIO first (MuPDF can't read HEIC).
- **Done when:** 50 photos convert in under 10 seconds on an iPhone 15; orientation is respected; output opens in Preview and Acrobat.

### 3. Fill & Sign (2.3)
- **Flow:** open PDF → tap form fields to fill (text, checkbox, radio, dropdown) → add signature, initials, date, text or checkmarks anywhere → Save.
- **Build:** PDFKit `PDFView` handles AcroForm widgets. Signatures are drawn with PencilKit and stored only on the device; placed as stamp annotations. On save, flatten with MuPDF `pdf_bake_document` so the signature can't be moved.
- **Be honest in the UI:** this is a drawn signature, not a certified digital signature.
- **Done when:** a standard tax form and a rental contract can be filled, signed and reopened correctly in Preview and Acrobat.

### 4. PDF to Images (2.1)
- **Flow:** open PDF → choose pages (reuse the Split page picker) → JPG or PNG, Standard (150 dpi) or High (300 dpi) → Export.
- **Build:** `mino_render_page` already renders pages. Output goes to Photos (`NSPhotoLibraryAddUsageDescription`, add-only), the share sheet, or a folder in Files.
- **Done when:** a 100-page export doesn't exceed memory limits (render one page at a time).

### 5. Organize Pages (2.1)
- **Flow:** page grid → select → rotate, delete, duplicate; drag to reorder; insert pages from another PDF, a blank page, or (from 2.2) a scan → Save.
- **Build:** MuPDF `pdf_rearrange_pages` for order and deletion (the wrapper already has `mino_delete_page`); rotation by setting the page's `/Rotate`.
- **Done when:** changes keep links, bookmarks and form fields on the remaining pages.

### 6. Edit & Annotate (2.3)
- **Flow:** open PDF → toolbar: Text, Highlight, Draw, White-out, Image, Shapes → undo/redo → Save.
- **Build:** PDFKit annotations (highlight, ink, free text, stamps); PencilKit for drawing with Apple Pencil. Standard annotations, so other apps can read and remove them; optional flatten.
- **Scope note:** this adds content on top of the page. Changing existing text is out of scope; "white-out + text" covers the common case.

### 7. Protect & Unlock (2.1)
- **Flow:** Protect: set a password, optionally block printing and copying. Unlock: enter the current password once, save a copy without it.
- **Build:** MuPDF `pdf_write_options.do_encrypt = PDF_ENCRYPT_AES_256` with user and owner passwords; `fz_authenticate_password` to open. No new dependency.
- **Be honest in the UI:** Unlock removes a password you know. It does not crack unknown passwords.

### 8. Recognize Text / OCR (2.2)
- **Flow:** open a scanned PDF → languages (automatic) → Searchable PDF or Text only → Recognize → result with a text preview and Copy.
- **Build:** Apple Vision text recognition on the device, page by page at about 200 dpi; add the text as an invisible layer over each page so search and copy work. MuPDF's own OCR needs Tesseract, which would add size and is worse; it stays disabled.
- **Done when:** a 20-page scan is recognized in under 30 seconds on an iPhone 15 and the text can be selected in Preview.

### 9. Office to PDF (2.4)
- **Flow:** pick a Word, Excel or PowerPoint file (also Pages, Numbers, Keynote, RTF, text) → page size → Convert.
- **Build:** render the file offscreen with WebKit, which uses the system's built-in Office renderers, and paginate to PDF. MuPDF's own Office reader is the fallback. Runs offline.
- **Risk:** layout fidelity (fonts, tables, page breaks). Gate: 20 real documents; ship if the result matches the Quick Look preview on at least 17.

### 10. PDF to Word (2.4)
- **Flow:** open PDF → Word (.docx) or Text → Convert. Scanned pages go through OCR first.
- **Build:** MuPDF's docx writer (`fz_new_docx_writer`). It needs the bundled `extract` library, so the MuPDF frameworks must be rebuilt with `HAVE_EXTRACT=yes` (`Scripts/build_mupdf_ios.sh`).
- **Quality gate before building the UI:** convert 20 documents (contracts, invoices, CVs, multi-column pages, tables, scans). Ship Word output only if at least 15 are usable without major fixing. Otherwise ship "PDF to Text" and say "best for text documents". This is the highest-demand and highest-risk tool; poor output costs ratings.

---

## 5. Free, Pro and Price

### What is free
| Free: 3 actions a day, shared | Pro |
|---|---|
| Compress (presets) | Unlimited actions |
| Scan to PDF | Batch compress, custom quality |
| Photos to PDF | Merge, Split |
| PDF to Images | Fill & Sign |
| Organize Pages | Edit & Annotate |
| | Protect & Unlock |
| | Recognize Text |
| | Office to PDF, PDF to Word |

Reasoning: the free tools match the highest-volume searches and bring downloads and ratings. The Pro tools are the urgent, high-intent ones (sign a contract tonight, unlock a statement, convert for an editor).

**Try before paying:** Pro tools open for everyone. People can load their file and set everything up; the paywall appears at the final button, with the reason ("Signing PDFs is part of Mino Pro"). This shows the value before asking for money and avoids "everything is locked" reviews.

### Price
- Mino Pro stays **€4.99**, one-time, through all four releases. No price increase is planned (owner's decision, 15 Nov 2026).
- No subscription at any point. "Pay once" is a headline feature against scanner apps.
- Don't call €4.99 a launch or introductory price in any store text, since it isn't going up.

### Paywall copy (2.4 state)
Unlimited actions · Scan with text recognition · Fill and sign · Edit and annotate · Convert to and from Word · Merge, split and batch · Password protection · Family Sharing for up to 6 people.

---

## 6. App Store Plan

| Release | Name (30 max) | Subtitle (30 max) | Keywords (100 max) |
|---|---|---|---|
| 2.1 | Mino - PDF Compressor & Merger | Merge, Split & JPG to PDF | photo,image,converter,password,protect,unlock,rotate,delete,pages,organize,batch,offline,reduce |
| 2.2 | Mino - PDF Scanner & Converter | Compress, Merge, Split & OCR | scan,document,camera,text,jpg,photo,image,password,unlock,rotate,organize,batch,offline,shrink |
| 2.3 | Mino - PDF Scanner & Converter | Sign, Fill, Compress & Merge | scan,ocr,split,jpg,photo,form,signature,annotate,highlight,edit,password,unlock,rotate,offline |
| 2.4 | Mino - PDF Scanner & Converter | Sign, Fill, Compress & Merge | scan,ocr,split,jpg,photo,word,docx,excel,form,signature,annotate,edit,password,unlock,rotate,offline |

- Keywords never repeat words from the name or subtitle; Apple indexes those already.
- These are starting points. Check popularity and difficulty in an ASO tool before each submission.
- Each release: new screenshots led by the new tool, a What's New text, and an In-App Event for the launch week.
- Screenshots: one tool per image with a caption; workflow in CLAUDE.md ("App Store Screenshots"). Add `-demoScreen` cases for every new tool.
- Localize the listing and the app after 2.2 (de, es, fr, pt-BR first), once the String Catalog exists.

### Measuring (no analytics in the app)
Use App Store Connect only: impressions, product page conversion, first-time downloads, Pro units ÷ first-time downloads, proceeds per download, ratings. Compare the 28 days before and after each release.

---

## 7. Engineering Notes

- **New MuPDF wrapper functions** (`MuPDFHelpers.c`): `mino_images_to_pdf`, `mino_authenticate`, `mino_save_encrypted`, `mino_rearrange_pages`, `mino_set_page_rotation`, `mino_bake`, `mino_write_docx`, `mino_add_text_layer`.
- **No new third-party code** except enabling MuPDF's bundled `extract` for tool 10. Everything else is Apple frameworks: VisionKit, Vision, PDFKit, PencilKit, PhotosUI, WebKit.
- **Permissions:** camera (scan), Photos add-only (saving images). The privacy label stays "Data Not Collected".
- **Share Extension:** accept images and Office files as well as PDFs, then show the tool picker.
- **Persistence:** all new storage goes through `StorageRoot`. Saved signatures are stored on the device only.
- **Memory:** process page by page everywhere (rendering, OCR, image export); a 500-page PDF must not be loaded as images at once.
- **Tests:** a fixture set of real-world PDFs, photos and Office files in the test target; one round-trip test per tool (output opens, page count and text are as expected).
- **Demo and screenshots:** every tool gets a `-demoScreen` case and sample data in the `-demoSandbox` store.
- **Layouts:** every tool screen is checked on iPhone, iPad, and the Duo closed, flat and in book pose (`hinge`).

---

## 8. Risks

| Risk | Effect | Mitigation |
|---|---|---|
| PDF to Word output is poor | Bad reviews on the most-searched tool | Quality gate before building; fall back to PDF to Text |
| Office to PDF layout differences | Refund requests, bad reviews | 20-document gate; show a preview before saving |
| Apple Preview covers scan, sign, fill, lock | Less reason to pay for those alone | Sell the toolkit and chaining (scan → sign → compress), not single tools |
| "Sign" misunderstood as legal e-signature | Review or legal complaints | Plain wording in the tool and the listing |
| Scope grows, releases slip | No sales effect for months | Four small releases; each tool has a "done when" |
| More tools, more support mail | Time | In-app help per tool; clear error messages |
| Home becomes crowded | Lower usability | Search, categories, file-first flow; test with the prototype |

---

## 9. Decisions (made by the owner, 15 Nov 2026)

1. **Free/Pro split:** approved as in section 5. Fill & Sign is Pro.
2. **Price:** stays €4.99. No increase.
3. **Rename** to "Mino - PDF Scanner & Converter" at 2.2: approved.
4. **PDF to Word** may ship as "PDF to Text" only if the quality gate fails: approved.
5. **Camera scanner on a real device:** the owner will test it themselves at the end. Do not run it on their phone.

## 10. Next Step

After 2.0 is submitted: build the 2.1 foundation (tool registry, new Home, file-first sheet), then Photos to PDF as the first new tool, since it reuses the most and has the highest search demand.

---

## 11. Progress

Work happens on branch `toolkit` (from `redesign-2.0`). Version and build numbers are unchanged (2.0, build 4): set them when a release is cut. This section is the place to resume from.

### Status

| Step | State | Verified how |
|---|---|---|
| 2.1 foundation | Done | Unit tests (`FoundationTests`), screenshots on iPhone 18 Pro Max, iPad Pro 13-inch and iPhone Duo closed, flat and book pose |
| Photos to PDF | Done | `PhotosToPDFTests`; demo run; output inspected with PDFKit |
| PDF to Images | Done | `PDFToImagesTests`; demo run; files inspected |
| Organize Pages | Done | `OrganizeTests`; demo run; output inspected with PDFKit |
| Protect & Unlock | Done | `ProtectTests`; demo runs; output inspected with PDFKit |
| Scan to PDF | Done, except the real camera (owner) | `ScanTests`; demo runs with sample pages; output inspected. The document camera itself has never run: it does not exist in the simulator |
| Recognize Text | Done | `OCRTests`; demo runs; output inspected with PDFKit |
| Fill & Sign | Done | `EditorTests`; demo runs; saved pages rendered and inspected |
| Edit & Annotate | Done | `EditorTests`; demo runs; saved pages rendered and inspected |
| Office to PDF | Not started | Gate: 17 of 20 documents |
| PDF to Word | Not started | Gate: 15 of 20 documents |

A tool appears in the app once it is listed in `Tool.available` (`Mino/App/Tools.swift`).

### How to verify (every tool)

```bash
# Unit tests (the test host runs with -demoSandbox, so no real data is touched)
xcodebuild test -project Mino.xcodeproj -scheme Mino -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -derivedDataPath build/DerivedData

# A tool's screen, and with -demoRun its result
xcrun simctl launch <udid> com.applestan.Mino -demoSandbox -demoAppearance light -demoFree -demoScreen organize [-demoRun]

# The files a demo run wrote
ls "$(xcrun simctl get_app_container <udid> com.applestan.Mino data)/Documents/DemoSandbox"

# After adding or changing UI text
python3 Scripts/sync_strings.py
```

Demo screens: `home`, `search`, `picker`, `password`, `compress`, `result`, `merge`, `split`, `scan`, `ocr`, `sign`, `signature`, `edit`, `photos`, `images`, `organize`, `protect`, `unlock`, `files`, `settings`, `paywall`.

### 2.1: what was built

- **Foundation:** `Tool` registry; new Home (search, Open PDF, tools by category, NEW and PRO badges); "What do you want to do?" sheet (after Open PDF, from Files, after a result, for incoming PDFs); "3 free actions a day" shared by the free tools; password prompt for locked PDFs; Files filter menu that lists only the kinds present; `Localizable.xcstrings` (384 strings, English, with plural forms); a `MinoTests` unit-test target with fixtures; Share Extension accepts PDFs, images and Office files, several at once.
- **Shared plumbing for new tools:** a session owns a `TaskState`; `AppState.mayRun` checks Pro or the allowance at the final button; `AppState.run` runs the engine off the main thread and files the result in `ToolResultStore`; `ToolFlow` gives every tool the same working, failure and result screens.
- **Photos to PDF:** Photos picker, Files, drag and drop; reorder by dragging; Fit to Photo, A4, Letter; margins.
- **PDF to Images:** all or chosen pages; JPG or PNG; 150 or 300 dpi; Save to Photos (add-only access), Save to Files, Share.
- **Organize Pages:** rotate, move, duplicate, delete, drag to reorder, insert a blank page or the pages of another PDF.
- **Protect & Unlock:** AES-256 password, optional limits on printing and copying; Unlock saves a copy without a password the person knows.

### Measured against "done when"

| Tool | Done when | Result |
|---|---|---|
| Photos to PDF | 50 photos in under 10 s on an iPhone 15; orientation respected; opens in Preview and Acrobat | 50 photos of 12 MP (10 of them HEIC) in about 4 s **on the simulator on this Mac**, not on an iPhone 15. Orientation matches ImageIO for JPEG with EXIF 1, 3 and 6, PNG and HEIC. JPEG bytes are found unchanged inside the PDF. Opens in PDFKit, which is what Preview uses. Not opened in Acrobat. |
| PDF to Images | A 100-page export doesn't exceed memory limits | 100 A4 pages at 300 dpi: memory peaks about 33 MB above the start (one page is about 35 MB of pixels). |
| Organize Pages | Links, bookmarks and form fields survive on the remaining pages | Tested on a fixture with all three: bookmarks still open their chapter, a link to a kept page still works, a link to a deleted page is removed, fields keep their values and can still be filled, and a deleted page's field value is gone from the file. |
| Protect & Unlock | Opens in Preview and Acrobat with the password, not without | PDFKit: locked without the password, opens with it, restrictions apply. The file contains the AESV3 (AES-256) filter. Not opened in Acrobat. |

### Choices made while building (not in the plan)

1. **One result store, not a service per tool.** New tools keep their results in `ToolResultStore`; each tool still has a session, a route, a flow view and an engine in `Mino/Features/<Tool>/`. This avoids copying the 200-line persistence code of the 2.0 services ten times.
2. **Locked PDFs become an unlocked working copy.** The password is asked once while opening; every tool then works on a copy without it (in `ImportedPDFs/`, cleared at launch). *Consequence:* a result made from a locked PDF is not locked. Use Protect to lock it again.
3. **Passwords are limited to printable ASCII.** MuPDF encodes other characters as UTF-8, as PDF 2.0 says, and PDFKit then refuses the same password ("café" failed; "密码" worked). Protect shows a hint and stays disabled. When opening a PDF locked elsewhere, an accented password is tried as UTF-8 and as Latin-1.
4. **A PDF that opens freely but limits printing or copying** is unlocked only with its permissions (owner) password.
5. **With restrictions on, the owner password is random.** Otherwise the opening password would also lift the restrictions. Unlock still works with the opening password.
6. **Files: tapping a file still previews it** (as in 2.0). "Use a Tool" is in the preview's toolbar, on a leading swipe and in the context menu. The prototype opens the tool sheet on tap; that would have removed the preview on iPhone.
7. **Merge, Split and batch compress now open for everyone** and ask for Pro at the final button, like the new Pro tools. In 2.0 they asked when opened.
8. **An incoming PDF opens the tool sheet** (2.0 sent it straight to Compress). Several PDFs offer Compress and Merge. Images go to Photos to PDF.
9. **Photos to PDF:** JPEG and PNG are embedded untouched; a rotated JPEG is turned by the page, not re-encoded. "Fit to Photo" gives the page the photo's shape with an 842 pt long side. Images MuPDF can't read are decoded by ImageIO.
10. **PDF to Images:** one export is one item in Files. Pages larger than 8000 pixels on a side are exported at a lower resolution.
11. **Organize:** "Pages from Another PDF" inserts all its pages after the selection; duplicates and inserted pages carry no links or form fields of their own.
12. `FileItem.Kind` also gained `signed` (the prototype has a Signed filter).
13. **Commits:** the foundation and the four 2.1 tools were developed together. The foundation commit holds the shared code; each tool has its own commit with its engine, screen and tests. The app builds from the Protect & Unlock commit onward.

### 2.2: what was built

- **Scan to PDF:** the system document camera (VisionKit) for capture, edge detection and straightening; review with reorder, delete, retake and "Add"; Color, Grayscale and Black & White; "Make Text Searchable" (Pro) runs Recognize Text on the scan. Home gets the "Scan" entry point. Settings gets a default scan filter. Organize Pages can insert scanned pages.
- **Recognize Text:** Apple Vision reads each page at 200 dpi on the device. Searchable PDF adds the words as an invisible layer; Text Only saves a `.txt`. The result screen shows the text with a Copy button. Language is automatic, or one of Vision's languages.

**Demo path (no camera in the simulator):** `-demoScreen scan` fills the review screen with sample pages (2480 x 3508 pictures of an invoice with uneven light and noise); add `-demoPages 10`, `-demoFilter grayscale|blackAndWhite`, `-demoSearchable`, `-demoEmpty`, `-demoRun`. In DEBUG builds the empty scan screen also has "Use Sample Pages". On a device without a document camera the screen offers "Choose Photos" instead.

| Tool | Done when | Result |
|---|---|---|
| Scan to PDF | A 10-page scan is under 3 MB at Balanced; works on iPad and on the Duo's outer and inner cameras | 10 sample pages at Balanced: about 1.9 MB in color, 1.8 MB grayscale, 2.0 MB black and white. **These are synthetic pages**; real paper under real light may compress differently. Balanced stores pages at 140 dpi, JPEG quality 0.4, which reads cleanly. **Camera on iPhone, iPad and both Duo cameras: not tested, needs the owner.** |
| Recognize Text | A 20-page scan in under 30 s on an iPhone 15; text can be selected in Preview | 20 pages in about 28 s **on the simulator**, where Vision runs without the Neural Engine; an iPhone should be faster, but that is not measured. PDFKit finds and selects the words where they are printed, also on pages turned 90, 180 and 270 degrees. The page looks identical afterwards and the file grows by about 3%. |

### Choices made in 2.2

1. **Scan presets** use the names of the compress presets but their own numbers: Smallest 110 dpi, Balanced 140 dpi, Best Quality 200 dpi (the long side counted as A4). The compress presets (72 to 150 dpi) would make text too soft.
2. **The text layer is drawn with CoreGraphics and merged with MuPDF** (`mino_overlay_pages`, which the roadmap called `mino_add_text_layer`). CoreGraphics embeds a font for any script Vision reads; MuPDF then places that layer on the original page without rewriting the page.
3. **Pages that already have text** (12 letters or more) are not read again, so nothing is doubled.
4. **Black & White** is a high-contrast gray JPEG, not a 1-bit image.
5. Results of Recognize Text: the searchable PDF is filed under Scans, the text file under Converted.

### 2.3: what was built

Both tools share one page editor (`Mino/Features/Editor/`, `Mino/UI/Tasks/EditorFlowView.swift`): a PDFKit view, a row of tools, undo and redo, and a bar that changes with what is selected.

- **Fill & Sign:** tap a form field to fill it (text, multiline text, checkbox, radio button, dropdown, signature field); add a signature, initials, text, today's date, checkmarks and crosses anywhere. The signature is drawn once in a PencilKit pad and stored on the device (`Signatures/`, shown and deletable in Settings). Saving flattens everything.
- **Edit & Annotate:** text, highlight (follows the lines of text under the drag), freehand drawing, white-out, images, rectangle, ellipse, arrow and line; five colors and three stroke widths. Things placed can be selected, moved, resized (text and images), edited (text) and deleted. Saved as standard annotations; "Flatten on Save" is in the menu.

Demo screens: `-demoScreen sign` (a rental agreement with a name field and a checkbox, filled, dated and signed), `signature` (the pad), `edit` (house rules with a highlight, a drawing, a note and a white-out); add `-demoRun` to save.

| Tool | Done when | Result |
|---|---|---|
| Fill & Sign | A standard tax form and a rental contract can be filled, signed and reopened correctly in Preview and Acrobat | The real **IRS W-9**: name, address and a checkbox filled, signature and date placed, saved, reopened with PDFKit: no fields or stamps left, the typed text is page text, the checkmark and signature are drawn, the other pages are untouched. A rental contract without fields: signed, text and checkmarks added, all fixed in place. A form with every field type: all values kept, undo and redo restore them. **Not opened in Acrobat.** |
| Edit & Annotate | Annotations show correctly in Preview and Acrobat, and can be flattened | Saved without flattening, PDFKit reads them as FreeText, Highlight, Ink, Square, Line and Stamp, they show, and removing them elsewhere gives back the original page. Flattened, nothing is left to remove and the added text is page text. **Not opened in Acrobat.** |

### Choices made in 2.3

1. **Mino fills form fields itself.** A tap on a field opens a text sheet, toggles the box or shows the options; PDFKit's own field editing is switched off while the editor is open (and switched back before saving). This way the behavior is the same on every device and can be tested.
2. **Drawing on the page is captured from touch and Apple Pencil strokes** and stored as ink annotations. PencilKit is used for the signature pad only. A PencilKit canvas over a scrolling, zooming PDF view would have been much more code for the same result in the file.
3. **Saving:** PDFKit writes the document (bookmarks, links and field values survive; verified), then MuPDF flattens (`mino_bake`) and saves **without cleaning content streams**. With cleaning, the flattened W-9 came out unreadable for PDFKit.
4. **Fill & Sign always flattens** fields and additions. Edit & Annotate flattens on request, and **always when a white-out was added**: a cover that another app could lift off would be worse than none.
5. **White-out is not redaction.** The covered text stays in the file and can still be found by search. The editor says so under the tool, and a test documents it. Redaction stays out of scope (section 2).
6. **Added text uses Helvetica.** PDFKit can't write the system font into a PDF and falls back to a serif face.
7. **On a page that is shown turned**, stamps are turned back so they appear upright, and text is placed as an image, because free text would lie on its side.
8. **Resize** is offered for text, signatures, marks and images (Smaller and Larger buttons). Shapes, highlights and drawings can be moved and deleted, not resized.
9. A PDF that limits changes (permissions password) is refused with a pointer to Protect & Unlock.

### Known gaps after 2.3

- **Touch input (owner):** every tap, drag and the signature pad were exercised through the session's functions and screenshots, never with a finger. On a device, check: tapping fields, drawing a signature, placing and dragging things, drawing with one finger while two fingers scroll, and Apple Pencil on iPad.
- Not opened in Acrobat.
- The W-9's seven "tax classification" boxes are separate checkboxes to PDFKit, so checking one doesn't clear another.
- A date or text placed on a page that is shown turned is an image and can't be edited afterwards, only moved or deleted.
- No comb fields or field formatting scripts: a field shows exactly what was typed.

### Known gaps after 2.2

- **Camera (owner):** capture, retake, the Add tile, the camera opening by itself when Scan is tapped, and Organize Pages > Insert > Scan Pages all go through `VNDocumentCameraViewController` and have never run. Test on iPhone, iPad and the Duo (outer and inner camera).
- A page that lies on its side is read and can be searched, but the selection highlight doesn't follow the sideways letters. Rotate it in Organize Pages first.
- Handwriting and poor scans read badly, as with any on-device OCR. The result screen shows the text so it can be checked.

### Known gaps after 2.1

- **Needs a device (owner):** the Share Extension with images, Office files and several files; Save to Photos (the permission prompt); drag to reorder in the photo and page grids with a finger (the reorder logic is unit-tested, the gesture is not).
- Speed was measured on the simulator. Run the 50-photo case once on an iPhone.
- Acrobat was not available here; PDFKit and MuPDF both read every output.
- The demo sandbox paywall now shows the storefront's live price when the simulator can load the product (it showed $3.99 on a US simulator); the hard-coded €4.99 is only the fallback.
- English only. The String Catalog is ready for translation.
