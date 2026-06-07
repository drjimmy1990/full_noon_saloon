# 📡 Noon Salon — Complete API Reference

> All endpoints across both projects with full request/response details.

---

# 🌐 WEBSITE (Storefront) — `noonweb.marka.giize.com`

> Public-facing. **No auth** unless noted.

---

## 📅 POST `/api/booking` — Create Booking

Creates a new booking with overlap checking, blocked date checking, and queue mode support.

**Body:**
```json
{
  "serviceId": "uuid",           // ✅ Required
  "date": "2026-06-10",          // ✅ Required (YYYY-MM-DD)
  "name": "Customer",            // ✅ Required
  "phone": "962791234567",       // ✅ Required
  "time": "10:00",               // HH:mm (null for queue mode)
  "branchId": "uuid",
  "staffId": "uuid",
  "serviceSummary": "بروتين",
  "notes": "Source: WhatsApp Bot",
  "depositAmount": 0,
  "paymentMethod": "cash",
  "channelType": "website",      // "website" | "whatsapp"
  "durationMode": "time",        // "time" | "queue"
  "durationMinutes": 60,
  "authUserId": "uuid"           // Optional (logged-in users)
}
```

**Responses:**
| Status | Response |
|--------|----------|
| `200` | `{ "success": true, "bookingId": "uuid", "queueNumber": null }` |
| `400` | `{ "error": "Missing required fields" }` |
| `409` | `{ "error": "العاملة في إجازة في هذا اليوم. يرجى اختيار يوم آخر." }` |
| `409` | `{ "error": "هذا الوقت محجوز بالفعل. يرجى اختيار وقت آخر." }` |

**Logic:** Finds/creates Client → Calculates bookingDate + endTime → Checks StaffBlockedDate → Checks booking overlaps → If queue mode: calculates queueNumber → Inserts Booking.

---

## 🕐 GET `/api/availability` — Check Available Slots

Returns available time slots or next queue number for a staff+service+date combo.

**Query Params:**
| Param | Required | Example |
|-------|----------|---------|
| `staffId` | ✅ | `abc-123` |
| `serviceId` | ✅ | `def-456` |
| `date` | ✅ | `2026-06-10` |

**Responses:**
```json
// ✅ Time-based service (mode = "time")
{
  "mode": "time",
  "slots": [
    { "time": "09:00", "booked": false },
    { "time": "09:30", "booked": true },
    { "time": "10:00", "booked": false }
  ],
  "staffSchedule": { "startTime": "09:00", "endTime": "21:00" },
  "serviceDuration": 60,
  "depositAmount": 0
}

// ✅ Queue-based service (mode = "queue")
{
  "mode": "queue",
  "nextQueueNumber": 3,
  "serviceDuration": 30,
  "depositAmount": 0
}

// ⛔ Staff on leave (blocked = true)
{
  "mode": "time",
  "slots": [],
  "blocked": true,
  "message": "العاملة في إجازة في هذا اليوم"
}

// ⛔ Staff is off on this day
{
  "mode": "time",
  "slots": [],
  "message": "Staff is off on this day"
}
```

**Logic:** Fetches service durationMode → If queue: returns nextQueueNumber → If time: checks StaffBlockedDate → Gets StaffSchedule for that weekday → Fetches existing Bookings → Generates slots at `durationMinutes` intervals → Marks overlapping slots as `booked: true`.

---

## 🏪 GET `/api/branches` — List Branches

**Query Params:**
| Param | Required | Example |
|-------|----------|---------|
| `active` | Optional | `true` — filters to `isActive = true` |

**Response:**
```json
[
  {
    "id": "uuid",
    "name": "Tressim",
    "nameAr": "برسيم",
    "address": "شارع...",
    "phone": "962...",
    "whatsapp": "962...",
    "email": "info@...",
    "instagramUrl": "https://...",
    "facebookUrl": "https://...",
    "googleMapsUrl": "https://maps.google.com/...",
    "isActive": true,
    "createdAt": "2026-01-01T..."
  }
]
```

Also has `POST` (create), `PUT` (update), `DELETE` (delete by `?id=uuid`) — all public (no auth).

