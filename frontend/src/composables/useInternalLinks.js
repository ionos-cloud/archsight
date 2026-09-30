import { onMounted, onBeforeUnmount } from 'vue'
import { useRouter } from 'vue-router'

const INTERNAL_PREFIXES = ['/kinds/', '/pages/', '/doc/']

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

  onMounted(() => {
    containerRef.value?.addEventListener('click', handleClick)
  })

  onBeforeUnmount(() => {
    containerRef.value?.removeEventListener('click', handleClick)
  })
}
