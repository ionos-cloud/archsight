// Hover hint for a label in the Details table: the annotation key(s) behind it, written exactly as
// the query language takes them (activity/status == "active"), one per line.
export function keyHint(...keys) {
  return keys.filter(Boolean).join('\n') || undefined
}
