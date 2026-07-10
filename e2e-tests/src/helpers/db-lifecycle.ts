import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import path from 'path';

// Ensure environment variables are loaded
dotenv.config({ path: path.resolve(__dirname, '../../../saloon-mostafa/.env') });

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;

if (!supabaseUrl || !supabaseServiceKey) {
  throw new Error('Supabase URL or Service Role Key is missing in environment.');
}

const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  }
});

export interface TestLifecycleData {
  branchId: string;
  productId: string;
  staffId: string;
  clientId: string;
  userId: string;
  email: string;
}

export async function executeCascadingCleanup(branchIds: string[], productIds: string[], clientIds: string[], staffIds: string[]) {
  // 1. Bookings referencing these clients, branches, or staff.
  if (clientIds.length > 0) {
    await supabaseAdmin.from('Booking').delete().in('client_id', clientIds);
  }
  if (branchIds.length > 0) {
    await supabaseAdmin.from('Booking').delete().in('branchId', branchIds);
  }
  if (staffIds.length > 0) {
    await supabaseAdmin.from('Booking').delete().in('staff_id', staffIds);
  }

  // 2. StaffBlockedDate records referencing staff.
  if (staffIds.length > 0) {
    await supabaseAdmin.from('StaffBlockedDate').delete().in('staff_id', staffIds);
  }

  // 3. StaffSchedule records referencing staff.
  if (staffIds.length > 0) {
    await supabaseAdmin.from('StaffSchedule').delete().in('staff_id', staffIds);
  }

  // 4. StaffService records referencing staff or products.
  if (staffIds.length > 0) {
    await supabaseAdmin.from('StaffService').delete().in('staff_id', staffIds);
  }
  if (productIds.length > 0) {
    await supabaseAdmin.from('StaffService').delete().in('product_id', productIds);
  }

  // 5. Staff records.
  if (staffIds.length > 0) {
    await supabaseAdmin.from('Staff').delete().in('id', staffIds);
  }

  // 6. Product (Service) records.
  if (productIds.length > 0) {
    await supabaseAdmin.from('Product').delete().in('id', productIds);
  }

  // 7. Client records.
  if (clientIds.length > 0) {
    await supabaseAdmin.from('Client').delete().in('id', clientIds);
  }

  // 8. Branch records.
  if (branchIds.length > 0) {
    await supabaseAdmin.from('Branch').delete().in('id', branchIds);
  }
}