---

## 💇 GET `/api/services` — List Services

**Query Params:**
| Param | Required | Example |
|-------|----------|---------|
| `branchId` | Optional | `uuid` — filter by branch |

**Response:**
```json
[
  {
    "id": "uuid",
    "name": "بروتين",
    "price": 35,
    "images": ["https://..."],
    "availableAtHome": false,
    "availableAtSalon": true,
    "branchId": "uuid",
    "category": "uuid",
    "durationMinutes": 60,
    "durationMode": "time",
    "depositAmount": 0,
    "publishAt": null
  }
]
```

**Filters:** Only `isAvailable = true`, `type = 'service'`, not future-published.

---

## 💇‍♀️ GET `/api/services-with-staff` — Services + Staff per Branch

**Query Params:**
| Param | Required | Example |
|-------|----------|---------|
| `branchId` | Optional (recommended) | `uuid` |

**Response:**
```json
[
  {
    "category": "شعر",
    "categoryId": "uuid",
    "image": "https://...",
    "services": [
      {
        "id": "service-uuid",
        "name": "بروتين",
        "price": 35,
        "images": ["https://..."],
        "durationMinutes": 60,
        "durationMode": "time",
        "depositAmount": 0,
        "branchId": "uuid",
        "staff": [
          { "id": "staff-uuid", "name": "هنا", "role": "stylist" },
          { "id": "staff-uuid", "name": "سارة", "role": "stylist" }
        ]
      }
    ]
  }
]
```

**Logic:** Fetches services (filtered by branch) → StaffService assignments → Staff details (active only, same branch) → Groups by Category → Returns with staff[] per service.

---

## 🛒 POST `/api/order` — Create Product Order

**Body:**
```json
{
  "customerName": "سارة",          // ✅ Required
  "customerPhone": "0791234567",   // ✅ Required
  "customerAddress": "عمان - خلدا",
  "items": [                       // ✅ Required
    { "id": "uuid", "name": "شامبو", "price": 12, "quantity": 2 }
  ],
  "subtotal": 24,
  "deliveryFee": 2,
  "total": 26,
  "paymentMethod": "cash",
  "notes": "Source: WhatsApp Bot",
  "authUserId": "uuid"             // Optional
}
```

**Response:**
```json
{ "success": true, "orderId": "uuid", "orderCode": "ORD-XXX" }
```

**Logic:** Finds/creates Client by phone → Inserts into Order table with all fields.

---

## ⚙️ GET `/api/settings` — System Settings

No params needed.

**Response:**
```json
{
  "salon_name": "صالون نون",
  "salon_address": "...",
  "working_hours_weekdays": "9AM - 9PM",
  "delivery_fee": "2",
  "order_notification_whatsapp": "962...",
  "bot_reminder_hours": "2",
  "google_maps_url": "https://..."
}
```

---

## 📞 POST `/api/contact` — Submit Contact Form

**Body:**
```json
{
  "name": "أحمد",        // ✅ Required
  "phone": "0791234567", // ✅ Required
  "email": "a@b.com",    // Optional
  "message": "استفسار",  // ✅ Required
  "branchId": "uuid"     // Optional
}
```

**Response:**
```json
{ "success": true, "id": "uuid" }
```

---

## 📄 GET `/api/terms` — Terms & Conditions

Returns HTML/text content of terms page.

---

## 👤 Account & Auth (Logged-in Customers)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/account` | Get customer profile (🔒 Supabase Auth) |
| `PUT` | `/api/account` | Update customer profile (🔒 Supabase Auth) |
| `POST` | `/api/auth/link-client` | Link auth user → Client record (🔒 Supabase Auth) |

---

## 💳 Payment (Paymob)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/payment/intent` | Create payment intent for deposit |
| `POST` | `/api/payment/webhook` | Paymob HMAC webhook callback |

---

---

# 🔐 DASHBOARD (CRM Admin) — `noondash.marka.giize.com`

> All require `getAuthUser()` unless marked 🌐 Public.

---

