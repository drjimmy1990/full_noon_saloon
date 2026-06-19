# n8n Payment Webhook & Booking Expiry — Setup Guide

## Overview

Two new n8n workflows are needed to complement the booking payment system:

1. **Payment Webhook Workflow** — Receives Paymob payment notifications, checks slot availability, updates booking status, and sends WhatsApp confirmation/rejection
2. **Booking Expiry Cron** — Runs every 2 minutes to expire unpaid bookings and cancel stale ones

---

## Workflow 1: Payment Webhook (`saloooon-payment`)

### Trigger
**Webhook Node** — POST to `https://n8n.asra3.com/webhook/saloooon-payment`

This URL is set in the `.env.local` as `N8N_PAYMENT_WEBHOOK_URL` and is passed to Paymob when creating the payment intention.

### Paymob Webhook Payload Structure
```json
{
  "type": "TRANSACTION",
  "obj": {
    "id": 123456,                           // Paymob transaction ID
    "success": true,                        // Payment success
    "order": {
      "merchant_order_id": "BOOKING-uuid-here"  // Our reference
    },
    "amount_cents": 5000,                   // Amount in halalas (50 SAR)
    "currency": "SAR"
  },
  "hmac": "hex_signature"                   // HMAC for verification
}
```

### Flow

```
Webhook (POST)
  → Code Node: Parse & Validate
    → IF success === true AND reference starts with "BOOKING-"
      → SQL: Get Booking by ID (extract UUID from "BOOKING-{id}")
        → IF booking exists AND depositStatus !== "paid"
          → SQL: Check for Conflicting Bookings (same staff, same time, status = "confirmed")
            → IF No Conflict
              → SQL: UPDATE Booking SET status='confirmed', depositStatus='paid', paymobTxnId=txnId
              → HTTP Request: Send WhatsApp Confirmation ✅
            → ELSE (Slot Taken)
              → SQL: UPDATE Booking SET status='cancelled', depositStatus='paid', paymobTxnId=txnId
              → HTTP Request: Send WhatsApp Rejection ❌
```

### Node Details

#### Node 1: Webhook
- **Type**: Webhook
- **Method**: POST
- **Path**: `saloooon-payment`

#### Node 2: Parse Payment (Code Node)
```javascript
const body = $input.first().json.body || $input.first().json;
const transaction = body.obj || body;

// Extract booking reference
const merchantOrderId = transaction?.order?.merchant_order_id || '';
const isBooking = merchantOrderId.startsWith('BOOKING-');
const bookingId = isBooking ? merchantOrderId.replace('BOOKING-', '') : '';
const success = transaction?.success === true || transaction?.success === 'true';
const txnId = transaction?.id || '';

return [{
  json: {
    success,
    isBooking,
    bookingId,
    txnId,
    merchantOrderId,
    hmac: body.hmac || ''
  }
}];
```

#### Node 3: IF — Check Success & Is Booking
- Condition: `{{ $json.success }}` equals `true` AND `{{ $json.isBooking }}` equals `true`

#### Node 4: SQL — Get Booking
```sql
SELECT b.*, c.phone as client_phone, c.name as client_name, s.name as staff_name
FROM "Booking" b
LEFT JOIN "Client" c ON b.client_id = c.id
LEFT JOIN "Staff" s ON b.staff_id = s.id
WHERE b.id = '{{ $json.bookingId }}'
LIMIT 1
```

#### Node 5: IF — Check Not Already Paid
- Condition: `{{ $json.depositStatus }}` NOT equals `paid`

#### Node 6: SQL — Check Slot Conflict
```sql
SELECT id FROM "Booking"
WHERE staff_id = '{{ $json.staff_id }}'
  AND status = 'confirmed'
  AND id != '{{ $json.id }}'
  AND "bookingDate" >= '{{ $json.bookingDate.substring(0,10) }}T00:00:00'
  AND "bookingDate" < '{{ $json.bookingDate.substring(0,10) }}T23:59:59'
  AND (
    ("bookingDate" < '{{ $json.endTime }}' AND "endTime" > '{{ $json.bookingDate }}')
  )
```

#### Node 7A (No Conflict): SQL — Confirm Booking
```sql
UPDATE "Booking"
SET status = 'confirmed',
    "depositStatus" = 'paid',
    "paymobTxnId" = '{{ $('Parse Payment').item.json.txnId }}'
WHERE id = '{{ $('Get Booking').item.json.id }}'
```

