import { createApp } from 'vue'
import App from './App.vue'
import router from './router'

// Vendor CSS from npm
import '@picocss/pico/css/pico.min.css'
import 'iconoir/css/iconoir.css'

// Custom CSS (global styles only — component styles are in <style scoped> blocks)
import './css/highlight.css'
import './css/base.css'
import './css/mermaid-layers.css'

createApp(App).use(router).mount('#app')
