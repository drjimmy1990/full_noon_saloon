# 🧪 Salon Noon — Testing Checklist (May 22, 2026)

Full QA checklist for all features deployed in this update. Test on the live dashboard at `noondash.marka.giize.com` and the website.

> [!IMPORTANT]
> **Prerequisites before testing:**
> 1. ✅ SQL migration applied in Supabase (Booking columns, StaffBlockedDate, Branch contacts, Offer.channel, Notification, Product.maxSlots)
> 2. ✅ Gallery storage bucket created + RLS policies applied
> 3. ✅ Dashboard rebuilt and restarted with `pm2`
> 4. ✅ Website rebuilt and restarted with `pm2`

---

## 1. Manual Booking (Dashboard)

| # | Test Case | How to Test | Expected Result | ✅/❌ |
|---|-----------|-------------|-----------------|-------|
| 1.1 | Manual booking button visible | Go to **الحجوزات** page | "إضافة حجز" button appears next to header | |
| 1.2 | Open manual booking dialog | Click "إضافة حجز" | Dialog opens with: Branch, Service, Staff (optional), Date, Time/Slot, Client Name, Phone, Location, Notes | |
| 1.3 | Select branch first | Pick a branch from dropdown | Services and staff filter based on selected branch | |
| 1.4 | Select a time-based service | Pick a service with `durationMode = time` | Date picker + time slot picker appear | |
| 1.5 | Select a queue-based service | Pick a service with `durationMode = queue` | Date picker + slot number selector appear (not time) | |
| 1.6 | Staff is optional | Leave staff blank and submit | Booking saves successfully without a staff member | |
| 1.7 | Create manual booking | Fill all fields and click save | Booking appears in list with source = "يدوي" and payment = "كاش" | |
| 1.8 | Auto-create client | Enter a NEW phone number + name | A new client record is created automatically in the clients page | |
| 1.9 | Match existing client | Enter an EXISTING phone number | The existing client is linked (no duplicate created) | |

---

## 2. Emergency Leave / Staff Blocked Dates (Dashboard)

| # | Test Case | How to Test | Expected Result | ✅/❌ |
|---|-----------|-------------|-----------------|-------|
| 2.1 | Block button visible | Go to **العاملات** page | A 🚫 (block/calendar) icon button appears for each staff member | |
| 2.2 | Open blocked dates dialog | Click the block icon on a staff member | Dialog opens showing blocked dates list + add form | |
| 2.3 | Add a blocked date | Pick a future date + optional reason, click add | Date appears in the blocked dates list | |
| 2.4 | Duplicate date prevention | Try adding the same date again | Error or prevention (unique constraint) | |
| 2.5 | Delete a blocked date | Click the trash icon on a blocked date | Date is removed from the list | |
| 2.6 | **Website: Blocked date prevents booking** | On the public website, try to book the blocked staff on that date | ⚠️ Warning message appears: "العاملة في إجازة في هذا اليوم" and time slots are empty | |
| 2.7 | **Website: Queue mode blocked** | Same test but with a queue-mode service | Same blocked message, cannot proceed | |
| 2.8 | **Website: Server-side validation** | Try to bypass the UI and POST directly to `/api/booking` with a blocked date | API returns 409 error with Arabic message | |

---

## 3. RBAC / Permissions (Dashboard)

| # | Test Case | How to Test | Expected Result | ✅/❌ |
|---|-----------|-------------|-----------------|-------|
| 3.1 | Extended permissions list | Go to **الإعدادات** → Edit a team user's permissions | All sections visible: العاملات, العروض, الخدمات, المنتجات, الطلبات, عروض البوت, إعدادات البوت, الإشعارات, etc. | |
| 3.2 | Restrict a user | Remove "العاملات" permission from a team user | |
| 3.3 | Verify restriction | Log in as that restricted user | "العاملات" page is hidden from sidebar and inaccessible | |
| 3.4 | Admin sees all | Log in as admin user | All pages visible regardless of permissions | |

---

## 4. Branch Contact Info (Dashboard)

| # | Test Case | How to Test | Expected Result | ✅/❌ |
|---|-----------|-------------|-----------------|-------|
| 4.1 | Contact fields in dialog | Go to **الفروع** → Edit a branch | New fields visible: WhatsApp, Email, Instagram URL, Facebook URL, Google Maps URL | |
| 4.2 | Save contact info | Fill in WhatsApp + Email + Instagram, click save | Data persists after page reload | |
| 4.3 | Display contact info | View the branch card/list | Contact info is displayed on the branch entry | |
| 4.4 | Create new branch with contacts | Add a new branch with all contact fields filled | Branch created successfully with all contact data | |

---

## 5. Client Page Filters (Dashboard)

| # | Test Case | How to Test | Expected Result | ✅/❌ |
|---|-----------|-------------|-----------------|-------|
| 5.1 | Filters visible | Go to **العملاء** page | Filter bar appears (matching the bookings page filters) | |
| 5.2 | Filter by channel | Select "WhatsApp" from channel filter | Only WhatsApp clients shown | |
| 5.3 | Filter by date range | Set a date range for "joined from / to" | Only clients created in that range shown | |
| 5.4 | Filter by staff | Select a staff member | Only clients who had bookings with that staff shown | |
| 5.5 | Combined filters | Apply multiple filters at once | Results narrow correctly | |
| 5.6 | Reset filters | Clear all filters | Full client list returns | |

