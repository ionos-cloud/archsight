// The status of an analysis run, without a judgement on its output: many analyses are reports, so output is not a
// problem. Only the errors and warnings the script reports itself (`error(...)`, `warning(...)`) are counted.
const plural = (count, word) => `${count} ${word}${count === 1 ? '' : 's'}`

export function analysisStatus(result) {
  if (!result) return null
  if (!result.success) return { failed: true, label: 'Failed', notes: '' }
  const levels = (result.sections || []).filter((s) => s.type === 'message').map((s) => s.level)
  const errors = levels.filter((l) => l === 'error').length
  const warnings = levels.filter((l) => l === 'warning').length
  const notes = [errors && plural(errors, 'error'), warnings && plural(warnings, 'warning')].filter(Boolean).join(', ')
  return { failed: false, label: 'Completed', notes }
}
