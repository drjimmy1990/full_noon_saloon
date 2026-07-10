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

test.describe('Tier 1: Feature Coverage (CRUD Bookings)', () => {
  let testData: TestLifecycleData;
  let authCookie: string;
  let createdBookingId: string;

  test.beforeAll(async () => {
    testData = await setupTestEnvironment();
    authCookie = await getAuthCookie(testData.email, 'E2ETestPassword123!');
  });

  test.afterAll(async () => {
    if (testData) {
      await teardownTestEnvironment(testData);
    }
  });

  test('Happy path manual booking creation (POST /api/bookings)', async ({ request }) => {
    const bookingDate = '2026-07-15';
    const bookingTime = '11:30';

    const response = await request.post('/api/bookings', {
      headers: {
        'Cookie': authCookie,
      },
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

    expect(response.status()).toBe(201);
    const body = await response.json();
    expect(body.id).toBeDefined();
    createdBookingId = body.id;

    // Check booking records in response
    expect(body.status).toBe('confirmed');
    expect(body.channelType).toBe('manual');
    expect(body.source).toBe('manual');
    expect(new Date(body.bookingDate).toISOString()).toBe(new Date(`${bookingDate}T${bookingTime}:00Z`).toISOString());
    expect(new Date(body.endTime).toISOString()).toBe(new Date(`${bookingDate}T12:00:00Z`).toISOString());

    // Check booking records in DB
    const { data: dbBooking, error } = await supabaseAdmin
      .from('Booking')
      .select('*')
      .eq('id', createdBookingId)
      .single();

    expect(error).toBeNull();
    expect(dbBooking).toBeDefined();
    expect(dbBooking.status).toBe('confirmed');
    expect(dbBooking.channelType).toBe('manual');
    expect(dbBooking.source).toBe('manual');
    expect(new Date(dbBooking.bookingDate).toISOString()).toBe(new Date(`${bookingDate}T${bookingTime}:00Z`).toISOString());
    expect(new Date(dbBooking.endTime).toISOString()).toBe(new Date(`${bookingDate}T12:00:00Z`).toISOString());
  });

  test('Retrieve created booking from GET /api/bookings', async ({ request }) => {
    expect(createdBookingId).toBeDefined();
    const response = await request.get('/api/bookings', {
      headers: {
        'Cookie': authCookie,
      },
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.data).toBeDefined();
    const found = body.data.find((b: any) => b.id === createdBookingId);
    expect(found).toBeDefined();
    expect(found.client_id).toBe(testData.clientId);
  });

  test('Retrieve created booking from GET /api/bookings/[id]', async ({ request }) => {
    expect(createdBookingId).toBeDefined();
    const response = await request.get(`/api/bookings/${createdBookingId}`, {
      headers: {
        'Cookie': authCookie,
      },
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.id).toBe(createdBookingId);
    expect(body.client_id).toBe(testData.clientId);
  });

  test('Update booking details in PUT /api/bookings/[id]', async ({ request }) => {
    expect(createdBookingId).toBeDefined();
    const updatedNotes = 'Updated Notes via E2E';
    const response = await request.put(`/api/bookings/${createdBookingId}`, {
      headers: {
        'Cookie': authCookie,
      },
      data: {
        notes: updatedNotes,
        status: 'pending',
      },
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.notes).toBe(updatedNotes);
    expect(body.status).toBe('pending');

    // Verify DB
    const { data: dbBooking } = await supabaseAdmin
      .from('Booking')
      .select('notes, status')
      .eq('id', createdBookingId)
      .single();
    expect(dbBooking?.notes).toBe(updatedNotes);
    expect(dbBooking?.status).toBe('pending');
  });

  test('Delete booking in DELETE /api/bookings/[id]', async ({ request }) => {
    expect(createdBookingId).toBeDefined();
    const response = await request.delete(`/api/bookings/${createdBookingId}`, {
      headers: {
        'Cookie': authCookie,
      },
    });
    expect(response.status()).toBe(200);

    const getResponse = await request.get(`/api/bookings/${createdBookingId}`, {
      headers: {
        'Cookie': authCookie,
      },
    });
    expect(getResponse.status()).toBe(404);

    // Verify DB
    const { data: dbBooking } = await supabaseAdmin
      .from('Booking')
      .select('*')
      .eq('id', createdBookingId)
      .maybeSingle();
    expect(dbBooking).toBeNull();
  });
});
