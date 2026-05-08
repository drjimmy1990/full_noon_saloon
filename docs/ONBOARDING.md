# Saloooon Project Onboarding Guide

## Project Overview
- **Project Name:** saloooon
- **Description:** Saloooon fullstack Next.js applications
- **Primary Languages:** TypeScript, JavaScript, CSS, SQL, JSON, Markdown, CSV, Plaintext, Env
- **Frameworks:** Next.js (implicitly detected based on folder structure and routing patterns)

## Architecture Layers
The project is split into three main architectural layers:

1. **Frontend**
   - **Description:** Next.js Public Website (`gardenia-website/`)
   - **Focus:** Contains the public-facing storefront, booking mechanisms, cart functionality, and informational pages.

2. **Backend**
   - **Description:** Dashboard & Admin (`saloon-mostafa/`)
   - **Focus:** Contains the secure administrative dashboard, order management, staff scheduling, client records, content management (CMS), and chat system integrations.

3. **Root Config**
   - **Description:** Configuration Files
   - **Focus:** Contains top-level project settings, git ignores, environment configurations, and other root configurations tying the monorepo together.

## Key Concepts
Based on the file patterns and architecture, here are the core concepts driving this project:
- **API Routes (Next.js):** Extensive use of App Router API endpoints (`route.ts`) in both the Frontend and Backend to handle operations like bookings, payments (webhook & intents), CMS content fetching, and database operations.
- **Shared UI Components:** Widespread use of structured, reusable UI components (likely shadcn/ui given the `components.json` and components like `accordion`, `alert-dialog`, `sheet`, `avatar`, etc.) inside the `src/components/ui/` folders.
- **Feature Sections:** The admin backend is neatly modularized into specific feature components under `src/components/sections/` (e.g., `bookings-section`, `chat-section`, `orders-section`).

## Guided Tour
*(Note: Because the graph was generated using the structural bypass script, a guided sequential tour has not been fully mapped by the AI yet. The recommended learning path is to start from the root configurations, move to the Frontend routing logic, and then explore the Backend dashboard API integrations.)*

## File Map
A high-level map of the key functional files across the architectural layers:

### Frontend (`gardenia-website`)
- **Pages:**
  - `src/app/booking/page.tsx` – Primary booking interface (442 lines).
  - `src/app/cart/page.tsx` – User shopping cart functionality (154 lines).
  - `src/app/about/page.tsx` – Informational About page.
- **APIs:**
  - `src/app/api/booking/route.ts` – Handles booking data submission.
  - `src/app/api/payment/intent/route.ts` & `webhook/route.ts` – Payment gateway integration.

### Backend (`saloon-mostafa`)
- **Admin Sections:**
  - `src/components/sections/bookings-section.tsx`
  - `src/components/sections/chat-section.tsx`
  - `src/components/sections/orders-section.tsx`
- **APIs:**
  - `src/app/api/clients/route.ts` & `src/app/api/staff/route.ts` – Core CRM and Staff management endpoints.
  - `src/app/api/settings/route.ts` & `src/app/api/cms/route.ts` – System configuration and CMS handlers.
- **Database/Storage:**
  - `src/lib/supabase.ts` & `src/utils/supabase/server.ts` – Supabase database and authentication configurations.
  - `seed-systemsettings.sql` – Initial SQL seeds for system states.

### Root Config
- `.env.local`, `package.json`, `next.config.ts`, `tailwind.config.ts`, `postcss.config.mjs`

## Complexity Hotspots
*(Note: System complexities are currently structurally marked as "moderate" across the board. However, based on typical architectural flow, pay special attention to the following areas:)*
1. **Frontend Booking Flow:** `gardenia-website/src/app/booking/page.tsx` is one of the larger files (442 lines) handling complex client-side state.
2. **Payment Webhooks:** `api/payment/webhook/route.ts` is crucial for order integrity and security validation.
3. **Supabase Middleware & Auth:** Files under `saloon-mostafa/src/utils/supabase/` contain sensitive route-protection rules.
