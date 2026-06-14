# 🤖 Noon Salon Bot — Complete Setup Guide (One File)

> **This single file replaces:** `n8n-production-guide.md`, `BOT-SMART-INTEGRATION.md`, `bot-booking-guide.md`, `n8n-system-prompt.md`, `n8n-workflow-guide.md`
>
> Read top to bottom. Do each section in order.

---

## 📊 CURRENT STATE AUDIT (What Your Workflow Has Right Now)

Based on analysis of `n8n-workflow copy.json`:

### ✅ What's WORKING

| Component | Status | Details |
|-----------|--------|---------|
| Webhook | ✅ Active | Receives Evolution API messages |
| If1 (filter) | ✅ Active | Filters out `fromMe` and `agent` messages |
| Code in JavaScript6 | ✅ Active | Extracts SenderJid, SenderName, Timestamp, MsgType, Msg, phonenumber |
| Edit Fields | ✅ Active | Maps 20 fields including `active_branches`, `active_staff`, `staff_services`, `bot_offers`, `categories` |
| Execute a SQL query | ✅ Active | **Enhanced SQL** — loads products, settings, branches, staff, staff_services, bot_offers, categories, image_sets |
| Client upsert (find contact → If → Supabase) | ✅ Active | Creates/finds client by platform_user_id |
| AI Agent1 | ✅ Active | Google Gemini via OpenRouter, Postgres Chat Memory |
| System Prompt | ✅ v4 Loaded | Has full booking flow with UUIDs, 7 tool descriptions, 6 intents |
| Code in JavaScript2 (JSON Parser) | ✅ Active | Parses AI response, handles markdown fences & unescaped newlines |
| Switch2 (Intent Router) | ✅ Active | 4 outputs: conversation, booking, product images, testimonials |
| Typing delay nodes (Code, Code1, Code4) | ✅ Active | Simulates typing delay |
| Evolution API send (send txt, send txt3, send txt8) | ✅ Active | Sends WhatsApp messages |
| Product Images flow | ✅ Active | Code4 → send txt3 → Supabase30 → image loop |
| Message logging (Supabase27, Supabase30, etc.) | ✅ Active | Logs messages to Message table |

### ✅ AI Agent Tools (3 of 4 needed tools exist)

| Tool Name | Type | URL | Status |
|-----------|------|-----|--------|
| `check_availability` | GET | `https://salonnoon.net/api/availability` | ✅ Connected to AI Agent1 |
| `get_staff_for_service` | GET | `https://salonnoon.net/api/services-with-staff` | ✅ Connected to AI Agent1 |
| `create_booking` | POST | `https://salonnoon.net/api/booking` | ✅ Connected to AI Agent1 |

> **Note:** `get_branches` tool is NOT needed — branches are already injected into the system message from the SQL query. The AI can read both branches with UUIDs directly from context.
>
> `get_all_products_and_services` and `get_product_details_by_id` (Tool 1 & 2 in system prompt) also don't need tool nodes — products come from the SQL query context. The AI uses context data directly.

### 🚨 CRITICAL DATA ISSUES (Fix in Dashboard FIRST)

| Issue | Current Value | Fix |
|-------|---------------|-----|
| **Salon Address is EMPTY** | `""` | Go to Dashboard → Settings → add `salon_address` value |
| **Image Sets is EMPTY** | `""` | Go to Dashboard → Channel settings → add `imageSets` JSON array to your WhatsApp channel. Without this, **testimonials will NOT work** even if you re-enable the nodes. |

### ❌ What's MISSING (Must Be Added)

| Component | What's Missing | Impact |
|-----------|---------------|--------|
| **`create_order` tool** | No httpRequestTool node exists | Bot can't create orders via API — orders NOT saved to database |
| **`create order` intent in Switch2** | Switch2 only has 4 outputs (no order route) | When AI returns `intent: "create order"`, it hits NOTHING |
| **`customer_service` intent in Switch2** | Not in Switch2 rules | When AI returns `intent: "customer_service"`, it hits NOTHING |
| **Testimonials flow** | `Code3` is DISABLED, `send txt1` is DISABLED, `Supabase28` is DISABLED | Testimonials intent goes to a dead end |

