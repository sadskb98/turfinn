import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  timeout: 30000,
  retries: 0,
  use: {
    baseURL: 'http://localhost:3000',
    screenshot: 'on',
    trace: 'on-first-retry',
    viewport: { width: 430, height: 932 }, // iPhone 14 Pro Max
  },
  projects: [
    { name: 'chromium', use: { browserName: 'chromium' } },
  ],
  reporter: [['list'], ['html', { open: 'never' }]],
  outputDir: './results',
});
