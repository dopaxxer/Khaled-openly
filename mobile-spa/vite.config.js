import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { fileURLToPath, URL } from 'node:url'

const here = new URL('.', import.meta.url)

export default defineConfig({
  root: fileURLToPath(here),
  base: './',
  plugins: [react()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('../', here)),
      'next/link': fileURLToPath(new URL('./src/next-link.jsx', here)),
      'next/navigation': fileURLToPath(new URL('./src/next-navigation.js', here))
    }
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true
  }
})
