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

test.describe('Tier 4: Real-World Workloads & Concurrency', () => {
  let testData: TestLifecycleData;
  let authCookie: string;
  let staffId2: string;

  test.beforeAll(async () => {
    testData = await setupTestEnvironment();
    authCookie = await getAuthCookie(testData.email, 'E2ETestPassword123!');

    // Create a second staff S2 under the same branch
    const { data: staff, error: staffErr } = await supabaseAdmin
      .from('Staff')
      .insert({
        name: 'E2E Test Staff 2',
        branchId: testData.branchId,
        role: 'staff',
        isActive: true
      })
      .select('id')
      .single();
    if (staffErr || !staff) throw new Error(`Failed to create second staff: ${staffErr?.message}`);
    staffId2 = staff.id;

    // Create StaffSchedule for staff S2 (all 7 days)
    const schedules = [];
    for (let i = 0; i < 7; i++) {
      schedules.push({
        staff_id: staffId2,
        dayOfWeek: i,
        startTime: '09:00',
        endTime: '18:00',
        isOff: false
      });
    }
    const { error: scheduleErr } = await supabaseAdmin
      .from('StaffSchedule')
      .insert(schedules);
    if (scheduleErr) throw new Error(`Failed to create schedule for staff 2: ${scheduleErr?.message}`);

    // Link staff S2 to product
    const { error: serviceLinkErr } = await supabaseAdmin
      .from('StaffService')
      .insert({
        staff_id: staffId2,
        product_id: testData.productId
      });
    if (serviceLinkErr) throw new Error(`Failed to link staff 2 to service: ${serviceLinkErr?.message}`);
  });

  test.afterAll(async () => {
    if (testData) {
      await teardownTestEnvironment(testData);
    }
  });

  test('Concurrency test - 5 concurrent bookings for same slot (only 1 succeeds)', async ({ request }) => {
    const bookingDate = '2026-07-28';
    const bookingTime = '10:00';

    const promises = Array.from({ length: 5 }).map(() =>
      request.post('/api/bookings', {
        headers: { 'Cookie': authCookie },
        data: {
          clientName: 'Concurrency Client',
          clientPhone: '+966555555559',
          serviceId: testData.productId,
          serviceSummary: 'E2E Test Service',
          bookingDate,
          bookingTime,
          staff_id: testData.staffId,
          branchId: testData.branchId,
          source: 'manual',
          channelType: 'manual',
        },
      })
    );

    const responses = await Promise.all(promises);
    const statuses = responses.map(res => res.status());
    const successes = statuses.filter(s => s === 201).length;
    const conflicts = statuses.filter(s => s === 409).length;

    console.log('[concurrency test] statuses:', statuses);

    // Expect exactly one request to succeed and others to fail with 409 Conflict
    expect(successes).toBe(1);
    expect(conflicts).toBe(4);
  });

  test('Lifecycle endurance (create -> verify -> reschedule -> shift staff -> delete)', async ({ request }) => {
    const bookingDate = '2026-07-29';
    const timeSlot1 = '10:00';
    const timeSlot2 = '10:30';

    // 1. Create booking for Staff 1 at 10:00
    const resCreate = await request.post('/api/bookings', {
      headers: { 'Cookie': authCookie },
      data: {
        clientName: 'Endurance Client',
        clientPhone: '+966555555550',
        serviceId: testData.productId,
        serviceSummary: 'E2E Test Service',
        bookingDate,
        bookingTime: timeSlot1,
        staff_id: testData.staffId,
        branchId: testData.branchId,
        source: 'manual',
        channelType: 'manual',
      },
    });
    expect(resCreate.status()).toBe(201);
    const booking = await resCreate.json();
    expect(booking.id).toBeDefined();

    // 2. Verify 10:00 slot is blocked for Staff 1
    const urlS1 = `http://localhost:3001/api/availability?staffId=${testData.staffId}&serviceId=${testData.productId}&date=${bookingDate}`;
    const resAvail1 = await request.get(urlS1);
    const body1 = await resAvail1.json();
    const slot100_S1 = body1.slots.find((s: any) => s.time === timeSlot1);
    expect(slot100_S1.booked).toBe(true);

    // 3. Edit/reschedule to 10:30
    const resEditTime = await request.put(`/api/bookings/${booking.id}`, {
      headers: { 'Cookie': authCookie },
      data: {
        bookingTime: timeSlot2,
      },
    });
    expect(resEditTime.status()).toBe(200);

    // 4. Verify old 10:00 slot is released and new 10:30 slot is blocked for Staff 1
    const resAvail2 = await request.get(urlS1);
    const body2 = await resAvail2.json();
    const slot100_S1_r = body2.slots.find((s: any) => s.time === timeSlot1);
    const slot103_S1 = body2.slots.find((s: any) => s.time === timeSlot2);
    expect(slot100_S1_r.booked).toBe(false);
    expect(slot103_S1.booked).toBe(true);

    // 5. Change staff to Staff 2 (at 10:30)
    const resEditStaff = await request.put(`/api/bookings/${booking.id}`, {
      headers: { 'Cookie': authCookie },
      data: {
        staff_id: staffId2,
      },
    });
    expect(resEditStaff.status()).toBe(200);

    // 6. Verify 10:30 is released for Staff 1, and now blocked for Staff 2
    const resAvailS1 = await request.get(urlS1);
    const bodyS1 = await resAvailS1.json();
    const slot103_S1_r = bodyS1.slots.find((s: any) => s.time === timeSlot2);
    expect(slot103_S1_r.booked).toBe(false);

    const urlS2 = `http://localhost:3001/api/availability?staffId=${staffId2}&serviceId=${testData.productId}&date=${bookingDate}`;
    const resAvailS2 = await request.get(urlS2);
    const bodyS2 = await resAvailS2.json();
    const slot103_S2 = bodyS2.slots.find((s: any) => s.time === timeSlot2);
    expect(slot103_S2.booked).toBe(true);

    // 7. Delete booking
    const resDelete = await request.delete(`/api/bookings/${booking.id}`, {
      headers: { 'Cookie': authCookie },
    });
    expect(resDelete.status()).toBe(200);

    // 8. Verify clean release of all slots
    const resAvailS2Final = await request.get(urlS2);
    const bodyS2Final = await resAvailS2Final.json();
    const slot103_S2_r = bodyS2Final.slots.find((s: any) => s.time === timeSlot2);
    expect(slot103_S2_r.booked).toBe(false);
  });
});
