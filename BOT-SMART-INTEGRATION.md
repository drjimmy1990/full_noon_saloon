# 🤖 Gardenia Bot — Smart Integration Blueprint

> Full analysis of what exists, what's missing, and what to build to make the WhatsApp bot fully synced with the dashboard and website.

---

## 📋 Table of Contents

1. [Current State: What the Bot Can Do](#1-current-state)
2. [Current State: What the Bot CANNOT Do](#2-gaps)
3. [Enhanced Startup SQL Query](#3-startup-query)
4. [Existing APIs the Bot Can Call](#4-existing-apis)
5. [New Tools to Implement for the AI Agent](#5-new-tools)
6. [New API Endpoints Needed](#6-new-endpoints)
7. [System Prompt Updates Needed](#7-system-prompt-updates)
8. [Implementation Priority](#8-priority)

---

## 1. Current State: What the Bot Can Do {#1-current-state}

### Startup SQL Query (runs once per message)
The n8n workflow currently runs **one Postgres query** after the webhook to load context:

```sql
-- CURRENT QUERY (Execute a SQL query node)
SELECT 
  c.*,
  (
    SELECT json_agg(
      json_build_object(
        'id', p.id,
        'name', p.name,
        'price', p.price,
        'images', p.images
      )
    )
    FROM public."Product" p
    WHERE p."isAvailable" = true
  ) as active_products,
  (
    SELECT json_object_agg(key, value)
    FROM public."SystemSetting"
  ) as system_settings
FROM public."Channel" c
WHERE c.name = '{{ instance_name }}'
LIMIT 1;
```

### What this gives the bot:
| Data | Source | Used For |
|------|--------|----------|
| Channel info (id, name, credentials) | `Channel` table | Identifying the WhatsApp instance |
| All active products (id, name, price, images) | `Product` table | Listing services/products to customers |
| System settings (address, working hours, delivery fee) | `SystemSetting` table | Replying with salon address, hours, etc. |

### AI Agent Tools (2 tools):
| Tool | Type | What It Does |
|------|------|--------------|
| `get all products and services` | HTTP → Supabase REST | Returns `{id, name, price, notes}` for all available products |
| `get product details by id` | HTTP → Supabase REST | Returns `{name, description, price, images, notes}` for a single product |

### What the bot does with intents:
| Intent | Action in n8n |
|--------|---------------|
| `conversation` | Sends text response via Evolution API |
| `create booking` | Inserts into `Booking` table (serviceSummary, bookingDate, client_id, channelType=whatsapp) |
| `create order` | Sends notification to admin WhatsApp with order details |
| `product images` | Fetches product images and sends them to customer |
| `testimonials` | Fetches image set by name and sends before/after photos |

---

## 2. Critical Gaps: What the Bot CANNOT Do {#2-gaps}

### ❌ Gap 1: No Availability Checking
The bot books **blindly** — it doesn't check if the time slot is free. The customer could book at 10:00 AM when there's already a booking there.

**Impact**: Double bookings, customer frustration, manual admin cleanup.

### ❌ Gap 2: No Branch Awareness
The bot doesn't know which branches exist, their names, or which services belong to which branch. The current startup query doesn't fetch branches.

**Impact**: Bot can't ask "which branch?" intelligently. It stores the branch name as free text from the customer, which might not match.

### ❌ Gap 3: No Staff Assignment
The bot doesn't know who the staff members are or which staff does which service. Bookings are created without a `staff_id`.

**Impact**: Dashboard shows bookings with "unassigned staff". No availability checking is possible without knowing the staff.

### ❌ Gap 4: No Blocked Date Awareness
The bot doesn't check `StaffBlockedDate` — it could book a staff member who is on emergency leave.

**Impact**: Booking confirmed to customer → staff is actually off → manual rescheduling.

### ❌ Gap 5: No Bot-Specific Offers
The bot doesn't know about bot-channel offers. It doesn't have access to the `channel` filter on offers.

**Impact**: Bot can't mention special bot-only promotions.

### ❌ Gap 6: No Queue/Slot Mode Support
When the service is `durationMode = 'queue'`, the bot still asks for a time. It doesn't know about max slots or queue numbers.

**Impact**: Incorrect booking flow for queue-based services.

### ❌ Gap 7: No "Customer Service Request" Notification
When a customer says "I want to talk to a human" or "customer service", the bot should create a notification in the dashboard. Currently this is just a text response.

**Impact**: Human agents miss customer service requests.

### ❌ Gap 8: No Order Creation in Database
Orders from the bot are only sent as WhatsApp messages to the admin. They are NOT inserted into the `Order` table.

**Impact**: Orders don't appear in the dashboard, no tracking, no analytics.

### ❌ Gap 9: No Working Hours Validation
The bot doesn't validate booking times against the salon's actual working hours per branch/staff. It uses hardcoded hours in the system prompt.

**Impact**: Bookings outside actual working hours.

### ❌ Gap 10: Missing Fields in Booking Insert
The current `Create a row` node only inserts: `serviceSummary`, `channelType`, `bookingDate`, `client_id`. It's missing: `branchId`, `staff_id`, `location`, `paymentMethod`, `source`, `notes`, `endTime`, `status`.

**Impact**: Incomplete booking records in dashboard.

---

## 3. Enhanced Startup SQL Query {#3-startup-query}

Replace the current `Execute a SQL query` node with this enhanced version:

```sql
SELECT 
  c.*,

  -- ✅ Active Products with type, availability, duration, branch assignment
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

  -- ✅ System Settings (address, working hours, delivery fee, bot reminder hours, etc.)
  (
    SELECT json_object_agg(key, value)
    FROM public."SystemSetting"
  ) as system_settings,

  -- ✅ Active Branches (id, name, nameAr, phone, whatsapp, address)
  (
    SELECT json_agg(
      json_build_object(
        'id', b.id,
        'name', b.name,
        'nameAr', b."nameAr",
        'address', b.address,
        'phone', b.phone,
        'whatsapp', b.whatsapp,
        'isActive', b."isActive"
      )
    )
    FROM public."Branch" b
    WHERE b."isActive" = true
  ) as active_branches,

  -- ✅ Active Staff (id, name, role, branchId)
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

  -- ✅ Staff ↔ Service assignments
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

  -- ✅ Bot-specific offers (active, channel = 'bot' or 'both')
  (
    SELECT json_agg(
      json_build_object(
        'id', o.id,
        'product_id', o.product_id,
        'discountType', o."discountType",
        'discountValue', o."discountValue",
        'startDate', o."startDate",
        'endDate', o."endDate",
        'channel', o.channel,
        'productName', p.name,
        'originalPrice', p.price
      )
    )
    FROM public."Offer" o
    INNER JOIN public."Product" p ON p.id = o.product_id
    WHERE o."isActive" = true
      AND o.channel IN ('bot', 'both')
      AND (o."startDate" IS NULL OR o."startDate" <= CURRENT_DATE)
      AND (o."endDate" IS NULL OR o."endDate" >= CURRENT_DATE)
  ) as bot_offers,

  -- ✅ Image sets for testimonials
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

  -- ✅ Categories (for smarter service grouping)
  (
    SELECT json_agg(
      json_build_object(
        'id', cat.id,
        'label', cat.label,
        'image', cat.image
      )
    )
    FROM public."Category" cat
  ) as categories

FROM public."Channel" c
WHERE c.name = '{{ $json.Instance }}'
LIMIT 1;
```

> [!IMPORTANT]
> **This single query replaces the need for multiple API calls.** The bot now has branches, staff, staff-service assignments, bot offers, image sets, and categories — all in one shot.

---

## 4. Existing APIs the Bot Can Already Call {#4-existing-apis}

These API endpoints exist on the **gardenia-website** (public, no auth needed) and can be used as AI tools in n8n:

| API Endpoint | What It Returns | Bot Use Case |
|--------------|----------------|--------------|
| `GET /api/branches?active=true` | List of active branches | Show branch options during booking |
| `GET /api/services?branchId=xxx` | Services filtered by branch | List services after branch selection |
| `GET /api/services-with-staff?branchId=xxx` | Services grouped by category with assigned staff | Full catalog with staff assignments |
| `GET /api/availability?staffId=xxx&serviceId=xxx&date=YYYY-MM-DD` | Available time slots or queue number | **Check free slots before confirming booking** |
| `GET /api/settings` | All system settings (address, hours, delivery fee) | Get salon info |
| `POST /api/booking` | Creates a booking with overlap checking | **Create booking with proper validation** |
| `POST /api/order` | Creates an order | Create product order in database |

> [!WARNING]
> **The bot currently does NOT use `/api/availability` or `/api/booking`.** It inserts directly into Supabase via the Supabase node, bypassing all validation (overlap checking, blocked dates, queue mode).

---

## 5. New AI Agent Tools to Implement {#5-new-tools}

These are the tools the AI agent needs to be truly smart. Each tool = one n8n `httpRequestTool` node calling an API.

### Tool 1: `get all products and services` ✅ EXISTS (needs update)
**Update needed**: Add `type`, `durationMode`, `branchId`, `availableAtHome`, `availableAtSalon` to the response so the bot can distinguish services from products and knows branch association.

### Tool 2: `get product details by id` ✅ EXISTS (OK as-is)

### Tool 3: `check availability` 🆕 NEW
```
GET https://noonweb.marka.giize.com/api/availability
  ?staffId={staff_uuid}
  &serviceId={service_uuid}
  &date={YYYY-MM-DD}

Returns:
  - mode: "time" → { slots: [{time: "09:00", booked: false}, ...] }
  - mode: "queue" → { nextQueueNumber: 3, blocked: false }
  - blocked: true → Staff is on emergency leave

Tool Description: "Use this tool to check available time slots for a service 
with a specific staff member on a given date. Call this AFTER the customer 
selects a branch, service, staff (if applicable), and date. Returns available 
time slots or the next queue number."
```

### Tool 4: `get branches` 🆕 NEW
```
GET https://noonweb.marka.giize.com/api/branches?active=true

Returns: [{id, name, nameAr, address, phone, whatsapp}]

Tool Description: "Use this tool to get the list of active salon branches. 
Call this when the customer is starting a booking and you need to ask which 
branch they want."
```

### Tool 5: `get staff for service` 🆕 NEW
```
GET https://noonweb.marka.giize.com/api/services-with-staff?branchId={branch_uuid}

Returns: [{category, services: [{id, name, price, staff: [{id, name}]}]}]

Tool Description: "Use this tool to get the services available at a specific 
branch along with which staff members can perform each service. Call this 
after the customer selects a branch."
```

### Tool 6: `create smart booking` 🆕 NEW
Instead of inserting directly into Supabase (current approach), call the website's booking API which has all validations:

```
POST https://noonweb.marka.giize.com/api/booking
Body: {
  serviceId: "uuid",
  branchId: "uuid",
  staffId: "uuid",
  date: "YYYY-MM-DD",
  time: "HH:mm",
  name: "customer name",
  phone: "phone number",
  durationMode: "time" | "queue",
  durationMinutes: 60,
  paymentMethod: "cash",
  notes: "Source: WhatsApp Bot"
}

Returns: { success: true, bookingId: "uuid", queueNumber: 3 }
OR: { error: "العاملة في إجازة في هذا اليوم" } (409)
OR: { error: "هذا الوقت محجوز بالفعل" } (409)

Tool Description: "Use this tool to create a booking ONLY after ALL booking 
fields are collected AND the customer confirmed. This validates availability 
and blocked dates automatically."
```

### Tool 7: `send notification` 🆕 NEW
For when customer requests human support:

```
POST https://noondash.marka.giize.com/api/notifications
Body: {
  type: "customer_service",
  title: "طلب خدمة عملاء",
  body: "العميلة [name] تريد التحدث مع الدعم",
  client_id: "uuid"
}

Tool Description: "Use this tool when the customer explicitly asks to speak 
to a human or requests customer service. It creates a notification in the 
dashboard for the team."
```

---

## 6. New API Endpoints Needed {#6-new-endpoints}

### Endpoint 1: `POST /api/booking` — Extend for bot source
The existing `/api/booking` on gardenia-website already works. Just need to add:
- Accept `source: "bot"` field
- Accept `channelType: "whatsapp"` field

### Endpoint 2: `POST /api/notifications` — Already exists ✅
The notifications API already exists and accepts POST without auth (designed for n8n calls).

### Endpoint 3: `POST /api/order` — Extend for bot
Need to check if `/api/order` exists and if it creates proper order records.

### Endpoint 4: `GET /api/bot/context` 🆕 NEW (OPTIONAL)
A single endpoint that returns everything the bot needs in one call (alternative to the enhanced SQL query):

```
GET https://noonweb.marka.giize.com/api/bot/context

Returns: {
  branches: [...],
  staff: [...],
  staffServices: [...],
  products: [...],
  offers: [...],
  settings: {...},
  categories: [...]
}
```

> [!TIP]
> This could replace both the startup SQL query AND Tool 1, simplifying the n8n workflow.

---

## 7. System Prompt Updates Needed {#7-system-prompt-updates}

### Changes to the booking flow:

```diff
### Step-by-Step Sequence (UPDATED)

 1. **Branch (الفرع)** — ALWAYS ASK FIRST
+   → Use Tool "get branches" to list options if not in context
+   → Store the branch UUID, not just the name

 2. **Service Type** — Always ask
+   → Use Tool "get staff for service" with the branch UUID
+   → Show services available at that branch

+3. **Staff Member (العاملة)** — Ask if service has multiple staff
+   → "مين العاملة اللي بتحبي تحجزي معها؟"
+   → If only one staff does this service, auto-assign

 4. **Preferred Day & Date**

-5. **Preferred Time**
+5. **Preferred Time** — VALIDATE with availability tool
+   → Call "check availability" with staffId + serviceId + date
+   → If mode=time: Show available slots, let customer pick
+   → If mode=queue: Tell customer their queue number
+   → If blocked=true: Tell customer staff is off, suggest another date

 6. **Full Name**
 7. **Phone Number**
 8. **Area/Location** (home only)

### Step B: Customer Confirms
-   → Insert directly into Supabase (CURRENT — NO VALIDATION)
+   → Call "create smart booking" API (validates overlaps + blocked dates)
+   → If 409 error: Inform customer and ask to pick another time
```

### New intents needed:

```diff
 | Intent | When to Use |
 |---|---|
 | `conversation` | DEFAULT |
 | `create booking` | After all fields + confirmed |
 | `create order` | After all order fields + confirmed |
 | `product images` | Customer asks for product photos |
 | `testimonials` | Customer asks for before/after |
+| `customer_service` | Customer asks to talk to a human |
```

### New context variables in system prompt:

```diff
 ### Context Variables
 - **Current Date/Time**: {{ $now }}
 - **Customer Name**: {{ SenderName }}
 - **Salon Address**: {{ system_settings.salon_address }}
+- **Active Branches**: {{ active_branches }}
+- **Active Staff**: {{ active_staff }}
+- **Staff-Service Assignments**: {{ staff_services }}
+- **Bot Offers**: {{ bot_offers }}
+- **Categories**: {{ categories }}
```

---

## 8. Implementation Priority {#8-priority}

### 🔴 Phase 1 — Critical (Bot is broken without these)

| # | Task | Effort | Impact |
|---|------|--------|--------|
| 1 | **Update startup SQL query** to include branches, staff, staff_services, bot_offers | 15 min | Bot knows the full context |
| 2 | **Add Tool 3: check availability** (HTTP tool → `/api/availability`) | 30 min | Prevents double bookings |
| 3 | **Add Tool 6: create smart booking** (replace Supabase insert with `/api/booking` POST) | 45 min | Validated bookings with staff, branch, overlap check |
| 4 | **Update Booking insert node** to include branchId, staff_id, location, paymentMethod, source, endTime | 30 min | Complete booking records |

### 🟡 Phase 2 — High Value

| # | Task | Effort | Impact |
|---|------|--------|--------|
| 5 | **Add Tool 4: get branches** | 15 min | Smart branch selection |
| 6 | **Add Tool 5: get staff for service** | 15 min | Staff assignment in booking |
| 7 | **Update system prompt** with new booking flow (branch → service → staff → date → check availability → time) | 1 hr | Smarter conversation flow |
| 8 | **Add Tool 7: send notification** for customer service requests | 15 min | Human support requests appear in dashboard |

### 🟢 Phase 3 — Nice to Have

| # | Task | Effort | Impact |
|---|------|--------|--------|
| 9 | **Add bot offers to prompt** so bot can mention active promotions | 30 min | Upselling |
| 10 | **Create `/api/bot/context` endpoint** to replace SQL query | 1 hr | Cleaner architecture |
| 11 | **Order creation via API** instead of WhatsApp notification | 45 min | Orders tracked in dashboard |
| 12 | **Bot conversation memory** — track which tools were already called via session variable | 1 hr | Prevents tool re-calling |

---

## 📊 Summary: Current vs Target

```
CURRENT BOT                          TARGET BOT
─────────────────                    ─────────────────
❌ Books blindly                     ✅ Checks availability first
❌ No branch awareness               ✅ Asks which branch, filters services
❌ No staff assignment               ✅ Assigns staff, checks their schedule
❌ No blocked date checking          ✅ Warns if staff is on leave
❌ Inserts directly into DB          ✅ Uses API with validation
❌ No bot offers                     ✅ Shows bot-specific promotions
❌ No queue mode support             ✅ Handles queue number assignment
❌ Orders via WhatsApp msg           ✅ Orders tracked in dashboard
❌ CS requests lost                  ✅ Dashboard notifications created
❌ Hardcoded working hours           ✅ Dynamic from staff schedule
```

---

## 🔧 Quick Reference: n8n Workflow Changes

### Step 1: Replace SQL Query
Copy the enhanced SQL from [Section 3](#3-startup-query) into the `Execute a SQL query` Postgres node.

### Step 2: Update `Edit Fields` Node
Add new output fields:
```
active_branches → {{ $json.active_branches }}
active_staff → {{ $json.active_staff }}
staff_services → {{ $json.staff_services }}
bot_offers → {{ $json.bot_offers }}
categories → {{ $json.categories }}
```

### Step 3: Add New AI Tools
Create 3-5 new `httpRequestTool` nodes connected to the AI Agent:
- Tool 3: Check Availability → `GET /api/availability`
- Tool 4: Get Branches → `GET /api/branches?active=true`
- Tool 5: Get Staff for Service → `GET /api/services-with-staff`
- Tool 6: Create Booking → `POST /api/booking`
- Tool 7: Send Notification → `POST /api/notifications`

### Step 4: Replace Booking Insert
Replace the `Create a row` Supabase node with an HTTP Request node that calls `POST /api/booking` with full validation.

### Step 5: Update System Prompt
Update the AI Agent's system prompt with the new booking flow and tool descriptions from [Section 7](#7-system-prompt-updates).
