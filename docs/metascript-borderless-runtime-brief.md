# MetaScript Borderless Application Runtime

**Working brief · 18 October 2026 · For Codex exploration**

> **Write an application, not a frontend and a backend.**  
> **Borderless for developers; explicit boundaries for the runtime.**

## 0. Status and intent

This is a **concept brief, not an implementation spec**. It records the product thesis, architectural options, reference projects, a smallest useful proof of concept, and the questions to resolve by inspecting the actual MetaScript and Neon repositories.

**Important:** Neon here means **the MetaScript-associated UI/application framework**, **not Neon Serverless Postgres**. The publicly accessible [`cocrafts/neon`](https://github.com/cocrafts/neon) README describes a native cross-platform UI framework and currently shows **Haxe** examples and proof-of-concept platform status. Do **not** assume production-ready native TypeScript support or a particular MetaScript integration without checking the current code and roadmap.

## 1. Core thesis

Build a **unified application runtime** where a developer defines components, application state, actions, sessions and subscriptions in one TypeScript-oriented programming model. The system can execute selected behavior on the client or server, synchronize relevant state, and optionally stream **render/UI patches** from the server to native or web clients.

The central ambition is **not** to build another database or to reproduce Phoenix LiveView literally. It is to make application boundaries *composable*:

- **UI and state** are part of the same reactive model.
- **Client and server** have explicit execution locations but share types, tooling and potentially safe transition logic.
- **State-driven UI:** server synchronizes data, client computes/render updates.
- **View-driven UI:** server owns a view/session and streams a UI-tree patch.
- **Local-first interactions:** input, drag, pan, animations, canvas work without network round trips.
- **Storage-neutral persistence:** adapter-based backing stores, not a proprietary DB requirement.
- **Optional collaborative editing:** CRDT/operation merge as a separate consistency model rather than a universal default.

**One application, one language family, multiple execution placements and rendering strategies.**

## 2. Intellectual lineage — what to borrow, what not to conflate

| Reference | Actual main idea | Borrow | Do **not** assume |
|---|---|---|---|
| **Phoenix LiveView** | Server-side stateful view process handles events, re-renders, sends diffs | Session lifecycle, events, assigns, incremental UI patches, reconnect semantics | That every interaction should round-trip to server |
| **LiveView Native** | Phoenix server-driven UI mapped to SwiftUI/Jetpack Compose | Wire format, native component mapping, client patch application | It has universal production maturity on all targets |
| **SpacetimeDB** | Database-hosted reducers + subscriptions that mirror server-owned state to client | Transactional actions, server authority, incremental state subscriptions | That database-owned application modules are mandatory |
| **Replicache** | Client-side mutators, push/pull, rebase, backend-implemented sync | Optimistic local mutations, backend agnosticism, version/cursor discipline | That all client conflicts magically merge |
| **Rocicorp Zero** | Local reactive queries, optimistic mutators and server-side reconciliation | Very ergonomic developer API, consistent client cache | That its underlying Postgres/zero-cache architecture is storage-neutral |
| **TanStack DB** | Reactive local collections, incremental live queries, optimistic writes | Collections + query dependency graph; UI consumes local state | That it itself implements universal authoritative server sync |
| **Loro / Yjs / Automerge** | Collaborative document CRDTs | Offline/concurrent document operations where needed | That arbitrary relational transactions can use CRDT semantics |
| **FoundationDB** | Strictly transactional ordered KV and layers | Server storage contract and substrate | That every generic `get/put` KV provides sufficient guarantees |
| **Datomic** | Immutable facts, temporal queries, persistent indexes | Optional history / as-of reads | That EAV history should be the default hot-path data layout |
| **TigerBeetle** | Specialized durable financial ledger, deterministic replicated state machine | Testing discipline, bounded resources, deterministic simulation | That it is a general-purpose storage adapter |

**Key distinction:** LiveView synchronizes **view output**; SpacetimeDB synchronizes **application data**; Replicache/Zero coordinate **optimistic local state**; document CRDTs resolve **concurrent operations**. The proposed runtime may support all, but these are *different semantics*.

## 3. Proposed system boundaries

```text
                   Application definition (TypeScript-oriented)
             components · local/session/shared state · actions · queries
                                      |
                          MetaScript compiler/tooling
                    placement · codegen · type/ABI checking
                           /                       \
        Client runtime (Neon)                  Server runtime
        native UI rendering                    session/view processes
        local reactive state                   actions + authorization
        gesture/render hot path                 shared state + subscriptions
        client cache + optimistic queue         query/view computation
                           \                       /
                         Versioned realtime protocol
                events · state deltas · UI patches · ACK/resume
                                      |
                           Persistence adapters
                        SQLite/Postgres/transactional KV
```

**Implementation principle:** Compiler and runtime should *know* boundaries; developer should not have to stitch everything together manually. This does **not** remove the need for authority, authorization, serialization, backpressure or latency controls.

### State categories (proposed)

| Scope | Owner and semantics | Examples |
|---|---|---|
| `local` | Client-only, responsive, optionally persisted locally | focus, hover, drag preview, animation |
| `session` | Server connection/view process, reconnectable only with defined policy | wizard, inspector tab, temporary view filters |
| `shared` | Authoritative transactional server state, replicated to clients | project metadata, inventory, permissions |
| `collaborative` | Concurrent editable documents with defined merge operations | design tree, text documents |
| `ephemeral` | Best-effort, TTL/coalesced presence signals | cursor, selection preview, typing |

A scope is a **consistency/execution contract**, not a physical database type. Different scopes may share transports but should not silently inherit one another's reliability rules.

### UI execution modes (proposed)

1. **Client-driven:** local reactive data → local Neon render (for high-frequency interactions).
2. **State-driven:** server produces authorized deltas → client local cache → Neon render.
3. **View-driven:** server owns view/session → computes component-tree diff → client applies native UI patch.
4. **Hybrid island:** server-driven surrounding UI, local-native canvas/editor and input handling.

Do not attempt to automatically select modes in V1. Begin with explicit annotations/APIs, benchmark, then explore compiler-assisted placement.

## 4. Illustrative developer API (NOT existing MetaScript/Neon API)

```tsx
// Pseudocode: names and syntax are exploratory.
const project = shared<Project>("projects/42");
const inspector = session({ selectedId: null as string | null });
const dragPreview = local({ x: 0, y: 0 });

const renameProject = serverAction(async (ctx, name: string) => {
  ctx.auth.require("project:write", project.id);
  await ctx.transaction(() => project.update({ name }));
});

const BillingPanel = serverView(() => {
  const billing = readAuthorizedBilling();
  return <Panel><Text>{billing.plan}</Text></Panel>;
});

function Editor() {
  const doc = useShared(project);     // state-driven client render
  return <Layout>
    <Header title={doc.name} />
    <NativeCanvas dragPreview={dragPreview} /> // local hot path
    <BillingPanel />                  // server-rendered UI patch
  </Layout>;
}
```

The hardest problem is **consistent semantics across these modes**, not writing JSX syntax. API design must distinguish *user-controlled* state from *trusted server capabilities*.

## 5. Unified protocol: separate semantics within one channel

Use a versioned, typed transport (WebSocket initially; don't tie core semantics to WebSocket). Message families:

- `join`, `leave`, `handshake`, protocol/schema versions, capabilities.
- `event` / `action_call` / `action_result` with idempotency and auth context.
- `state_snapshot`, `state_delta`, `subscription_change` with stable revision/cursor.
- `view_snapshot`, `view_patch` with stable component IDs, ordered tree mutations and revision.
- `presence` with TTL, low-priority delivery and optional lossy coalescing.
- `ack`, `resume`, `resync_required`, `error`.

**Critical invariants:** no missing/duplicated applied commits on reconnect; consistent snapshot+stream cutover; UI patches applied only to compatible tree revisions; per-client authorized projections; backpressure and bounded memory; schema/protocol upgrade path.

**Do not** send server-private state/closures/functions to the client merely because a shared compiler generated code for both targets.

## 6. Storage adapter strategy: database optionality without false guarantees

The app runtime should own state/change-stream semantics. A backend adapter must declare capabilities, e.g. atomic batch, serializable transaction or compare-and-swap, ordered scans, durability/recovery, snapshot support. Log/version feeds may be supplied by the runtime if the database does not expose CDC.

Start with **SQLite or Postgres** as a reference adapter. Add one *truly different* transactional KV backend later (FoundationDB is a meaningful reference) to verify the abstraction. Do **not** promise arbitrary KV compatibility for authoritative transactional state.

**No new DB engine required for MVP.** Persistence is necessary for durable scopes but LiveView-like sessions and ephemeral signals can initially be held in memory with explicit restart behavior.

## 7. Sharp boundaries / non-negotiables

- **Security:** client is untrusted. Server revalidates all actions; authorization applies to queries, snapshots, deltas and UI output.
- **Responsiveness:** keystrokes, high-frequency gestures, canvas/3D must not depend on RTT.
- **Determinism:** shared client/server mutators must define treatment of time, random, I/O, execution differences and conflicts.
- **Consistency:** no accidental mixing of optimistic local state, authoritative committed state and CRDT state.
- **Availability:** define behavior for disconnect, suspend/resume, server crash and invalidated sessions.
- **Migrations:** protocol, schema and native component compatibility must be versioned.
- **Measurability:** latency, message bytes, UI patch size, rendering time and resync rate must be instrumented.

## 8. MVP: prove the thesis before building a platform

### Demo: collaborative project editor

Two clients (web first, native if current Neon support permits) view one project.

- Local canvas supports pan, zoom and drag without server trips.
- Server-owned **inspector panel** or small form accepts events and streams **view patches**.
- Shared project title/metadata changes propagate as **state deltas** to both clients.
- Presence cursors use a distinct **ephemeral** channel.
- Disconnect/reconnect resumes or performs a consistent full resync.
- One durable backing store, with a minimal transaction adapter.

### Suggested implementation sequence

1. **Repo reality check:** inspect current MetaScript native TS capabilities, Neon targets, signal/render model, available server runtime and tests.
2. **Single server session:** events → stateful view → deterministic tree diff → simple web client patch application.
3. **Shared state:** two clients, versioned snapshot+delta, server-authoritative action.
4. **Neon renderer bridge:** map a small stable component set to native UI; defer large layout/style scope.
5. **Local island:** native canvas hot path remains independent of server.
6. **Reconnect + durable adapter:** version/cursor, replay or resync, tests.
7. **Instrumentation:** demonstrate when state-vs-view updates cost fewer bytes/CPU/RTTs.

### V1 explicitly excludes

New KV/LSM database; multi-node consensus; distributed transactions; universal SQL/Datalog engine; generic CRDT layer; AI-based automatic placement; complex arbitrary JSX serialization; full offline multi-document merge; production-scale Figma clone.

## 9. Acceptance tests / success metrics

**Functional:**
- Same action converges both subscribed clients to authorized state.
- Inspector server-rendered patch changes a native/web component without manual REST endpoint wiring.
- Drag/zoom continue smoothly during simulated 300–500 ms RTT or total disconnect.
- Snapshot-to-delta transition, reordered/duplicated messages, resume and forced resync are testable.
- Unauthorized client cannot infer private fields through state or view patches.

**Measured (record baseline rather than invent targets):**
- p50/p95 input-to-paint for local, state-driven and view-driven paths.
- Bytes/action and bytes/patch vs sending full JSON/tree.
- Server CPU/memory per connected session and per active subscription.
- Initial hydration, reconnect/recovery and schema migration behavior.
- Native binary size/memory and runtime differences vs web target.

## 10. Research and source projects (official/docs/repositories)

### Highest priority — server view and native rendering

1. **Phoenix LiveView** — server assigns, event handling, lifecycle and render diffs.  
   https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html
2. **LiveView Native** — server-provided platform-specific templates mapped into native components.  
   https://github.com/liveview-native/live_view_native
3. **LiveView Native Core** — cross-platform client connection, virtual tree, patch handling; *repository says not yet production-ready*.  
   https://github.com/liveview-native/liveview-native-core
4. **LiveView Native SwiftUI / Jetpack** — renderer adapters.  
   https://github.com/liveview-native/liveview-client-swiftui  
   https://github.com/liveview-native/liveview-client-jetpack

### High priority — state synchronization and queries

5. **SpacetimeDB** — reducers, subscriptions, client state mirroring.  
   https://spacetimedb.com/docs/intro/key-architecture/
6. **Replicache** — backend-defined push/pull, local mutation reapplication and sync strategies.  
   https://doc.replicache.dev/concepts/how-it-works  
   https://doc.replicache.dev/strategies/overview
7. **Rocicorp Zero** — optimistic mutators and reconciliation against server-driven change stream.  
   https://zero.rocicorp.dev/docs/mutators
8. **TanStack DB** — reactive collection/query model with incremental updates and optimistic state.  
   https://tanstack.com/db/latest/docs/overview  
   https://tanstack.com/db/latest/docs/guides/live-queries

### Selective references — later phases

9. **Loro** — collaborative tree/data structures when offline document merging is required.  
   https://www.loro.dev/
10. **Yjs** — CRDT documents and pluggable provider pattern.  
    https://docs.yjs.dev/
11. **FoundationDB** — transactional ordered KV and layers.  
    https://apple.github.io/foundationdb/
12. **Datomic** — temporal/as-of/immutable information model (optional, not MVP).  
    https://docs.datomic.com/
13. **TigerBeetle** — deterministic state machine, crash/fault simulation and engineering discipline; *not* a general KV store.  
    https://github.com/tigerbeetle/tigerbeetle
14. **Neon project** — check actual implementation and compilation integration before designing APIs.  
    https://github.com/cocrafts/neon

## 11. Design questions Codex should answer first

1. Which Neon render nodes, reactivity primitives and native bridges already exist? Can they consume an incremental remote tree safely?
2. Does MetaScript currently compile the intended server/client TypeScript subset to native on each target? What is missing?
3. What *minimal* view-patch IR maps cleanly onto Neon without serializing arbitrary application closures?
4. Is a unified ordered channel preferable to separate streams, given priority and backpressure needs?
5. How should session state survive reconnect: process-local only, TTL snapshot, or durable state?
6. What invariant defines consistency between a committed state delta and a server-rendered UI patch?
7. When do optimistic actions re-run, rebase or get rejected? What code is safe to share client/server?
8. Which exact transaction guarantees must each storage adapter expose?
9. How are queries and view trees scoped per user so subscriptions never leak server-only data?
10. Where is the genuine MetaScript advantage: runtime footprint, native codegen, compile-time dependency analysis, shared execution model, or developer simplicity? How will it be measured?

## 12. Suggested first Codex mission

> Inspect the actual MetaScript and Neon repositories. Separate implemented capabilities from this concept brief. Produce (a) a dependency/feasibility map, (b) an ADR comparing state-delta and UI-patch protocols, and (c) a runnable minimal proof of concept with a server-owned counter/inspector and a client-owned interactive component. Prefer existing infrastructure. Do not start by building a database, consensus engine, full CRDT or generalized compiler magic. Include reproducible tests for event ordering, reconnect and authorization. Treat all code shown in this brief as illustrative pseudocode.

---

**Product positioning candidate:**

> **MetaScript + Neon: one application model across native UI, server-owned views and synchronized state — without forcing developers to assemble the frontend/backend boundary themselves.**

**Scope discipline:** First prove a native UI patch + shared state + local interaction can coexist cleanly. Build universal state/storage/collaboration features only after that works.