### ⚠️ DISABLED Nodes (13 nodes disabled by you)

| Node | Type | Should Re-enable? |
|------|------|-------------------|
| `Aggregate4` | Aggregate | ❓ Only if you need queue aggregation |
| `Sort2` | Sort | ❓ Only if you need queue sorting |
| `Supabase5` | Supabase | ❓ Only if you need queue DB lookup |
| `Supabase23` | Supabase | ❌ Safe to keep disabled (old booking insert) |
| `If23` | If | ❓ Only if you need queue branching |
| `Code2` | Code | ❓ Only if you need queue typing delay |
| `Code3` | Code | ✅ **RE-ENABLE** — Testimonials typing delay |
| `send txt1` | HTTP Request | ✅ **RE-ENABLE** — Testimonials send text |
| `Supabase28` | Supabase | ✅ **RE-ENABLE** — Testimonials message logging |
| `HTTP Request12` | HTTP Request | ❌ Safe to keep disabled (old testimonials image sender) |
| `Code in JavaScript1` | Code | ❌ Safe to keep disabled (old testimonials formatter) |
| `Split Out` | Split Out | ❌ Safe to keep disabled (old testimonials loop) |
| `Supabase29` | Supabase | ❌ Safe to keep disabled (old testimonials logging) |

---

## 🔴 PHASE 1 — Fix Critical Gaps (Bot Broken Without These)

### Step 1.1: Fix Empty Data in Dashboard

Before touching n8n, fix these database issues:

**1. Salon Address:**
- Go to Dashboard → Settings
- Add/update the `salon_address` setting (e.g., "عمان - الوزيرية" or your actual address)
- Currently the bot shows EMPTY when customer asks for the address

**2. Image Sets for Testimonials:**
- Go to Dashboard → Channel settings → Your WhatsApp channel
- Add the `imageSets` JSON field with your before/after image collections
- Format: `[{"name": "بروتين", "images": ["url1", "url2"]}, ...]`
- Without this, testimonials flow will return nothing even when re-enabled

- [ ] Salon address added in dashboard
- [ ] Image sets configured for WhatsApp channel

---

### Step 1.2: Add `customer_service` Intent to Switch2

**Where:** Switch2 node → Settings → Add Rule (6th output)

| Setting | Value |
|---------|-------|
| **Output Name** | `customer_service` |
| **Condition** | `{{ $json.intent }}` equals `customer_service` |

**Option A — Simple (send text only):**
Connect to the same `Code1` node as `conversation` (output index 0).
This just sends the response text to the customer.

**Option B — With Dashboard Notification (recommended):**
Create an HTTP Request node:

| Setting | Value |
|---------|-------|
| **Node Name** | `HTTP Request14` |
| **Method** | `POST` |
| **URL** | `https://noondash.marka.giize.com/api/notifications` |
| **Body Content Type** | `JSON` |
| **Body** | See below |

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

Then connect Switch2 customer_service output → `Code1` (typing) → `send txt` (send response) AND also → `HTTP Request14` (dashboard notification).

- [ ] `customer_service` intent added to Switch2

---

### Step 1.3: Re-Enable Testimonials Flow (requires Image Sets from Step 1.1)

The testimonials intent is currently broken because 3 nodes are disabled.

**Re-enable these 3 nodes** (right-click each → Enable):

1. ✅ `Code3` — Typing delay calculator for testimonials
2. ✅ `send txt1` — Sends the testimonials text response via Evolution API
3. ✅ `Supabase28` — Logs the testimonials message to the Message table

**Verify connections:**
```
Switch2 (output 3: testimonials) → Code3 → send txt1 → Supabase28 → image sending flow
```

- [ ] Testimonials flow re-enabled

---

## 🟡 PHASE 2 — Verify System Prompt (Already Done)

The AI Agent1 system prompt is already v4 (Production). Here's the complete prompt that should be in the AI Agent node's **System Message** field. Verify it matches:

