<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue'
import { displayName } from '../../composables/useFormatting.js'
import { useInternalLinks } from '../../composables/useInternalLinks.js'
import { configPreviewUrl, assetUrl } from '../../api/client.js'

// Detail view of a Config of type pdf: the settings as they look (palette, fonts, logos, page texts) and, beside
// them, the real thing: the sample document the server typesets with exactly these settings.
const props = defineProps({
  data: Object,
  kindMeta: Object,
})

// The built-in look (Archsight::Pdf::Theme): what a setting that is left out falls back to
const COLOURS = [
  { key: 'primary', label: 'Primary', use: 'headings, cover band, table headers', fallback: '#1f3a5f', tall: true },
  { key: 'accent', label: 'Accent', use: 'rules and links', fallback: '#2f7fd1', tall: true },
  { key: 'text', label: 'Text', fallback: '#1c1c1c' },
  { key: 'muted', label: 'Muted', fallback: '#6b7280' },
  { key: 'ok', label: 'Positive', fallback: '#1f9d55' },
  { key: 'warn', label: 'Warning', fallback: '#d98e04' },
  { key: 'danger', label: 'Danger', fallback: '#c0392b' },
]
const FONTS = [
  { key: 'body', label: 'Body text' },
  { key: 'heading', label: 'Headings' },
  { key: 'mono', label: 'Code and ids' },
]
const PAPERS = { a4: 'A4', a5: 'A5', 'us-letter': 'US Letter' }
const LANGUAGES = { en: 'English', de: 'German' }

const annotations = computed(() => props.data.metadata?.annotations || {})
const description = computed(() => annotations.value['architecture/description'])
const get = (key) => annotations.value[`pdf/${key}`]

const palette = computed(() => COLOURS.map((c) => {
  const value = get(`color-${c.key}`)
  const hex = value || c.fallback
  return { ...c, hex, builtin: !value, ink: readableInk(hex) }
}))
const fonts = computed(() => FONTS.map((f) => ({ ...f, family: get(`font-${f.key}`) })))
const primary = computed(() => palette.value[0].hex)
const logos = computed(() => ({
  onWhite: get('logo') ? assetUrl(get('logo')) : null,
  onBand: (get('logo-light') || get('logo')) ? assetUrl(get('logo-light') || get('logo')) : null,
}))
const facts = computed(() => [
  { label: 'Paper', value: PAPERS[get('paper')] || 'A4' },
  { label: 'Language', value: LANGUAGES[get('lang')] || 'English' },
  { label: 'Margin', value: get('margin') || '16mm' },
  { label: 'Header line', value: (get('header-meta') || 'id, version, date, owner').replace(/\s*,\s*/g, ', ') },
  { label: 'Footer text', value: get('footer-text') },
  { label: 'Classification', value: get('classification') },
  { label: 'Font directory', value: get('font-dir') },
])

// black or white text, whichever reads better on the colour
function readableInk(hex) {
  const h = hex.replace('#', '')
  const full = h.length === 3 ? [...h].map((c) => c + c).join('') : h
  const [r, g, b] = [0, 2, 4].map((i) => parseInt(full.slice(i, i + 2), 16) / 255)
    .map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4))
  return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.4 ? '#111' : '#fff'
}

// ---- preview: fetched, so that a missing typst or a broken setting is said in words, not shown as JSON in a frame.
// The cover and the page are two documents of one page each, fetched when first shown (no navigation inside the viewer).
const part = ref('cover') // cover | page
const state = ref('loading') // loading | ready | error
const problem = ref('')
const blobUrl = ref(null)
const urls = {} // part -> object URL of its PDF
let request = 0

async function show(which) {
  part.value = which
  const mine = ++request
  if (urls[which]) {
    blobUrl.value = urls[which]
    state.value = 'ready'
    return
  }
  state.value = 'loading'
  try {
    const res = await fetch(configPreviewUrl(props.data.name, which))
    if (!res.ok) {
      const err = await res.json().catch(() => ({ message: res.statusText }))
      const error = new Error(err.message || res.statusText)
      error.status = res.status
      throw error
    }
    urls[which] = URL.createObjectURL(await res.blob())
    if (mine !== request) return
    blobUrl.value = urls[which]
    state.value = 'ready'
  } catch (e) {
    if (mine !== request) return
    problem.value = e.status === 503
      ? 'The server cannot typeset PDFs because typst is not installed there.'
      : e.message
    state.value = 'error'
  }
}

function release() {
  Object.keys(urls).forEach((key) => { URL.revokeObjectURL(urls[key]); delete urls[key] })
  blobUrl.value = null
}

