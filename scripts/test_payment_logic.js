const { createClient } = require('./gardenia-website/node_modules/@supabase/supabase-js');
const fs = require('fs');
const env = fs.readFileSync('gardenia-website/.env.local', 'utf8');
const parsed = {};
env.split('\n').forEach(l => {
  const i = l.indexOf('=');
  if (i > 0) parsed[l.slice(0, i).trim()] = l.slice(i+1).trim().replace(/^['"]|['"]$/g, '');
});
const sb = createClient(parsed.NEXT_PUBLIC_SUPABASE_URL, parsed.SUPABASE_SERVICE_ROLE_KEY);

async function test() {
  const bookingId = '2afd9bb2-7d32-4193-942d-3a941ed2dccf';
  const amountCents = 15000;
  const paidAmount = amountCents / 100; // 150 SAR

  // SQL test:
  const sql = `
    WITH target_booking AS (
      SELECT id, "paymobIntentionId", "depositAmount"
      FROM "Booking"
      WHERE id = '${bookingId}'
      LIMIT 1
    )
    SELECT 
      b.id,
      b.id AS booking_id,
      b.client_id,
      b."bookingCode" AS booking_code,
      b."bookingDate" AS booking_date,
      b."bookingTime" AS booking_time,
      b."depositAmount" AS deposit_amount,
      b."serviceSummary" AS service_summary,
      b."paymobIntentionId" AS paymob_intention_id,
      TRIM(c.phone) AS client_phone,
      COALESCE(NULLIF(TRIM(c.name), ''), 'عميلتنا العزيزة') AS client_name,
      COALESCE(NULLIF(TRIM(br."nameAr"), ''), TRIM(br.name), 'فرع السنابل – جدة') AS branch_name,
      COALESCE(TRIM(p.name), b."serviceSummary") AS service_name,
      COALESCE(p.price::text, b."depositAmount"::text, '0') AS service_price,
      COALESCE(TRIM(st.name), 'أخصائية الصالون') AS staff_name
    FROM "Booking" b
    LEFT JOIN "Client" c ON b.client_id = c.id
    LEFT JOIN "Branch" br ON b."branchId" = br.id
    LEFT JOIN "Product" p ON b."serviceId" = p.id
    LEFT JOIN "Staff" st ON b.staff_id = st.id
    WHERE b.id = '${bookingId}'
       OR (
         b."paymobIntentionId" IS NOT NULL 
         AND b."paymobIntentionId" = (SELECT "paymobIntentionId" FROM target_booking)
       )
    ORDER BY b."bookingDate" ASC;
  `;

  // We can run via RPC or inspect
  // Let's test using Supabase JS client to verify the logic:
  const { data: target } = await sb.from('Booking').select('id, paymobIntentionId, depositAmount').eq('id', bookingId).single();
  let q = sb.from('Booking').select(`
    id,
    bookingCode,
    bookingDate,
    bookingTime,
    depositAmount,
    serviceSummary,
    paymobIntentionId,
    Client(name, phone),
    Branch(name, nameAr),
    Product(name, price),
    Staff!Booking_staff_id_fkey(name)
  `);

  if (target?.paymobIntentionId) {
    q = q.eq('paymobIntentionId', target.paymobIntentionId);
  } else {
    q = q.eq('id', bookingId);
  }

  const { data: items, error } = await q.order('bookingDate', { ascending: true });
  if (error) {
    console.error('Error:', error);
    return;
  }

  console.log(`Found ${items.length} bookings for this payment.`);
  const unitDeposit = Number(items[0]?.depositAmount) || 50;
  const countFromMoney = Math.round(paidAmount / unitDeposit);

  console.log(`Paid Amount: ${paidAmount} SAR, Unit Deposit: ${unitDeposit} SAR => Covers: ${countFromMoney} bookings.`);
  console.log(`Bookings in DB for this group: ${items.length}`);

  // Format message:
  const timesList = items.map((b, i) => {
    const d = new Date(b.bookingDate);
    const timeStr = b.bookingTime || d.toLocaleTimeString('ar-SA', { timeZone: 'Asia/Riyadh', hour: '2-digit', minute: '2-digit' });
    return `* الموعد ${i + 1}: الساعة ${timeStr} (كود: ${b.bookingCode})`;
  }).join('\n');

  console.log('Formatted Times:\n' + timesList);
}
test();