<details>
<summary>📋 Click to expand full System Prompt (v4)</summary>

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
- ❌ **NEVER add fields outside this schema** (no stray "branchId", "staffId", etc. at root level). Only the fields listed above are allowed.

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
1. NEVER call a tool if you already have the answer from context
2. Maximum tool calls per turn: 2
3. If a tool errors, respond gracefully — do NOT retry

### ⚠️ CRITICAL: Tool Call Behavior
1. **NEVER say "خليني أشوف" or "دقيقة" or "رح أتحقق" and then return without the data.** You MUST call the tool AND include the results in your response in the SAME turn.
2. When a customer selects a branch → call `get_staff_for_service` immediately and show the services in the SAME response. Do NOT send a separate "let me check" message.
3. When you need to check availability → call `check_availability` and show the slots in the SAME response.
4. Every response to the customer MUST contain complete, actionable information. Never promise to return with data — return it NOW.
5. The customer will NEVER receive a follow-up message. Your response is the ONLY message they get this turn.

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

</details>

**Verification:** The system prompt is already loaded in your workflow. If it doesn't match the above, replace it.

- [ ] System prompt verified / updated

---

## 🟢 PHASE 3 — Verify Data Flow (Already Working)

These are already working in your workflow. Just verify:

### 3.1: SQL Query (Enhanced) ✅ Already Done
The `Execute a SQL query` node already has the enhanced SQL that loads:
- `active_products` (with type, durationMode, branchId, etc.)
- `system_settings`
- `active_branches`
- `active_staff`
- `staff_services`
- `bot_offers`
- `image_sets` (from Channel.imageSets)
- `categories`

### 3.2: Edit Fields Node ✅ Already Done
The `Edit Fields` node already maps all 20 fields including:
- `active_branches` → `{{ JSON.stringify($json.active_branches) }}`
- `active_staff` → `{{ JSON.stringify($json.active_staff) }}`
- `staff_services` → `{{ JSON.stringify($json.staff_services) }}`
- `bot_offers` → `{{ JSON.stringify($json.bot_offers) }}`
- `categories` → `{{ JSON.stringify($json.categories) }}`

### 3.3: AI Agent Configuration ✅ Already Done
- Model: OpenRouter Chat Model (Gemini)
- Memory: Postgres Chat Memory
- System prompt: v4 Production
- Input: `{{ $('Edit Fields').item.json.Msg }}`

---

## 📐 COMPLETE WORKFLOW FLOW DIAGRAM

```
Webhook
  ↓
If1 (filter fromMe / agent messages)
  ↓ (false = real customer message)
Code in JavaScript6 (extract sender data)
  ↓
Edit Fields (map 20 fields)
  ↓
Execute a SQL query (load everything from DB)
  ↓
Edit Fields5 (remap after SQL — adds active_branches, etc.)
  ↓
find contact (Supabase GET: Client by platform_user_id)
  ↓
If (client exists?)
  ├─ true → use existing client_id
  └─ false → Supabase20 (create new Client)
       ↓
Wait1 (wait for client creation)
  ↓
If (audio message?)
  ├─ true → download audio → Analyze audio (Gemini) → feed text to AI
  └─ false → feed text directly to AI
       ↓
AI Agent1 (Gemini + 4 tools + Postgres Memory)
  ↓
Code in JavaScript2 (parse JSON response)
  ↓
Switch2 (route by intent)
  ├─ "conversation"     → Code1 (typing) → send txt → Supabase27 (log)
  ├─ "create booking"   → Code (typing) → send txt8 → Update Client → Log → Notify Admin
  ├─ "product images"   → Code4 (typing) → send txt3 → Supabase30 → fetch images → send images
  ├─ "testimonials"     → Code3 (typing) → send txt1 → Supabase28 → fetch images → send images
  ├─ "create order"     → [MISSING — ADD TO Code → send txt8 → same as booking]
  └─ "customer_service" → [MISSING — ADD TO Code1 + HTTP notification]
```

---

## 🔧 AI AGENT TOOLS — Complete Configuration

### Currently Connected (3 tools):

#### Tool 1: `check_availability`
```
Type: httpRequestTool
Method: GET
URL: https://salonnoon.net/api/availability
Query Params: staffId, serviceId, date
Description: Use this tool to check available time slots for a service with a specific staff member on a given date. Returns available time slots or the next queue number. If blocked=true, the staff is on leave. Parameters: staffId (UUID), serviceId (UUID), date (YYYY-MM-DD format).
```

