import { watch, onBeforeUnmount } from 'vue'
import { useRouter } from 'vue-router'

const INTERNAL_PREFIXES = ['/kinds/', '/pages/', '/doc/']

// Links to other views inside `containerRef` navigate in-app instead of reloading the page.
// The container often appears after the component mounted (content that loads first), so the
// listener follows the element instead of attaching once on mount.
export function useInternalLinks(containerRef) {
  const router = useRouter()

  function handleClick(e) {
    const anchor = e.target.closest('a[href]')
    if (!anchor) return
    const href = anchor.getAttribute('href')
    if (!href || !INTERNAL_PREFIXES.some((prefix) => href.startsWith(prefix))) return
    e.preventDefault()
    router.push(href)
  }

  watch(containerRef, (element, previous) => {
    previous?.removeEventListener('click', handleClick)
    element?.addEventListener('click', handleClick)
  }, { immediate: true, flush: 'post' })

  onBeforeUnmount(() => {
    containerRef.value?.removeEventListener('click', handleClick)
  })
}
