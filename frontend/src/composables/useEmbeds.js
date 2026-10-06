import { ref, nextTick } from 'vue'
import { viewSpec } from './useViewSpec.js'

// Views and analyses embedded in rendered markdown (`![[View/Name]]`). The server leaves a placeholder
//   <div class="kind-embed" data-kind="View" data-name="Name"><a href="...">Name</a></div>
// (the link is the fallback for consumers that do not run this). The page renders first; the host component
// teleports an <EmbeddedKind> into each placeholder, which loads its own content, so a slow query or
// analysis never delays the text around it.
//
// An inline view (a ```view block) is a placeholder that carries the spec of the view itself:
//   <div class="view-embed" data-title data-query data-fields data-sort data-type>...source...</div>
// Its entry has a `spec` instead of being loaded by name. The same for the requirements of a selection of resources
// (a ```requirements block): <div class="requirements-embed" data-title data-of data-priority data-status>, kind 'Requirements'.
const list = (raw) => (raw || '').split(',').filter(Boolean)

export function useEmbeds() {
  const embeds = ref([])

  async function scanEmbeds(container) {
    await nextTick()
    const found = container ? [...container.querySelectorAll('.kind-embed[data-kind][data-name], .view-embed[data-query], .requirements-embed[data-of]')] : []
    embeds.value = found.map((el, index) => {
      el.replaceChildren()
      if (el.classList.contains('requirements-embed')) {
        const d = el.dataset
        const spec = { of: d.of, priority: list(d.priority), status: list(d.status) }
        return { el, key: `requirements/${index}`, kind: 'Requirements', name: d.title, spec }
      }
      if (el.classList.contains('view-embed')) {
        const d = el.dataset
        const spec = viewSpec({ 'view/query': d.query, 'view/fields': d.fields, 'view/sort': d.sort, 'view/type': d.type })
        return { el, key: `inline/${index}`, kind: 'View', name: d.title, spec }
      }
      return { el, key: `${el.dataset.kind}/${el.dataset.name}`, kind: el.dataset.kind, name: el.dataset.name }
    })
  }

  return { embeds, scanEmbeds }
}
