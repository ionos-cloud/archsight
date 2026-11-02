// Page shell of the Archsight PDF export. Generic: every colour, font, logo and text comes from `theme`
// (see Archsight::Pdf::Theme), every per-document value is an argument.

#let labels = (
  en: (page: "Page", of: "of", contents: "Contents", draft: "DRAFT", doc-id: "Document ID", version: "Version", date: "Date", owner: "Owner", classification: "Classification"),
  de: (page: "Seite", of: "von", contents: "Inhalt", draft: "ENTWURF", doc-id: "Dokument-ID", version: "Version", date: "Datum", owner: "Eigentümer", classification: "Einstufung"),
)

// Identifiers have no spaces: allow a line break after `-`, `:` and `/` and between camel-case words (no visible change)
#let breakable(s) = if type(s) != str { s } else {
  s.replace(regex("([:/-])"), m => m.text + "\u{200B}").replace(regex("([a-z0-9])([A-Z])"), m => m.captures.at(0) + "\u{200B}" + m.captures.at(1))
}

// An image at its natural size, shrunk to fit the text width and `max-height` of the page, centred
#let fit-image(path, max-height: 0.5) = layout(size => context {
  let natural = measure(image(path))
  let limit = page.height * max-height
  let w = calc.min(natural.width, size.width)
  let h = w * (natural.height / natural.width)
  if h > limit {
    h = limit
    w = h * (natural.width / natural.height)
  }
  align(center, image(path, width: w, height: h))
})

// The meta line of the header: the document id in the mono font, the parts separated by a light bar
#let _meta-line(theme, id, version, date, owner) = {
  let t = labels.at(theme.lang)
  let parts = ()
  if "id" in theme.header-meta and id != none { parts.push(text(font: theme.font-mono, breakable(id))) }
  if "version" in theme.header-meta and version != none { parts.push(box[#t.version #version]) }
  if "date" in theme.header-meta and date != none { parts.push(box[#date]) }
  if "owner" in theme.header-meta and owner != none { parts.push(box[#owner]) }
  parts.join(h(4pt) + text(fill: theme.muted.lighten(60%), "|") + h(4pt))
}

// The document shell: page layout, header, footer, headings, watermark.
#let doc(
  theme: none,
  title: "",
  doc-id: none,
  version: none,
  date: none,
  owner: none,
  classification: none,
  draft: false,
  landscape: false,
  body,
) = {
  let t = labels.at(theme.lang)
  set document(title: title)
  set page(
    paper: theme.paper,
    flipped: landscape,
    margin: (x: theme.margin, top: 22mm, bottom: 16mm),
    header-ascent: 30%,
    footer-descent: 35%,
    header: grid(
      columns: (1fr, auto),
      align: (left + bottom, right + bottom),
      text(size: 7pt, fill: theme.muted.lighten(30%), _meta-line(theme, doc-id, version, date, owner)),
      if theme.logo != none { image(theme.logo, height: 6.5mm) },
    ),
    footer: {
      set text(size: 7pt, fill: theme.muted)
      line(length: 100%, stroke: 0.5pt + theme.muted.lighten(70%))
      v(-2pt)
      grid(
        columns: (1fr, auto, 1fr),
        column-gutter: 8pt,
        align: (left + horizon, center + horizon, right + horizon),
        if classification != none { text(weight: "bold", tracking: 0.06em, fill: theme.danger, classification) },
        if theme.footer-text != none { text(style: "italic", theme.footer-text) },
        context [#t.page #counter(page).display() #t.of #counter(page).final().first()],
      )
    },
    background: if draft {
      rotate(-45deg, text(size: 110pt, weight: "bold", fill: theme.muted.transparentize(85%), t.draft))
    },
  )
  set text(font: theme.font-body, size: 10pt, fill: theme.text, lang: theme.lang)
  set par(justify: false, leading: 0.62em)
  show raw: set text(font: theme.font-mono, size: 8.5pt)
  show raw.where(block: true): it => block(fill: luma(245), inset: 8pt, radius: 3pt, width: 100%, it)
  show heading: set text(font: theme.font-heading, fill: theme.primary)
  show heading.where(level: 1): set text(size: 16pt)
  show heading.where(level: 2): set text(size: 13pt)
  show heading.where(level: 3): set text(size: 11pt)
  show link: set text(fill: theme.accent)
  // Tables have horizontal rules only: a stronger one under the header, a light one under every other row, no frame and
  // no vertical lines; the first column is flush with the text. Tables that pass their own stroke keep it.
  set table(
    stroke: (x, y) => if y == 0 { (bottom: 0.7pt + theme.muted.lighten(35%)) } else { (bottom: 0.4pt + theme.muted.lighten(75%)) },
    inset: (x, y) => (left: if x == 0 { 0pt } else { 6pt }, right: 6pt, y: 6pt),
  )
  set table.cell(breakable: false)
  show table.header: set text(weight: "semibold")
  body
}

// Title with the kind at its right, a hairline directly below, then an optional intro
#let title-block(theme: none, title: "", kind: none, intro: none) = {
  grid(
    columns: (1fr, auto),
    align: (left + bottom, right + bottom),
    text(font: theme.font-heading, size: 22pt, weight: "bold", fill: theme.primary, breakable(title)),
    if kind != none { text(size: 8pt, fill: theme.muted, kind) },
  )
  v(-4pt)
  line(length: 100%, stroke: 0.5pt + theme.muted.lighten(70%))
  if intro != none { block(above: 8pt, below: 6pt, text(size: 9pt, fill: theme.muted, intro)) }
}

// A cover page without header and footer: a band with the logo at its bottom left, kind, title and a short rule, the
// document meta at the bottom left of the page. The pages after it are numbered from 1.
#let cover-page(theme: none, title: "", kind: none, doc-id: none, version: none, date: none, owner: none, classification: none) = {
  let t = labels.at(theme.lang)
  page(header: none, footer: none, margin: 0mm, background: none)[
    #block(width: 100%, height: 52mm, fill: theme.primary, inset: (x: theme.margin, bottom: 12mm), align(left + bottom, if theme.logo-light != none { image(theme.logo-light, height: 9mm) }))
    #block(width: 100%, inset: (x: theme.margin, top: 34mm), {
      if kind != none {
        text(size: 7.5pt, weight: 600, tracking: 0.04em, fill: theme.accent, upper(kind))
        v(2pt)
      }
      par(leading: 0.4em, text(font: theme.font-heading, size: 28pt, weight: "bold", fill: theme.primary, breakable(title)))
      v(10pt)
      line(length: 36mm, stroke: 2pt + theme.accent)
    })
    #let meta = (
      (t.doc-id, if doc-id != none { text(font: theme.font-mono, breakable(doc-id)) }),
      (t.version, version),
      (t.date, date),
      (t.owner, owner),
      (t.classification, if classification != none { text(weight: "bold", fill: theme.danger, classification) }),
    ).filter(m => m.at(1) != none)
    #place(bottom + left, dx: theme.margin, dy: -20mm, grid(
      columns: 2,
      column-gutter: 14pt,
      row-gutter: 7pt,
      ..meta.map(((k, v)) => (text(size: 8pt, fill: theme.muted, k), text(size: 9pt, v))).flatten(),
    ))
    // the pages after the cover count from 1 (set inside the cover, so that nothing after it forces another page)
    #counter(page).update(0)
  ]
}

#let toc-page(theme: none, depth: 3) = {
  let t = labels.at(theme.lang)
  outline(title: t.contents, depth: depth)
  pagebreak()
}
