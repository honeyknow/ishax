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
      '^/(auth|alerts|stats|rules|admin|deploy|threatintel|tenant|health)(/.*)?$': {
        target: apiTarget,
        changeOrigin: true,
      },
    },
  },
})
