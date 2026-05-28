import type { Config } from 'jest';

const config: Config = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  rootDir: 'src',
  testMatch: ['**/__tests__/**/*.test.ts'],
  clearMocks: true,
  collectCoverageFrom: [
    '**/*.ts',
    '!**/__tests__/**',
    '!**/index.ts',    // server entry point — not unit-testable
  ],
};

export default config;
