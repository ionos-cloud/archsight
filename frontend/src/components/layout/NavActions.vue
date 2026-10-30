<script setup>
import { ref, inject } from 'vue'
import { useRouter } from 'vue-router'
import { reload as apiReload } from '../../api/client.js'
import { toggleSidebar, toggleMobileSidebar } from '../../composables/useSidebarCollapsed.js'

const router = useRouter()
const reloadKinds = inject('reloadKinds')
const reloading = ref(false)

// wide windows hide the sidebar for good, narrow ones close the menu again
function hideSidebar() {
  if (window.matchMedia('(min-width: 800px)').matches) toggleSidebar()
  else toggleMobileSidebar()
}

async function reload() {
  reloading.value = true
  try {
    const result = await apiReload()
    if (result.error) {
      router.push({ name: 'error', query: { data: JSON.stringify(result.error) } })
    } else {
      await reloadKinds()
      window.location.reload()
    }
  } finally {
    reloading.value = false
  }
}
</script>

<template>
  <!-- one segmented control: hide sidebar, reload and help -->
  <div class="nav-actions" role="group" aria-label="Actions">
    <button
      type="button"
      class="nav-action"
      aria-controls="sidebar"
      aria-expanded="true"
      title="Hide sidebar"
      aria-label="Hide sidebar"
      @click="hideSidebar"
    >
      <i class="iconoir-sidebar-collapse hide-icon" aria-hidden="true"></i>
    </button>
    <a class="nav-action" href="#" title="Reload" aria-label="Reload" @click.prevent="reload">
      <i :class="['iconoir-reload-window', { spinning: reloading }]" aria-hidden="true"></i>
    </a>
    <router-link class="nav-action" to="/doc/index" title="Help" aria-label="Help">
      <i class="iconoir-help-circle" aria-hidden="true"></i>
    </router-link>
  </div>
</template>

<style scoped>
/* icon-only, a shared hairline between the buttons */
.nav-actions {
  display: inline-flex;
  width: auto; /* Pico's [role="group"] makes a group full width and adds a bottom margin */
  margin: 0;
}

/* Pico sizes buttons in a [role="group"] on its own (width: 100%), so every action sets its size
   explicitly and the <button> matches the links */
.nav-actions .nav-action {
  box-sizing: border-box;
  flex: 0 0 auto;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2.25rem;
  height: 2rem;
  margin: 0;
  padding: 0;
  font: inherit;
  line-height: 1;
  color: var(--pico-muted-color);
  background-color: var(--pico-card-background-color);
  border: 1px solid var(--pico-muted-border-color);
  text-decoration: none;
  transition: background-color 0.15s ease, color 0.15s ease;
}

.nav-actions .nav-action + .nav-action {
  margin-left: -1px; /* the two borders become one line */
}

.nav-action:first-child {
  border-radius: var(--pico-border-radius) 0 0 var(--pico-border-radius);
}

.nav-action:last-child {
  border-radius: 0 var(--pico-border-radius) var(--pico-border-radius) 0;
}

.nav-action:hover,
.nav-action:focus-visible {
  color: var(--pico-primary);
  background-color: color-mix(in srgb, var(--pico-primary) 12%, var(--pico-card-background-color));
  position: relative; /* keeps the hovered edge above its neighbour */
}

.nav-action i {
  font-size: var(--fs-md);
  line-height: 1;
}

/* below 800px the sidebar sits above the content: the panel and its arrow point up, not left */
@media all and (max-width: 799px) {
  .hide-icon {
    transform: rotate(90deg);
  }
}

.spinning {
  animation: spin 1s linear infinite;
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}
</style>
