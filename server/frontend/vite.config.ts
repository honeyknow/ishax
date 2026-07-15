import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

const apiTarget = process.env.VITE_API_TARGET || 'http://localhost:8000'
const devPort = Number(process.env.VITE_DEV_PORT || 5173)

export default defineConfig({
  plugins: [react()],
  server: {
    port: devPort,
    allowedHosts: true,
    proxy: {
      '/auth': { target: apiTarget, changeOrigin: true },
      '/alerts': { target: apiTarget, changeOrigin: true },
      '/stats': { target: apiTarget, changeOrigin: true },
      '/rules': { target: apiTarget, changeOrigin: true },
      '/admin': { target: apiTarget, changeOrigin: true },
      '/deploy': { target: apiTarget, changeOrigin: true },
      '/threatintel': { target: apiTarget, changeOrigin: true },
      '/tenant': { target: apiTarget, changeOrigin: true },
      '/health': { target: apiTarget, changeOrigin: true },
    },
  },
})
