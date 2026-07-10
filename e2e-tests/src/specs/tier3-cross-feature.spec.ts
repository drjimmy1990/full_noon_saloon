import { test, expect } from '@playwright/test';
import { setupTestEnvironment, teardownTestEnvironment, TestLifecycleData } from '../helpers/db-lifecycle';
import { getAuthCookie } from '../helpers/auth';

test.describe('Tier 3: Cross-Feature Availability Checking', () => {
  let testData: TestLifecycleData;
  let authCookie: string;

  test.beforeAll(async () => {
    testData = await setupTestEnvironment();
    authCookie = await getAuthCookie(testData.email, 'E2ETestPassword123!');
  });

  test.afterAll(async () => {
    if (testData) {
      await teardownTestEnvironment(testData);
    }
  });

  test('Storefront availability updates accurately when booking lifecycle changes', async ({ request }) => {
    const bookingDate = '2026-07-25'; // A Saturday
    const bookingTime = '10:30';

    // 1. Query storefront availability: slot should be available
    const url = `http://localhost:3001/api/availability?staffId=${testData.staffId}&serviceId=${testData.productId}&date=${bookingDate}`;
    const resAvail1 = await request.get(url);
    expect(resAvail1.status()).toBe(200);
    const body1 = await resAvail1.json();
    expect(body1.slots).toBeDefined();
    const slot1 = body1.slots.find((s: any) => s.time === bookingTime);
    expect(slot1).toBeDefined();
    expect(slot1.booked).toBe(false);

    // 2. Create manual CRM booking for S1 on D1 at 10:30
    const resCreate = await request.post('/api/bookings', {
      headers: { 'Cookie': authCookie },
      data: {
        clientName: 'E2E Test Client',
        clientPhone: '+966555555555',
        serviceId: testData.productId,
        serviceSummary: 'E2E Test Service',
        bookingDate,
        bookingTime,
        staff_id: testData.staffId,
        branchId: testData.branchId,
        source: 'manual',
        channelType: 'manual',
      },
    });
    expect(resCreate.status()).toBe(201);
    const createdBooking = await resCreate.json();
    expect(createdBooking.id).toBeDefined();

    // 3. Query storefront availability again: slot should now be booked
    const resAvail2 = await request.get(url);
    expect(resAvail2.status()).toBe(200);
    const body2 = await resAvail2.json();
    const slot2 = body2.slots.find((s: any) => s.time === bookingTime);
    expect(slot2).toBeDefined();
    expect(slot2.booked).toBe(true);

    // 4. Delete manual booking via CRM
    const resDelete = await request.delete(`/api/bookings/${createdBooking.id}`, {
      headers: { 'Cookie': authCookie },
    });
    expect(resDelete.status()).toBe(200);

    // 5. Query storefront availability third time: slot should be available again
    const resAvail3 = await request.get(url);
    expect(resAvail3.status()).toBe(200);
    const body3 = await resAvail3.json();
    const slot3 = body3.slots.find((s: any) => s.time === bookingTime);
    expect(slot3).toBeDefined();
    expect(slot3.booked).toBe(false);
  });
});
