import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { fileURLToPath, URL } from 'node:url'

const here = new URL('.', import.meta.url)

export default defineConfig({
  root: fileURLToPath(here),
  base: './',
  plugins: [react()],
  resolve: {
    dedupe: ['react', 'react-dom', 'lucide-react'],
    alias: {
      '@': fileURLToPath(new URL('../', here)),
      'next/link': fileURLToPath(new URL('./src/next-link.jsx', here)),
      'next/navigation': fileURLToPath(new URL('./src/next-navigation.js', here)),
      'lucide-react': fileURLToPath(new URL('./node_modules/lucide-react/', here)),
      'react-dom': fileURLToPath(new URL('./node_modules/react-dom/', here)),
      'react': fileURLToPath(new URL('./node_modules/react/', here))
    }
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true
  }
})
