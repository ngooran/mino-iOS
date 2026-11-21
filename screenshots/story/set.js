// Mino store screenshots: the frames, the copy, and how one frame is drawn.
//
// Everything shared (canvases, the device mock, headline fit, the gallery, the export) is
// ShotKit. This file is only what is Mino's. The plan and its reasons: ../screenshot-plan.md.
// Read ShotKit docs/approach.md and docs/rules.md before changing the order or the copy.

const DEVICES = ShotKit.devices({ iphone: {}, ipad: {}, duo: {} });
const LOC = ShotKit.param('loc', 'en');
const { px, esc, headHTML, deviceHTML } = ShotKit;

// ../raw/<iPhone|iPad|Duo-inner>/<locale>/<shot>.png, written by ../capture.sh.
const rawSrc = (dev, shot) => `../raw/${DEVICES[dev].raw}/${LOC}/${shot}.png`;

// Store order. Frame 1 is the install pitch; frames 1 to 3 show in search results.
// `pro: true` puts the Pro mark on a frame that shows a paid feature (Guideline 2.3.2).
const SLOTS = [
  { key: 'hero',     shot: '01_Home' },
  { key: 'scan',     shot: '02_Scan' },
  { key: 'sign',     shot: '03_Sign', pro: true, zoom: 'sign' },
  { key: 'photos',   shot: '04_Photos' },
  { key: 'office',   shot: '05_Office', pro: true },
  { key: 'compress', shot: '06_Compress', zoom: 'compress' },
  { key: 'edit',     shot: '07_Edit', pro: true, zoom: 'edit' },
  { key: 'organize', shot: '08_Organize' },
  { key: 'ocr',      shot: '09_OCR', pro: true, zoom: 'ocr' },
  { key: 'images',   shot: '10_Images' },
];

// `head`: `|` breaks a line, everything after `§` is the accent. `sub`: the proof line.
// Nothing about price: no price, no "free", no "subscription", no "one purchase" (2.3.7).
// Never "PDF to Word"; "sign" is a drawn signature, never "legally binding".
const EN = {
  hero:     { head: 'Every PDF tool.|§Offline.',      sub: 'Scan, sign, convert and compress. Your files never leave your device.' },
  scan:     { head: 'Scan paper|§into clean PDFs',    sub: 'Edges found, pages straightened, in color or black and white.' },
  sign:     { head: 'Fill and sign|§in seconds',      sub: 'Type into form fields, then add your signature and the date.' },
  photos:   { head: 'Turn photos|§into a PDF',        sub: 'JPG, PNG and HEIC, in the order you choose.' },
  office:   { head: 'Office files|§to PDF',           sub: 'Word, Excel and PowerPoint, converted on your device.' },
  compress: { head: 'Shrink big PDFs|§to send them',  sub: 'See the size of each setting before you compress.' },
  edit:     { head: 'Highlight, draw|§and add text',  sub: 'Mark up any PDF with your finger or Apple Pencil.' },
  organize: { head: 'Rotate, delete,|§reorder pages', sub: 'Drag pages into place, or add pages from another PDF.' },
  ocr:      { head: 'Make scans|§searchable',         sub: 'Text is recognized on your device, ready to copy.' },
  images:   { head: 'PDF pages|§to images',           sub: 'Every page as JPG or PNG, saved to Photos.' },
  pro: 'Mino Pro',
};
const TR = (typeof I18N !== 'undefined' && I18N[LOC]) || {};
const copy = (key) => ShotKit.copy(EN, TR, key);

// Three looks for the owner to choose from. All use the icon's teal.
const DIRECTIONS = {
  A: { name: 'Clean Paper', tag: 'light, calm, one teal line through the row',
       pitch: 'White paper and ink with a teal accent. Reads like a document app; the light frames sit well next to the light app screens.' },
  B: { name: 'Night Teal', tag: 'dark teal, white type, pages drifting across the edges',
       pitch: 'A dark stage like the dark icon, so the light screens glow. Folded pages from the icon cross from one frame into the next.' },
  C: { name: 'Icon Teal', tag: 'the icon\'s own gradient, bold white type',
       pitch: 'Every frame in the icon\'s teal, so icon and screenshots read as one in search. A soft white wave runs through the row.' },
};

