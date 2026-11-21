// Per-locale copy, keyed by app locale code, same shape as EN in set.js. Headline format: `|`
// breaks a line, everything after `§` is the accent. Tool names follow the app's own strings
// (Mino/Localizable.xcstrings). Registers as in the app: de du, es tú. No French: Mino 2.0 is
// not sold in France (RELEASE-2.0.md, "Export compliance").
// Nothing about price (no price, "kostenlos"/"gratis", "Abo"/"suscripción"): Guideline 2.3.7.
const I18N = {
  de: {
    hero:     { head: 'Alles für PDFs.|§Offline.',         sub: 'Scannen, unterschreiben, umwandeln, verkleinern: jedes Werkzeug, und deine Dateien verlassen nie dein Gerät.' },
    scan:     { head: 'Papier scannen|§als sauberes PDF',  sub: 'Kanten erkannt, Seiten gerade gerückt, in Farbe oder Schwarzweiß.' },
    sign:     { head: 'Ausfüllen und|§signieren',          sub: 'Tippe in die Formularfelder, dann setze Unterschrift und Datum.' },
    photos:   { head: 'Fotos|§in ein PDF',                 sub: 'JPG, PNG und HEIC, in der Reihenfolge, die du wählst.' },
    office:   { head: 'Office-Dateien|§in PDF',            sub: 'Word, Excel und PowerPoint, umgewandelt auf deinem Gerät.' },
    compress: { head: 'Große PDFs|§verkleinern',           sub: 'Sieh die Größe jeder Einstellung, bevor du komprimierst.' },
    edit:     { head: 'Markieren|§und zeichnen',          sub: 'Füge Text hinzu und bearbeite jedes PDF mit dem Finger oder dem Apple Pencil.' },
    organize: { head: 'Seiten drehen,|§löschen, ordnen',   sub: 'Zieh Seiten an ihren Platz oder füge Seiten aus einem anderen PDF ein.' },
    ocr:      { head: 'Text in Scans|§finden',             sub: 'Der Text wird auf deinem Gerät erkannt, bereit zum Kopieren.' },
    images:   { head: 'PDF-Seiten|§als Bilder',            sub: 'Jede Seite als JPG oder PNG, in Fotos gesichert.' },
  },
  es: {
    hero:     { head: 'Tus PDF,|§sin conexión.',           sub: 'Escanea, firma, convierte y comprime: todas las herramientas, sin que tus archivos salgan de tu dispositivo.' },
    scan:     { head: 'Escanea papel|§en PDF nítidos',     sub: 'Bordes detectados, páginas enderezadas, en color o en blanco y negro.' },
    sign:     { head: 'Rellena y firma|§en segundos',      sub: 'Escribe en los campos del formulario y añade tu firma y la fecha.' },
    photos:   { head: 'Convierte fotos|§en un PDF',        sub: 'JPG, PNG y HEIC, en el orden que elijas.' },
    office:   { head: 'Archivos de Office|§a PDF',         sub: 'Word, Excel y PowerPoint, convertidos en tu dispositivo.' },
    compress: { head: 'Reduce PDF|§para enviarlos',        sub: 'Haz pequeños los PDF grandes y mira el tamaño de cada ajuste antes de comprimir.' },
    edit:     { head: 'Resalta, dibuja|§y añade texto',    sub: 'Marca cualquier PDF con el dedo o con el Apple Pencil.' },
    organize: { head: 'Gira, elimina|§y ordena páginas',   sub: 'Arrastra páginas a su sitio o añade páginas de otro PDF.' },
    ocr:      { head: 'Busca texto|§en tus escaneos',      sub: 'El texto se reconoce en tu dispositivo, listo para copiar.' },
    images:   { head: 'Páginas PDF|§a imágenes',           sub: 'Cada página como JPG o PNG, guardada en Fotos.' },
  },
};