#### Tool 2: `get_staff_for_service`
```
Type: httpRequestTool
Method: GET
URL: https://salonnoon.net/api/services-with-staff
Query Params: branchId
Description: Use this tool to get the services available at a specific branch along with which staff members can perform each service. Call this after the customer selects a branch. Parameter: branchId (UUID).
```

#### Tool 3: `create_booking`
```
Type: httpRequestTool
Method: POST
URL: https://salonnoon.net/api/booking
Body: JSON
Description: Use this tool to create a booking ONLY after ALL booking fields are collected AND the customer explicitly confirmed. This validates availability and blocked dates automatically. If it returns an error (409), tell the customer the issue and ask them to pick another time/date. Parameters: serviceId (UUID), branchId (UUID), staffId (UUID), date (YYYY-MM-DD), time (HH:mm or null for queue), name (customer name), phone (customer phone), durationMode ("time" or "queue"), durationMinutes (number), paymentMethod ("cash"), serviceSummary (service name), notes (optional).
```

### That's It — All 3 Tools Are Already Connected ✅

No additional tool nodes needed for services. The `create_order` tool will be added later when you enable the product ordering flow.

### NOT Needed as Tool Nodes (Data Comes from System Message Context):

| System Prompt Tool | Why No Node Needed |
|--------------------|--------------------|
| `get_all_products_and_services` (Tool 1) | Products loaded via SQL → `active_products` in context |
| `get_product_details_by_id` (Tool 2) | Product details available in context data |
| `get_branches` (Tool 4) | Branches already injected into system message — AI sees both branches with UUIDs directly |

---

## 👩‍🔧 HOW STAFF ↔ SERVICES ↔ PRICES WORK

This is the key relationship the bot uses during booking:

### Pricing Architecture
* **The database price** is attached to the service (the `Product` table with `type = 'service'`), not directly to the staff member.
* **Different staff members have different prices** for the same type of service (e.g., "سميرة" charges 175 JOD, while "أريج" charges 255 JOD).
* **The Solution (Option 1):** To handle this in the database, **create a separate service (Product) for each staff member** in the dashboard/DB (e.g., "مكياج سميرة" priced at 175 JOD, and "مكياج أريج عرض" priced at 255 JOD).
* Each staff member is linked to their corresponding service using the `StaffService` junction table.

### Database Structure
```
Product (services)           StaffService (junction)       Staff
┌────────────────────┐       ┌─────────────────┐          ┌──────────────────┐
│ id (UUID)          │←──────│ product_id      │          │ id (UUID)        │
│ name = "مكياج سميرة"│       │ staff_id        │──────────│ name = "سميرة 175"│
│ price = 175        │       └─────────────────┘          │ branchId = UUID  │
│ type = "service"   │                                    │ isActive = true  │
│ durationMode       │                                    └──────────────────┘
│ durationMinutes    │
│ branchId = UUID    │
│ category = UUID    │
└────────────────────┘
```

### What `get_staff_for_service` Returns (Real Example)

When the bot calls `GET /api/services-with-staff?branchId=ec0a1b3d-...` (الوزيريه branch), it gets:

```json
[
  {
    "category": "مكياج",
    "categoryId": "03359459-...",
    "services": [
      {
        "id": "17a81046-...",
        "name": "مكياج سميرة",
        "price": 175,
        "durationMinutes": 60,
        "durationMode": "time",
        "staff": [
          {"id": "5a2f7290-...", "name": "سميرة 175"}
        ]
      },
      {
        "id": "28b92157-...",
        "name": "مكياج أريج عرض",
        "price": 255,
        "durationMinutes": 60,
        "durationMode": "time",
        "staff": [
          {"id": "f4cb769d-...", "name": "أريج عرض 255"}
        ]
      }
    ]
  }
]
```

### What the Bot Shows the Customer

