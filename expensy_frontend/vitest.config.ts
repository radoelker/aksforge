import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./__tests__/setup.ts'],
    include: ['__tests__/**/*.test.{ts,tsx}'],
    coverage: {
      provider: 'v8',
      exclude: ['node_modules/**', '.next/**'],
    },
  },
  resolve: {
    alias: {
      // Match the @ alias used in Next.js imports
      '@': path.resolve(__dirname, './src'),
    },
  },
});
