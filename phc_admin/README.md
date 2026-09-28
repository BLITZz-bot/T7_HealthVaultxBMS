# T7 HealthVault — PHC Admin Panel (web)

Web dashboard for PHC supervisors / medical officers. It shares one Supabase
database with the ASHA Flutter app (`../flutter_app`), and is deployed on Vercel.

> **Current state: skeleton.** It runs with a **dummy login and in-memory demo
> data** (`VITE_BACKEND=mock`). No Supabase project is needed yet. The Supabase
> code paths and schema are written but not connected. See
> [Connecting Supabase later](#connecting-supabase-later).

## How data flows

```
 ┌──────────────────────┐        upsert on sync          ┌───────────────────────┐        read / triage       ┌─────────────────────┐
 │  ASHA Flutter app    │ ─────────────────────────────▶ │                       │ ◀───────────────────────── │  PHC Admin Panel    │
 │  (offline-first,     │  households, members, vitals,  │  Supabase             │   alerts, referrals,       │  (this repo, Vercel)│
 │   SQLite on device)  │  alerts, referrals             │  Postgres + Auth +    │   households, workers      │                     │
 │                      │ ◀───────────────────────────── │  Row Level Security   │ ─────────────────────────▶ │                     │
 └──────────────────────┘   pull on sync (+ realtime):   │  + Realtime           │   writes: alert status,    └─────────────────────┘
                            visit_tasks, alert/referral  └───────────────────────┘   referral status, tasks
                            status changed by the PHC
```

- There is **no custom backend** in between. Both clients talk to Supabase directly with
  the public anon key. **Row Level Security is the security boundary.**
- Every row carries `phc_id`. A supervisor only ever sees their own PHC. An ASHA only
  sees her own rows plus tasks assigned to her.
- The panel **reads** clinical data and **writes** workflow state: acknowledging and resolving
  alerts, updating referral status and facility, and assigning visit tasks. It never edits
  a patient's clinical record.

## Quick start (demo mode)

```bash
cd phc_admin
npm install
cp .env.example .env.local   # optional: defaults already point to mock mode
npm run dev                  # http://localhost:5173
```

Sign in with the demo credentials shown on the login page (default
`supervisor@phc.demo` / `demo1234`, configurable via `VITE_DUMMY_*`).

| Script              | What it does                        |
| ------------------- | ----------------------------------- |
| `npm run dev`       | Vite dev server                     |
| `npm run build`     | Type-check + production build → `dist/` |
| `npm run preview`   | Serve the production build locally  |
| `npm run typecheck` | TypeScript only                     |

## Project layout

```
phc_admin/
├── .env.example                 # all env vars, documented
├── vercel.json                  # SPA rewrites + security headers
├── supabase/migrations/
│   └── 0001_init.sql            # shared schema, RLS, views, realtime (not applied yet)
└── src/
    ├── config/env.ts            # reads VITE_* vars, refuses to boot if misconfigured
    ├── lib/supabase.ts          # lazy Supabase client (sessionStorage, not localStorage)
    ├── auth/
    │   ├── adapters.ts          # dummyAuth + supabaseAuth behind one interface
    │   ├── AuthContext.tsx      # session state, useSession() = the ONE identity source
    │   └── RequireAuth.tsx      # route guard
    ├── backend/
    │   ├── types.ts             # domain types (Session, Alert, Referral, VisitTask…)
    │   ├── repository.ts        # PhcRepository interface — every read/write goes here
    │   ├── mockRepository.ts    # in-memory implementation (demo mode)
    │   ├── supabaseRepository.ts# real implementation against the SQL in supabase/
    │   └── index.ts             # picks one based on VITE_BACKEND
    ├── hooks/useLiveQuery.ts    # fetch + auto-refresh on realtime changes
    ├── components/              # AppLayout (sidebar/drawer), UI primitives
    └── pages/                   # Dashboard, Alerts, Referrals, Tasks, Workers, Households, Reports*, Settings
```

\* Reports is a placeholder that lists the planned reports.

**Rule of thumb:** pages never import Supabase. They call `repository.*` with
`session.phcId`. When Supabase is connected, no page code changes.

## Deploying to Vercel

1. Push the repo to GitHub and import it in Vercel.
2. **Root Directory:** `phc_admin`. Vercel detects Vite. Build = `npm run build`, output = `dist`.
3. Environment variables (Project → Settings → Environment Variables):
   - For a demo deploy: `VITE_BACKEND=mock` (and optionally `VITE_DUMMY_EMAIL` / `VITE_DUMMY_PASSWORD`).
   - For real use: see the next section.
4. Deploy. `vercel.json` already rewrites all routes to `index.html` (so `/alerts` etc. work on refresh).

`VITE_*` vars are baked in at **build time**. After changing them, redeploy.

## Connecting Supabase later

1. **Create a project** at [supabase.com](https://supabase.com). Pick the Mumbai (ap-south-1) region for latency and data residency.
2. **Apply the schema:** open SQL Editor, paste `supabase/migrations/0001_init.sql`, and run it.
   (Or with the Supabase CLI: `supabase link` then `supabase db push`.)
3. **Create your first PHC and admin:**
   ```sql
   insert into public.phcs (code, name, block, district, state)
   values ('KA-BLR-HSK-01', 'PHC Hosakote', 'Hosakote', 'Bengaluru Rural', 'Karnataka')
   returning id;   -- copy this id
   ```
   Then go to **Authentication → Users → Add user** (email + password, auto-confirm) and copy the user's UUID:
   ```sql
   insert into public.profiles (user_id, phc_id, role, full_name)
   values ('<auth-user-uuid>', '<phc-id>', 'phc_admin', 'Dr. Your Name');
   ```
   ASHA workers are created the same way with `role = 'asha'` (phone OTP or email auth, whichever the app uses).
4. **Set env vars** (`.env.local` locally, and in Vercel):
   ```
   VITE_BACKEND=supabase
   VITE_SUPABASE_URL=https://<ref>.supabase.co
   VITE_SUPABASE_ANON_KEY=<anon public key>
   ```
   Both values are under Project Settings → API. **Use only the `anon` key, never `service_role`.**
5. **Auth settings:** in Authentication → URL Configuration, add your Vercel URL(s) to the redirect allow-list.
   Turn off public sign-ups (Authentication → Providers → Email → "Allow new users to sign up") so that only
   admin-created accounts exist.
6. Redeploy. The demo banner and demo credentials disappear automatically in `supabase` mode.

If `VITE_BACKEND=supabase` is set but the URL or key is missing, the app shows a configuration
error page instead of falling back to demo data.

## Connecting the Flutter ASHA app

Nothing in `flutter_app` has been changed yet. Here is the plan for the app side.

1. Add `supabase_flutter` to `pubspec.yaml`.
2. Pass the keys at build time. Copy `flutter_app/dart_defines.example.json` to
   `flutter_app/dart_defines.json` (gitignored), then build with:
   ```bash
   flutter run --dart-define-from-file=dart_defines.json
   ```
   ```dart
   await Supabase.initialize(
     url: const String.fromEnvironment('SUPABASE_URL'),
     anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
   );
   ```
3. **Keep SQLite as the source of truth on the device** (it's offline-first). Add a sync layer:
   - **IDs:** add a `uuid TEXT` column to `families` / `members` / `medical_records` and generate
     it on the device when a row is created. That uuid becomes the `id` in Supabase, so
     re-uploading after a flaky connection never creates duplicates.
   - **Push:** mark changed rows `dirty = 1`. When online, run
     `supabase.from('households').upsert(rows, onConflict: 'id')` in batches, then clear `dirty`.
     Every pushed row must include `phc_id` and `asha_id` (from the logged-in profile); RLS rejects anything else.
   - **Pull:** store `last_pulled_at` per table, then
     `supabase.from('visit_tasks').select().gt('updated_at', lastPulledAt)`. Do the same for
     `alerts` and `referrals`, whose status the PHC may have changed. `updated_at` is maintained by
     database triggers.
   - **Deletes:** set `deleted_at` instead of deleting rows, so deletions sync too.
   - **After a successful sync:** `update profiles set last_sync_at = now()` for the ASHA's own row.
     This drives the "not synced in 3+ days" card on the dashboard.
   - **Conflicts:** last write wins on `updated_at`. For alert and referral status, the server value wins.
4. Table mapping (SQLite → Supabase): `families` → `households`, `members` → `members`,
   `medical_records` → `vitals`. NEWS2 or sepsis results above your thresholds → insert into `alerts`.

## Security notes

- **Dummy login is not authentication.** The demo credentials are compiled into the JS bundle.
  Demo mode must never be used with real patient data.
- The Supabase **anon key is public by design**. What protects the data is RLS in
  `0001_init.sql`: every policy is scoped by `phc_id` and role, and clients can't change their
  own role or PHC.
- Never put the `service_role` key in any `VITE_*` variable or in the Flutter app.
- Sessions are stored in `sessionStorage`, so closing the browser signs the user out (PHC machines are often shared).
  There is no service worker and no offline cache of patient data in the panel.
- `vercel.json` sets `X-Frame-Options: DENY`, `nosniff`, a strict referrer policy and `no-store` on `index.html`.

## Not done yet / next steps

- Server-side pagination and search for households, since the current limit is 500 rows.
- Reports, CSV/PDF export, and a village coverage map.
- Adding and deactivating ASHA workers from the UI. This needs a Supabase Edge Function with the service role, not the browser.
- i18n (Kannada / Hindi / Marathi UI).
- Idle-timeout auto sign-out.
- ESLint and tests.