After calling this tool, the bot presents the services by their specific staff names and prices:
```
خدمات فرع الوزيريه ✨

💄 مكياج:
• مكياج سميرة — 175 دينار (60 دقيقة)
• مكياج أريج عرض — 255 دينار (60 دقيقة)

مين الخدمة والعاملة اللي بتحبي تحجزي معها؟
```

### Price Logic
- **Service price** = from `Product.price` (e.g., مكياج سميرة = 175 JOD, مكياج أريج عرض = 255 JOD)
- **Staff name** matches the service and contains the price hint (e.g., "سميرة 175", "أريج عرض 255")

### The Full Booking Data Flow
```
1. Customer picks branch → Bot reads from context (active_branches)
2. Bot calls get_staff_for_service(branchId) → Gets services + staff + prices
3. Customer picks service (e.g., "مكياج سميرة") → Bot stores serviceId + price + durationMode
4. Customer picks staff (e.g., "سميرة 175") → Bot stores staffId
5. Customer picks date → Bot calls check_availability(staffId, serviceId, date)
6. API returns slots (time mode) or queue number (queue mode)
7. Customer picks time → Bot collects name + phone
8. Bot summarizes → Customer confirms
9. Bot calls create_booking(all fields) → Booking created
```

---

## 📋 COMPLETE SWITCH2 CONFIGURATION (Target State)

The Switch2 node should have **5 outputs** (currently has 4, add 1):

| Output # | Output Name | Condition | Connects To |
|----------|-------------|-----------|-------------|
| 0 | `conversation` | `{{ $json.intent }}` equals `conversation` | `Code1` → `send txt` → `Supabase27` |
| 1 | `booking` | `{{ $json.intent }}` equals `create booking` | `Code` → `send txt8` → `Update a row` → `Supabase26` → `Edit Fields1` → `send txt2` |
| 2 | `product images` | `{{ $json.intent }}` equals `product images` | `Code4` → `send txt3` → `Supabase30` → image loop |
| 3 | `testimonials` | `{{ $json.intent }}` equals `testimonials` | `Code3` → `send txt1` → `Supabase28` → image loop |
| 4 | `customer_service` ← **ADD** | `{{ $json.intent }}` equals `customer_service` | `Code1` → `send txt` (+ optional HTTP notification) |

---

## 📐 POST-CONFIRMATION FLOW (Booking)

When the `create booking` intent fires, the flow is:

```
Code (typing delay)
  ↓
send txt8 (send confirmation message to customer via Evolution API)
  ↓
Update a row (update Client name + phone)
  Fields:
    - name: bookingDetails.name
  ↓
Supabase26 (log bot confirmation message in Message table)
  ↓
Edit Fields1 (format admin notification)
  Expression: formats booking summary (service, date, time, name, staff)
  ↓
send txt2 (send formatted text to admin's WhatsApp number)
```

---

## 🔗 API ENDPOINTS REFERENCE

All APIs are on the public storefront (`salonnoon.net` or `noonweb.marka.giize.com`):

| Endpoint | Method | Auth Required | Used By |
|----------|--------|---------------|---------|
| `/api/branches?active=true` | GET | ❌ No | System message context (no tool needed) |
| `/api/services-with-staff?branchId=UUID` | GET | ❌ No | `get_staff_for_service` tool |
| `/api/availability?staffId=UUID&serviceId=UUID&date=YYYY-MM-DD` | GET | ❌ No | `check_availability` tool |
| `/api/booking` | POST | ❌ No | `create_booking` tool |
| `/api/settings` | GET | ❌ No | Startup SQL (not needed as API) |
| `/api/notifications` | POST | ❌ No | Optional `customer_service` notification |

### API Response Formats:

**`/api/availability`:**
```json
// Time-based service:
{ "mode": "time", "slots": [{"time": "09:00", "booked": false}, {"time": "09:30", "booked": true}] }

// Queue-based service:
{ "mode": "queue", "nextQueueNumber": 3 }

// Staff on leave:
{ "blocked": true, "message": "العاملة في إجازة في هذا اليوم" }
```

**`/api/booking` POST success:**
```json
{ "success": true, "bookingId": "uuid", "queueNumber": null }
```

**`/api/booking` POST error (409):**
```json
{ "error": "هذا الوقت محجوز بالفعل. يرجى اختيار وقت آخر." }
```

