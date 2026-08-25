import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    globals: true,
    setupFiles: ['./tests/setup.js'],
    testTimeout: 20000, // mongodb-memory-server al primo avvio scarica il binario, può essere lento
    hookTimeout: 60000, // più margine per il download del binario MongoDB al primo avvio
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov', 'html'],
      thresholds: {
        statements: 80,
        branches: 25,
        functions: 55,
        lines: 85,
      },
    },
  },
});