---

## 6. Bot Offers Page (Dashboard)

| # | Test Case | How to Test | Expected Result | ✅/❌ |
|---|-----------|-------------|-----------------|-------|
| 6.1 | Page accessible | Click **عروض البوت** in sidebar | Bot offers page loads | |
| 6.2 | Create bot offer | Click "Add Bot Offer", fill fields, save | Offer created with `channel = 'bot'` | |
| 6.3 | Bot offer NOT on website | Visit the public website services/products page | The bot offer does NOT appear on the storefront | |
| 6.4 | Website offers NOT in bot page | Check the bot offers page | Regular website offers do NOT appear here | |
| 6.5 | Edit bot offer | Edit an existing bot offer | Changes save correctly | |
| 6.6 | Delete bot offer | Delete a bot offer | Offer removed from list | |

---

## 7. Bot Settings Page (Dashboard)

| # | Test Case | How to Test | Expected Result | ✅/❌ |
|---|-----------|-------------|-----------------|-------|
| 7.1 | Page accessible | Click **إعدادات البوت** in sidebar | Bot settings page loads with reminder controls | |
| 7.2 | Staff reminder hours | Change "Staff Reminder" to 3 hours, save | Toast confirms save, value persists on reload | |
| 7.3 | Client reminder hours | Change "Client Reminder" to 12 hours, save | Toast confirms save, value persists on reload | |
| 7.4 | Values in settings API | Call `GET /api/settings` | Returns `bot_staff_reminder_hours` and `bot_client_reminder_hours` with correct values | |

---

## 8. Notifications (Dashboard)

| # | Test Case | How to Test | Expected Result | ✅/❌ |
|---|-----------|-------------|-----------------|-------|
| 8.1 | Page accessible | Click **الإشعارات** in sidebar | Notifications page loads | |
| 8.2 | Create test notification | POST to `/api/notifications` with `{ type: "customer_service", title: "طلب خدمة عملاء", body: "العميلة تريد التحدث مع الدعم", client_id: "<valid_id>" }` | Notification appears in the list | |
| 8.3 | Unread badge in sidebar | After creating an unread notification | Red badge with count appears next to الإشعارات in sidebar | |
| 8.4 | Mark as read | Click "Mark as Read" on a notification | Badge count decreases, notification visual changes | |
| 8.5 | Mark all read | Click "Mark All as Read" | All notifications marked read, badge disappears | |
| 8.6 | Filter unread / all | Toggle between "غير مقروء" and "الكل" tabs | Correct filtering applies | |
| 8.7 | Delete notification | Delete a notification | Removed from the list | |

---

## 9. Offer Channel Filtering (Website)

| # | Test Case | How to Test | Expected Result | ✅/❌ |
|---|-----------|-------------|-----------------|-------|
| 9.1 | Services page shows only website offers | Visit website `/services` | Only offers with `channel = 'website'` or `channel IS NULL` are shown | |
| 9.2 | Products page shows only website offers | Visit website `/products` | Same — no bot-only offers visible | |
| 9.3 | Service detail page | Visit `/services/[id]` for a service with a bot offer | Bot offer discount NOT applied on the storefront | |
| 9.4 | Product detail page | Visit `/products/[id]` for a product with a bot offer | Bot offer discount NOT applied on the storefront | |

---

## 10. Gallery Upload (Dashboard)

| # | Test Case | How to Test | Expected Result | ✅/❌ |
|---|-----------|-------------|-----------------|-------|
| 10.1 | Upload image | Go to **معرض الصور** → Click "إضافة صورة" | Image uploads successfully (no RLS error) | |
| 10.2 | Image displays | After upload | Image appears in the gallery grid | |
| 10.3 | Delete image | Delete a gallery image | Image removed from grid and storage | |

---

## 11. Sidebar Navigation (Dashboard)

| # | Test Case | How to Test | Expected Result | ✅/❌ |
|---|-----------|-------------|-----------------|-------|
| 11.1 | New nav items visible | Check sidebar | عروض البوت, إعدادات البوت, الإشعارات all appear | |
| 11.2 | RTL layout | Switch to Arabic | Sidebar and all new pages render correctly in RTL | |
| 11.3 | LTR layout | Switch to English | Sidebar and all new pages render correctly in LTR | |
| 11.4 | Mobile responsive | Open dashboard on mobile | Sidebar collapses, all pages accessible via mobile menu | |

---

## 12. Deployment Health

| # | Test Case | How to Test | Expected Result | ✅/❌ |
|---|-----------|-------------|-----------------|-------|
| 12.1 | Dashboard PM2 status | `pm2 status` on VPS | `salon-dashboard` online, 0-1 restarts | |
| 12.2 | Website PM2 status | `pm2 status` on VPS | `salon-website` online, 0 restarts | |
| 12.3 | Dashboard loads | Visit dashboard URL | Login page or dashboard loads without errors | |
| 12.4 | Website loads | Visit website URL | Homepage loads without errors | |
| 12.5 | No console errors | Check browser DevTools console | No critical errors (warnings are OK) | |

---

## ✍️ Notes

Use this space to track any bugs or issues found during testing:

| # | Issue Description | Severity | Status |
|---|-------------------|----------|--------|
| | | | |
| | | | |
| | | | |
