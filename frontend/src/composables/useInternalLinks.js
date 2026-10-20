import { watch, onBeforeUnmount } from 'vue'
import { useRouter } from 'vue-router'
import { anchorTarget } from './useRouteFocus.js'

const INTERNAL_PREFIXES = ['/kinds/', '/pages/', '/doc/']

// Links to other views inside `containerRef` navigate in-app instead of reloading the page, and a
// `#section` link of the same page goes through the router too, so it is an entry of the history.
// The container often appears after the component mounted (content that loads first), so the
// listener follows the element instead of attaching once on mount.
export function useInternalLinks(containerRef) {
  const router = useRouter()

  function handleClick(e) {
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
    const anchor = e.target.closest('a[href]')
    if (!anchor || (anchor.target && anchor.target !== '_self')) return
    const href = anchor.getAttribute('href')
    if (href?.startsWith('#') && href.length > 1) {
      e.preventDefault()
      const current = router.currentRoute.value
      if (current.hash === href) anchorTarget(href)?.scrollIntoView({ behavior: 'smooth' })
      else router.push({ query: current.query, hash: href })
      return
    }
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
