# ConstructLedger — Application Documentation

> **"No guesswork. Just the granular, project-tied truth of your profit."**

ConstructLedger is a multi-tenant, web-based profit tracking tool built for construction companies. It lets managers and their teams log income and costs against specific projects, then instantly see real-time P&L (Profit & Loss) figures — all in a clean, industrial-themed dashboard.

---

## Table of Contents

1. [Tech Stack](#tech-stack)
2. [Architecture Overview](#architecture-overview)
3. [Database Schema](#database-schema)
4. [Authentication & Access Control](#authentication--access-control)
5. [Pages & User Flows](#pages--user-flows)
   - [Landing Page (`/`)](#landing-page-)
   - [Auth Page (`/auth`)](#auth-page-auth)
   - [Dashboard (`/dashboard`)](#dashboard-dashboard)
   - [New Project (`/projects/new`)](#new-project-projectsnew)
   - [Project Detail (`/projects/:id`)](#project-detail-projectsid)
   - [Settings (`/settings`)](#settings-settings)
   - [Reset Password (`/reset-password`)](#reset-password-reset-password)
6. [Key Components](#key-components)
7. [Multi-Tenant Isolation](#multi-tenant-isolation)
8. [Edge Functions (Supabase)](#edge-functions-supabase)
9. [Running Locally](#running-locally)

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend Framework | React 18 + TypeScript |
| Build Tool | Vite |
| Routing | React Router v6 |
| UI Components | shadcn/ui (Radix UI) |
| Styling | Tailwind CSS |
| Data Fetching | TanStack Query v5 |
| Backend / DB | Supabase (PostgreSQL + Auth + Edge Functions) |
| Charts | Recharts |
| Forms | React Hook Form + Zod |
| Currency | Kenyan Shilling (KES) via `Intl.NumberFormat` |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                   React SPA (Vite)                       │
│  ┌──────────┐  ┌───────────┐  ┌─────────────────────┐  │
│  │  Pages   │  │Components │  │  Hooks / Auth        │  │
│  │ Dashboard│  │AddCost    │  │  useAuth (Context)   │  │
│  │ Project  │  │AddIncome  │  │  useNavigate         │  │
│  │ Settings │  │Charts     │  │                      │  │
│  │ Auth     │  │Dialogs    │  │                      │  │
│  └────┬─────┘  └─────┬─────┘  └──────────┬──────────┘  │
│       └───────────────┴─────────────────┘               │
│                Supabase JS Client                        │
└────────────────────────┬────────────────────────────────┘
                         │ HTTPS (REST + Realtime)
┌────────────────────────▼────────────────────────────────┐
│                     Supabase                            │
│  ┌────────────┐  ┌─────────────────┐  ┌─────────────┐  │
│  │  Auth      │  │  PostgreSQL DB   │  │Edge Functions│  │
│  │  (JWT)     │  │  (Row-Level      │  │send-invitation│ │
│  │            │  │   Security)      │  │send-password- │ │
│  │            │  │                  │  │  reset       │  │
│  └────────────┘  └─────────────────┘  └─────────────┘  │
└─────────────────────────────────────────────────────────┘
```

All data access goes through **Supabase's Row Level Security (RLS)** policies. The client never talks directly to the database in a privileged way — every query is scoped to the authenticated user's company.

---

## Database Schema

The database is multi-tenant: every key table is scoped to a `company_id`.

### Tables

#### `companies`
Represents an organisation (tenant). Created when the first user registers.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `name` | TEXT | Company display name |
| `created_at` | TIMESTAMPTZ | — |
| `updated_at` | TIMESTAMPTZ | Auto-updated by trigger |

---

#### `profiles`
Links a Supabase auth user to a company. One user → one profile.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `user_id` | UUID | FK → `auth.users` |
| `company_id` | UUID | FK → `companies` |
| `full_name` | TEXT | Optional display name |

---

#### `user_roles`
Controls what a user can do within their company.

| Column | Type | Notes |
|---|---|---|
| `user_id` | UUID | FK → `auth.users` |
| `company_id` | UUID | FK → `companies` |
| `role` | ENUM | `manager` or `viewer` |

- **manager** — Can create/edit/delete projects, costs, income, and manage team members.
- **viewer** — Read-only access to all projects and financials within the company.

---

#### `projects`
A construction project belonging to a company.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `company_id` | UUID | FK → `companies` |
| `name` | TEXT | Project title |
| `description` | TEXT | Optional |
| `client_name` | TEXT | Optional client label |
| `status` | TEXT | `active`, `completed`, or `on_hold` |

---

#### `income`
Client payments or revenue received for a project.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `project_id` | UUID | FK → `projects` |
| `amount` | DECIMAL(12,2) | KES amount |
| `description` | TEXT | Optional note |
| `invoice_reference` | TEXT | Optional invoice/ref number |
| `date` | DATE | Date of payment |
| `created_by` | UUID | FK → `auth.users` |

---

#### `costs`
All expenditure on a project, categorised by type.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `project_id` | UUID | FK → `projects` |
| `cost_type` | ENUM | `materials`, `labor`, `equipment`, `subcontractors` |
| `amount` | DECIMAL(12,2) | KES amount |
| `description` | TEXT | Required label |
| `date` | DATE | Date of cost |
| **(materials)** | | `supplier`, `quantity`, `unit_cost` |
| **(labor)** | | `worker_name`, `hours`, `hourly_rate` |
| **(equipment)** | | `equipment_name`, `rental_days`, `daily_rate` |
| **(subcontractors)** | | `contractor_name`, `invoice_reference` |
| `created_by` | UUID | FK → `auth.users` |

> Each cost type surfaces different contextual fields in the UI form.

---

#### `invitations` *(managed via Edge Functions)*
Pending email invitations to join a company. Expires after a set period.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `company_id` | UUID | FK → `companies` |
| `email` | TEXT | Invitee email |
| `role` | ENUM | `manager` or `viewer` |
| `expires_at` | TIMESTAMPTZ | Invitation expiry |
| `accepted_at` | TIMESTAMPTZ | Null until accepted |

---

## Authentication & Access Control

Authentication is handled entirely by **Supabase Auth** (email + password).

### Sign Up Flow

1. User fills in: company name, full name, email, password.
2. A new `companies` row is created.
3. A `profiles` row is created linking the user to the company.
4. A `user_roles` row is inserted with `role = 'manager'` — the founding user is always the first manager.
5. User is redirected to `/dashboard`.

### Sign In Flow

1. User enters email + password.
2. Supabase returns a JWT session.
3. `AuthProvider` (context) reads the session on load and provides `user` to the rest of the app.
4. Protected routes redirect to `/auth` if no session is found.

### Invitation Flow

1. A **manager** on the Settings page enters an email + role and clicks "Send Invitation".
2. The `send-invitation` Edge Function creates an `invitations` row and sends an email with a unique token link.
3. The invitee visits `/auth?invite=<token>`.
4. The `get_invitation_details` RPC validates the token and pre-fills the form.
5. The invitee sets their name and password, then the `accept_invitation` RPC links them to the company with the assigned role.

### Password Reset Flow

1. User clicks "Forgot password?" on the sign-in form.
2. The `send-password-reset` Edge Function is invoked to send a reset email.
3. The user visits `/reset-password` from the email link.
4. They set a new password via the Supabase Auth API.

---

## Pages & User Flows

### Landing Page (`/`)

A public-facing splash page introducing the app. Redirects authenticated users to `/dashboard`.

---

### Auth Page (`/auth`)

Handles three modes in a single view:
- **Sign In** — default mode.
- **Sign Up** — toggle to create a new company account.
- **Accept Invitation** — activated when `?invite=<token>` is in the URL; pre-fills email and skips company name entry.
- **Forgot Password** — inline sub-view to request a reset email.

---

### Dashboard (`/dashboard`)

The main home screen after login. Shows all projects belonging to the user's company.

**What it does:**
- Fetches all `projects` for the company.
- For each project, fetches the sum of `income.amount` and `costs.amount` in parallel.
- Displays each project as a card showing:
  - Project name and client name.
  - Status badge (`active`, `completed`, `on_hold`).
  - Total income, total costs, and net profit (with a trending-up/down icon).
- Hovering a project card reveals an action menu to **Edit** or **Delete** the project.
- Deleting a project cascades and removes all its costs and income.

**Navigation:**
- **New Project** button → `/projects/new`
- **Project card** → `/projects/:id`
- **Settings** → `/settings`
- **Sign Out** → clears session, redirects to `/auth`

---

### New Project (`/projects/new`)

A form for managers to create a new project.

**Fields:**
- Project Name *(required)*
- Client Name *(optional)*
- Description *(optional)*
- Status (`active` by default)

On submit, a `projects` row is created. Redirects to the new project's detail page.

---

### Project Detail (`/projects/:id`)

The financial control centre for a single project.

**Sections:**

**1. P&L Hero**
Three prominent figures at the top:
- **Total Income** (green)
- **Total Costs** (red)
- **Net Profit** — green with a trending-up icon if profitable, red with trending-down if not.

**2. Cost Breakdown Chart**
A Recharts bar/pie chart breaking costs into the four categories:
- 📦 Materials
- 👷 Labor
- 🚛 Equipment
- 🔨 Subcontractors

**3. Quick Add Panel**
Shortcut buttons to log income or costs by category. Each button also shows the current running total for that category.

**4. Recent Transactions**
A unified, date-sorted list of all income and cost entries. Each row shows:
- Category icon.
- Description and date.
- Amount (green `+` for income, red `-` for costs).
- On hover: **Edit** (pencil icon) and **Delete** (trash icon) actions.

**Adding a Cost** opens a side sheet (`AddCostSheet`) that adapts its fields to the selected cost type (e.g., shows `worker_name` and `hours` for labor).

**Adding Income** opens `AddIncomeSheet` for logging a payment with an optional invoice reference.

---

### Settings (`/settings`)

Account and team management.

**Profile section:**
- View email (read-only).
- Edit full name.

**Company section:**
- Edit company name *(managers only)*.

**Invite Team Member** *(managers only):*
- Enter an email and assign a role (`manager` or `viewer`).
- Sends an invitation email via Edge Function.
- Shows a list of pending (unexpired) invitations with the ability to cancel each.

**Team Members:**
- Lists all users in the company with their names and roles.
- Managers can remove other team members (but not themselves).

---

### Reset Password (`/reset-password`)

A standalone page (reached via email link) allowing a user to set a new password. Validates the Supabase session from the reset token before allowing the update.

---

## Key Components

| Component | Purpose |
|---|---|
| `AddCostSheet` | Slide-over form for adding or editing a cost entry. Dynamically shows fields based on cost type. |
| `AddIncomeSheet` | Slide-over form for adding or editing an income entry. |
| `CostBreakdownChart` | Recharts visualisation of costs split by category. |
| `EditProjectDialog` | Modal dialog for editing a project's name, client, description, and status. |
| `NavLink` | Wrapper for styled navigation links. |
| `AuthProvider` / `useAuth` | React context that wraps the app, exposes `user`, `signIn`, `signUp`, `signOut`, and `loading` state. |

---

## Multi-Tenant Isolation

Every table that holds business data (`projects`, `income`, `costs`) is protected by **Row Level Security (RLS)** policies in PostgreSQL. The key mechanism:

1. **`get_user_company_id(user_id)`** — A `SECURITY DEFINER` function that safely returns the `company_id` for any given user without exposing the `profiles` table directly.
2. **`has_role(user_id, company_id, role)`** — Checks whether a user has a specific role within a company.

RLS policies use these functions so that:
- Any `SELECT` query automatically filters to the current user's company.
- `INSERT`, `UPDATE`, and `DELETE` operations require the user to have the `manager` role.
- No data from another company can ever be read or written, even if a client-side bug somehow sent the wrong `company_id`.

---

## Edge Functions (Supabase)

Located in `supabase/functions/`.

| Function | Trigger | Purpose |
|---|---|---|
| `send-invitation` | Called from Settings page | Creates an `invitations` row and emails the recipient a unique join link. |
| `send-password-reset` | Called from Auth page | Sends a password reset email via a custom flow (bypasses Supabase's default reset to allow custom branding). |

---

## Running Locally

**Prerequisites:** Node.js ≥ 18, npm or bun.

```sh
# 1. Clone the repo
git clone https://github.com/macxwhale/constructledger.git
cd constructledger

# 2. Install dependencies
npm install

# 3. Set up environment variables
#    Copy .env.example → .env and fill in your Supabase project URL and anon key
#    VITE_SUPABASE_URL=https://<your-project>.supabase.co
#    VITE_SUPABASE_ANON_KEY=<your-anon-key>

# 4. Start the dev server
npm run dev
```

The app will be available at `http://localhost:5173`.

> For Supabase Edge Functions, use the Supabase CLI: `supabase functions serve`
