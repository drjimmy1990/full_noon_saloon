import { test, expect } from '@playwright/test';
import { setupTestEnvironment, teardownTestEnvironment, TestLifecycleData } from '../helpers/db-lifecycle';
import { getAuthCookie } from '../helpers/auth';

test.describe('E2E Sanity Connectivity Checks', () => {
  let testData: TestLifecycleData;
  let authCookie: string;

  test.beforeAll(async () => {
    // Initialize the test data in the DB
    testData = await setupTestEnvironment();
    // Programmatically log in and obtain the session cookie
    authCookie = await getAuthCookie(testData.email, 'E2ETestPassword123!');
  });

  test.afterAll(async () => {
    // Clean up created test data
    if (testData) {
      await teardownTestEnvironment(testData);
    }
  });

  test('Public storefront endpoint (GET http://localhost:3001/api/settings) should be accessible without authentication', async ({ request }) => {
    const response = await request.get('http://127.0.0.1:3001/api/settings');
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body).toBeDefined();
    // Verify some expected storefront settings keys
    expect(body.whatsapp_number).toBeDefined();
  });

  test('Protected CRM endpoint (GET /api/bookings) should redirect to login without auth cookie', async ({ request }) => {
    // Disable redirects so we can inspect the redirect response from the CRM middleware
    const response = await request.get('/api/bookings', { maxRedirects: 0 });
    expect([302, 307, 308]).toContain(response.status());
  });

  test('Protected CRM endpoint (GET /api/bookings) should succeed with a valid admin auth cookie', async ({ request }) => {
    const response = await request.get('/api/bookings', {
      headers: {
        'Cookie': authCookie,
      },
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.data).toBeDefined();
    expect(Array.isArray(body.data)).toBe(true);
  });
});
