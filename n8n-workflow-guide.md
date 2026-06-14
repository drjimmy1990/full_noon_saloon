# Gardenia n8n Workflow — Code Nodes & Setup Guide (v4 — Production)

## Table of Contents
1. [Webhook Data Extraction](#1-webhook-data-extraction)
2. [SQL Query — Load Channel + Settings](#2-sql-query)
3. [Client Upsert Logic](#3-client-upsert)
4. [Typing Delay Calculator](#4-typing-delay)
5. [AI Agent JSON Parser](#5-ai-json-parser)
6. [Intent Router (Switch)](#6-intent-router)
7. [Booking & Order Post-Confirmation Flow](#7-booking-order-post-confirmation-flow)
8. [AI Agent Tools Configuration](#8-ai-agent-tools-configuration)
9. [Admin Notification Formatter](#9-admin-notification)

---

## 1. Webhook Data Extraction

**Node**: `Edit Fields` (Set node)  
**Purpose**: Normalize the raw Evolution API webhook payload.

```javascript
// n8n Set Node — Field Assignments:

// Instance name
Instance = {{ $json.body.instance }}

// Sender JID
SenderJid = {{ $json.body.data.key.remoteJid }}

// Sender Name (push name from WhatsApp)
SenderName = {{ $json.body.data.pushName || 'Customer' }}

// Message body (text)
body = {{ $json.body.data.message?.conversation 
       || $json.body.data.message?.extendedTextMessage?.text 
       || '' }}

// Timestamp (convert epoch to ISO)
Timestamp = {{ new Date($json.body.data.messageTimestamp * 1000).toISOString() }}

// Message type
MessageType = {{ $json.body.data.message?.imageMessage ? 'image' 
              : $json.body.data.message?.audioMessage ? 'audio'
              : 'text' }}

// API Key (from channel credentials, filled after SQL query)
Key = {{ $('Execute a SQL query').first().json.credentials?.[0]?.value || '' }}

// Image sets (from channel)
image_sets = {{ JSON.stringify($('Execute a SQL query').first().json.imageSets || []) }}

// Active Branches, Staff, Assignments, Offers, Categories (Stringified JSONs to prevent [object Object] errors in prompt)
active_branches = {{ JSON.stringify($('Execute a SQL query').first().json.active_branches || []) }}
active_staff = {{ JSON.stringify($('Execute a SQL query').first().json.active_staff || []) }}
staff_services = {{ JSON.stringify($('Execute a SQL query').first().json.staff_services || []) }}
bot_offers = {{ JSON.stringify($('Execute a SQL query').first().json.bot_offers || []) }}
categories = {{ JSON.stringify($('Execute a SQL query').first().json.categories || []) }}
```

---

## 2. SQL Query

**Node**: `Execute a SQL query` (Postgres node)  
**Purpose**: Loads channel settings, branches, active staff, services assignments, bot offers, categories, and image sets in one query.

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

  -- Image sets for testimonials (stored directly in Channel.imageSets JSONB)
  c."imageSets" as image_sets,

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

---

## 3. Client Upsert Logic

**Node**: `find contact` (Supabase GET) + `If19` + `Supabase20` (Supabase INSERT)

*   **Step 1: Check if client exists**
    ```
    Table: Client
    Filter: platform_user_id = {{ $json.SenderJid }}
    Filter: channel_id = {{ $('Execute a SQL query').first().json.id }}
    ```
*   **Step 2: If no client found, create one (`Supabase20`)**
    ```
    Table: Client
    Fields:
      name = {{ $('Edit Fields').first().json.SenderName }}
      phone = {{ $('Edit Fields').first().json.phonenumber }}
      platform = "whatsapp"
      platform_user_id = {{ $('Edit Fields').first().json.SenderJid }}
      channel_id = {{ $('Execute a SQL query').first().json.id }}
    ```

---

## 4. Typing Delay Calculator

**Node**: `Code` / `Code1` / `Code3` / `Code4` (JavaScript)  
**Purpose**: Simulate typing delays for natural response delivery.

```javascript
const minTimePerChar = 20;
const maxTimePerChar = 70;

for (const item of items) {
  const message = $input.first().json.response || '';
  const characterCount = message.length;
  let totalTypingTime = 0;

  for (let i = 0; i < characterCount; i++) {
    totalTypingTime += Math.random() * (maxTimePerChar - minTimePerChar) + minTimePerChar;
  }

  item.json.typingAnalysis = {
    characterCount: characterCount,
    calculatedTimeMs: Math.round(totalTypingTime),
    originalMessage: message,
  };
}

return items;
```

---

## 5. AI JSON Parser

**Node**: `Code in JavaScript2` (JavaScript)  
**Purpose**: Parses raw JSON responses output by the LLM agent, resolving unescaped newlines.

```javascript
const rawOutputString = $input.first().json.output;
if (!rawOutputString || typeof rawOutputString !== 'string') {
  return [{ json: { error: "Input 'output' is missing or not a string." } }];
}

let jsonString = null;
const markdownRegex = /`{3,}(?:json)?\s*([\s\S]*?)\s*`{3,}/;
const markdownMatch = rawOutputString.match(markdownRegex);
if (markdownMatch && markdownMatch[1]) {
  jsonString = markdownMatch[1].trim();
}

if (!jsonString) {
  const startIndex = rawOutputString.indexOf('{');
  const endIndex = rawOutputString.lastIndexOf('}');
  if (startIndex > -1 && endIndex > -1 && endIndex > startIndex) {
    jsonString = rawOutputString.substring(startIndex, endIndex + 1).trim();
  }
}

try {
  return [{ json: JSON.parse(jsonString) }];
} catch (error) {
  try {
    const fixed = jsonString.replace(/\n/g, '\\n');
    return [{ json: JSON.parse(fixed) }];
  } catch (retryError) {
    return [{ json: { error: "JSON parse failed", errorMessage: retryError.message } }];
  }
}
```

---

## 6. Intent Router

**Node**: `Switch2` (Switch node)  
**Purpose**: Routes based on the parsed `intent` field.

| Switch Output | Condition | Target Connection |
|---|---|---|
| `conversation` | `{{ $json.intent }}` equals `conversation` | `Code1` ➔ `send txt` ➔ `Supabase27` |
| `booking` | `{{ $json.intent }}` equals `create booking` | `Code` ➔ `send txt8` (Bypasses DB insert; goes straight to confirmation + admin notification) |
| `product images` | `{{ $json.intent }}` equals `product images` | `Code4` ➔ `send txt3` ➔ `Supabase30` ➔ Send Images loop |
| `testimonials` | `{{ $json.intent }}` equals `testimonials` | `Code3` ➔ `send txt1` ➔ `Supabase28` ➔ Send Testimonials loop |
| `order` | `{{ $json.intent }}` equals `create order` | `Code` ➔ `send txt8` (Bypasses DB insert; routes to confirmation + admin notification) |
| `customer_service` | `{{ $json.intent }}` equals `customer_service` | `HTTP Request14` (POSTs support request to `/api/notifications`) |

---

## 7. Booking & Order Post-Confirmation Flow

Since bookings and orders are created **directly** by the AI Agent using the `create_booking` and `create_order` API tools, the database records are already present. The post-intent flow after sending the customer confirmation text is:

1.  **`Update a row`** (Supabase): Updates the Client's address and name dynamically.
    *   Address: `={{ $('Code in JavaScript2').item.json.intent === 'create order' ? $('Code in JavaScript2').item.json.orderDetails.customerAddress : $('Code in JavaScript2').item.json.bookingDetails.area }}`
    *   Name: `={{ $('Code in JavaScript2').item.json.intent === 'create order' ? $('Code in JavaScript2').item.json.orderDetails.customerName : $('Code in JavaScript2').item.json.bookingDetails.name }}`
2.  **`Supabase26`** (Supabase): Logs the bot's confirmation message in the `Message` table.
3.  **`Edit Fields1`** (Set Node): Formats the WhatsApp notification message sent to the admin.
4.  **`send txt2`** (HTTP Request): Sends the formatted text to the admin's phone number.

---

## 8. AI Agent Tools Configuration

The AI Agent node (`AI Agent1`) is configured with the following 5 API tools:

### 1. `check_availability` (httpRequestTool)
*   **Method**: `GET`
*   **URL**: `https://salonnoon.net/api/availability`
*   **Query Params**: `staffId`, `serviceId`, `date`

### 2. `get_staff_for_service` (httpRequestTool)
*   **Method**: `GET`
*   **URL**: `https://salonnoon.net/api/services-with-staff`
*   **Query Params**: `branchId`

### 3. `create_booking` (httpRequestTool)
*   **Method**: `POST`
*   **URL**: `https://salonnoon.net/api/booking`
*   **Body Type**: `JSON` (contains all booking parameters mapped from AI arguments)

### 4. `get_branches` (httpRequestTool)
*   **Method**: `GET`
*   **URL**: `https://salonnoon.net/api/branches?active=true`

### 5. `create_order` (httpRequestTool)
*   **Method**: `POST`
*   **URL**: `https://salonnoon.net/api/order`
*   **Body Type**: `JSON` (contains products items list, client name, phone, and address)

---

## 9. Admin Notification Formatter

**Node**: `Edit Fields1` (Set Node)  
**Expression**: Formats either a booking or an order notification depending on the intent.

```javascript
message = {{ $('Code in JavaScript2').item.json.intent === 'create order' ? `طلب جديد 🛒
المنتجات: ${$('Code in JavaScript2').item.json.orderDetails.items.map(i => i.name + ' x' + i.quantity).join(', ')}
المجموع: ${$('Code in JavaScript2').item.json.orderDetails.items.reduce((sum, i) => sum + i.price * i.quantity, 0)} JOD
الاسم: ${$('Code in JavaScript2').item.json.orderDetails.customerName}
الرقم: ${$('Code in JavaScript2').item.json.orderDetails.customerPhone}
العنوان: ${$('Code in JavaScript2').item.json.orderDetails.customerAddress}
الدفع: كاش` : `حجز جديد 🌸
نوع الخدمة: ${$('Code in JavaScript2').item.json.bookingDetails.serviceSummary}
المكان: ${$('Code in JavaScript2').item.json.bookingDetails.location}
التاريخ: ${$('Code in JavaScript2').item.json.bookingDetails.date} ${$('Code in JavaScript2').item.json.bookingDetails.time}
الاسم: ${$('Code in JavaScript2').item.json.bookingDetails.name}
رقم الموبايل: ${$('Code in JavaScript2').item.json.bookingDetails.phone}
العنوان: ${$('Code in JavaScript2').item.json.bookingDetails.area}` }}
```