export async function setupTestEnvironment(): Promise<TestLifecycleData> {
  const email = 'e2e-admin@saloonnoon.test';
  const password = 'E2ETestPassword123!';

  // 0. Stale data cleanup from previous runs to ensure idempotency
  const { data: branches } = await supabaseAdmin.from('Branch').select('id').eq('name', 'E2E Test Branch');
  const { data: products } = await supabaseAdmin.from('Product').select('id').eq('name', 'E2E Test Service');
  const { data: clients } = await supabaseAdmin.from('Client').select('id').eq('name', 'E2E Test Client');
  const { data: staff } = await supabaseAdmin.from('Staff').select('id').eq('name', 'E2E Test Staff');

  const branchIds = branches?.map(x => x.id) || [];
  const productIds = products?.map(x => x.id) || [];
  const clientIds = clients?.map(x => x.id) || [];
  const staffIds = staff?.map(x => x.id) || [];

  await executeCascadingCleanup(branchIds, productIds, clientIds, staffIds);
  
  // Clean up user by getting user_id from AppUserRole mapping table first to bypass listUsers pagination limit
  const { data: roleRecord } = await supabaseAdmin
    .from('AppUserRole')
    .select('user_id')
    .eq('email', email)
    .maybeSingle();

  // Delete AppUserRole mapping record first (removes the FK constraint pointing to auth.users)
  await supabaseAdmin.from('AppUserRole').delete().eq('email', email);

  // Delete from Auth second
  if (roleRecord?.user_id) {
    await supabaseAdmin.auth.admin.deleteUser(roleRecord.user_id).catch(() => {});
  }

  // Fallback cleanup using listUsers in case AppUserRole entry didn't exist but Auth user did
  let page = 1;
  let hasMore = true;
  while (hasMore) {
    const { data: usersData, error: listError } = await supabaseAdmin.auth.admin.listUsers({
      page,
      perPage: 100,
    });
    if (listError || !usersData?.users || usersData.users.length === 0) {
      hasMore = false;
      break;
    }
    const existingUser = usersData.users.find(u => u.email === email);
    if (existingUser) {
      await supabaseAdmin.auth.admin.deleteUser(existingUser.id).catch(() => {});
      hasMore = false;
      break;
    }
    page++;
    if (usersData.users.length < 100) {
      hasMore = false;
    }
  }

  // 1. Create Branch
  const { data: branch, error: branchErr } = await supabaseAdmin
    .from('Branch')
    .insert({
      name: 'E2E Test Branch',
      nameAr: 'فرع اختبار E2E',
      address: 'E2E Address',
      phone: '+966111111111',
      isActive: true
    })
    .select('id')
    .single();
  if (branchErr || !branch) throw new Error(`Failed to create Branch: ${branchErr?.message}`);
  const branchId = branch.id;

  // 2. Create Product (Service)
  const { data: product, error: productErr } = await supabaseAdmin
    .from('Product')
    .insert({
      name: 'E2E Test Service',
      price: 100,
      durationMinutes: 30,
      durationMode: 'time',
      isAvailable: true,
      category: 'Test'
    })
    .select('id')
    .single();
  if (productErr || !product) throw new Error(`Failed to create Product: ${productErr?.message}`);
  const productId = product.id;

  // 3. Create Staff
  const { data: staffData, error: staffErr } = await supabaseAdmin
    .from('Staff')
    .insert({
      name: 'E2E Test Staff',
      branchId: branchId,
      role: 'staff',
      isActive: true
    })
    .select('id')
    .single();
  if (staffErr || !staffData) throw new Error(`Failed to create Staff: ${staffErr?.message}`);
  const staffId = staffData.id;

  // 4. Create StaffSchedule (all 7 days, 0 to 6)
  const schedules = [];
  for (let i = 0; i < 7; i++) {
    schedules.push({
      staff_id: staffId,
      dayOfWeek: i,
      startTime: '09:00',
      endTime: '18:00',
      isOff: false
    });
  }
  const { error: scheduleErr } = await supabaseAdmin
    .from('StaffSchedule')
    .insert(schedules);
  if (scheduleErr) throw new Error(`Failed to create StaffSchedules: ${scheduleErr?.message}`);

  // 5. Create StaffService association
  const { error: serviceLinkErr } = await supabaseAdmin
    .from('StaffService')
    .insert({
      staff_id: staffId,
      product_id: productId
    });
  if (serviceLinkErr) throw new Error(`Failed to link Staff to Service: ${serviceLinkErr?.message}`);

  // 6. Create Client
  const { data: client, error: clientErr } = await supabaseAdmin
    .from('Client')
    .insert({
      name: 'E2E Test Client',
      phone: '+966555555555',
      address: 'E2E Client Address',
      notes: 'E2E Client Notes'
    })
    .select('id')
    .single();
  if (clientErr || !client) throw new Error(`Failed to create Client: ${clientErr?.message}`);
  const clientId = client.id;

  // 7. Create Test Admin User in Supabase Auth
  const { data: authUser, error: authErr } = await supabaseAdmin.auth.admin.createUser({
    email,
    password,
    email_confirm: true
  });
  if (authErr || !authUser?.user) throw new Error(`Failed to create Auth User: ${authErr?.message}`);
  const userId = authUser.user.id;

  // 8. Create entry in AppUserRole mapping user_id
  const { error: roleErr } = await supabaseAdmin
    .from('AppUserRole')
    .insert({
      user_id: userId,
      email: email,
      name: 'E2E Test Administrator',
      role: 'admin',
      permissions: ['bookings', 'staff', 'services', 'settings']
    });
  if (roleErr) throw new Error(`Failed to create AppUserRole: ${roleErr?.message}`);

  return {
    branchId,
    productId,
    staffId,
    clientId,
    userId,
    email
  };
}

export async function teardownTestEnvironment(data: TestLifecycleData) {
  const branchIds = data.branchId ? [data.branchId] : [];
  const productIds = data.productId ? [data.productId] : [];
  const clientIds = data.clientId ? [data.clientId] : [];
  const staffIds = data.staffId ? [data.staffId] : [];

  await executeCascadingCleanup(branchIds, productIds, clientIds, staffIds);

  // Delete Admin User Role entry
  if (data.email) {
    await supabaseAdmin.from('AppUserRole').delete().eq('email', data.email);
  }
  // Delete Auth User
  if (data.userId) {
    await supabaseAdmin.auth.admin.deleteUser(data.userId).catch(() => {});
  }
}
