export function numberWithDelimiter(num) {
  return num.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',')
}

export function toEuro(num) {
  const rounded = Math.round(num * 100) / 100
  const parts = rounded.toFixed(2).split('.')
  parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',')
  return `\u20AC${parts.join('.')}`
}

const AI_CONFIG = {
  cocomoSalary: 150000,
  targetSalary: 80000,
  aiCostMultiplier: 3.0,
  aiScheduleMultiplier: 2.5,
  aiTeamMultiplier: 3.0,
}

export function aiAdjustedEstimate(type, value) {
  if (value == null) return null
  const salaryRatio = AI_CONFIG.targetSalary / AI_CONFIG.cocomoSalary
  const v = parseFloat(value)
  switch (type) {
    case 'cost': return v * salaryRatio / AI_CONFIG.aiCostMultiplier
    case 'schedule': return v / AI_CONFIG.aiScheduleMultiplier
    case 'team': return Math.ceil(v / AI_CONFIG.aiTeamMultiplier)
    default: return null
  }
}

export function httpGit(url) {
  return url.replace(/\.git$/, '').replace(':', '/').replace('git@', 'https://')
}

export function timeAgo(timestamp) {
  if (!timestamp) return null
  const time = new Date(timestamp)
  let seconds = Math.floor((Date.now() - time.getTime()) / 1000)
  if (seconds < 10) return 'just now'

  const units = [
    [60, 'second'], [60, 'minute'], [24, 'hour'],
    [7, 'day'], [4, 'week'], [12, 'month'], [Infinity, 'year'],
  ]
  let value = seconds
  for (const [divisor, unit] of units) {
    if (value < divisor) return `${value} ${unit}${value !== 1 ? 's' : ''} ago`
    value = Math.floor(value / divisor)
  }
  return `${value} years ago`
}

export function iconForUrl(url) {
  if (/docs\.google\.com\/(document|spreadsheets|presentation)/.test(url)) return 'iconoir-google-docs'
  if (/github\.com/.test(url)) return 'iconoir-github'
  if (/gitlab/.test(url)) return 'iconoir-git-fork'
  if (/confluence\.|atlassian\.net/.test(url)) return 'iconoir-page-edit'
  if (/jira\.|atlassian\.net.*jira/.test(url)) return 'iconoir-list'
  if (/grafana/.test(url)) return 'iconoir-graph-up'
  if (/prometheus/.test(url)) return 'iconoir-database'
  if (/api\./.test(url)) return 'iconoir-code'
  if (/docs\./.test(url)) return 'iconoir-book'
  return 'iconoir-internet'
}

export function categoryForUrl(url) {
  if (/docs\.google\.com/.test(url)) return 'Documentation'
  if (/github\.com|gitlab/.test(url)) return 'Code Repository'
  if (/confluence\.|atlassian\.net/.test(url)) return 'Documentation'
  if (/jira\.|atlassian\.net.*jira/.test(url)) return 'Project Management'
  if (/grafana|prometheus/.test(url)) return 'Monitoring'
  if (/api\./.test(url)) return 'API'
  if (/docs\./.test(url)) return 'Documentation'
  return 'Other'
}
