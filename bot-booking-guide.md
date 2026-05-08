# Bot Booking Integration Guide 🤖

## Two Approaches for the Bot

### Option A: Supabase RPC Functions (Recommended for n8n)
The bot calls PostgreSQL functions directly via Supabase REST API.  
**Advantages:** Single call, no middleware, faster, works offline from website.

### Option B: Website REST Endpoints
The bot calls your gardenia-website Next.js API routes via HTTP.  
**Advantages:** Already built, shared logic with website.

---

## Available Functions & Endpoints

### 1. 🏢 Get Branches
**Bot asks:** "إيه الفروع المتاحة؟"

| Method | How to call |
|--------|-------------|
| **RPC** | `POST /rest/v1/rpc/get_active_branches` — Body: `{}` |
| **REST** | `GET /api/branches?active=true` |

**Returns:** `[{ id, name, name_ar, address, phone }]`

---

### 2. 💅 Get Services (by branch)
**Bot asks:** "إيه الخدمات في فرع X؟"

| Method | How to call |
|--------|-------------|
| **RPC** | `POST /rest/v1/rpc/get_services_by_branch` — Body: `{ "p_branch_id": "uuid" }` |
| **REST** | `GET /api/services?branchId=uuid` |

**Returns:** `[{ id, name, price, duration_minutes, duration_mode, deposit_amount }]`

---

### 3. 👩 Get Staff for Service
**Bot asks:** "مين العاملات اللي بتعمل خدمة X؟"

| Method | How to call |
|--------|-------------|
| **RPC** | `POST /rest/v1/rpc/get_staff_for_service` — Body: `{ "p_service_id": "uuid", "p_branch_id": "uuid" }` |
| **REST** | `GET /api/staff-by-service?serviceId=uuid&branchId=uuid` |

**Returns:** `[{ id, name, role, branch_id }]`

---

### 4. ⏰ Get Available Time Slots
**Bot asks:** "إيه الأوقات المتاحة مع فاطمة يوم الأحد؟"

| Method | How to call |
|--------|-------------|
| **RPC** | `POST /rest/v1/rpc/get_available_slots` — Body: `{ "p_staff_id": "uuid", "p_service_id": "uuid", "p_date": "2026-05-10" }` |
| **REST** | `GET /api/availability?staffId=uuid&serviceId=uuid&date=2026-05-10` |

**Returns (time mode):**
```json
{
  "mode": "time",
  "slots": ["09:00", "09:15", "09:30", "10:00", "10:30", ...],
  "duration_minutes": 30,
  "deposit_amount": 5
}
```

**Returns (queue mode):**
```json
{
  "mode": "queue",
  "next_queue_number": 4,
  "duration_minutes": 30,
  "deposit_amount": 0
}
```

---

### 5. ✅ Create Booking
**Bot says:** "تمام هحجزلك مع فاطمة يوم الأحد الساعة 10"

| Method | How to call |
|--------|-------------|
| **RPC** | `POST /rest/v1/rpc/create_bot_booking` — Body below |
| **REST** | `POST /api/booking` — Body below |

**RPC Body:**
```json
{
  "p_client_name": "سارة أحمد",
  "p_client_phone": "+962791234567",
  "p_service_id": "uuid",
  "p_staff_id": "uuid",
  "p_branch_id": "uuid",
  "p_date": "2026-05-10",
  "p_time": "10:00",
  "p_channel": "whatsapp"
}
```

**Returns (success):**
```json
{
  "success": true,
  "booking_id": "uuid",
  "service": "قص شعر",
  "date": "2026-05-10",
  "time": "10:00",
  "deposit_amount": 5,
  "message": "تم تأكيد حجزك بنجاح! 🌸"
}
```

**Returns (conflict):**
```json
{
  "success": false,
  "error": "هذا الوقت محجوز بالفعل. يرجى اختيار وقت آخر."
}
```

---

### 6. 📋 Check Customer Bookings
**Bot asks:** "عايزه أعرف حجوزاتي"

| Method | How to call |
|--------|-------------|
| **RPC** | `POST /rest/v1/rpc/check_customer_bookings` — Body: `{ "p_phone": "+962791234567" }` |
| **REST** | Not built yet (can add if needed) |

**Returns:**
```json
{
  "found": true,
  "count": 2,
  "bookings": [
    { "service": "قص شعر", "date": "2026-05-10", "time": "10:00", "status": "confirmed", "staff": "فاطمة" }
  ]
}
```

---

### 7. ❌ Cancel Booking
**Bot says:** "تم إلغاء حجزك"

| Method | How to call |
|--------|-------------|
| **RPC** | `POST /rest/v1/rpc/cancel_bot_booking` — Body: `{ "p_booking_id": "uuid", "p_phone": "+962791234567" }` |

---

## n8n Workflow Setup

### Using Supabase RPC (Recommended)
In n8n, use an **HTTP Request** node:

```
URL: https://havgzkklfiengdxsyqmf.supabase.co/rest/v1/rpc/get_available_slots
Method: POST
Headers:
  apikey: <SUPABASE_ANON_KEY>
  Authorization: Bearer <SUPABASE_ANON_KEY>
  Content-Type: application/json
Body:
  { "p_staff_id": "...", "p_service_id": "...", "p_date": "2026-05-10" }
```

### Bot Conversation Flow
```
Customer: عايزه أحجز
Bot: في أي فرع؟ → [get_active_branches]
Customer: فرع المدينة
Bot: أي خدمة؟ → [get_services_by_branch(branch_id)]
Customer: قص شعر
Bot: مع أي عاملة؟ → [get_staff_for_service(service_id, branch_id)]
Customer: فاطمة
Bot: أي يوم؟
Customer: الأحد الجاي
Bot: الأوقات المتاحة: 9:00, 9:30, 10:00... → [get_available_slots(...)]
Customer: 10:00
Bot: ✅ تم الحجز! → [create_bot_booking(...)]
```

## Migration
Run `migration-bot-functions.sql` in Supabase SQL Editor to install all functions.
