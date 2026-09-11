# Project: Salon CRM Manual Booking & Overlap Validation

## Architecture
- **saloon-mostafa (CRM Admin)**: Next.js application managing administrative actions.
  - API Routes: `/api/bookings` and `/api/bookings/[id]` for CRUD operations on bookings.
  - UI Components: `bookings-section.tsx` for displaying, creating, editing, and deleting bookings.
- **gardenia-website (Public Storefront)**: Next.js application for public booking and checking availability.
  - API Routes: `/api/availability` to query available slots for a given staff and service on a date.
  - API Routes: `/api/booking` to create storefront bookings.
- **Database (Supabase)**: Holds `Booking`, `Product` (Services), `Staff`, `StaffBlockedDate`, `StaffSchedule`, `Client`, `Branch` tables.

## Code Layout
- **CRM App**: `saloon-mostafa/`
  - Bookings List/CRUD page: `src/app/(dashboard)/bookings/page.tsx`
  - Bookings Components: `src/components/sections/bookings-section.tsx`
  - Bookings API Endpoints:
    - Create/List: `src/app/api/bookings/route.ts`
    - Update/Delete: `src/app/api/bookings/[id]/route.ts`
- **Storefront App**: `gardenia-website/`
  - Availability API Endpoint: `src/app/api/availability/route.ts`
  - Booking API Endpoint: `src/app/api/booking/route.ts`

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | E2E Testing Track | Define test infra, write Tier 1-4 opaque-box tests covering booking, editing, deletion, validation, and availability blocks. | None | PLANNED |
| M2 | Align Manual Booking & Save | Fix POST `/api/bookings` to calculate combined UTC `bookingDate` and `endTime`, save `serviceId`, set channel to 'manual'. Verify storefront availability recognizes manual bookings. | M1 | PLANNED |
| M3 | Overlap & Blocked Date Validation | Implement strict overlap checks (staff availability / staff leave) in POST `/api/bookings` and PUT `/api/bookings/[id]`. Prevent double booking and return clear error messages. | M1, M2 | PLANNED |
| M4 | Edit & Delete Actions UI/API | Extend PUT `/api/bookings/[id]` to support editing all booking details. Build UI forms/modals for Edit & Delete in `bookings-section.tsx` with proper error handling and confirmation alerts. | M1, M2, M3 | PLANNED |
| M5 | E2E Integration & Verification | Run all test tiers, verify 100% pass, run Tier 5 adversarial checks for coverage hardening. | M1, M2, M3, M4 | PLANNED |

## Interface Contracts
### CRM Bookings API ↔ Database / Storefront Availability
- **POST `/api/bookings`**:
  - Request body: `{ clientName, clientPhone, serviceId, bookingDate, bookingTime, staff_id, branchId, location, notes, channelType: 'manual', ... }`
  - Response: Created Booking object or `{ error: string }`
  - Side effects: Stores `bookingDate` and `endTime` in ISO UTC format.
- **PUT `/api/bookings/[id]`**:
  - Request body: `{ clientName, clientPhone, serviceId, bookingDate, bookingTime, staff_id, branchId, location, notes, status, ... }`
  - Response: Updated Booking object or `{ error: string }`
- **GET `/api/availability` (Storefront)**:
  - Query params: `staffId`, `serviceId`, `date`
  - Response: `{ mode, slots: [{ time, booked }], ... }`
