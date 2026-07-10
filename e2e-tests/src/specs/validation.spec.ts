import { test, expect } from '@playwright/test';
import { setupTestEnvironment, teardownTestEnvironment, TestLifecycleData } from '../helpers/db-lifecycle';
import { getAuthCookie } from '../helpers/auth';
import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import path from 'path';

dotenv.config({ path: path.resolve(__dirname, '../../../saloon-mostafa/.env') });

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
  auth: { persistSession: false, autoRefreshToken: false }
});

test.describe('Milestone M3: Blocked Date and Overlap Validation E2E Tests', () => {
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

  test('1. Blocked Date Validation - Staff on leave', async ({ request }) => {
    const testDate = '2026-07-10';

    // Seed blocked date in the database
    const { data: blockedRecord, error: blockErr } = await supabaseAdmin
      .from('StaffBlockedDate')
      .insert({
        staff_id: testData.staffId,
        blockedDate: testDate,
        reason: 'Holiday'
      })
      .select()
      .single();

    expect(blockErr).toBeNull();
    expect(blockedRecord).toBeDefined();

    // Try POST to create booking on the blocked date
    const response = await request.post('/api/bookings', {
      headers: { 'Cookie': authCookie },
      data: {
        client_id: testData.clientId,
        serviceId: testData.productId,
        serviceSummary: 'E2E Test Service',
        bookingDate: testDate,
        bookingTime: '10:00',
        staff_id: testData.staffId,
        branchId: testData.branchId,
        location: 'salon',
        status: 'confirmed'
      }
    });

    expect(response.status()).toBe(409);
    const body = await response.json();
    expect(body.error).toBe('العاملة في إجازة في هذا اليوم');

    // Clean up blocked date
    await supabaseAdmin.from('StaffBlockedDate').delete().eq('id', blockedRecord.id);
  });

  test('2. Overlap Validation - Double booking same slot', async ({ request }) => {
    const testDate = '2026-07-11';

    // 2.1 Create first valid booking (10:00 to 10:30, duration = 30)
    const res1 = await request.post('/api/bookings', {
      headers: { 'Cookie': authCookie },
      data: {
        client_id: testData.clientId,
        serviceId: testData.productId,
        serviceSummary: 'E2E Test Service',
        bookingDate: testDate,
        bookingTime: '10:00',
        staff_id: testData.staffId,
        branchId: testData.branchId,
        location: 'salon',
        status: 'confirmed'
      }
    });

    expect(res1.status()).toBe(201);
    const booking1 = await res1.json();
    expect(booking1.id).toBeDefined();

    // 2.2 Attempt overlapping booking (10:15 to 10:45)
    const res2 = await request.post('/api/bookings', {
      headers: { 'Cookie': authCookie },
      data: {
        client_id: testData.clientId,
        serviceId: testData.productId,
        serviceSummary: 'E2E Test Service',
        bookingDate: testDate,
        bookingTime: '10:15',
        staff_id: testData.staffId,
        branchId: testData.branchId,
        location: 'salon',
        status: 'confirmed'
      }
    });

    expect(res2.status()).toBe(409);
    const body2 = await res2.json();
    expect(body2.error).toBe('هذا الوقت محجوز بالفعل. يرجى اختيار وقت آخر.');

    // 2.3 Attempt updating first booking's notes (should NOT trigger self-overlap)
    const resUpdateNotes = await request.put(`/api/bookings/${booking1.id}`, {
      headers: { 'Cookie': authCookie },
      data: {
        notes: 'Updated note without changing time'
      }
    });

    expect(resUpdateNotes.status()).toBe(200);
    const updated1 = await resUpdateNotes.json();
    expect(updated1.notes).toBe('Updated note without changing time');

    // 2.4 Try updating to an overlapping slot on a different day/time that has another booking.
    // Let's create booking2 on 14:00
    const res3 = await request.post('/api/bookings', {
      headers: { 'Cookie': authCookie },
      data: {
        client_id: testData.clientId,
        serviceId: testData.productId,
        serviceSummary: 'E2E Test Service',
        bookingDate: testDate,
        bookingTime: '14:00',
        staff_id: testData.staffId,
        branchId: testData.branchId,
        location: 'salon',
        status: 'confirmed'
      }
    });
    expect(res3.status()).toBe(201);
    const booking2 = await res3.json();

    // Now try to update booking1 to 14:15 (overlaps with booking2)
    const resUpdateOverlap = await request.put(`/api/bookings/${booking1.id}`, {
      headers: { 'Cookie': authCookie },
      data: {
        bookingDate: testDate,
        bookingTime: '14:15'
      }
    });

    expect(resUpdateOverlap.status()).toBe(409);
    const bodyUpdateOverlap = await resUpdateOverlap.json();
    expect(bodyUpdateOverlap.error).toBe('هذا الوقت محجوز بالفعل. يرجى اختيار وقت آخر.');
  });
});
