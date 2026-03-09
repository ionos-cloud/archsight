import { defineConfig } from 'vite'
import { resolve } from 'path'
import { rename } from 'fs/promises'
import vue from '@vitejs/plugin-vue'

// Rename index.html to vue.html after build so it doesn't shadow Sinatra's / route
function renameIndexPlugin() {
  return {
    name: 'rename-index',
    writeBundle: async () => {
      const outDir = resolve(__dirname, '../lib/archsight/web/public')
      await rename(resolve(outDir, 'index.html'), resolve(outDir, 'vue.html'))
    }
  }
}

export default defineConfig({
  plugins: [vue(), renameIndexPlugin()],
  build: {
    outDir: '../lib/archsight/web/public',
    emptyOutDir: true,
    rollupOptions: {
      input: resolve(__dirname, 'index.html'),
      output: {
        manualChunks: {
          mermaid: ['mermaid'],
        },
        chunkFileNames: 'vue/[name]-[hash].js',
        entryFileNames: 'vue/[name]-[hash].js',
        assetFileNames: 'vue/[name]-[hash][extname]',
      },
    },
  },
  server: {
    proxy: {
      '/api': 'http://localhost:4567',
      '/dot': 'http://localhost:4567',
      '/reload': 'http://localhost:4567',
      '/favicon.ico': 'http://localhost:4567',
      '/kinds': {
        target: 'http://localhost:4567',
        bypass(req) {
          // Only proxy DOT and JSON requests to Sinatra
          // Let Vite/Vue handle HTML page routes
          if (!/\/dot$/.test(req.url) && !/\.json$/.test(req.url)) {
            return req.url
          }
        }
      }
    }
  }
})
