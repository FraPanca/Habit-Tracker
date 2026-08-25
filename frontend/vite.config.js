// frontend/vite.config.js
import { defineConfig, coverageConfigDefaults } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./tests/setup.js'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov', 'html'],
      exclude: [
        ...coverageConfigDefaults.exclude,
        '**/*.css',        // CSS trasformato in modulo: non è logica applicativa
        'src/main.jsx',    // entry point, solo bootstrap di ReactDOM
      ],
      thresholds: {
        statements: 50,
        branches: 75,
        functions: 45,
        lines: 55,
      },
    },
  },
});