## 🔑 Auth

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/auth/me` | Get current user info |
| `PUT` | `/api/auth/password` | Change password |

---

## 📅 Bookings

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/bookings` | List all bookings (with Client relation) |
| `POST` | `/api/bookings` | Create booking manually |
| `GET` | `/api/bookings/:id` | Get single booking with client details |
| `PUT` | `/api/bookings/:id` | Update booking (status, client_id, serviceSummary, channelType) |
| `DELETE` | `/api/bookings/:id` | Delete booking |

**GET Response includes:** `*, client:Client(*)`

---

## 🏪 Branches

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/branches` | List all branches |
| `POST` | `/api/branches` | Create branch |
| `PUT` | `/api/branches` | Update branch (body must include `id`) |
| `DELETE` | `/api/branches` | Delete branch (`?id=uuid`) |

---

## 🏷️ Categories

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/categories` | List categories |
| `POST` | `/api/categories` | Create category |
| `PUT` | `/api/categories/:id` | Update category |
| `DELETE` | `/api/categories/:id` | Delete category |

---

## 📡 Channels (WhatsApp/Instagram instances)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/channels` | List all channels |
| `POST` | `/api/channels` | Create channel |
| `GET` | `/api/channels/:id` | Get channel details |
| `PUT` | `/api/channels/:id` | Update channel |
| `DELETE` | `/api/channels/:id` | Delete channel |

---

## 👥 Clients

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/clients?page=1&limit=10&search=xxx&ai_enabled=true` | List clients (paginated) |
| `POST` | `/api/clients` | Create/upsert client (by phone or platform_user_id) |
| `GET` | `/api/clients/:id` | Get client details |
| `PUT` | `/api/clients/:id` | Update client (ai_enabled, name, etc.) |
| `DELETE` | `/api/clients/:id` | Delete client + all their messages |
| `POST` | `/api/clients/:id/read` | Mark client messages as read |
| `GET` | `/api/clients/export` | Export clients CSV (🔒 Admin only) |

**GET `/api/clients` Response:**
```json
{
  "data": [
    {
      "id": "uuid",
      "name": "رنا",
      "phone": "962791234567",
      "platform": "whatsapp",
      "platform_user_id": "962791234567@s.whatsapp.net",
      "ai_enabled": true,
      "messages": [...],
      "bookings_count": 2,
      "Channel": { "name": "gardenia", "type": "whatsapp" }
    }
  ],
  "total": 150
}
```

---

## 📸 CMS (Content Management)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/cms` | Get CMS content blocks |
| `PUT` | `/api/cms` | Update CMS content |

---

## 📬 Contact Messages

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/contact-messages` | List contact form submissions |
| `GET` | `/api/contact-messages/:id` | Get single message + auto mark as read |
| `DELETE` | `/api/contact-messages/:id` | Delete message |

---

## 📊 GET `/api/dashboard` — Dashboard Statistics

No params needed. Returns comprehensive stats.

**Response:**
```json
{
  "activeChannels": 2,
  "totalChannels": 3,
  "totalMessages": 1250,
  "totalBookings": 85,
  "pendingBookings": 12,
  "confirmedBookings": 60,
  "cancelledBookings": 13,
  "conversionRate": 15.5,
  "totalClients": 200,
  "totalProducts": 15,
  "blacklistCount": 5,
  "activeConversations": 30,
  "channelPerformanceData": [
    { "channel": "WhatsApp", "channelAr": "واتساب", "messages": 800 },
    { "channel": "Facebook", "channelAr": "فيسبوك", "messages": 300 },
    { "channel": "Instagram", "channelAr": "انستجرام", "messages": 150 }
  ],
  "recentBookings": [
    {
      "id": "uuid", "clientName": "رنا", "service": "بروتين",
      "channel": "whatsapp", "channelAr": "واتساب",
      "date": "2026-06-05", "status": "pending"
    }
  ],
  "weeklyTrendData": [
    { "day": "Sun", "dayAr": "الأحد", "messages": 45, "bookings": 3 }
  ]
}
```

---

## 🖼️ Gallery

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/gallery` | List gallery sets with images |
| `POST` | `/api/gallery` | Create/update gallery set |
| `DELETE` | `/api/gallery` | Delete gallery set (`?id=uuid`) |

