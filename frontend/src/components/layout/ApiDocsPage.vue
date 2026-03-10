<script setup>
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'

const router = useRouter()

const container = ref(null)
const error = ref(null)

function loadScript(src) {
  return new Promise((resolve, reject) => {
    if (window.Redoc) return resolve()
    const script = document.createElement('script')
    script.src = src
    script.onload = resolve
    script.onerror = () => reject(new Error('Failed to load ReDoc'))
    document.head.appendChild(script)
  })
}

onMounted(async () => {
  try {
    await loadScript('https://cdn.redoc.ly/redoc/latest/bundles/redoc.standalone.js')
    window.Redoc.init('/api/v1/openapi.yaml', {}, container.value)
  } catch (e) {
    error.value = e.message
  }
})
</script>

<template>
  <div class="api-docs-page">
    <a href="#" class="back-link" @click.prevent="router.back()">&larr; Back</a>
    <div v-if="error" class="pico-color-red-500">{{ error }}</div>
    <div ref="container"></div>
  </div>
</template>

<style scoped>
.back-link {
  position: fixed;
  top: 12px;
  right: 12px;
  z-index: 100;
  padding: 6px 14px;
  background: #fff;
  border: 1px solid #ddd;
  border-radius: 4px;
  text-decoration: none;
  font-size: 0.875rem;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.1);
}
</style>
