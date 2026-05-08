# Gardenia n8n Workflow — Code Nodes & Setup Guide

## Table of Contents
1. [Webhook Data Extraction](#1-webhook-data-extraction)
2. [SQL Query — Load Channel + Settings](#2-sql-query)
3. [Client Upsert Logic](#3-client-upsert)
4. [Typing Delay Calculator](#4-typing-delay)
5. [AI Agent JSON Parser](#5-ai-json-parser)
6. [Intent Router (Switch)](#6-intent-router)
7. [Booking Creator Code](#7-booking-creator)
8. [Order Creator Code](#8-order-creator)
9. [Product Image Resolver](#9-product-image-resolver)
10. [Admin Notification Formatter](#10-admin-notification)
11. [Agent Reply Flow](#11-agent-reply-flow)

---

## 1. Webhook Data Extraction

**Node**: `Edit Fields` (Set node)
**Purpose**: Normalize the raw Evolution API webhook payload.

```javascript
// n8n Set Node — Field Assignments:

// Instance name
Instance = {{ $json.body.instance }}

// Sender JID (strip @s.whatsapp.net for storage, keep for API calls)
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
```

---

## 2. SQL Query

**Node**: `Execute a SQL query` (Postgres node)
**Purpose**: Get channel info, active products, and system settings in one query.

```sql
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
WHERE c.name = '{{ $json.Instance || $('Edit Fields').first().json.Instance }}'
LIMIT 1;
```

---

## 3. Client Upsert

**Node**: `Get a row` (Supabase GET) + `If` + `Create a row` (Supabase INSERT)

### Step 1: Check if client exists
```
Table: Client
Filter: platform_user_id = {{ $('Edit Fields').item.json.SenderJid }}
Filter: channel_id = {{ $('Execute a SQL query').first().json.id }}
```

### Step 2: If no client found, create one
```
Table: Client
Fields:
  name = {{ $('Edit Fields').item.json.SenderName }}
  phone = {{ $('Edit Fields').item.json.SenderJid.replace('@s.whatsapp.net', '') }}
  platform = "whatsapp"
  platform_user_id = {{ $('Edit Fields').item.json.SenderJid }}
  channel_id = {{ $('Execute a SQL query').first().json.id }}
```

### Step 3: Store client ID for downstream use
**Node**: `Edit Fields13` (Set node)
```
id = {{ $json.id }}  // client UUID from GET or INSERT result
```

---

## 4. Typing Delay Calculator

**Node**: `Code` (JavaScript)
**Purpose**: Simulate human typing speed for natural-feeling responses.

```javascript
const minTimePerChar = 20;
const maxTimePerChar = 70;

for (const item of items) {
  const message = $input.first().json.response || '';
  const characterCount = message.length;
  let totalTypingTime = 0;

  for (let i = 0; i < characterCount; i++) {
    const randomTimeForChar = Math.random() * (maxTimePerChar - minTimePerChar) + minTimePerChar;
    totalTypingTime += randomTimeForChar;
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
**Purpose**: Extract JSON from AI agent output (handles markdown fences and raw JSON).

```javascript
const rawOutputString = $input.first().json.output;

if (!rawOutputString || typeof rawOutputString !== 'string') {
  return [{ json: { error: "Input 'output' is missing or not a string." } }];
}

let jsonString = null;

// STRATEGY 1: Markdown code fence
const markdownRegex = /`{3,}(?:json)?\s*([\s\S]*?)\s*`{3,}/;
const markdownMatch = rawOutputString.match(markdownRegex);
if (markdownMatch && markdownMatch[1]) {
  jsonString = markdownMatch[1].trim();
}

// STRATEGY 2: First '{' to last '}'
if (!jsonString) {
  const startIndex = rawOutputString.indexOf('{');
  const endIndex = rawOutputString.lastIndexOf('}');
  if (startIndex > -1 && endIndex > -1 && endIndex > startIndex) {
    jsonString = rawOutputString.substring(startIndex, endIndex + 1).trim();
  }
}

if (!jsonString) {
  return [{ json: { error: "No JSON found", originalOutput: rawOutputString } }];
}

try {
  return [{ json: JSON.parse(jsonString) }];
} catch (error) {
  try {
    const fixed = jsonString.replace(/\n/g, '\\n');
    return [{ json: JSON.parse(fixed) }];
  } catch (retryError) {
    return [{ json: { error: "JSON parse failed", stringThatFailed: jsonString, errorMessage: retryError.message } }];
  }
}
```

---

## 6. Intent Router

**Node**: `Switch2` (Switch node)
**Purpose**: Route based on parsed `intent` field.

| Output | Condition |
|---|---|
| `conversation` | `{{ $json.intent }}` equals `conversation` |
| `booking` | `{{ $json.intent }}` equals `create booking` |
| `order` | `{{ $json.intent }}` equals `create order` |
| `product images` | `{{ $json.intent }}` equals `product images` |
| `testimonials` | `{{ $json.intent }}` equals `testimonials` |

---

## 7. Booking Creator

**After** the `create booking` branch:

### 7a. Send confirmation text (HTTP Request → Evolution API)
```json
{
  "number": "{{ $('Edit Fields').item.json.SenderJid }}",
  "text": "{{ JSON.stringify($json.response).slice(1, -1) }}",
  "delay": {{ $json.typingAnalysis.calculatedTimeMs }}
}
```

### 7b. Create Booking row (Supabase INSERT)
```
Table: Booking
Fields:
  serviceSummary = {{ $json.bookingDetails.service }}
  channelType = "whatsapp"
  bookingDate = {{ $json.bookingDetails.date }} {{ $json.bookingDetails.time }}
  client_id = {{ $('Edit Fields13').item.json.id }}
  status = "pending"
```

### 7c. Update Client name/address (Supabase PATCH)
```
Table: Client
Filter: id = {{ $('Edit Fields13').item.json.id }}
Fields:
  address = {{ $json.bookingDetails.area }}
  name = {{ $json.bookingDetails.name }}
```

---

## 8. Order Creator

**After** the `create order` branch — **NEW NODE SETUP**:

### 8a. Code Node — Build Order Payload
```javascript
const order = $input.first().json.orderDetails;
const deliveryFee = parseFloat(
  $('Execute a SQL query').first().json.system_settings.delivery_fee || '2'
);

const subtotal = order.items.reduce((sum, item) => {
  return sum + (parseFloat(item.price) * (item.quantity || 1));
}, 0);

return [{
  json: {
    client_id: $('Edit Fields13').item.json.id,
    customerName: order.name,
    customerPhone: order.phone,
    customerAddress: order.address,
    items: order.items,
    subtotal: subtotal,
    deliveryFee: deliveryFee,
    total: subtotal + deliveryFee,
    paymentMethod: order.paymentMethod || 'cash',
    paymentStatus: 'unpaid',
    status: 'pending',
    notes: ''
  }
}];
```

### 8b. Supabase INSERT → Order table
```
Table: Order
Fields: (all from the code node output above)
```

### 8c. Update Client (same as booking flow)

---

## 9. Product Image Resolver

**After** the `product images` branch:

```javascript
const productIds = $input.first().json.productIds || [];
const activeProducts = $('Execute a SQL query').first().json.active_products || [];

let imageLinks = [];
for (const id of productIds) {
  const matches = activeProducts.filter(p => p.id === id);
  for (const product of matches) {
    if (product && product.images) {
      imageLinks.push(...product.images);
    }
  }
}

return { productImages: imageLinks };
```

Then: **Split Out** node → field `productImages` → **HTTP Request** (send media loop).

---

## 10. Admin Notification Formatter

**Node**: `Edit Fields1` (Set node)
**Purpose**: Format the WhatsApp notification to the admin.

### For Bookings:
```
message = حجز جديد
نوع الخدمه: {{ $json.bookingDetails.service }}
المكان: {{ $json.bookingDetails.location }}
التاريخ: {{ $json.bookingDetails.date }} {{ $json.bookingDetails.time }}
الاسم: {{ $json.bookingDetails.name }}
رقم الموبايل: {{ $json.bookingDetails.phone }}
العنوان: {{ $json.bookingDetails.area }}
```

### For Orders (NEW):
```
message = طلب جديد 🛒
المنتجات: {{ $json.orderDetails.items.map(i => i.name + ' x' + i.quantity).join(', ') }}
المجموع: {{ total }} دينار
الاسم: {{ $json.orderDetails.name }}
الرقم: {{ $json.orderDetails.phone }}
العنوان: {{ $json.orderDetails.address }}
الدفع: كاش
```

### Send to admin number:
```json
{
  "number": "{{ $('Execute a SQL query').first().json.system_settings.order_notification_whatsapp }}@s.whatsapp.net",
  "text": "{{ JSON.stringify($json.message).slice(1, -1) }}",
  "delay": 2000
}
```

---

## 11. Agent Reply Flow

**Trigger**: Separate Webhook (POST) from dashboard.

### Step 1: Typing Delay Code
```javascript
const message = $input.first().json.body.message.text_content || '';
const characterCount = message.length;
let totalTypingTime = 0;
for (let i = 0; i < characterCount; i++) {
  totalTypingTime += Math.random() * 50 + 20;
}
items[0].json.typingAnalysis = {
  calculatedTimeMs: Math.round(totalTypingTime)
};
return items;
```

### Step 2: Send via Evolution API
```json
POST https://evo.hillhousevilla.com/message/sendText/{{ $json.body.channel.name }}
Headers: { "apikey": "{{ $json.body.channel.credentials.evolution_key }}" }
Body: {
  "number": "{{ $json.body.client.phone }}",
  "text": "{{ JSON.stringify($json.body.message.text_content).slice(1, -1) }}",
  "delay": {{ $json.typingAnalysis.calculatedTimeMs }}
}
```

### Step 3: Log to Supabase
```
Table: Message
Fields:
  channel_id = {{ $json.body.client.channel_id }}
  client_id = {{ $json.body.client.id }}
  sender_type = "agent"
  content_type = "text"
  text_content = {{ $json.body.message.text_content }}
```

---

## n8n Credentials Required

| Credential | Type | Purpose |
|---|---|---|
| `Postgres account` | Postgres | Direct SQL queries for channel loading |
| `Supabase account` | Supabase API | CRUD on Client, Message, Booking, Order tables |
| `Google Gemini API` | Google PaLM | LLM for AI Agent |
| `OpenRouter account` | OpenRouter | Alternative LLM (Grok) |

## AI Agent Node Configuration

| Setting | Value |
|---|---|
| **Agent Type** | Tools Agent |
| **Prompt Type** | Define |
| **Text Input** | `{{ $json.body }}` (the customer message) |
| **System Message** | Paste from `n8n-system-prompt.md` |
| **Chat Memory** | Postgres Chat Memory |
| **Session Key** | `{{ $('Edit Fields').item.json.SenderJid }}` |
| **Table Name** | `saloon2` |
| **Context Window** | 20 messages |
| **Tools** | `get all products and services` + `get product details by id` |
