import { onMounted, onBeforeUnmount } from 'vue'
import { useRouter } from 'vue-router'

export function useInternalLinks(containerRef) {
  const router = useRouter()

  function handleClick(e) {
    const anchor = e.target.closest('a[href]')
    if (!anchor) return
    const href = anchor.getAttribute('href')
    if (!href || !href.startsWith('/kinds/')) return
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