---

## 💬 POST `/api/messages` — Send Message (Agent Reply)

Creates a Message row and triggers the n8n webhook to send via WhatsApp.

**Body:**
```json
{
  "client_id": "uuid",        // ✅ Required
  "text_content": "مرحبا",     // ✅ Required
  "sender_type": "agent",     // "agent" | "user" | "bot"
  "content_type": "text",     // "text" | "image" | "audio"
  "attachment_url": "",
  "platform_timestamp": "2026-06-05T10:00:00Z"
}
```

**Webhook trigger:** If `sender_type === "agent"`, fetches Client → Channel → fires `channel.webhookUrl` with `{ event, message, client, channel }`.

---

## 🔔 Notifications

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/api/notifications?unread=true` | 🔒 Auth | List notifications |
| `POST` | `/api/notifications` | 🌐 **Public** | Create notification (for n8n/bot) |
| `PUT` | `/api/notifications` | 🔒 Auth | Mark as read (single or all) |
| `DELETE` | `/api/notifications?id=uuid` | 🔒 Auth | Delete notification |

**POST Body (🌐 Public — used by n8n bot):**
```json
{
  "type": "customer_service",     // "customer_service" | "new_booking" | "new_order"
  "title": "طلب خدمة عملاء",      // ✅ Required
  "body": "العميلة رنا تريد التحدث مع الدعم",
  "client_id": "uuid"             // Optional
}
```

**PUT Body:**
```json
// Mark single as read
{ "id": "uuid", "isRead": true }

// Mark ALL as read
{ "markAllRead": true }
```

---

## 🎁 Offers (عروض)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/offers?channel=bot` | List offers (filterable by channel) |
| `POST` | `/api/offers` | Create offer |
| `PUT` | `/api/offers` | Update offer (body must include `id`) |
| `DELETE` | `/api/offers?id=uuid` | Delete offer |

**GET Query Params:**
| Param | Effect |
|-------|--------|
| `channel=bot` | Returns offers where `channel IN ('bot', 'both')` |
| `channel=website` | Returns offers where `channel IN ('website', 'both')` |
| (no param) | Returns ALL offers |

**Offer Object:**
```json
{
  "id": "uuid",
  "product_id": "uuid",
  "discountType": "percentage",     // "percentage" | "fixed"
  "discountValue": 20,              // 20% or 20 JOD
  "startDate": "2026-06-01",
  "endDate": "2026-06-30",
  "isActive": true,
  "channel": "bot",                 // "website" | "bot" | "both"
  "product": {
    "id": "uuid",
    "name": "بروتين",
    "price": 35
  }
}
```

**POST/PUT Body:**
```json
{
  "id": "uuid",                    // Required for PUT only
  "product_id": "uuid",
  "discountType": "percentage",
  "discountValue": 20,
  "startDate": "2026-06-01",
  "endDate": "2026-06-30",
  "isActive": true,
  "channel": "bot"                 // "website" | "bot" | "both"
}
```

> **🤖 Bot Offers Note:** The bot gets offers in two ways:
> 1. **Startup SQL query** — loads `bot_offers` (active offers where `channel IN ('bot', 'both')`) into context
> 2. **Dashboard API** — `GET /api/offers?channel=bot` (requires auth, for dashboard use only)

---

## 📦 Orders

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/orders` | List all orders |
| `POST` | `/api/orders` | Create order |
| `PUT` | `/api/orders` | Update order (status, paymentStatus) |
| `DELETE` | `/api/orders?id=uuid` | Delete order |

---

## 🛍️ Products

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/products` | List all products (services + retail) |
| `POST` | `/api/products` | Create product |
| `PUT` | `/api/products` | Update product |
| `GET` | `/api/products/:id` | Get single product |
| `DELETE` | `/api/products/:id` | Delete product |

---

## ⚙️ Settings

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/api/settings` | 🌐 **Public** | Get all settings (for website consumption) |
| `POST` | `/api/settings` | 🔒 Admin | Update settings |

---

## 👩‍💼 Staff

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/staff` | List staff members |
| `POST` | `/api/staff` | Create staff |
| `PUT` | `/api/staff` | Update staff |
| `DELETE` | `/api/staff?id=uuid` | Delete staff |