**`/api/services-with-staff` GET response:**
```json
[
  {
    "category": "مكياج",
    "categoryId": "03359459-...",
    "services": [
      {
        "id": "17a81046-...",
        "name": "مكياج",
        "price": 175,
        "durationMinutes": 60,
        "durationMode": "time",
        "staff": [
          {"id": "5a2f7290-...", "name": "سميرة 175"},
          {"id": "f43cf22d-...", "name": "سمية 175"}
        ]
      }
    ]
  }
]
```

---

## 🧪 TESTING CHECKLIST

After completing Phases 1-2, test each flow:

### Flow 1: Greeting
- [ ] Send "مرحبا" → Bot responds with greeting + 2 options

### Flow 2: Full Booking
- [ ] Say "بدي أحجز" → Bot asks which branch (using context data)
- [ ] Pick branch → Bot calls `get_staff_for_service` and shows services **in the same message** (not "let me check")
- [ ] Pick service → Bot shows available staff
- [ ] Pick date → Bot calls `check_availability` and shows slots **in the same message**
- [ ] Pick time → Bot asks for name
- [ ] Give name + phone → Bot summarizes and asks confirmation
- [ ] Confirm → Bot calls `create_booking` API → intent = "create booking"
- [ ] Check dashboard → Booking appears with correct branch, staff, time

### Flow 3: Double Booking Prevention
- [ ] Try booking same staff/time → Bot gets 409 → Tells customer

### Flow 4: Customer Service
- [ ] Say "بدي أحكي مع حدا" → Bot acknowledges

### Flow 5: Edge Cases
- [ ] Send a sticker → Bot stays silent
- [ ] Send a hair photo → Bot says "الأخصائية رح تقيّم"
- [ ] Ask for Tuesday booking → Bot says Tuesday not available
- [ ] Send audio → Bot transcribes and responds
- [ ] Bot NEVER says "خليني أشوف" without including the data in the same response

---

## ⚡ QUICK ACTION SUMMARY (Services Focus)

Here's exactly what you need to do, in order:

| # | Action | Time | Where |
|---|--------|------|-------|
| 1 | **Fix salon_address in dashboard** | 2 min | Dashboard → Settings |
| 2 | **Add `customer_service` to Switch2** | 5 min | n8n: Switch2 → Add Rule → connect to `Code1` node |
| 3 | **Update system prompt** (add tool call behavior rules) | 5 min | n8n: AI Agent1 → System Message → paste from `n8n-system-prompt.md` |
| 4 | **Re-enable Code3** | 1 min | n8n: Right-click → Enable |
| 5 | **Re-enable send txt1** | 1 min | n8n: Right-click → Enable |
| 6 | **Re-enable Supabase28** | 1 min | n8n: Right-click → Enable |
| 7 | **Test booking flow** | 15 min | WhatsApp: Send test messages |

**Total estimated time: ~30 minutes**

> **Skipped for now (Phase 2 — later):** `create_order` tool, `create order` Switch2 intent, product images flow

---

## ⚠️ ROLLBACK PLAN

If something breaks:
1. **Remove** the new Switch2 `customer_service` output
2. **Re-disable** Code3, send txt1, Supabase28
3. **Revert** system prompt to old version (keep a backup before pasting)
4. The SQL query and Edit Fields changes are safe — extra data doesn't break anything
5. The salon_address data fix is safe — it only adds data

---

## 📂 FILES REFERENCE

| File | Purpose | Status |
|------|---------|--------|
| `n8n-workflow copy.json` | Latest workflow export | Source of truth |
| `n8n-system-prompt.md` | AI system prompt v4 | Already loaded in workflow |
| `n8n-production-guide.md` | Phased upgrade guide | Superseded by this file |
| `BOT-SMART-INTEGRATION.md` | Architecture analysis | Superseded by this file |
| `bot-booking-guide.md` | API reference | Superseded by this file |
| `n8n-workflow-guide.md` | Code node reference | Superseded by this file |
| `COMPLETE-BOT-SETUP.md` | **THIS FILE** — single source of truth | ✅ Current |
