import { categoryForUrl } from './useFormatting.js'

// How the links of a resource (the `link/<name>` annotations, `links:` of a page) read: the name says the system.
const SYSTEMS = {
  confluence: 'Confluence',
  jira: 'Jira',
  github: 'GitHub',
  gitlab: 'GitLab',
  servicenow: 'ServiceNow',
  grafana: 'Grafana',
  prometheus: 'Prometheus',
  sonar: 'SonarQube',
  slack: 'Slack',
  drive: 'Google Drive',
}

// `confluence` -> "Confluence", `confluence-isms` -> "Confluence isms", anything else stays as written
export function linkLabel(name) {
  const [system, ...rest] = name.split('-')
  const label = SYSTEMS[system.toLowerCase()]
  return label ? [label, ...rest].join(' ') : name
}

export function isKnownSystem(name) {
  return Object.hasOwn(SYSTEMS, name.split('-')[0].toLowerCase())
}

// The host of a URL, `confluence.example.com`, without the scheme and the path
export function linkHost(url) {
  try {
    return new URL(url).host
  } catch {
    return ''
  }
}

// { name: url } as entries: the links someone wrote (known systems) first, the scraped ones after, each sorted
export function sortedLinks(links) {
  return Object.entries(links || {}).sort(([a], [b]) => {
    const known = Number(isKnownSystem(b)) - Number(isKnownSystem(a))
    return known || a.localeCompare(b)
  })
}

// More than this many links are grouped by what they are (code, documentation, ...)
export const GROUP_FROM = 10

export function groupedLinks(entries) {
  const groups = {}
  for (const [name, url] of entries) {
    const category = categoryForUrl(url)
    ;(groups[category] ||= []).push({ name, url })
  }
  return Object.entries(groups).sort(([a], [b]) => a.localeCompare(b))
}
