# Technical Architecture Plan: Offline-First Sync for Notepad Pro

---

## 1. Summary

**What this addresses:** Notepad Pro currently requires an internet connection to function. Users are losing work when connectivity drops, and the app becomes completely unusable during outages or poor signal conditions. A significant subset of users work on the go or in environments with unreliable connectivity (trains, flights, co-working spaces with spotty WiFi). This plan introduces offline-first capability: the app works fully without a connection, and changes sync reliably when connectivity is restored.

---

## 2. Existing System

Notepad Pro is an existing, production web application used by approximately 4,000 paying users. The relevant existing architecture:

- **Frontend:** React SPA, bundled with Vite. State managed with Zustand. No service worker currently exists.
- **Backend:** Node.js (Express) REST API. No real-time infrastructure.
- **Database:** PostgreSQL. Notes are stored in a `notes` table with `id`, `user_id`, `title`, `content` (text), `updated_at`, `created_at`.
- **Auth:** JWT-based, tokens stored in localStorage.
- **Deployment:** Vercel (frontend), Railway (backend + Postgres).

The existing sync model is simple: every save makes a `PUT /notes/:id` request. There is no versioning, no conflict detection, and no local persistence beyond the React state (a refresh loses unsaved changes).

**This plan extends the existing system.** It does not replace it. The backend API, database, auth, and deployment remain. We are adding a sync layer on top.

---

## 3. Requirements

### 3.1 Functional Requirements

**FR-1: Offline read access**
Users must be able to open and read all of their notes when offline, including notes not recently visited.

**FR-2: Offline write access**
Users must be able to create, edit, and delete notes when offline. Changes must persist across browser refreshes and tab closes.

**FR-3: Background sync**
When connectivity is restored, all offline changes must sync to the server automatically, without user action.

**FR-4: Multi-device support**
A user editing a note on their laptop and then opening it on their phone must see the latest version. Edits from one device must reach other devices.

**FR-5: Conflict handling**
If the same note is edited on two devices while both are offline, the conflict must be resolved without data loss. Both sets of changes should be preserved where possible.

**FR-6: Sync status visibility**
Users must be able to see at a glance: whether they are online or offline, and whether all local changes have synced.

**FR-7: Deletion sync**
Deleting a note offline must propagate correctly. A note deleted on one device must not re-appear when another device syncs.

### 3.2 Non-Functional Requirements

**NFR-1: Correctness above all**
Data loss is unacceptable. If there is a conflict or an error during sync, the system must err on the side of preserving data rather than discarding it.

**NFR-2: Minimal backend changes**
The existing REST API should be extended, not replaced. We do not want to migrate to a new infrastructure stack.

**NFR-3: No new backend services**
We will not introduce Redis, a message queue, or a WebSocket server as part of this work. Railway costs and operational complexity must not increase materially.

**NFR-4: Sync latency**
When a device comes back online, pending changes should sync within 5 seconds under normal conditions.

**NFR-5: Storage limits**
Local storage must not exceed 50MB per user. If a user has too many notes to cache, we cache the most recently accessed ones.

**NFR-6: Browser support**
Must work in the last two major versions of Chrome, Firefox, and Safari. Safari's IndexedDB implementation has known quirks that must be accounted for.

**NFR-7: Graceful degradation**
In browsers that do not support service workers or IndexedDB, the app must continue to function exactly as it does today (online-only). No new breakage.

---

## 4. Solution

### 4.1 Local Storage Layer (IndexedDB via Dexie.js)

We introduce a local database in the browser using IndexedDB, accessed through the Dexie.js wrapper library. Dexie provides a clean promise-based API and handles Safari's IndexedDB quirks.

The local schema mirrors the server schema with two additions: a `syncStatus` field (`synced` | `pending` | `conflict`) and a `localVersion` incrementing counter used to detect which changes haven't been pushed yet.

All reads in the app read from IndexedDB first. Writes go to IndexedDB immediately (making them instant and offline-safe), then trigger a sync attempt.

**Addresses:** FR-1, FR-2, FR-3, NFR-5, NFR-6, NFR-7

### 4.2 Sync Protocol (Last-Write-Wins with Per-Field Timestamps)

Each note field (`title`, `content`) gets its own `updatedAt` timestamp. When syncing, we compare timestamps field-by-field rather than treating the note as a single atomic unit.

**Sync up (local → server):** We collect all notes with `syncStatus = 'pending'` and send them to a new endpoint `POST /notes/sync`. The payload includes the note ID, all fields, and their individual timestamps. The server merges per-field: for each field, whichever version has the later timestamp wins. The server returns the merged result.

**Sync down (server → local):** After pushing, we request all notes updated since our last sync (`GET /notes?since=<timestamp>`). We apply the same per-field merge locally.

**Conflict detection:** A conflict is flagged when the same field has been modified on both sides since the last successful sync, and the timestamps are within 5 seconds of each other (indicating near-simultaneous edits, not sequential ones). Conflicted notes get `syncStatus = 'conflict'` and a UI prompt is shown (see FR-5).

