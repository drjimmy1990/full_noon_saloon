import { defineConfig } from '@playwright/test';
import dotenv from 'dotenv';
import path from 'path';

// Load environment variables from the CRM .env file
dotenv.config({ path: path.resolve(__dirname, '../saloon-mostafa/.env') });

export default defineConfig({
  testDir: './src/specs',
  timeout: 45000,
  workers: 1, // Run sequentially to avoid database/availability conflicts
  retries: 0,
  reporter: [
    ['list'],
    ['html', { outputFolder: 'playwright-report', open: 'never' }]
  ],
  use: {
    baseURL: 'http://127.0.0.1:3000',
    extraHTTPHeaders: {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    },
  },
  webServer: [
    {
      command: 'npm run dev',
      cwd: path.resolve(__dirname, '../saloon-mostafa'),
      url: 'http://127.0.0.1:3000/api/settings', // Setting GET is public and fast
      reuseExistingServer: true,
      timeout: 120000,
    },
    {
      command: 'npm run dev -- -p 3001',
      cwd: path.resolve(__dirname, '../gardenia-website'),
      url: 'http://127.0.0.1:3001', // Frontpage
      reuseExistingServer: true,
      timeout: 120000,
    }
  ],
});
