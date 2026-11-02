# Slide Decks

A [page](/doc/pages) can show a finished slide deck above its text. Archsight does not make or render slides: the deck is
the file your slide tool produced, and the page is its summary. That works for every tool that can write a PDF or one
self-contained HTML page (Slidev, reveal.js, Marp, PowerPoint, Keynote, Google Slides, ...).

## Layout

One folder per deck, and one menu that lists them, so a large collection stays orderly:

```
resources/slides/
  menu.yaml                      # a PageMenu "Slides": spec.contains.pages lists the decks in display order
  2026-06-08-guardrails/
    2026-06-08-guardrails.md     # the page: frontmatter and a summary
    deck.pdf                     # the deck (or deck.html)
    cover.png                    # optional poster image
```

A deck page is an ordinary page: it is searchable, can link and embed, has an owner and tags, and is edited and exported
like any other. Page names are unique across the resources, so name the page after its folder rather than `index.md`.
Only `*.yaml` files are loaded, so the menu is `menu.yaml`. A deck missing from the menu appears under "Unsorted" and is
reported by `archsight lint`.

## Frontmatter

```yaml
---
title: Guardrails for the Target Picture
owner: Architecture Team
slides: deck.pdf        # or deck.html, a file next to the page
cover: cover.png        # optional; with a cover the page shows a poster and loads the deck on a click
---
The summary of the deck, in markdown.
```

`slides` and `cover` are resolved like images (relative to the page, never outside the resources directory). The page shows
the deck in a frame with **Full screen**, **Open** and **Download** links. The page's own PDF button still exports the
summary text. Without a cover the deck is shown right away.

## HTML decks run in a sandbox

An HTML deck is a program written by someone else, so it is served by `GET /api/v1/decks/<path>` (not as an image or asset)
and only with a `Content-Security-Policy` that starts with `sandbox allow-scripts` and has no `allow-same-origin`: the deck
cannot read the API, cookies or storage of Archsight, also when its file is opened on its own, and it cannot load data from
other hosts (`connect-src` allows only `blob:` and `data:`). Scripts, styles and fonts may be loaded from the hosts of
the setting `slides.script_hosts` (`ARCHSIGHT_SLIDES_SCRIPT_HOSTS`, `https://` hosts separated by spaces or commas), by default
`unpkg.com`, `cdn.jsdelivr.net` and `cdnjs.cloudflare.com`. Images
and media must be inside the file (`data:` or `blob:`).

PDF decks are served inline with `nosniff` and shown by the browser's own viewer.

## Making the file

- **Slidev:** `slidev export` for a PDF, or any tool that bundles the deck into one HTML file. A multi-file `dist/` folder
  is not supported yet.
- **PowerPoint, Keynote, Google Slides:** export as PDF.
- Files are limited to 25 MB.