**Deletions:** Deletions are recorded as soft-deletes on the server (`deleted_at` timestamp added to notes table). The sync-down endpoint returns deleted note IDs so local copies can be removed. A note can only be deleted if it's synced — attempting to delete an offline note with a pending local creation simply cancels the creation instead.

**Addresses:** FR-3, FR-4, FR-5, FR-7, NFR-1, NFR-2, NFR-3

### 4.3 Sync Transport (Periodic Poll + Online Event)

Sync is triggered by two mechanisms:

1. **Connectivity restored:** The browser's `online` event fires a sync immediately.
2. **Periodic poll:** While online, sync runs every 30 seconds in the background. This picks up changes from other devices.

There is no WebSocket or SSE connection. The 30-second poll interval is acceptable given that real-time collaborative editing (two people editing the same note simultaneously) is out of scope. The goal is eventual consistency across a single user's devices.

**Addresses:** FR-3, FR-4, NFR-3, NFR-4

### 4.4 Service Worker (Precaching + Offline Shell)

A service worker is registered using Workbox (via `vite-plugin-pwa`). It precaches the app shell (HTML, JS, CSS bundles) so the app loads when offline. API requests are not intercepted by the service worker — all network logic lives in the application layer, not the service worker, keeping the sync logic easier to reason about and debug.

**Addresses:** FR-1, FR-2, NFR-7

### 4.5 Backend Additions

Two new endpoints added to the existing Express API:

- `POST /notes/sync` — accepts an array of note payloads, performs per-field merge, returns merged notes
- `GET /notes?since=<iso-timestamp>` — returns all notes (including soft-deleted) modified after the given timestamp

A `deleted_at` column is added to the `notes` table. A cleanup job runs weekly to hard-delete notes where `deleted_at` is older than 30 days.

No new services, no new infrastructure. Both endpoints are authenticated the same way as existing endpoints (JWT middleware).

**Addresses:** FR-3, FR-4, FR-5, FR-7, NFR-2, NFR-3

### 4.6 Sync Status UI

A persistent status indicator in the app header shows:
- **Cloud icon (filled, green):** All changes synced.
- **Cloud icon (upload arrow, amber):** Changes pending sync.
- **Cloud icon (crossed out, grey):** Offline. Changes will sync when connection is restored.
- **Warning icon (red):** One or more notes have a conflict requiring resolution.

Clicking the warning icon opens a conflict resolution panel showing both versions of the conflicted field side by side with options to keep either or both (appended).

**Addresses:** FR-5, FR-6

---

## 5. Implementation Plan

### Phase 1: Backend foundations
*Get server-side sync infrastructure in place before touching the client, so it can be deployed and tested independently.*
- Add `deleted_at` column to `notes` table (migration)
- Add per-field timestamps (`title_updated_at`, `content_updated_at`) to the `notes` table
- Implement `POST /notes/sync` endpoint with per-field merge logic
- Implement `GET /notes?since=<timestamp>` endpoint including soft-deleted notes
- Write integration tests for both endpoints

### Phase 2: Local storage layer
*Wire up IndexedDB so the frontend persists data locally — the app won't sync yet, but writes survive a refresh.*
- Install and configure Dexie.js
- Define local schema mirroring server schema, adding `syncStatus` and `localVersion` fields
- Replace all note reads with IndexedDB-first reads
- Replace all note writes with IndexedDB-first writes (fire-and-forget API call as before)

### Phase 3: Sync engine
*Connect the local store to the server — after this phase the app is functionally offline-first.*
- Implement sync-up logic (collect `pending` notes, POST to `/notes/sync`)
- Implement sync-down logic (GET since last sync timestamp, apply per-field merge)
- Wire `online` event to trigger sync on reconnect
- Wire 30-second polling interval while online
- Implement conflict detection and set `syncStatus = 'conflict'` on affected notes

### Phase 4: Service worker
*Make the app shell load when fully offline.*
- Install `vite-plugin-pwa` and configure Workbox
- Precache HTML, JS, and CSS bundles
- Test offline app load in Chrome DevTools and Safari

### Phase 5: Sync status UI & conflict resolution
*Surface sync state to the user and provide a path to resolve conflicts.*
- Build sync status indicator component (synced / pending / offline / conflict states)
- Add indicator to app header
- Build conflict resolution panel (side-by-side diff, keep either or both)
- End-to-end QA: offline editing, multi-device sync, conflict flow

---

## Appendix: Key Decisions

---

### Decision 1: Local Storage Mechanism

**What's needed:** A way to persist note data in the browser so it survives offline periods and page refreshes.

**Options considered:**

**Option A: localStorage**
- Pro: Simple API, universally supported.
- Con: Synchronous, which blocks the main thread on large reads/writes. 5MB storage limit — easily exceeded. No indexing, so querying "all notes modified since timestamp" requires scanning everything. Not appropriate for structured data at this volume.

**Option B: IndexedDB (raw API)**
- Pro: Asynchronous, large storage quota, supports indexing and cursors.
- Con: Notoriously verbose and error-prone API. Lots of boilerplate for even simple operations. Safari has had significant bugs (especially around private browsing and version upgrades).