const frameSrc = computed(() => blobUrl.value && `${blobUrl.value}#toolbar=0&navpanes=0&view=Fit`)

watch(() => props.data.name, () => { release(); show('cover') }, { immediate: true })
onBeforeUnmount(() => { request++; release() })

const descEl = ref(null)
useInternalLinks(descEl)
</script>

<template>
  <article class="pdf-config">
    <header>
      <h2>
        <i v-if="kindMeta" :class="`iconoir-${kindMeta.icon} icon-${kindMeta.layer}`"></i>
        <div class="instance-title-text">
          <span class="instance-name">{{ displayName(data.name, 'Config') }}</span>
          <span class="instance-kind-subtitle">Config for the PDF export</span>
        </div>
      </h2>
      <div class="header-actions">
        <router-link class="btn-header" :to="`/kinds/Config/instances/${encodeURIComponent(data.name)}/edit`" title="Edit this resource">
          <i class="iconoir-edit-pencil"></i> Edit
        </router-link>
      </div>
    </header>
    <div ref="descEl" v-if="description" class="description-box prose" v-html="description"></div>

    <div class="sheet">
      <div class="settings">
        <section aria-labelledby="pdf-colours">
          <h3 id="pdf-colours">Colours</h3>
          <ul class="palette">
            <li v-for="c in palette" :key="c.key" :class="{ tall: c.tall }" :style="{ background: c.hex, color: c.ink }">
              <span class="role">
                {{ c.label }}
                <small v-if="c.use">{{ c.use }}</small>
              </span>
              <code>{{ c.hex }}<small v-if="c.builtin"> built-in</small></code>
            </li>
          </ul>
        </section>

        <section aria-labelledby="pdf-type">
          <h3 id="pdf-type">Fonts</h3>
          <dl class="facts">
            <template v-for="f in fonts" :key="f.key">
              <dt>{{ f.label }}</dt>
              <dd :class="{ unset: !f.family }">{{ f.family || 'built-in' }}</dd>
            </template>
          </dl>
        </section>

        <section aria-labelledby="pdf-logos">
          <h3 id="pdf-logos">Logo</h3>
          <div class="logos">
            <figure class="on-white">
              <img v-if="logos.onWhite" :src="logos.onWhite" alt="Logo on white, as in the page header" />
              <span v-else class="unset">No logo</span>
              <figcaption>Page header</figcaption>
            </figure>
            <figure class="on-band" :style="{ background: primary }">
              <img v-if="logos.onBand" :src="logos.onBand" alt="Logo on the cover band" />
              <span v-else class="unset">No logo</span>
              <figcaption :style="{ color: palette[0].ink }">Cover band</figcaption>
            </figure>
          </div>
        </section>

        <section aria-labelledby="pdf-page">
          <h3 id="pdf-page">Page</h3>
          <dl class="facts">
            <template v-for="f in facts" :key="f.label">
              <template v-if="f.value">
                <dt>{{ f.label }}</dt>
                <dd>{{ f.value }}</dd>
              </template>
            </template>
          </dl>
        </section>
      </div>

      <section class="preview" aria-labelledby="pdf-preview">
        <div class="preview-bar">
          <h3 id="pdf-preview">Preview</h3>
          <div class="pager" role="group" aria-label="Part of the sample">
            <button type="button" class="outline" :class="{ secondary: part !== 'cover' }" :aria-pressed="part === 'cover'" @click="show('cover')">Cover</button>
            <button type="button" class="outline" :class="{ secondary: part !== 'page' }" :aria-pressed="part === 'page'" @click="show('page')">Page</button>
          </div>
          <a v-if="blobUrl" class="btn-header" :href="blobUrl" target="_blank" rel="noopener" title="Open the sample in its own tab">
            <i class="iconoir-open-new-window"></i> Open
          </a>
        </div>

        <div class="frame" :aria-busy="state === 'loading'">
          <iframe v-if="state === 'ready'" :key="part" :src="frameSrc" title="Sample document in the look of this Config"></iframe>
          <p v-else-if="state === 'loading'" class="note" role="status">Typesetting the sample…</p>
          <div v-else class="note failed" role="alert">
            <i class="iconoir-warning-triangle"></i>
            <p><strong>The preview could not be made.</strong> {{ problem }}</p>
          </div>
        </div>
        <p class="hint">A fixed sample with this Config's settings, as the PDF export typesets it. Save a change to see it here.</p>
      </section>
    </div>
  </article>
</template>

<style scoped>
.instance-title-text {
  display: flex;
  flex-direction: column;
  line-height: 1;
}

