<script setup>
import { computed } from 'vue'
import { numberWithDelimiter } from '../../composables/useFormatting.js'

const props = defineProps({ annotations: Object, kind: String })

const langData = computed(() => {
  const languages = props.annotations['scc/languages']
  if (!languages) return null

  const items = languages.split(',').map(lang => {
    const key = `scc/language/${lang.trim()}/loc`
    return { name: lang.trim(), loc: parseInt(props.annotations[key] || '0', 10) }
  }).sort((a, b) => b.loc - a.loc)

  const total = items.reduce((s, l) => s + l.loc, 0)
  if (total <= 0) return null

  const significant = items.filter(l => (l.loc / total * 100) >= 0.1)
  const top = significant.slice(0, 10)
  const others = [...significant.slice(10), ...items.filter(l => (l.loc / total * 100) < 0.1)]
  const otherLoc = others.reduce((s, l) => s + l.loc, 0)

  const display = [...top]
  if (otherLoc > 0) {
    display.push({ name: 'Other', loc: otherLoc, isOther: true, otherNames: others.map(l => l.name) })
  }

  return { display, total }
})

function pct(loc) {
  return (loc / langData.value.total * 100).toFixed(1)
}

function colorClass(idx, item) {
  return item.isOther ? 'lang-other' : `lang-${idx}`
}

function filterUrl(key, value) {
  return { name: 'search', query: { q: `${key} == "${value}"` } }
}
</script>

<template>
  <tr v-if="langData">
    <th scope="row">Languages</th>
    <td>
      <div class="language-distribution">
        <div class="language-total">
          <span class="language-count">{{ numberWithDelimiter(langData.total) }}</span>
          <span class="language-label">lines of code</span>
        </div>
        <div class="language-bar">
          <div
            v-for="(lang, idx) in langData.display"
            :key="lang.name"
            :class="['language-bar-segment', colorClass(idx, lang)]"
            :style="{ width: pct(lang.loc) + '%' }"
            :title="`${lang.name}: ${numberWithDelimiter(lang.loc)} (${pct(lang.loc)}%)`"
          ></div>
        </div>
        <div class="language-legend">
          <div v-for="(lang, idx) in langData.display" :key="lang.name" class="language-legend-item">
            <div :class="['language-legend-dot', colorClass(idx, lang)]"></div>
            <template v-if="lang.isOther">
              <span>Other {{ pct(lang.loc) }}%</span>
              <span class="other-languages">
                (<template v-for="(name, i) in lang.otherNames" :key="name">
                  <router-link :to="filterUrl('scc/languages', name)">{{ name }}</router-link><template v-if="i < lang.otherNames.length - 1">, </template>
                </template>)
              </span>
            </template>
            <router-link v-else :to="filterUrl('scc/languages', lang.name)">
              {{ lang.name }} {{ pct(lang.loc) }}%
            </router-link>
          </div>
        </div>
      </div>
    </td>
  </tr>
</template>

<style scoped>
.language-distribution {
  display: flex;
  flex-direction: column;
  gap: 8px;
  min-width: 200px;
  padding: 8px 12px;
  background-color: var(--card-background-color);
  border-radius: 6px;
  border: 1px solid var(--muted-border-color);
}

.language-total {
  display: flex;
  align-items: baseline;
  gap: 6px;
}

.language-total .language-count {
  font-size: 1.5em;
  font-weight: 600;
  color: var(--color);
}

.language-total .language-label {
  color: var(--muted-color);
  font-size: 0.9em;
}

.language-bar {
  display: flex;
  height: 8px;
  border-radius: 4px;
  overflow: hidden;
  background-color: var(--muted-border-color);
}

.language-bar-segment {
  height: 100%;
  min-width: 2px;
}

.language-bar-segment.lang-0,
.language-legend-dot.lang-0 { background-color: #3178c6; }
.language-bar-segment.lang-1,
.language-legend-dot.lang-1 { background-color: #00add8; }
.language-bar-segment.lang-2,
.language-legend-dot.lang-2 { background-color: #f1e05a; }
.language-bar-segment.lang-3,
.language-legend-dot.lang-3 { background-color: #e34c26; }
.language-bar-segment.lang-4,
.language-legend-dot.lang-4 { background-color: #563d7c; }
.language-bar-segment.lang-5,
.language-legend-dot.lang-5 { background-color: #89e051; }
.language-bar-segment.lang-6,
.language-legend-dot.lang-6 { background-color: #f34b7d; }
.language-bar-segment.lang-7,
.language-legend-dot.lang-7 { background-color: #b07219; }
.language-bar-segment.lang-8,
.language-legend-dot.lang-8 { background-color: #4f5d95; }
.language-bar-segment.lang-9,
.language-legend-dot.lang-9 { background-color: #6b7280; }
.language-bar-segment.lang-other,
.language-legend-dot.lang-other { background-color: #9ca3af; }

.language-legend {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  font-size: 0.85em;
}

.language-legend-item {
  display: flex;
  align-items: center;
  gap: 4px;
}

.language-legend-item a {
  color: var(--muted-color);
  text-decoration: none;
}

.language-legend-item a:hover {
  color: var(--primary);
  text-decoration: underline;
}

.language-legend-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  flex-shrink: 0;
}
</style>
