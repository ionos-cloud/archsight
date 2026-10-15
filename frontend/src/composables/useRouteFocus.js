// After a navigation to another page (sidebar, links), the keyboard focus moves to the new content's heading, so
// focus does not stay on the clicked link and a screen reader reads the new page. Pages load their data first, so
// it waits until the heading is there. A change of the query only (filters, ?view=graph) is the same page and keeps
// the focus, and so does typing in a field (the search box navigates while the user types).
const HEADING = '.content h1, .content article > header h2, .content h2'
const WAIT_MS = 3000

function typing() {
  const el = document.activeElement
  return !!el && (el.matches('input, textarea, select') || el.isContentEditable)
}

function focusHeading(started = performance.now()) {
  if (typing()) return
  const heading = document.querySelector(HEADING)
  if (heading) {
    if (!heading.hasAttribute('tabindex')) heading.setAttribute('tabindex', '-1')
    heading.focus({ preventScroll: true })
    return
  }
  if (performance.now() - started < WAIT_MS) requestAnimationFrame(() => focusHeading(started))
}

export function installRouteFocus(router) {
  router.afterEach((to, from, failure) => {
    if (failure || !from.matched.length || to.path === from.path) return
    requestAnimationFrame(() => focusHeading())
  })
}

// A new page starts at the top, back and forward return to where the page was, a #anchor scrolls to its target;
// a change of the query only stays where it is
export function scrollBehavior(to, from, savedPosition) {
  if (savedPosition) return savedPosition
  if (to.hash) return { el: to.hash }
  if (to.path === from.path) return false
  return { top: 0 }
}
