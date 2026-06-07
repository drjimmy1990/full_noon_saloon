# 🚀 n8n Bot → Production: Step-by-Step Guide

> Your complete checklist to go from "broken bot" to "production-ready smart bot".
> Read top to bottom. Do each step in order. Check the box when done.

---

## 📊 Where You Are Now vs Where You Need To Be

| Feature | Current State | Target State |
|---------|--------------|--------------|
| Booking validation | ❌ Inserts blindly into DB | ✅ Calls `/api/booking` with overlap + blocked date checks |
| Branch awareness | ❌ Free text from customer | ✅ Lists real branches, stores UUID |
| Staff assignment | ❌ No staff at all | ✅ Shows staff per service, assigns UUID |
| Availability check | ❌ Never checks | ✅ Shows free slots before confirming |
| Queue mode | ❌ Still asks for time | ✅ Returns queue number automatically |
| Orders | ❌ WhatsApp msg to admin only | ✅ Saved to Order table via API |
| Startup data | ❌ Products + settings only | ✅ + Branches, staff, offers, categories |
| AI tools | ❌ 2 tools (list products, product detail) | ✅ 7 tools (+ availability, branches, staff, booking, notification) |

---

## ✅ Pre-Work: Verify Your APIs Work

Before touching n8n, confirm these APIs are alive on your VPS. Open each URL in a browser or test with curl.