// Per device: where the text sits and how big the device is. Canvas units are CSS px
// (iPhone 402 x 874, iPad 516 x 688, Duo 951 x 669, landscape). Frame 1 gets the biggest device.
function geom(dev, k) {
  const { W } = DEVICES[dev];
  const hero = k === 0;
  if (dev === 'iphone') return { tx: 30, ty: 54, tw: W - 60, devW: hero ? 318 : 300, devY: hero ? 250 : 264, head: hero ? 40 : 35, sub: 14.5 };
  if (dev === 'ipad')   return { tx: 40, ty: 40, tw: W - 80, devW: hero ? 410 : 392, devY: hero ? 206 : 218, head: hero ? 36 : 32, sub: 13 };
  return { tx: 38, ty: hero ? 196 : 206, tw: 252, devW: 610, devY: 118, devX: W - 610 - 24, head: hero ? 42 : 37, sub: 15 };
}

function panel(dev, k) {
  const { W } = DEVICES[dev];
  const G = geom(dev, k), s = SLOTS[k], c = copy(s.key);
  const x = dev === 'duo' ? G.devX : (W - G.devW) / 2;
  return `<div class="txt" style="left:${px(G.tx)};top:${px(G.ty)};width:${px(G.tw)}">
      ${s.pro ? `<div class="pro-tab">${esc(copy('pro'))}</div>` : '<div class="pro-tab spacer"></div>'}
      <h1 class="head" data-fit style="font-size:${px(G.head)}">${headHTML(c.head)}</h1>
      <div class="sub" style="font-size:${px(G.sub)}">${esc(c.sub)}</div></div>
    ${deviceHTML(dev, rawSrc(dev, s.shot), x, G.devY, G.devW)}`;
}

// ---------- close-ups: a piece of the real capture, enlarged over the device ----------

// [x0, y0, x1, y1] as fractions of each device's capture (measured on the English captures of
// 21 Nov 2026; re-check them whenever the captures are retaken). On the Duo the signature sits
// under the hint bar, so its sign close-up shows the filled fields and the checkbox.
const ZOOMS = {
  sign:     { iphone: [0.06, 0.395, 0.62, 0.58],  ipad: [0.42, 0.41, 0.76, 0.60],  duo: [0.44, 0.52, 0.72, 0.69] },
  compress: { iphone: [0.08, 0.365, 0.94, 0.585], ipad: [0.39, 0.25, 0.99, 0.39],  duo: [0.42, 0.38, 0.92, 0.66] },
  edit:     { iphone: [0.08, 0.345, 0.98, 0.45],  ipad: [0.41, 0.36, 0.85, 0.475], duo: [0.44, 0.44, 0.80, 0.61] },
  ocr:      { iphone: [0.06, 0.395, 0.98, 0.60],  ipad: [0.38, 0.265, 0.99, 0.40], duo: [0.41, 0.41, 0.90, 0.70] },
};
// How large a close-up may get, and where: below the region it enlarges, inside the frame.
const ZOOM_OPTS = {
  iphone: { mag: 1.55, maxW: 374, maxH: 250, margin: 14, dy: 46 },
  ipad:   { mag: 2.1, maxW: 448, maxH: 300, margin: 18, dy: 54 },
  duo:    { mag: 2.0, maxW: 560, maxH: 330, margin: 18, dy: 70 },
};

// Strip-wide, so it uses strip coordinates; a close-up stays inside its own frame.
function zoomLayer(dev, i) {
  const s = SLOTS[i];
  if (!s.zoom) return '';
  const { W } = DEVICES[dev];
  const G = geom(dev, i);
  const x = dev === 'duo' ? G.devX : (W - G.devW) / 2;
  const scr = ShotKit.screenRect(dev, i * W + x, G.devY, G.devW);
  const o = { ...ZOOM_OPTS[dev], minY: G.devY + 30 };
  return ShotKit.zoomHTML(dev, i, rawSrc(dev, s.shot), ZOOMS[s.zoom][dev], scr, o);
}

