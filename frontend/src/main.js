import { createApp } from 'vue'
import App from './App.vue'
import router from './router'
import { usePrintFit } from './composables/usePrintFit.js'
import { usePrintWatermark } from './composables/usePrintWatermark.js'

// Vendor CSS from npm
import '@picocss/pico/css/pico.min.css'
import 'iconoir/css/iconoir.css'

// Custom CSS (global styles only — component styles are in <style scoped> blocks)
import './css/tokens.css'
import './css/prose.css'
import './css/highlight.css'
import './css/base.css'
import './css/mermaid-layers.css'
import './css/print.css'

usePrintFit()
usePrintWatermark()
createApp(App).use(router).mount('#app')
