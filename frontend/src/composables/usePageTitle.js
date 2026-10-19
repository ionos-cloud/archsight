// The browser title of every page, `<what> - Archsight`, so the history and the tabs tell the pages apart. The router
// sets it from the URL on every navigation; wiki and documentation pages replace it with their real title once loaded.
const BRAND = 'Archsight'

export function setTitle(...parts) {
  const what = parts.filter(Boolean).join(' · ')
  document.title = what ? `${what} - ${BRAND}` : BRAND
}

// The parts of a route's title, from its name, params and query alone (nothing has to load)
export function titleFor(route) {
  const { kind, instance, name, filename } = route.params
  switch (route.name) {
    case 'kind': return [kind, route.query.view === 'graph' && 'Graph']
    case 'instance': return [instance, kind]
    case 'search': return [route.query.q ? `Search: ${route.query.q}` : 'Search']
    case 'editor-new': return [`New ${kind}`]
    case 'editor-edit': return [`Edit ${instance}`, kind]
    case 'page': return [name]
    case 'doc': return [filename]
    case 'error': return ['Error']
    case 'api-docs': return ['API']
    default: return []
  }
}

// A jump to a #section is the same page: it keeps the title the page set
export function installPageTitle(router) {
  router.afterEach((to, from, failure) => {
    if (failure || (from.matched.length && to.fullPath.split('#')[0] === from.fullPath.split('#')[0])) return
    setTitle(...titleFor(to))
  })
}