---

## 📅 Staff Blocked Dates

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/staff/blocked-dates?staffId=uuid` | List blocked dates for a staff member |
| `POST` | `/api/staff/blocked-dates` | Add blocked date `{ staff_id, blockedDate, reason }` |
| `DELETE` | `/api/staff/blocked-dates?id=uuid` | Remove blocked date |

---

## 🕐 Staff Schedule

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/staff/schedule?staffId=uuid` | Get weekly schedule (7 days) |
| `PUT` | `/api/staff/schedule` | Update schedule `{ staffId, schedules: [...] }` |

**Schedule Object:**
```json
{
  "dayOfWeek": 0,        // 0=Sunday ... 6=Saturday
  "startTime": "09:00",
  "endTime": "21:00",
  "isOff": false
}
```

---

## 🔗 Staff-Services (Assignments)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/staff-services?staffId=uuid` | List services assigned to a staff member |
| `POST` | `/api/staff-services` | Assign service to staff `{ staff_id, product_id }` |
| `PUT` | `/api/staff-services` | Bulk update assignments `{ staffId, productIds: [...] }` |

---

## 👤 Users (Dashboard Admin Management)

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/api/users` | 🔒 Admin | List dashboard users |
| `POST` | `/api/users` | 🔒 Admin | Create dashboard user |
| `GET` | `/api/users/:id` | 🔒 Admin | Get user details |
| `PUT` | `/api/users/:id` | 🔒 Admin | Update user |
| `DELETE` | `/api/users/:id` | 🔒 Admin | Delete user |

---

---

# 🤖 Bot-Relevant APIs (Quick Reference)

These are the endpoints the n8n WhatsApp bot should use as AI tools:

| Tool Name | Method | Base | Endpoint | Purpose |
|-----------|--------|------|----------|---------|
| `get_branches` | `GET` | Website | `/api/branches?active=true` | List branches for booking selection |
| `get_staff_for_service` | `GET` | Website | `/api/services-with-staff?branchId=uuid` | Services + staff at a branch |
| `check_availability` | `GET` | Website | `/api/availability?staffId=...&serviceId=...&date=...` | Free slots / queue number / blocked check |
| `create_booking` | `POST` | Website | `/api/booking` | Validated booking (overlap + blocked) |
| `create_order` | `POST` | Website | `/api/order` | Product order creation |
| `send_notification` | `POST` | Dashboard | `/api/notifications` | Customer service request alert (🌐 Public) |
| `get_all_products` | — | Supabase REST | Direct Supabase query | Product/service catalog (existing tool) |
| `get_product_details` | — | Supabase REST | Direct Supabase query | Single product details (existing tool) |

### Bot Offers (عروض البوت)

The bot accesses offers in **two ways**:

1. **Via startup SQL query** (recommended, already in context):
   ```sql
   -- This is loaded automatically into active context as `bot_offers`
   SELECT * FROM "Offer" WHERE "isActive" = true AND channel IN ('bot', 'both')
   ```

2. **Via Dashboard API** (if you prefer HTTP tool over SQL):
   ```
   GET https://noondash.marka.giize.com/api/offers?channel=bot
   ```
   > ⚠️ This requires dashboard auth. For the bot, use the SQL query method instead.

### Summary of Bot Data Sources

| Data | How Bot Gets It |
|------|-----------------|
| Products & Services | Startup SQL → `active_products` |
| System Settings | Startup SQL → `system_settings` |
| Branches | Startup SQL → `active_branches` OR Tool `get_branches` |
| Staff | Startup SQL → `active_staff` |
| Staff ↔ Service Mapping | Startup SQL → `staff_services` OR Tool `get_staff_for_service` |
| **Bot Offers (عروض)** | **Startup SQL → `bot_offers`** |
| Categories | Startup SQL → `categories` |
| Availability | Tool → `check_availability` (must be called per request) |
| Image Sets (Testimonials) | Startup SQL → `image_sets` |