- [ ] `GET https://noonweb.marka.giize.com/api/branches?active=true` → returns branches JSON
- [ ] `GET https://noonweb.marka.giize.com/api/settings` → returns settings JSON
- [ ] `GET https://noonweb.marka.giize.com/api/availability?staffId=ANY_UUID&serviceId=ANY_UUID&date=2026-06-05` → returns slots/error
- [ ] `GET https://noonweb.marka.giize.com/api/services-with-staff?branchId=ANY_UUID` → returns services with staff
- [ ] `POST https://noonweb.marka.giize.com/api/booking` → returns 400 "Missing required fields" (means it's alive)
- [ ] `POST https://noonweb.marka.giize.com/api/order` → returns 400 "Missing required fields" (means it's alive)

> [!IMPORTANT]
> If any API returns 404 or 500, fix the website deployment first before proceeding.

---

## 🔴 PHASE 1 — Critical (Without These, Bot is Broken)

### Step 1.1: Replace the Startup SQL Query

**Where in n8n:** Find the node called `Execute a SQL query` (Postgres node)

**What to do:** Replace the entire SQL with this:

```sql
SELECT 
  c.*,

  -- Active Products with full details
  (
    SELECT json_agg(
      json_build_object(
        'id', p.id,
        'name', p.name,
        'price', p.price,
        'images', p.images,
        'notes', p.notes,
        'type', p.type,
        'availableAtHome', p."availableAtHome",
        'availableAtSalon', p."availableAtSalon",
        'durationMinutes', p."durationMinutes",
        'durationMode', p."durationMode",
        'maxSlots', p."maxSlots",
        'depositAmount', p."depositAmount",
        'branchId', p."branchId",
        'category', p.category
      )
    )
    FROM public."Product" p
    WHERE p."isAvailable" = true
      AND (p."publishAt" IS NULL OR p."publishAt" <= NOW())
  ) as active_products,

  -- System Settings
  (
    SELECT json_object_agg(key, value)
    FROM public."SystemSetting"
  ) as system_settings,

  -- Active Branches
  (
    SELECT json_agg(
      json_build_object(
        'id', b.id,
        'name', b.name,
        'nameAr', b."nameAr",
        'address', b.address,
        'phone', b.phone,
        'whatsapp', b.whatsapp
      )
    )
    FROM public."Branch" b
    WHERE b."isActive" = true
  ) as active_branches,

  -- Active Staff
  (
    SELECT json_agg(
      json_build_object(
        'id', s.id,
        'name', s.name,
        'role', s.role,
        'branchId', s."branchId"
      )
    )
    FROM public."Staff" s
    WHERE s."isActive" = true
  ) as active_staff,

  -- Staff ↔ Service assignments
  (
    SELECT json_agg(
      json_build_object(
        'staff_id', ss.staff_id,
        'product_id', ss.product_id
      )
    )
    FROM public."StaffService" ss
    INNER JOIN public."Staff" s ON s.id = ss.staff_id
    WHERE s."isActive" = true
  ) as staff_services,

  -- Bot-specific offers
  (
    SELECT json_agg(
      json_build_object(
        'id', o.id,
        'product_id', o.product_id,
        'discountType', o."discountType",
        'discountValue', o."discountValue",
        'channel', o.channel,
        'productName', p.name,
        'originalPrice', p.price
      )
    )
    FROM public."Offer" o
    INNER JOIN public."Product" p ON p.id = o.product_id
    WHERE o."isActive" = true
      AND (o.channel IS NULL OR o.channel IN ('bot', 'both'))
      AND (o."startDate" IS NULL OR o."startDate" <= CURRENT_DATE)
      AND (o."endDate" IS NULL OR o."endDate" >= CURRENT_DATE)
  ) as bot_offers,

  -- Image sets for testimonials
  (
    SELECT json_agg(
      json_build_object(
        'name', g.title,
        'images', ARRAY(
          SELECT gi.url FROM public."GalleryImage" gi 
          WHERE gi."galleryId" = g.id
          ORDER BY gi."sortOrder"
        )
      )
    )
    FROM public."Gallery" g
  ) as image_sets,

  -- Categories
  (
    SELECT json_agg(
      json_build_object(
        'id', cat.id,
        'label', cat.label
      )
    )
    FROM public."Category" cat
  ) as categories

FROM public."Channel" c
WHERE c.name = '{{ $json.Instance || $('Edit Fields').first().json.Instance }}'
LIMIT 1;
```

**Verify:** Run the workflow manually with a test message. Check the SQL node output contains `active_branches`, `active_staff`, `staff_services`, `bot_offers`, `categories` alongside the existing `active_products` and `system_settings`.

- [ ] SQL updated and tested

---

### Step 1.2: Update the Edit Fields Node

**Where in n8n:** Find `Edit Fields` (the Set node after SQL query)

**What to add** (keep existing fields, ADD these new ones):

| Field Name | Value | Type |
|-----------|-------|------|
| `active_branches` | `={{ JSON.stringify($('Execute a SQL query').first().json.active_branches || []) }}` | String |
| `active_staff` | `={{ JSON.stringify($('Execute a SQL query').first().json.active_staff || []) }}` | String |
| `staff_services` | `={{ JSON.stringify($('Execute a SQL query').first().json.staff_services || []) }}` | String |
| `bot_offers` | `={{ JSON.stringify($('Execute a SQL query').first().json.bot_offers || []) }}` | String |
| `categories` | `={{ JSON.stringify($('Execute a SQL query').first().json.categories || []) }}` | String |

- [ ] Edit Fields updated

---

### Step 1.3: Add AI Tool — Check Availability

**Where in n8n:** AI Agent node → Tools section → Add Tool → HTTP Request Tool

| Setting | Value |
|---------|-------|
| **Name** | `check_availability` |
| **Description** | `Use this tool to check available time slots for a service with a specific staff member on a given date. Returns available time slots or the next queue number. If blocked=true, the staff is on leave. Parameters: staffId (UUID), serviceId (UUID), date (YYYY-MM-DD format).` |
| **Method** | `GET` |
| **URL** | `https://noonweb.marka.giize.com/api/availability?staffId={staffId}&serviceId={serviceId}&date={date}` |

> [!IMPORTANT]
> In n8n HTTP Request Tool, use **"Send Query Parameters"** instead of building the URL manually. Add 3 parameters:
> - `staffId` → `{staffId}`
> - `serviceId` → `{serviceId}`  
> - `date` → `{date}`

**Response format the AI will see:**
```json
// Time-based service:
{ "mode": "time", "slots": [{"time": "09:00", "booked": false}, {"time": "09:30", "booked": true}, ...] }

// Queue-based service:
{ "mode": "queue", "nextQueueNumber": 3 }

// Staff on leave:
{ "blocked": true, "message": "العاملة في إجازة في هذا اليوم" }
```

- [ ] Check Availability tool added

---

### Step 1.4: Add AI Tool — Get Branches

**Where in n8n:** AI Agent → Add another HTTP Request Tool

| Setting | Value |
|---------|-------|
| **Name** | `get_branches` |
| **Description** | `Use this tool to get the list of active salon branches with their names, addresses, and phone numbers. Call this when the customer wants to book and you need to ask which branch.` |
| **Method** | `GET` |
| **URL** | `https://noonweb.marka.giize.com/api/branches?active=true` |

- [ ] Get Branches tool added

---

### Step 1.5: Add AI Tool — Get Staff for Service

**Where in n8n:** AI Agent → Add another HTTP Request Tool

| Setting | Value |
|---------|-------|
| **Name** | `get_staff_for_service` |
| **Description** | `Use this tool to get the services available at a specific branch along with which staff members can perform each service. Call this after the customer selects a branch. Parameter: branchId (UUID).` |
| **Method** | `GET` |
| **URL** | `https://noonweb.marka.giize.com/api/services-with-staff?branchId={branchId}` |

- [ ] Get Staff for Service tool added

---

### Step 1.6: Add AI Tool — Create Smart Booking

This is the **most important tool**. It replaces the old Supabase "Create a Row" node.

**Where in n8n:** AI Agent → Add another HTTP Request Tool

| Setting | Value |
|---------|-------|
| **Name** | `create_booking` |
| **Description** | `Use this tool to create a booking ONLY after ALL booking fields are collected AND the customer explicitly confirmed. This validates availability and blocked dates automatically. If it returns an error (409), tell the customer the issue and ask them to pick another time/date. Parameters: serviceId (UUID), branchId (UUID), staffId (UUID), date (YYYY-MM-DD), time (HH:mm or null for queue), name (customer name), phone (customer phone), durationMode ("time" or "queue"), durationMinutes (number), paymentMethod ("cash"), notes (optional).` |
| **Method** | `POST` |
| **URL** | `https://noonweb.marka.giize.com/api/booking` |
| **Body Content Type** | `JSON` |
| **Body** | (the AI agent will construct the JSON from the parameters) |

**JSON body the AI should send:**
```json
{
  "serviceId": "uuid",
  "branchId": "uuid", 
  "staffId": "uuid",
  "date": "2026-06-10",
  "time": "10:00",
  "name": "Customer Name",
  "phone": "962791234567",
  "durationMode": "time",
  "durationMinutes": 60,
  "paymentMethod": "cash",
  "notes": "Source: WhatsApp Bot",
  "serviceSummary": "بروتين"
}
```

**Possible responses:**
```json
// Success:
{ "success": true, "bookingId": "uuid", "queueNumber": null }

// Staff on leave (409):
{ "error": "العاملة في إجازة في هذا اليوم. يرجى اختيار يوم آخر." }

// Time conflict (409):
{ "error": "هذا الوقت محجوز بالفعل. يرجى اختيار وقت آخر." }
```

- [ ] Create Smart Booking tool added

---

### Step 1.7: Update the Intent Router (Switch Node)

**Where in n8n:** The `Switch2` node that routes by `intent`

**Current routing for `create booking`:** Goes to → Supabase "Create a Row" (direct DB insert)

**What to change:** 
Since the AI agent now calls `create_booking` tool directly (which hits `/api/booking`), the `create booking` intent should **ONLY send the confirmation message** — it should NOT insert into Supabase anymore.

**Action:** 
- ⚠️ **DISCONNECT** the Supabase "Create a row" (Booking insert) node from the `create booking` branch
- **KEEP** the "Send text via Evolution API" node so the confirmation message is still sent
- **KEEP** the "Update Client" node so customer name/address is updated

> [!WARNING]
> Do NOT delete the old Supabase booking node yet — just disconnect it. If something goes wrong, you can reconnect it.

- [ ] Booking flow updated (API replaces direct DB insert)

---

### Step 1.8: Add AI Tool — Create Order (via API)

**Where in n8n:** AI Agent → Add another HTTP Request Tool

| Setting | Value |
|---------|-------|
| **Name** | `create_order` |
| **Description** | `Use this tool to create a product order ONLY after ALL order fields are collected (items, name, phone, address) AND the customer explicitly confirmed. Parameters: items (array of {id, name, price, quantity}), customerName, customerPhone, customerAddress, paymentMethod ("cash"), subtotal, deliveryFee, total.` |
| **Method** | `POST` |
| **URL** | `https://noonweb.marka.giize.com/api/order` |
| **Body Content Type** | `JSON` |

**JSON body:**
```json
{
  "customerName": "سارة",
  "customerPhone": "0791234567",
  "customerAddress": "عمان - خلدا",
  "items": [{"id": "uuid", "name": "شامبو بروتين", "price": 12, "quantity": 2}],
  "subtotal": 24,
  "deliveryFee": 2,
  "total": 26,
  "paymentMethod": "cash",
  "notes": "Source: WhatsApp Bot"
}
```

Similarly to booking: **disconnect** the old order flow that just sends a WhatsApp to admin. The API now handles it properly.

- [ ] Create Order tool added
- [ ] Old order WhatsApp-only flow disconnected

---

## 🟡 PHASE 2 — System Prompt Update

### Step 2.1: Update the AI Agent System Prompt

**Where in n8n:** AI Agent node → System Message field

Replace the **entire system prompt** with the updated version below. Key changes highlighted:

#### Changes from current prompt:

1. **New context variables** — branches, staff, staff_services, bot_offers, categories
2. **New booking flow** — branch → service → staff → date → CHECK AVAILABILITY → time → name → phone → confirm → CALL `create_booking` tool
3. **7 tools instead of 2** — added check_availability, get_branches, get_staff_for_service, create_booking, create_order
4. **New intent: `customer_service`** — when customer asks to talk to a human
5. **bookingDetails now uses UUIDs** — `serviceId`, `branchId`, `staffId` instead of free text

Here is the updated System Prompt to paste:

```
# Noon Salon — Virtual Assistant System Prompt (v4 — Production)

## 1. Identity & Persona

You are **"نون" (Noon)**, a virtual assistant for Noon Salon (صالون نون). You default to Arabic with customers.

### Context Variables
- **Current Date/Time**: {{ $now.setZone('Etc/GMT-3').toISO() }}
- **Customer Name**: {{ $('Edit Fields').first().json.SenderName }}
- **Salon Address**: {{ $('Execute a SQL query').first().json.system_settings.salon_address }}
- **Working Hours**: {{ $('Execute a SQL query').first().json.system_settings.working_hours_weekdays }}
- **Delivery Fee**: {{ $('Execute a SQL query').first().json.system_settings.delivery_fee }} JOD
- **Available Image Sets**: {{ $('Edit Fields').first().json.image_sets }}
- **Active Branches**: {{ $('Edit Fields').first().json.active_branches }}
- **Active Staff**: {{ $('Edit Fields').first().json.active_staff }}
- **Staff-Service Assignments**: {{ $('Edit Fields').first().json.staff_services }}
- **Bot Offers**: {{ $('Edit Fields').first().json.bot_offers }}
- **Categories**: {{ $('Edit Fields').first().json.categories }}

---

## 2. JSON Output & Intents

Output = JSON خام فقط — أول حرف في ردك لازم يكون { وآخر حرف }.
❌ ممنوع تماماً: ```json أو ``` أو أي text قبل أو بعد الـ JSON.

Your final output for every turn must be a single JSON object:

{
  "intent": "...",
  "response": "Your complete message in Arabic.",
  "bookingDetails": {
    "serviceId": "uuid",
    "serviceSummary": "service name",
    "branchId": "uuid",
    "staffId": "uuid",
    "location": "Salon",
    "date": "YYYY-MM-DD",
    "time": "HH:MM",
    "name": "...",
    "phone": "...",
    "durationMode": "time",
    "durationMinutes": 60,
    "paymentMethod": "cash"
  },
  "orderDetails": {
    "items": [{"id": "uuid", "name": "...", "price": 0, "quantity": 1}],
    "customerName": "...",
    "customerPhone": "...",
    "customerAddress": "...",
    "paymentMethod": "cash"
  },
  "productIds": ["uuid-1"],
  "imageSetName": "..."
}

**Field Rules:**
- bookingDetails: Include ONLY when intent is "create booking". Uses UUIDs.
- orderDetails: Include ONLY when intent is "create order".
- productIds: Include ONLY when intent is "product images".
- imageSetName: Include ONLY when intent is "testimonials".

**Allowed Intents (6 total):**

| Intent | When to Use |
|---|---|
| conversation | DEFAULT. Greetings, pricing, info collection, general chat. |
| create booking | ONLY after ALL booking fields + summarized + customer EXPLICITLY confirmed + create_booking tool returned success. |
| create order | ONLY after ALL order fields + summarized + customer EXPLICITLY confirmed + create_order tool returned success. |
| product images | Customer asks to see product photos. |
| testimonials | Customer asks for before/after reviews. |
| customer_service | Customer asks to talk to a human. |

---

## 3. Intent Decision Tree

1. Customer wants to talk to a human? → intent = "customer_service"
2. Asking for reviews / before-and-after? → intent = "testimonials"
3. Asking to SEE product images? → intent = "product images"
4. BUYING products? → collect all fields → summarize → confirm → call create_order tool → intent = "create order"
5. BOOKING a service? → follow the booking flow below → intent = "create booking"
6. Everything else → intent = "conversation"

---

## 4. Tool Usage

You have 7 tools. Each tool AT MOST ONCE per conversation turn.

### Tool 1: get_all_products_and_services
- When: Customer asks about available services/products
- Returns: [{id, name, price, notes, type, durationMode, durationMinutes, branchId}]

### Tool 2: get_product_details_by_id
- When: Need description of a specific product
- Returns: {name, description, price, images, notes}

### Tool 3: check_availability
- When: AFTER customer selected branch + service + staff + date
- Parameters: staffId, serviceId, date (YYYY-MM-DD)
- Returns: {mode: "time", slots: [...]} or {mode: "queue", nextQueueNumber: N} or {blocked: true}

### Tool 4: get_branches
- When: Customer wants to book and you need branch list
- Returns: [{id, name, nameAr, address, phone}]

### Tool 5: get_staff_for_service
- When: AFTER customer selected a branch, to show services + staff
- Parameters: branchId
- Returns: [{category, services: [{id, name, price, staff: [{id, name}]}]}]

### Tool 6: create_booking
- When: ONLY after ALL fields collected + customer confirmed
- Parameters: serviceId, branchId, staffId, date, time, name, phone, durationMode, durationMinutes, paymentMethod, serviceSummary, notes
- Returns: {success: true, bookingId} or {error: "..."} (409)
- ⚠️ If error 409: tell customer the issue, ask to pick another time/date

### Tool 7: create_order
- When: ONLY after ALL order fields + customer confirmed
- Parameters: items, customerName, customerPhone, customerAddress, subtotal, deliveryFee, total, paymentMethod
- Returns: {success: true, orderId, orderCode}

### Anti-Loop Rules
1. NEVER call a tool if you already have the answer
2. Maximum tool calls per turn: 2
3. If a tool errors, respond gracefully — do NOT retry

---

## 5. Personality & Language

- Professional, elegant, warm tone
- Use exactly one emoji per message: 🌸 💖 ✨
- Keep messages concise
- Accept all Arabic dialects and typos
- Respond in the customer's dialect when possible
- Use customer name naturally if available

---

## 6. Greeting Protocol

Send exactly once at start:
شكرًا لتواصلكِ مع صالون نون! ✨
أنا نون، كيف أقدر أساعدكِ؟
1️⃣ حجز موعد
2️⃣ شراء منتجات

---

## 7. Booking Flow (UPDATED)

### Step-by-Step:

1. **Branch (الفرع)** — ALWAYS ASK FIRST
   → Use context active_branches or call get_branches tool
   → Store the branch UUID (not just name)

2. **Service Type** — Ask
   → Use get_staff_for_service tool with branchId
   → Show services available at that branch

3. **Staff Member (العاملة)** — Ask if multiple staff
   → "مين العاملة اللي بتحبي تحجزي معها؟"
   → If only one staff does this service, auto-assign
   → Store the staff UUID

4. **Preferred Day & Date** — Ask

5. **Check Availability** — MANDATORY
   → Call check_availability tool with staffId + serviceId + date
   → If mode=time: Show available (unbooked) slots, let customer pick
   → If mode=queue: Tell customer their queue number
   → If blocked=true: Tell customer staff is off, suggest another date/staff

6. **Preferred Time** — Customer picks from available slots

7. **Full Name** — Ask

8. **Phone Number** — Ask, then "نفس رقم الواتس؟"

### Summary & Confirmation:
After ALL fields, summarize and ask for confirmation (intent = "conversation")

### Customer Confirms:
→ Call create_booking tool with ALL collected UUIDs
→ If success: intent = "create booking"
→ If 409 error: tell customer, ask to adjust (intent stays "conversation")

### Special Rules:
- Tuesday Rule: No bookings on Tuesdays
- Date/Day conflict: Ask customer to confirm
- Location: Always "Salon" (home services disabled)

---

## 8. Product Order Flow

1. Product Selection → show products (type = "product")
2. Quantity
3. Full Name
4. Phone Number
5. Delivery Address
6. Payment = "cash"

After confirmation: call create_order tool → intent = "create order"

---

## 9. Conversation Rules

### DO:
- Accept all dialects gracefully
- Never collect personal info until service/product confirmed
- Always ask which service — never assume

### DO NOT:
- Never offer times outside 9AM–9PM
- Never evaluate customer images — specialist handles this
- Never repeat the same phrase
- If customer sends sticker/smiley to end conversation, stay silent

---

## 10. Image Handling Rule

If customer sends any image (especially hair photos):
- ❌ Do NOT quote a price
- ❌ Do NOT evaluate
- ✅ "الأخصائية رح تقيّم وتعطيكِ السعر"
- Intent: conversation

---

CRITICAL NOTES:
- NEVER ASSUME PRODUCTS OR SERVICES YOU DON'T HAVE
- NEVER call a tool more than once for the same data
- For SERVICES (type=service) → BOOKING flow
- For PRODUCTS (type=product) → ORDER flow
- NEVER confuse the two flows
- bookingDetails must use UUIDs for serviceId, branchId, staffId
```

- [ ] System prompt updated in n8n

---

### Step 2.2: Update bookingDetails in the Intent Router

**The `create booking` branch** now expects UUIDs in `bookingDetails`:

Old format:
```json
{ "service": "بروتين", "branch": "خلدا" }
```

New format:
```json
{ "serviceId": "uuid", "branchId": "uuid", "staffId": "uuid", "serviceSummary": "بروتين" }
```

Make sure the **Send text via Evolution API** node still works — it reads `$json.response` which hasn't changed format.

Make sure the **Update Client** node still reads from the correct JSON path for `name` and `phone`.

- [ ] Intent router outputs verified

---

## 🟢 PHASE 3 — Nice-to-Have Enhancements

### Step 3.1: Add `customer_service` Intent to Switch Node

**Where:** Switch2 node → Add new output

| Output Name | Condition |
|-------------|-----------|
| `customer_service` | `{{ $json.intent }}` equals `customer_service` |

**Connect to:** An HTTP Request node that:
- Method: `POST`
- URL: `https://noondash.marka.giize.com/api/notifications`
- Body:
```json
{
  "type": "customer_service",
  "title": "طلب خدمة عملاء",
  "body": "العميلة {{ $('Edit Fields').first().json.SenderName }} تريد التحدث مع الدعم",
  "metadata": {
    "phone": "{{ $('Edit Fields').first().json.SenderJid }}"
  }
}
```

> [!NOTE]
> This requires that `POST /api/notifications` exists and accepts unauthenticated requests. If it requires auth, you'll need to add the service role key as a header.

- [ ] Customer service intent added (optional)

---

### Step 3.2: Update Booking insert with `source` field

**If you keep the Supabase insert as a backup:** Add `channelType: "whatsapp"` and `source: "bot"` fields.

But since the `/api/booking` API handles `channelType: "website"` by default, you may want to update the booking API to accept a `source` parameter:

```diff
// In gardenia-website/src/app/api/booking/route.ts
- channelType: "website",
+ channelType: body.channelType || "website",
```

This way the bot can send `channelType: "whatsapp"` in its booking request.

- [ ] Booking API updated to accept channelType (optional)

---

## 🧪 Testing Checklist

### Test 1: Greeting
- [ ] Send "مرحبا" → Bot responds with greeting menu

### Test 2: Branch Selection
- [ ] Say "بدي أحجز" → Bot asks which branch
- [ ] Pick a branch → Bot shows services at that branch

### Test 3: Staff Assignment
- [ ] Pick a service → Bot shows available staff (or auto-assigns)

### Test 4: Availability Check
- [ ] Pick a date → Bot calls check_availability and shows available slots
- [ ] If staff is on leave → Bot says "العاملة في إجازة" and suggests another date

### Test 5: Booking Confirmation
- [ ] Complete all fields → Bot summarizes and asks for confirmation
- [ ] Confirm → Bot calls create_booking API
- [ ] Check dashboard → Booking appears with correct branch, staff, time

### Test 6: Double Booking Prevention
- [ ] Try to book the same staff at the same time → Bot gets 409 error → Tells customer

### Test 7: Product Order
- [ ] Say "بدي أشتري" → Bot shows products
- [ ] Complete order → Bot calls create_order API
- [ ] Check dashboard → Order appears in Orders section

### Test 8: Testimonials
- [ ] Say "وريني شغلكم" → Bot sends before/after images

### Test 9: Product Images
- [ ] Say "وريني صور المنتجات" → Bot sends product images

### Test 10: Edge Cases
- [ ] Send a sticker → Bot stays silent
- [ ] Send a hair photo → Bot says specialist will evaluate
- [ ] Ask for Tuesday booking → Bot says Tuesday not available

---

## 📋 Quick Reference: Node Changes Summary

| n8n Node | Action | Status |
|----------|--------|--------|
| `Execute a SQL query` | Replace SQL with enhanced version | Phase 1 |
| `Edit Fields` | Add 5 new output fields | Phase 1 |
| AI Agent → Tools | Add 5 new HTTP tools | Phase 1 |
| AI Agent → System Message | Replace with v4 prompt | Phase 2 |
| `Switch2` (Intent Router) | Add `customer_service` output | Phase 3 |
| Supabase "Create a row" (Booking) | **DISCONNECT** (replaced by API tool) | Phase 1 |
| Old order WhatsApp notification | **DISCONNECT** (replaced by API tool) | Phase 1 |

---

## ⚠️ Rollback Plan

If something goes wrong after these changes:
1. **Re-connect** the old Supabase "Create a row" booking node
2. **Remove** the new AI tools from the agent
3. **Revert** the system prompt to the old v3
4. The SQL query change is safe — extra data doesn't break anything

---

> [!TIP]
> **Recommended approach:** Make Phase 1 changes, test thoroughly, then move to Phase 2. Don't do everything at once.
