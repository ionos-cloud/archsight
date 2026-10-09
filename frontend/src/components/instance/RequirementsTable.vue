<script setup>
// The table of requirements (instance page section and `requirements` blocks of pages).
// items: [{ name, status: 'implemented'|'partial'|'planned', priority, story (html), by: [{ kind, name, status }] }]
// priorityLink: priority -> route location of the search for it; showBy adds the "Realized by" column.
defineProps({
  items: { type: Array, default: () => [] },
  priorityLink: { type: Function, required: true },
  showBy: { type: Boolean, default: false },
})

function statusIcon(status) {
  switch (status) {
    case 'implemented': return 'iconoir-check-circle'
    case 'partial': return 'iconoir-half-moon'
    case 'planned': return 'iconoir-calendar'
    default: return 'iconoir-circle'
  }
}
</script>

<template>
  <table class="requirements-table">
    <thead>
      <tr>
        <th></th>
        <th>Name</th>
        <th>Priority</th>
        <th>Story</th>
        <th v-if="showBy">Realized by</th>
      </tr>
    </thead>
    <tbody>
      <tr v-for="req in items" :key="req.name">
        <td class="requirement-status">
          <i :class="[statusIcon(req.status), `status-${req.status}`]" class="requirement-status-icon" :title="req.status"></i>
        </td>
        <td>
          <router-link :to="{ name: 'instance', params: { kind: 'MotivationRequirement', instance: req.name } }">
            {{ req.name }}
          </router-link>
        </td>
        <td>
          <router-link v-if="req.priority" class="badge badge-info" :to="priorityLink(req.priority)">
            {{ req.priority }}
          </router-link>
          <span v-else class="view-empty-value">-</span>
        </td>
        <td class="requirement-story">
          <div v-if="req.story" v-html="req.story"></div>
          <span v-else class="view-empty-value">-</span>
        </td>
        <td v-if="showBy" class="requirement-by">
          <ul>
            <li v-for="b in req.by" :key="`${b.kind}/${b.name}`">
              <i :class="[statusIcon(b.status), `status-${b.status}`]" class="requirement-status-icon" :title="b.status"></i>
              <router-link :to="{ name: 'instance', params: { kind: b.kind, instance: b.name } }">{{ b.name }}</router-link>
            </li>
          </ul>
        </td>
      </tr>
    </tbody>
  </table>
</template>

<style scoped>
.requirement-status-icon {
  font-size: var(--fs-md);
}

.requirement-status-icon.status-implemented {
  color: #10b981;
}

.requirement-status-icon.status-partial {
  color: #f59e0b;
}

.requirement-status-icon.status-planned {
  color: #3b82f6;
}

.requirement-status-icon.status-not-started,
.requirement-status-icon.status-unknown {
  color: #9ca3af;
}

.requirement-by ul {
  margin: 0;
  padding: 0;
  list-style: none;
}
</style>