**Option C: IndexedDB via Dexie.js** ✓ *Selected*
- Pro: Clean promise-based API over IndexedDB. Handles Safari quirks. Actively maintained. Excellent TypeScript support. Tiny footprint (~24KB gzipped).
- Con: Adds a dependency. Minor abstraction overhead.

**Option D: SQLite via WASM (e.g. sql.js or wa-sqlite)**
- Pro: Full SQL, very expressive queries.
- Con: 1MB+ WASM binary to load. Experimental persistence in browsers (requires OPFS, which is not universally supported). Significant complexity for what is essentially a key-value store.

**Decision:** Dexie.js. The API improvement over raw IndexedDB is substantial and the dependency cost is trivial. WASM-based SQLite is premature — we don't need SQL, we need indexed key-value storage.

---

### Decision 2: Conflict Resolution Strategy

**What's needed:** A way to handle the case where the same note is edited on two devices while offline.

**Options considered:**

**Option A: Last-write-wins (whole note)**
- Pro: Simple to implement. No user-facing conflict UI needed.
- Con: Silently discards data. If a user writes a paragraph on their phone while offline and also edits the title on their laptop, the phone sync wipes the title change or vice versa. This violates NFR-1.

**Option B: Operational Transforms (OT)**
- Pro: True real-time merge. What Google Docs uses. Can merge character-level edits from two users.
- Con: Extremely complex to implement correctly. Requires server-side operation log. Significant ongoing maintenance burden. Total overkill — we are not building collaborative editing, just single-user multi-device sync.

**Option C: CRDTs**
- Pro: Mathematically correct merge without coordination. Libraries like Yjs or Automerge exist.
- Con: Meaningful conceptual overhead. Requires storing CRDT state (not just note content), which changes the data model substantially. Yjs/Automerge add ~100KB+ to bundle. Again, overkill for single-user sync.

**Option D: Per-field last-write-wins with conflict flagging** ✓ *Selected*
- Pro: Granular enough to handle the common case (editing different fields on different devices) automatically. Surfaces genuine conflicts to the user rather than silently discarding data. Simple to implement with timestamps. No new libraries.
- Con: Timestamp comparison is imperfect if clocks are skewed between devices. Does not handle concurrent edits to the same paragraph. But: for single-user notes (not collaborative editing), paragraph-level conflicts are rare and a manual resolution UI is acceptable.

**Decision:** Per-field LWW with conflict flagging. OT and CRDTs solve a more complex problem than we have. Full whole-note LWW is dangerous for NFR-1. Per-field LWW hits the right point on the complexity/correctness curve for our use case.

---

### Decision 3: Sync Transport Mechanism

**What's needed:** A way for changes to propagate from server to all of a user's devices, and for offline changes to push back to the server.

**Options considered:**

**Option A: WebSockets**
- Pro: True real-time push. Other devices see changes immediately.
- Con: Requires a persistent connection. Node.js on Railway can handle this, but it complicates deployment (sticky sessions needed for multi-instance scaling). Adds operational complexity (connection management, reconnect logic, heartbeats). Violates NFR-3.

**Option B: Server-Sent Events (SSE)**
- Pro: Push from server, simpler than WebSockets (HTTP-based). Good browser support.
- Con: Still requires a persistent connection on the server. Same operational concerns as WebSockets, though lighter. SSE is one-directional, so we still need REST for writes.

**Option C: Polling** ✓ *Selected*
- Pro: Dead simple. Stateless. No new infrastructure. Works identically whether Railway runs one instance or ten. Easy to test.
- Con: Not real-time — 30 seconds of latency for cross-device updates. Slightly wasteful (requests even when nothing changed).

**Decision:** Polling, 30-second interval. Real-time cross-device sync is desirable but not required. The use case is a single user's devices (not collaboration), and 30-second latency is entirely acceptable. A WebSocket or SSE server would add meaningful operational overhead that isn't justified by the benefit at this scale.

---

### Decision 4: Service Worker Scope

**What's needed:** The app shell (HTML/JS/CSS) needs to load when offline.

**Options considered:**

**Option A: Service worker handles all network requests (full proxy)**
- Pro: Can serve cached API responses, enabling offline reads without IndexedDB for notes that were fetched while online.
- Con: Two layers of caching (service worker + IndexedDB) with different invalidation logic creates hard-to-debug inconsistencies. Service worker caching strategies (stale-while-revalidate, etc.) are subtle and easy to misconfigure. Testing service workers is painful.

**Option B: Service worker precaches app shell only; app code handles data** ✓ *Selected*
- Pro: Clear separation of concerns. Service worker does one thing: serve the app offline. All sync logic lives in the app where it's testable. Much simpler to reason about.
- Con: Slightly more work in the application layer. API responses are not cached by the service worker (but IndexedDB handles this anyway).

**Decision:** App-shell-only service worker. Putting sync logic in the application code (not the service worker) makes it vastly easier to write, test, and debug. IndexedDB already handles data persistence — there's no need for a second caching layer.
