import { defineConfig } from 'vite'
import { resolve } from 'path'
import { rename, rm } from 'fs/promises'
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

// The output directory is the static directory of the app. It also holds files that are not build output
// (vendor/drawio, the favicon), so a build must not empty it: it removes only what a build creates.
function cleanBuildOutputPlugin() {
  return {
    name: 'clean-build-output',
    buildStart: async () => {
      const outDir = resolve(__dirname, '../lib/archsight/web/public')
      await rm(resolve(outDir, 'vue'), { recursive: true, force: true })
      await rm(resolve(outDir, 'vue.html'), { force: true })
    }
  }
}

export default defineConfig({
  plugins: [vue(), renameIndexPlugin(), cleanBuildOutputPlugin()],
  build: {
    outDir: '../lib/archsight/web/public',
    emptyOutDir: false,
    rollupOptions: {
      input: resolve(__dirname, 'index.html'),
      output: {
        manualChunks: (id) => {
          if (id.includes('/mermaid/')) return 'mermaid'
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