.instance-kind-subtitle {
  font-size: var(--fs-xs);
  font-weight: 400;
  color: var(--pico-muted-color);
  opacity: 0.7;
  margin-top: 0.1em;
}

.instance-name {
  font-weight: 600;
  color: var(--pico-primary);
}

.pdf-config h2 {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.btn-header {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  width: auto;
  margin: 0;
  padding: 0.4rem 0.75rem;
  font-size: var(--fs-sm);
  color: var(--pico-muted-color);
  background: transparent;
  border: 1px solid transparent;
  border-radius: var(--pico-border-radius);
  text-decoration: none;
  cursor: pointer;
  transition: all 0.15s ease;
}

.btn-header:hover,
.btn-header:focus-visible {
  color: var(--pico-primary);
  border-color: var(--pico-primary);
}

.sheet {
  display: grid;
  grid-template-columns: minmax(0, 1fr);
  gap: var(--space-5);
  margin-top: var(--space-4);
}

/* the preview is the point of the page: first on a narrow screen, beside the settings on a wide one */
.preview { order: -1; }

@media (min-width: 900px) {
  .sheet { grid-template-columns: minmax(18rem, 22rem) minmax(0, 1fr); align-items: start; }
  .preview { order: 0; position: sticky; top: var(--space-4); }
}

h3 {
  margin: 0 0 var(--space-2);
  font-size: var(--fs-md);
  font-weight: var(--fw-strong);
}

.settings section + section { margin-top: var(--space-5); }

/* the palette is a stack of its own colours, the two that carry the look are taller */
.palette {
  margin: 0;
  padding: 0;
  list-style: none;
  border-radius: var(--pico-border-radius);
  overflow: hidden;
  border: 1px solid var(--line);
}

.palette li {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3);
  min-height: 2.4rem;
  padding: 0 var(--space-3);
  margin: 0;
  font-size: var(--fs-sm);
}

.palette li.tall { min-height: 3.6rem; }
.palette .role { display: flex; flex-direction: column; font-weight: var(--fw-strong); line-height: var(--lh-tight); }
.palette small { font-weight: 400; opacity: 0.8; font-size: var(--fs-2xs); }
.palette code { background: none; color: inherit; padding: 0; font-size: var(--fs-xs); text-align: right; }

.facts {
  display: grid;
  grid-template-columns: max-content minmax(0, 1fr);
  gap: var(--space-1) var(--space-4);
  margin: 0;
  font-size: var(--fs-sm);
}

.facts dt { color: var(--pico-muted-color); }
.facts dd { margin: 0; overflow-wrap: anywhere; }
.unset { color: var(--pico-muted-color); }

.logos { display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-2); margin: 0; }

.logos figure {
  margin: 0;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  gap: var(--space-3);
  min-height: 5.5rem;
  padding: var(--space-3);
  border: 1px solid var(--line);
  border-radius: var(--pico-border-radius);
  font-size: var(--fs-2xs);
}

.logos .on-white { background: #fff; color: #555; }
.logos .on-band { border-color: transparent; }
.logos img { display: block; max-width: 100%; max-height: 2rem; object-fit: contain; object-position: left; }
.logos figcaption { margin: 0; padding: 0; background: none; color: inherit; font-size: var(--fs-2xs); }
.logos .on-white .unset { color: #777; }
.logos .on-band .unset { color: inherit; opacity: 0.7; }

.preview-bar { display: flex; align-items: center; gap: var(--space-2); margin-bottom: var(--space-2); }
.preview-bar h3 { margin: 0 auto 0 0; }

.pager[role="group"] { display: inline-flex; width: auto; margin: 0; }
.pager[role="group"] button {
  flex: 0 0 auto;
  width: auto;
  margin: 0;
  padding: 0.25rem 0.75rem;
  font-size: var(--fs-xs);
}

.frame {
  /* a sheet of paper: A4 proportions, as tall as the screen allows, so that a whole page is in view */
  aspect-ratio: 210 / 297;
  width: min(100%, calc(78vh / 1.414));
  min-width: min(100%, 18rem);
  margin: 0 auto;
  border: 1px solid var(--line);
  border-radius: var(--pico-border-radius);
  background: var(--tint);
  overflow: hidden;
}

.frame iframe { display: block; width: 100%; height: 100%; border: 0; background: #fff; }

.note {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: var(--space-3);
  height: 100%;
  margin: 0;
  padding: var(--space-4);
  color: var(--pico-muted-color);
  text-align: center;
}

.note.failed { color: var(--pico-del-color); }
.note.failed p { margin: 0; max-width: 32rem; }

.hint { margin: var(--space-2) 0 0; font-size: var(--fs-xs); color: var(--pico-muted-color); }
</style>