#### Node 7B (No Conflict): Send WhatsApp Confirmation
- **HTTP Request** to Evolution API
- **URL**: `https://evo.hillhousevilla.com/message/sendText/{{ instance }}`
- **Method**: POST
- **Headers**: `apikey: YOUR_API_KEY`
- **Body**:
```json
{
  "number": "{{ $('Get Booking').item.json.client_phone }}@s.whatsapp.net",
  "text": "✅ تم تأكيد حجزك بنجاح!\n\n📋 كود الحجز: {{ $('Get Booking').item.json.bookingCode }}\n💇 الخدمة: {{ $('Get Booking').item.json.serviceSummary }}\n📅 التاريخ: {{ $('Get Booking').item.json.bookingDate.substring(0,10) }}\n\nشكراً لاختيارك صالون نون 🌸",
  "delay": 1200
}
```

#### Node 8A (Conflict): SQL — Cancel & Mark as Paid
```sql
UPDATE "Booking"
SET status = 'cancelled',
    "depositStatus" = 'paid',
    "paymobTxnId" = '{{ $('Parse Payment').item.json.txnId }}',
    notes = COALESCE(notes, '') || ' - الوقت اتحجز بعد انتهاء فترة الانتظار، يحتاج استرداد العربون'
WHERE id = '{{ $('Get Booking').item.json.id }}'
```

#### Node 8B (Conflict): Send WhatsApp Rejection
```json
{
  "number": "{{ $('Get Booking').item.json.client_phone }}@s.whatsapp.net",
  "text": "عذراً 💔\n\nالوقت اللي حجزتيه اتحجز من شخص آخر.\nكود الحجز: {{ $('Get Booking').item.json.bookingCode }}\n\nتقدرين تتواصلي معنا لاختيار وقت تاني أو لاسترداد العربون.\nصالون نون 🌸",
  "delay": 1200
}
```

---

## Workflow 2: Booking Expiry Cron

### Trigger
**Schedule Trigger** — Every 2 minutes

### Flow
```
Schedule (every 2 min)
  → HTTP Request: GET https://salonnoon.net/api/booking/expire
  → (Optional) IF: Log expired count > 0
```

The `/api/booking/expire` endpoint handles:
1. **10-min expiry**: `waiting_payment` bookings past `paymentExpiresAt` → reverted to `pending`
2. **24-hour expiry**: `pending` bookings older than 24h → set to `cancelled`

### Alternative: Direct SQL in n8n

If you prefer to avoid the API call, you can use SQL nodes directly:

#### SQL Node 1: Expire waiting_payment
```sql
UPDATE "Booking"
SET status = 'pending', "paymentExpiresAt" = NULL
WHERE status = 'waiting_payment'
  AND "paymentExpiresAt" < NOW()
RETURNING id, "bookingCode"
```

#### SQL Node 2: Cancel stale pending
```sql
UPDATE "Booking"
SET status = 'cancelled'
WHERE status = 'pending'
  AND "createdAt" < NOW() - INTERVAL '24 hours'
RETURNING id, "bookingCode"
```

---

## Bot System Prompt Updates

The bot's `create_booking` tool now returns these new fields:
- `bookingCode` — Human-readable code like `NOON-4821`
- `paymentUrl` — Paymob checkout link (if deposit required)
- `depositAmount` — Amount in SAR

### Bot behavior after booking creation:
1. If `paymentUrl` is returned → tell customer: "تم حجز الموعد! ادفعي العربون من الرابط ده خلال 10 دقائق: {paymentUrl}"
2. If no `paymentUrl` → normal flow (booking is pending, admin will confirm)

### New tool: `check_my_bookings`
- **URL**: `GET https://salonnoon.net/api/booking/lookup?phone={phone}`
- **Returns**: List of customer bookings with codes, dates, statuses

---

## Paymob Dashboard Setup

Set the **Transaction Processed Callback** URL in Paymob dashboard to:
```
https://n8n.asra3.com/webhook/saloooon-payment
```

This ensures ALL Paymob payment notifications go to n8n.

---

## Database Migration

Run this SQL in Supabase Dashboard → SQL Editor:

```sql
-- File: saloon-mostafa/migrations/004_payment_booking_flow.sql
ALTER TABLE "Booking"
  ADD COLUMN IF NOT EXISTS "bookingCode" TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS "paymentExpiresAt" TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS "paymobIntentionId" TEXT,
  ADD COLUMN IF NOT EXISTS "paymobTxnId" TEXT;

CREATE INDEX IF NOT EXISTS idx_booking_code ON "Booking" ("bookingCode");
CREATE INDEX IF NOT EXISTS idx_booking_payment_expires ON "Booking" ("paymentExpiresAt")
  WHERE status = 'waiting_payment';
CREATE INDEX IF NOT EXISTS idx_booking_pending_created ON "Booking" ("createdAt")
  WHERE status = 'pending';
```