// ---------- strip-wide layers: one continuous thing per direction ----------

// A: one teal line through the whole row, behind the devices.
function lineA(dev) {
  const { W, H } = DEVICES[dev];
  const n = SLOTS.length;
  // Between the text and the top of the device, never through the text.
  const y = { iphone: 0.272, ipad: 0.298, duo: 0.88 }[dev];
  const amp = { iphone: 0.01, ipad: 0.008, duo: 0.04 }[dev];
  const pts = [[-W / 2, y * H]];
  for (let k = 0; k < n; k++) pts.push([k * W + W / 2, (y + amp * (k % 2 ? 1 : -1)) * H]);
  pts.push([n * W + W / 2, y * H]);
  return `<svg class="line-a" width="${n * W}" height="${H}" viewBox="0 0 ${n * W} ${H}">
      <path d="${ShotKit.easePath(pts)}" fill="none" stroke-width="${dev === 'duo' ? 5 : 4}" stroke-linecap="round"/></svg>`;
}

// B: folded pages (the icon's page) straddling every frame edge.
function pagesB(dev) {
  const { W, H } = DEVICES[dev];
  const n = SLOTS.length;
  const s = dev === 'duo' ? 1.2 : 1;
  const page = (cx, cy, w, rot, o) => {
    const h = w * 1.3, f = w * 0.26, r = w * 0.09;
    const x0 = -w / 2, y0 = -h / 2;
    const d = `M${x0 + r},${y0} H${w / 2 - f} L${w / 2},${y0 + f} V${h / 2 - r} Q${w / 2},${h / 2} ${w / 2 - r},${h / 2} H${x0 + r} Q${x0},${h / 2} ${x0},${h / 2 - r} V${y0 + r} Q${x0},${y0} ${x0 + r},${y0} Z`;
    return `<g transform="translate(${cx},${cy}) rotate(${rot})" opacity="${o}"><path d="${d}" class="pg"/>
      <path d="M${w / 2 - f},${y0} V${y0 + f} H${w / 2} Z" class="fold"/></g>`;
  };
  let out = '';
  for (let k = 1; k < n; k++) {
    const up = k % 2 === 0;
    const cy = (dev === 'duo' ? (up ? 0.12 : 0.9) : (up ? 0.07 : 0.93)) * H;
    out += page(k * W, cy, 120 * s, up ? -12 : 10, 0.11);
  }
  return `<svg class="pages-b" width="${n * W}" height="${H}" viewBox="0 0 ${n * W} ${H}">${out}</svg>`;
}

// C: a soft white wave through the whole row.
function waveC(dev) {
  const { W, H } = DEVICES[dev];
  const n = SLOTS.length;
  const y = { iphone: 0.62, ipad: 0.66, duo: 0.7 }[dev];
  const top = [[-W / 2, y * H]];
  for (let k = 0; k <= n; k++) top.push([k * W, (y + (k % 2 ? -0.07 : 0.05)) * H]);
  top.push([n * W + W / 2, y * H]);
  const d = `${ShotKit.easePath(top)} L${n * W + W / 2},${H} L${-W / 2},${H} Z`;
  return `<svg class="wave-c" width="${n * W}" height="${H}" viewBox="0 0 ${n * W} ${H}"><path d="${d}"/></svg>`;
}

const LAYERS = { A: lineA, B: pagesB, C: waveC };

function frameHTML(dir, dev, i) {
  const d = DIRECTIONS[dir] ? dir : 'A';
  return ShotKit.stripFrame(dev, i, [
    { html: LAYERS[d](dev) },
    { html: ShotKit.panels(dev, i, SLOTS.length, (k) => panel(dev, k)) },
    { html: zoomLayer(dev, i), cls: 'zooms' },
  ], `frame dir-${d}`);
}

ShotKit.mount({
  name: 'Mino',
  loc: LOC,
  locales: ['en', ...Object.keys(typeof I18N !== 'undefined' ? I18N : {})],
  slots: SLOTS,
  directions: DIRECTIONS,
  direction: 'B',
  store: true,
  frame: (dir, dev, i) => frameHTML(dir, dev, i),
});
