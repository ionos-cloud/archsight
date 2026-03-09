<script setup>
import { ref, provide, computed } from 'vue'
import { useRoute } from 'vue-router'
import { getKinds } from './api/client.js'
import NavigationBar from './components/layout/NavigationBar.vue'
import SidebarPanel from './components/layout/SidebarPanel.vue'

const route = useRoute()
const fullscreen = computed(() => route.meta.fullscreen)

const kinds = ref(null)
const kindsError = ref(null)

async function loadKinds() {
  try {
    kinds.value = await getKinds()
  } catch (e) {
    kindsError.value = e.message
  }
}
loadKinds()

provide('kinds', kinds)
provide('reloadKinds', loadKinds)
</script>

<template>
  <template v-if="fullscreen">
    <router-view />
  </template>
  <template v-else>
    <NavigationBar />
    <main class="container-fluid">
      <SidebarPanel :kinds="kinds" />
      <div class="content">
        <router-view />
      </div>
    </main>
  </template>
</template>
