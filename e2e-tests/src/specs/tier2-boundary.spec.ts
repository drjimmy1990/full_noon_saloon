import { test, expect } from '@playwright/test';
import { setupTestEnvironment, teardownTestEnvironment, TestLifecycleData } from '../helpers/db-lifecycle';
import { getAuthCookie } from '../helpers/auth';
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;

const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  }
});

test.describe('Tier 2: Boundary & Corner Cases', () => {
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

  test('Overlap booking prevention (409 Conflict)', async ({ request }) => {
    const bookingDate = '2026-07-21';
    const bookingTimeA = '10:00';
    const bookingTimeB = '10:15'; // Overlaps with 10:00-10:30 slot

    // 1. Create first booking
    const responseA = await request.post('/api/bookings', {
      headers: { 'Cookie': authCookie },
      data: {
        clientName: 'Client A',
        clientPhone: '+966555555551',
        serviceId: testData.productId,
        serviceSummary: 'E2E Test Service',
        bookingDate,
        bookingTime: bookingTimeA,
        staff_id: testData.staffId,
        branchId: testData.branchId,
        source: 'manual',
        channelType: 'manual',
      },
    });
    expect(responseA.status()).toBe(201);

    // 2. Attempt to create overlapping booking
    const responseB = await request.post('/api/bookings', {
      headers: { 'Cookie': authCookie },
      data: {
        clientName: 'Client B',
        clientPhone: '+966555555552',
        serviceId: testData.productId,
        serviceSummary: 'E2E Test Service',
        bookingDate,
        bookingTime: bookingTimeB,
        staff_id: testData.staffId,
        branchId: testData.branchId,
        source: 'manual',
        channelType: 'manual',
      },
    });
    expect(responseB.status()).toBe(409);
  });

  test('Staff leave / blocked dates prevention (409 Conflict)', async ({ request }) => {
    const blockedDate = '2026-07-22';

    // 1. Block Staff on that date
    const { error } = await supabaseAdmin
      .from('StaffBlockedDate')
      .insert({
        staff_id: testData.staffId,
        blockedDate,
        reason: 'E2E Test Blocked'
      });
    expect(error).toBeNull();

    // 2. Attempt to create a booking on the blocked date
    const response = await request.post('/api/bookings', {
      headers: { 'Cookie': authCookie },
      data: {
        clientName: 'Client C',
        clientPhone: '+966555555553',
        serviceId: testData.productId,
        serviceSummary: 'E2E Test Service',
        bookingDate: blockedDate,
        bookingTime: '10:00',
        staff_id: testData.staffId,
        branchId: testData.branchId,
        source: 'manual',
        channelType: 'manual',
      },
    });
    expect(response.status()).toBe(409);
  });

  test('Edit-time collision prevention (409 Conflict)', async ({ request }) => {
    const bookingDate = '2026-07-23';

    // 1. Create Booking C at 11:00
    const resC = await request.post('/api/bookings', {
      headers: { 'Cookie': authCookie },
      data: {
        clientName: 'Client C',
        clientPhone: '+966555555554',
        serviceId: testData.productId,
        serviceSummary: 'E2E Test Service',
        bookingDate,
        bookingTime: '11:00',
        staff_id: testData.staffId,
        branchId: testData.branchId,
        source: 'manual',
        channelType: 'manual',
      },
    });
    expect(resC.status()).toBe(201);
    const bookingC = await resC.json();

    // 2. Create Booking D at 11:30
    const resD = await request.post('/api/bookings', {
      headers: { 'Cookie': authCookie },
      data: {
        clientName: 'Client D',
        clientPhone: '+966555555555',
        serviceId: testData.productId,
        serviceSummary: 'E2E Test Service',
        bookingDate,
        bookingTime: '11:30',
        staff_id: testData.staffId,
        branchId: testData.branchId,
        source: 'manual',
        channelType: 'manual',
      },
    });
    expect(resD.status()).toBe(201);

    // 3. Attempt to edit Booking C to 11:30 (colliding with Booking D)
    const resEdit = await request.put(`/api/bookings/${bookingC.id}`, {
      headers: { 'Cookie': authCookie },
      data: {
        bookingTime: '11:30',
      },
    });
    expect(resEdit.status()).toBe(409);
  });

  test('Invalid schema validation (400 Bad Request)', async ({ request }) => {
    // 1. Missing client details
    const resMissingClient = await request.post('/api/bookings', {
      headers: { 'Cookie': authCookie },
      data: {
        serviceId: testData.productId,
        serviceSummary: 'E2E Test Service',
        bookingDate: '2026-07-24',
        bookingTime: '10:00',
        staff_id: testData.staffId,
        branchId: testData.branchId,
      },
    });
    expect(resMissingClient.status()).toBe(400);

    // 2. Invalid booking time format
    const resInvalidTime = await request.post('/api/bookings', {
      headers: { 'Cookie': authCookie },
      data: {
        clientName: 'Client Invalid',
        clientPhone: '+966555555556',
        serviceId: testData.productId,
        serviceSummary: 'E2E Test Service',
        bookingDate: '2026-07-24',
        bookingTime: '99:99',
        staff_id: testData.staffId,
        branchId: testData.branchId,
      },
    });
    expect(resInvalidTime.status()).toBe(400);
  });
});
