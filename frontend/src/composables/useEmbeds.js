import { ref, nextTick } from 'vue'

// Views and analyses embedded in rendered markdown (`![[View/Name]]`). The server leaves a placeholder
//   <div class="kind-embed" data-kind="View" data-name="Name"><a href="...">Name</a></div>
// (the link is the fallback for consumers that do not run this). The page renders first; the host component
// teleports an <EmbeddedKind> into each placeholder, which loads its own content, so a slow query or
// analysis never delays the text around it.
export function useEmbeds() {
  const embeds = ref([])

  async function scanEmbeds(container) {
    await nextTick()
    embeds.value = container
      ? [...container.querySelectorAll('.kind-embed[data-kind][data-name]')].map((el) => {
          el.replaceChildren()
          return { el, kind: el.dataset.kind, name: el.dataset.name }
        })
      : []
  }

  return { embeds, scanEmbeds }
}
