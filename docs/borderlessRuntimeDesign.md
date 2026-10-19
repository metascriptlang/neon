# Borderless application data runtime

Reference-backed proposal, investigated 2026-10-18 with an extended SpacetimeDB source trace on 2026-10-19. The golden path, composable open-source/self-hosted stack, managed freemium/SaaS offering and database requirements below are approved product direction. Runtime/API/protocol details remain recommendations, not implementation approval. No data runtime, database binding, sync service or compiler feature was implemented in this investigation.

The [original brief](metascript-borderless-runtime-brief.md) remains background. The product is a Firebase/Vercel-like application environment for MetaScript and Neon: ship an app with its backend without assembling a backend stack. An autonomous client database remains a requirement, not server-owned views or a disposable subscription cache.

## 1. Approved product contract

The golden path is **create a project → sign in for shared data → define/query data → execute an authorized action → see reactive UI updates → preview → publish**. Ordinary application CRUD needs no handwritten endpoints. Custom privileged functions remain explicit escape hatches. Local-only projects need no account; offline writes distinguish local durability from server confirmation.

The delivery model is **open-source composition plus managed convenience**, not an opaque hosted service:

- The self-hostable application stack is open source, including the client SDK, data/runtime core, public protocols and reference adapters needed to run it. Self-hosters own their infrastructure and operations.
- The commercial cloud packages, provisions and operates that stack as a freemium/SaaS product. It sells a managed deployment, not exclusive access to the application's core runtime. License choice, pricing, quotas and cloud packaging details are not settled here.
- The golden path is a supported default composition. Authors can use packages independently and replace supported boundaries through explicit adapters rather than forking the core. Composable does not mean every storage or service backend is semantically interchangeable.
- Managed and self-hosted deployments preserve the same declared schema, actions, policies and client consistency contract. Credentials, placement and operational setup may differ. An adapter declares capabilities and passes the relevant conformance corpus; unsupported behavior fails explicitly instead of silently weakening durability, authorization or atomicity.

The proposed first complete example is a task/project app with sign-in, authorized shared data, an action, reactive UI and a deployed preview. It also exercises offline persistence/reconnect and one explicitly online privileged function. Success is that end-to-end author workflow, not a standalone engine benchmark.

### Required database capabilities

1. **Embedded application execution:** the database loads and runs application logic. Authors do not assemble a separate application server. Managed cloud owns operations; this does not mean distributed database nodes cease to exist or self-hosting needs no operations.
2. **Distribution within one logical database:** partition data and workload across machines, with horizontal growth, rebalancing and recovery. Many independent projects/databases on different machines do not meet this requirement. A database-wide single-writer engine is not the production target.
3. **Code-native queries:** ordinary MetaScript query functions are delivered to and executed inside the database, through a candidate Wasm or Raiser runtime. This is not a MetaScript facade generating SQL. Datomic informs snapshots/indexed queries, but its Datalog surface and Peer execution are not this code-shipping contract.
4. **Reuse durable storage:** prefer an established lower storage engine such as RocksDB where it fits. RocksDB alone is local storage, not sharding, consensus or distributed transactions. A reusable distributed transactional store may already include the local storage layer; do not build those mechanisms twice.

### Proposed runtime direction

Build a **programmable distributed application database**, with offline-capable client replication:

- An embedded, persistent database on the device, with local queries, transactions and reactive results. It is not a disposable subscription cache.
- A deployed database module: schema, registered mutations, executable queries and permissions. Ordinary shared mutations need no handwritten HTTP endpoints.
- An execution runtime inside the logical database, not a separately authored backend facade. It authenticates commands and executes application code within database transaction/capability boundaries; it never trusts client-computed writes.
- A logical query/index/transaction layer over a proven storage boundary. Guest execution, query planning and distributed storage are distinct responsibilities: a VM does not automatically optimize or parallelize arbitrary code, and a KV connector is not a database engine.
- Commands travel upstream; authorized data changes and mutation outcomes travel downstream. Local prediction is reconciled against authoritative commits.
- Managed cloud and an own-backend deployment implement the same sync contract. They do not create different client consistency models.

A SQL engine underneath is excluded, not merely SQL syntax in the public API. The earlier SQLite recommendation is superseded. The logical query/index engine and its native/browser persistence adapters remain unselected; existing SQLite probes are comparative evidence only. A KV connector alone does not supply queries, indexes, transactions, recovery or scalable authority. No arbitrary distributed-KV backend or horizontal write-scaling guarantee is established.

Keep the data package independent of Neon. Neon supplies a thin subscription/owner bridge. Ion keeps packaging and native host ownership; the compiler stays general-purpose. A project can use the data runtime without a UI.

This is a **new framework subsystem**, assembled from existing mechanisms, not an existing Neon API. Any compiler capability extension, reducer VM or novel reconciliation algorithm needs its own reference trace and approval before implementation.

## 2. What the references actually support

Repositories were read at these commits. Source links are pinned; line numbers below accompany symbols, not replace them.

| Reference | Commit | Role |
|---|---|---|
| SpacetimeDB | `7cdacda31593d3829e60aa3f2a4670aec1c758fe` | module execution, authority, subscriptions and confirmed reads |
| Rocicorp mono | `512baff4bc8384f0ddc6b68818c9b2e8d857bf02` | Replicache replay; Zero transaction receipts and framed updates |
| Firebase JS SDK | `d7bb0e16f2b13ba15f74b690596eb70ef145d4f6` | durable local mutations, overlays, rejection and user transitions |
| Triplit | `d3029ee13e747abeeab8cf5bf64427f77a142e1f` | client database/outbox, server permissions and schema handshake |
| SQLSync | `7dc1af6b082023982fd2697f913f5b27453747f1` | SQLite plus local reducers/coordinator/rebase; not a production dependency recommendation |
| celld | `90b43017241f81189453d326d05948f388b34652` | ownership/fencing and durability-gated outputs; its SQLite data path is not a storage candidate |

### Source ledger

- **R1 — authoritative execution.** SpacetimeDB [`module_host_actor.rs:1161`, `call_reducer_with_tx_inner`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/core/src/host/wasm_common/module_host_actor.rs#L1161): a serializable transaction encloses reducer execution and view refresh; final commit/broadcast happens afterward. [`module_subscription_actor.rs:2041`, `commit_and_broadcast_event`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/core/src/subscription/module_subscription_actor.rs#L2041) holds the subscription lock across commit to avoid duplicate updates.
- **R2 — snapshot/stream cutover.** SpacetimeDB [`module_subscription_actor.rs:1587`, `subscribe_query_sets`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/core/src/subscription/module_subscription_actor.rs#L1587): compilation, registration and initial evaluation share a transaction and offset. `subscribe_batch_applies_sets_and_reports_errors` is a test pin in that file; it was read, not executed here.
- **R3 — durability and client cache.** SpacetimeDB [`client_connection.rs`, `ClientConnectionReceiver::recv_many`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/core/src/client/client_connection.rs#L209) waits for the durable offset when confirmed reads are requested. SDK [`db_connection_impl.ts:1113`, `#replaySubscriptions` / `#applyReplayBatch`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/bindings-typescript/src/sdk/db_connection_impl.ts#L1113) reconciles a replay snapshot before callbacks. `#callReducerGeneric` at 1986 refuses disconnected calls. [`v2.rs`, `ClientMessage`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/client-api-messages/src/websocket/v2.rs#L10) defines `request_id` as response correlation, not a durable idempotency receipt. SDK `tests/table_cache_reconnect.test.ts`, `preserves unchanged rows and adjusts overlapping subscription references`, is a read-only test pin.
- **R4 — prediction and replay.** Replicache [`replicache-impl.ts:1978`, `#mutate`](https://github.com/rocicorp/mono/blob/512baff4bc8384f0ddc6b68818c9b2e8d857bf02/packages/replicache/src/replicache-impl.ts#L1978) commits to `memdag`, fires subscriptions, then schedules persistence. `persist` at 1405 and `close` at 950 are separate paths. [`db/rebase.ts`, `rebaseMutation`](https://github.com/rocicorp/mono/blob/512baff4bc8384f0ddc6b68818c9b2e8d857bf02/packages/replicache/src/db/rebase.ts#L37) reruns pending commands; a throwing prediction is abandoned without dropping the command. `db/rebase.test.ts`, `a mutator that throws does not block replay of later mutations`, is a read-only pin. Missing-mutator substitution with a no-op is deliberately not adopted.
- **R5 — authoritative deduplication and outcomes.** Zero's current custom-mutation path [`process-mutations.ts`, `#transactImpl` / `#checkAndIncrementLastMutationID`](https://github.com/rocicorp/mono/blob/512baff4bc8384f0ddc6b68818c9b2e8d857bf02/packages/zero-server/src/process-mutations.ts#L720) updates the mutation sequence and invokes the callback in one transaction; application failure can be durably recorded without rerunning the failed callback. [`zql-database.ts:47`, `transaction`](https://github.com/rocicorp/mono/blob/512baff4bc8384f0ddc6b68818c9b2e8d857bf02/packages/zero-server/src/zql-database.ts#L47) supplies transactional sequence/result hooks. This is not the older CRUD authorizer path in `zero-cache/services/mutagen`, which can acknowledge blocked writes without a write effect. Server suites were not run.
- **R6 — receive framing.** Zero [`zero-poke-handler.ts:93`, `handlePokeStart` / `handlePokePart` / `handlePokeEnd`](https://github.com/rocicorp/mono/blob/512baff4bc8384f0ddc6b68818c9b2e8d857bf02/packages/zero-client/src/client/zero-poke-handler.ts#L93) assembles a complete poke before playback; `mergePokes` checks cookie gaps. Replicache [`sync/pull.ts`, `handlePullResponse`](https://github.com/rocicorp/mono/blob/512baff4bc8384f0ddc6b68818c9b2e8d857bf02/packages/replicache/src/sync/pull.ts#L210) validates the base cookie and monotonic mutation acknowledgments before applying a patch.
- **R7 — local durability and rejection.** Firebase [`local_store_impl.ts:318`, `localStoreWriteLocally`](https://github.com/firebase/firebase-js-sdk/blob/d7bb0e16f2b13ba15f74b690596eb70ef145d4f6/packages/firestore/src/local/local_store_impl.ts#L318) records mutation batches and overlays inside a persistence transaction. `localStoreAcknowledgeBatch` at 428 and `localStoreRejectBatch` at 487 atomically update their corresponding local state. [`sync_engine_impl.ts:532`, `syncEngineWrite`](https://github.com/firebase/firebase-js-sdk/blob/d7bb0e16f2b13ba15f74b690596eb70ef145d4f6/packages/firestore/src/core/sync_engine_impl.ts#L532) publishes after the local-store operation and does not send a mutation that failed to persist. Its user write callback is not the proposed local-durable receipt below: successful-write callbacks run through `syncEngineApplySuccessfulWrite` at 748.
- **R8 — identity, resume and migration.** Firebase `local_store_impl.ts:258`, `localStoreHandleUserChange`, changes mutation queues; `localStoreApplyRemoteEventToLocalCache` at 569 persists target membership, resume metadata and document updates in one transaction. `sync_engine_impl.ts:1185`, `syncEngineHandleCredentialChange`, rejects old-user pending-write waiters. [`persistence_spec.test.ts`](https://github.com/firebase/firebase-js-sdk/blob/d7bb0e16f2b13ba15f74b690596eb70ef145d4f6/packages/firestore/test/unit/specs/persistence_spec.test.ts#L24) pins `Local mutations are persisted and re-sent` and `Mutation Queue is persisted across uid switches (with restarts)`; [`write_spec.test.ts`, `Failed writes are released immediately.`](https://github.com/firebase/firebase-js-sdk/blob/d7bb0e16f2b13ba15f74b690596eb70ef145d4f6/packages/firestore/test/unit/specs/write_spec.test.ts#L421) pins permission rejection. These tests were read, not run. `indexeddb_schema_converter.ts`, `createOrUpgrade`, is persistence-format migration, not application-schema compatibility.
- **R9 — full-stack DB and permissions.** Triplit [`entity-store-with-outbox.ts:21`, `EntityStoreWithOutbox`](https://github.com/aspen-cloud/triplit/blob/d3029ee13e747abeeab8cf5bf64427f77a142e1f/packages/db/src/entity-store-with-outbox.ts#L21) overlays durable buffers on confirmed data. [`sync-connection.ts`, `handleConnectQueryMessage` / `handleChangesMessage`](https://github.com/aspen-cloud/triplit/blob/d3029ee13e747abeeab8cf5bf64427f77a142e1f/packages/server-core/src/sync-connection.ts#L301) applies read permissions and validates writes with the server session. `start` and `handleSchemaResponseMessage` negotiate schema compatibility. [`storage.ts`, `DEFAULT_STORAGE_OPTION`](https://github.com/aspen-cloud/triplit/blob/d3029ee13e747abeeab8cf5bf64427f77a142e1f/packages/client/src/storage.ts) is `memory`; full DB functionality does not imply durable-by-default storage. Its client outbox is change-oriented, not the proposed command-replay contract.
- **R10 — SQLite reducer reference and limits.** SQLSync [`local.rs`, `LocalDocument::mutate` / `rebase`](https://github.com/orbitinghail/sqlsync/blob/7dc1af6b082023982fd2697f913f5b27453747f1/lib/sqlsync/src/local.rs#L99), [`timeline.rs`, `apply_mutation` / `rebase_timeline` / `apply_timeline_range`](https://github.com/orbitinghail/sqlsync/blob/7dc1af6b082023982fd2697f913f5b27453747f1/lib/sqlsync/src/timeline.rs#L52), and `coordinator.rs`, `CoordinatorDocument::step`, provide local execution, acknowledged-prefix trimming and authoritative ordering. `apply_mutation` commits the SQLite operation before appending to its separate journal; this source is not proof of the single durable data/outbox boundary required here. `reducer.rs`, `WasmReducer`, uses an explicit Wasm host ABI. Do not assume its runner is already a MetaScript capability. Its [guide](https://github.com/orbitinghail/sqlsync/blob/7dc1af6b082023982fd2697f913f5b27453747f1/GUIDE.md#L1) warns against production use. Its storage-journal replication is not a permission-filtered row protocol.
- **R11 — Datomic concepts, not engine source.** Official [transaction model](https://docs.datomic.com/transactions/model.html), [ACID](https://docs.datomic.com/transactions/acid.html), [transaction functions](https://docs.datomic.com/transactions/transaction-functions.html) and [clients/peers](https://docs.datomic.com/reference/clients-and-peers.html), read 2026-10-18: immutable database values, a time basis, speculative `with`, conditional transactions, and local peer query execution. Datomic's engine source was unavailable; `~/projects/datomic-client-examples/examples/tutorial.clj`, the as-of/history examples, is consumer evidence only. No claim of a Datomic engine source trace or runnable Datomic probe.
- **R12 — storage isolation.** [SQLite isolation](https://www.sqlite.org/isolation.html): WAL permits read snapshots alongside a writer; same-connection reads inside a write see that write. This does not give arbitrary historical `as-of` values, and does not establish browser VFS parity.

- **R13 — hosting authority and durability, not a query engine.** celld [`ownership_store.rs`, `BucketOwnership`](https://github.com/denoland/celld/blob/90b43017241f81189453d326d05948f388b34652/crates/celld/ownership_store.rs#L386) adapts conditional bucket writes for ownership. [`output_gate.rs:283`, `durable_reached` / `ownership_verified`](https://github.com/denoland/celld/blob/90b43017241f81189453d326d05948f388b34652/crates/logic/output_gate.rs#L283) requires a covering durability proof and checks ownership for bucket proofs before releasing output. [`db.rs`, SQLite database lifecycle](https://github.com/denoland/celld/blob/90b43017241f81189453d326d05948f388b34652/crates/ltx/src/db.rs#L1) captures SQLite WAL into LTX; replacing SQLite is not a generic storage-adapter swap. These paths were read, not exercised here.

### Extended SpacetimeDB trace (2026-10-19)

The existing clean checkout is `~/projects/spacetimedb`, at the commit above; it was reused, not cloned again or updated. This is a source-path inspection, not a runtime benchmark or a completed audit of every cloud deployment mode.

- **R14 — code-defined reads already exist.** [`modules/sdk-test-view/src/lib.rs:85`, `my_player` / `my_player_and_level` / `players_at_level_0` / `nearby_players`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/modules/sdk-test-view/src/lib.rs#L85) implement unique-index reads, a join and ordinary code filters inside database views. SDK [`table.rs`, the generic `filter` helper](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/bindings/src/table.rs#L1411) selects a point/range host call; it does not compile the whole Rust function into SQL. [`wasm_instance_env.rs:786`, `datastore_index_scan_range_bsatn`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/core/src/host/wasmtime/wasm_instance_env.rs#L786) validates guest memory and calls [`instance_env.rs:791`, `datastore_index_scan_range_bsatn_chunks`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/core/src/host/instance_env.rs#L791). The range read forwards through [`RelationalDB::index_scan_range`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/engine/src/relational_db.rs#L1622) to [`MutTxId::index_scan_range`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/datastore/src/locking_tx_datastore/mut_tx.rs#L2092); its inner iterator combines transaction-local and committed indexes while excluding deleted rows. The inspected scan collects encoded rows into host-owned chunks before exposing an iterator handle; this is not evidence of bounded-memory streaming. It is a reference for a database execution ABI, not distributed query planning.
- **R15 — execution and view refresh share transaction fate.** R1 encloses reducer code, successful hooks and affected-view refresh before commit. Concrete [`wasmtime_module.rs:683`, `call_view`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/core/src/host/wasmtime/wasmtime_module.rs#L683) invokes the guest export; SDK [`rt.rs:1458`, `__call_view__`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/bindings/src/rt.rs#L1458) dispatches the registered view with decoded arguments and writes its serialized result. [`module_host_actor.rs:1521`, `call_view_with_tx`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/core/src/host/wasm_common/module_host_actor.rs#L1521) executes view code and materializes returned rows; an alternative return path can supply raw SQL. [`wasmtime/mod.rs`, `wasmtime_config`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/core/src/host/wasmtime/mod.rs#L90) enables fuel and epoch interruption. That does not prove every database host-call cost is bounded by guest fuel.
- **R16 — the inspected engine is database-wide locking, not shardable persistence.** [`datastore.rs:67`, `Locking`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/datastore/src/locking_tx_datastore/datastore.rs#L67) holds `CommittedState` behind one `RwLock`. `begin_mut_tx` at 1013 takes its write guard for the transaction. [`committed_state.rs:72`, `CommittedState`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/datastore/src/locking_tx_datastore/committed_state.rs#L72) owns tables; [`btree_index.rs:12`, `BTreeIndex`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/table/src/table_index/btree_index.rs#L12) maps keys to in-memory row pointers. A replacement log store does not remove that write guard, distribute table/index access or make one database's data path horizontally scalable.
- **R17 — durability is a log boundary, not a KV query adapter.** [`durability/src/lib.rs:127`, `Durability` / `History`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/durability/src/lib.rs#L127) expose transaction append, durable offsets and ordered history. [`relational_db.rs:924`, `commit_tx`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/engine/src/relational_db.rs#L924) requests durability before releasing the commit guard. [`local.rs:321`, `flush_and_sync`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/durability/src/imp/local.rs#L321) advances the durable offset after sync; R3 gates confirmed reads on it. [`relational_db.rs:282`, `open`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/engine/src/relational_db.rs#L282) chooses a snapshot no newer than durable history, restores and replays. [`replay.rs:492`, `rebuild_state_after_replay`](https://github.com/clockworklabs/SpacetimeDB/blob/7cdacda31593d3829e60aa3f2a4670aec1c758fe/crates/datastore/src/locking_tx_datastore/replay.rs#L492) rebuilds schema/tables/indexes afterward.

Related regression pins read, **not run**: `module_host_actor.rs` `test_dedup_anonymous_view_calls` and `test_distinct_sender_scoped_view_calls`; `relational_db.rs` `test_multi_column_index`, `tries_older_snapshots`, `load_1_2_quickstart_from_snapshot_test` and `load_1_2_quickstart_without_snapshot_test`; `crates/smoketests/tests/standalone/views.rs` `test_repair_stale_sender_scoped_view_backing_table_on_startup` and `test_repair_stale_anonymous_view_backing_table_on_startup`.

Use the embedded module/transaction/host-ABI mechanisms as references. Do not treat SpacetimeDB's current in-memory row/index layout or database-wide lock as the distributed foundation, and do not mistake a `Durability` implementation for the required transactional KV/data-access boundary. No SpacetimeDB suite, live instance, throughput benchmark or crash probe ran in this trace.

Reference mechanisms are architectural evidence, not permission to copy their code. SpacetimeDB's root BSL restricts production instance count and commercial Database Services, with directory-specific terms; it is not an open-source license for the proposed platform. celld's root license is Apache-2.0. Check applicable licenses before any adoption or port; this proposal neither adopts SpacetimeDB's engine nor selects our own license.

## 3. What the author writes

One project has explicit shared, client and authority entries:

```text
app/data/schema.ms       declared tables, keys, scalar types and sync scopes
app/data/mutations.ms    registered replayable mutations and argument schemas
app/data/queries.ms      executable MetaScript query functions
app/client.ms            Neon app plus local data connection
app/authority.ms         mutation registry, server policies and privileged functions
```

These are proposed project roles, not generated files or existing APIs. The same mutation declaration is imported into the client DB-owner entry and the authority entry. Builds register ordinary functions by stable ID/version; IPC sends data, not function objects. No automatic code placement, uploaded closures or Neon-specific compiler pass is assumed.

Illustrative API, uncompiled and not a promise about current MetaScript bindings:

```ts
const renameProject = defineMutation("project.rename", 1,
  (tx: SharedTx, args: RenameArgs) =>
    tx.projects.patch(args.id, { name: args.name },
      { expect: { name: args.expectedName } })
);

const saved = await data.mutate(renameProject, args);
if (saved.ok) {
  showSavedLocally(saved.value.id);
} else {
  showLocalWriteError(saved.error);
}
```

Minimum public surface, with names still provisional:

| Operation | Contract |
|---|---|
| `open` | persistent namespace, declared schema, local-only or synced scope; recoverable error if persistence cannot open |
| `query` | execute a declared MetaScript query inside an explicit local or authority DB context, with scoped reads and typed results; artifact loading/transport remains unselected |
| `watchQuery` | observe a parameterized local query plus immutable snapshot/coverage; returns an explicit disposer; the Neon adapter owns that disposer |
| `mutate` | registered handler plus typed arguments; returns a recoverable local-durable receipt, not a remote-commit promise |
| `watchMutation` | observe durable pending/terminal status by command identity, including after restart |
| `attach` | explicit, collision-checked import from a standalone local project into a new remote scope |
| `invoke` | explicitly online, authenticated server-only function; no automatic offline payment/job replay |

`mutate` returns a recoverable local write result only after its durable transaction. It does not await connectivity. Mutation status is observable again by ID after reopening: `pending`, `confirmed`, `rejected`, or `blocked` with a named cause. A query snapshot carries immutable result data, a local publication token and coverage/freshness information. A `local-only` scope returns a durable local-only receipt, needs no account, and does not create an indefinitely pending cloud command.

Shared tables are writable only through registered mutations. Writes bypassing that API must fail before changing shared data because otherwise no command would enter the outbox. Local-only tables allow ordinary local transactions and survive resync. Multiple shared-table writes in one mutation are atomic within one sync scope.

Authority policies run with server-derived identity and current authoritative state; they are not trusted client arguments and do not have to be shipped in the client bundle. Privileged functions have an explicitly online API and server-only dependencies. Payment/email/HTTP side effects do not run in replayable mutations; reliable post-commit work uses an idempotent job/outbox path, not a claim of exactly-once external effects.

### Execution boundary

The database runner must load and execute declared MetaScript query/action code, not translate it to SQL or expose an external handwritten backend. Wasm and Raiser are candidates; module format, loading/call ABI and resource/capability enforcement remain unselected and unproved here. Deploying a module versus submitting code per query is an unresolved delivery detail, not permission to ship captured UI objects or secrets. Code admission/compilation and execution both need isolation and resource limits before accepting untrusted tenants. Do not infer a secure multi-tenant sandbox from type checking or a VM loop limit. A mutation receives only scoped transaction operations; transaction handles cannot outlive the call. The browser DB worker loads the registered module, rather than trying to structured-clone a UI callback.

Replayable mutations must not depend on ambient time, fresh randomness, network I/O or mutable UI state. Generate stable inputs once, before enqueueing; repeatable DB reads run inside the transaction. The initial API contract follows Zero's replayable-function discipline: this pass did **not** prove a sound MetaScript effect/purity checker. Do not advertise compile-time purity enforcement. Capability-limited execution is a production requirement for untrusted modules; a verified compile-time effect system remains a separate, unproved mechanism. SQLSync's Wasm runner is reference material, not a selected implementation or proof of the required sandbox.

## 4. Storage and consistency contract

The client keeps four logical categories in one persistent store:

| Category | Lifetime/authority |
|---|---|
| confirmed scope data | authorized projection from the authority; replaceable by a complete resync |
| pending commands and their predicted working state | local durable intent; never cleared merely to repair sync |
| receipts/checkpoints/version metadata | durable processing and recovery state |
| local-only application data | device-owned; never overwritten by remote snapshots |

These do not mandate four physical databases or a SQL layout. Confirmed data, working data and outbox/status/metadata need a proven atomic commit boundary in the selected non-SQL engine. Start by measuring a full rebuild of the working scope from confirmed data plus pending commands. More selective reconciliation or query maintenance requires a measured consumer; no implementation of this non-SQL boundary was proved here.

Minimum persistent metadata, proposed rather than an existing schema:

| Store | Required key/invariant |
|---|---|
| client `sync_state` | namespace key; active projection/epoch/cursor/publication token move with received data |
| client `streams` | stream ID, identity/scope binding, next sequence and observed outcome watermark; sequence allocation shares the enqueue transaction |
| client `outbox` | primary key `(stream,sequence)`, also the public mutation identity; immutable handler ID/version/args/canonical payload hash plus prediction diagnostic |
| client `mutation_status` | mutation ID; durable terminal result and preserved rejected arguments after removal from the active outbox |
| authority `streams` | authenticated binding, processed sequence, observed sequence and explicit retirement marker |
| authority `receipts` | primary key `(stream,sequence)`; payload hash, terminal result and commit reference; committed with the write or rejection |
| authority `changes` | ordered commit reference and changes sufficient for scope snapshot/stream cutover; never served without projection authorization |

Runtime metadata is not application-writable. Business tables are separate from these tables; local-only tables are outside remote replacement. IDs and counters use the canonical codec rather than a sanitized filename as identity.

**Local transaction:** validate command/version/coverage; reserve its stream sequence; execute against the working view; write the command, status and sequence; commit; only then publish durable query results and return the receipt. On any error, neither the command nor its writes are accepted. Disk/quota/unavailable-persistence errors are errors, not a memory fallback.

**Receive transaction:** validate frame identity and cursor; update confirmed data; settle receipt statuses; remove only commands with terminal authoritative outcomes; rebuild working state; replay remaining commands; persist the cursor/publication token; commit; then notify queries. Each replay has a savepoint. A failed prediction rolls back only that prediction, retains its intent and named diagnostic, and does not prevent later independent predictions (R4). The server outcome remains pending until received.

A partial local projection is not evidence that a row does not exist globally. Coverage is explicit. The pilot sync unit is a declared project/workspace working set, complete for that authorized view; local read queries run over that set. A mutation that requires unavailable local input returns `needs_sync` before accepting a prediction; an invariant requiring hidden/global state belongs to authority validation. Arbitrary live-query-shaped replication and automatic query-policy rewriting are not V1 mechanisms.

Atomicity is per scope, not global across files/workspaces. A single scope has one authoritative commit order; concurrent clients may all predict locally, but only the authority assigns accepted order. Global inventory, uniqueness and authorization are never confirmed offline. Independent field patches may compose; stale same-field preconditions can reject. Append-only metadata does not settle conflicting user intent.

### Snapshot publication, not a Datomic clone

Expose a stable local query snapshot/publication token, not a mutable row graph observed halfway through reconciliation. Confirmed cursor and pending-local generation are different notions; a query result influenced by pending commands is not an authoritative snapshot.

The portable baseline is a single DB owner and complete transactions; the selected non-SQL engine must prove stable reads and atomic publication. The historical browser SQLite `OpfsDb` probe stayed in `delete` journal mode even after requesting WAL; that result does not establish any non-SQL engine's behavior. Do not assume simultaneous browser readers/writers or long-lived historical snapshots. Group snapshot reads while the owner is not mutating; UI receives detached results. Datomic-style permanent history, EAV and Datalog are not implied by snapshot publication and have not been selected.

## 5. Four end-to-end flows

### A. Offline write, restart, recovery

`data.mutate` reaches the DB owner, not the network. Successful completion means the local data/outbox transaction committed. Publish a single local revision; an offline connection leaves the command pending. Reopen loads that same working state and command identity before attempting sync. Persist failure returns a local error without sending the command (R7).

No reference observation in this pass proves physical power-loss safety. Native SQLite probes used `synchronous=FULL` and child process exit; browser probes terminated a worker and restarted Chrome. Browser eviction, OS failure, encrypted storage and device loss require separate acceptance checks and recovery/export policy.

### B. Concurrent changes and rejection

The mutation identity is `(streamId, sequence)`, not an additional independent UUID. Send that pair plus `(handlerId, handlerVersion, args)` under an authenticated connection. The authority binds the stream to app/principal/scope, checks sequence and argument types, checks policy, then executes the deployed handler in a transaction.

Success commits data, terminal outcome and replay metadata atomically. A permanent business rejection commits a terminal rejection and advances the stream without the mutation's writes, using a separate clean transaction after rollback when needed (R5). A transient storage failure commits neither. This avoids a permanently failing command blocking every later command, without treating infrastructure failure as successful rejection.

A duplicate ID cannot execute again. While its receipt is retained, return the stored outcome and reject a different payload/version under that ID. After acknowledged outcome compaction, the processed high-water mark still prevents execution, but cannot reconstruct the result or compare an erased payload hash. A client missing that outcome must reconcile from snapshot/high-water metadata or enter `outcome_unknown`, not infer success or retag the command. A future sequence reports the expected sequence rather than skipping a gap. Receipts and the corresponding projected data become client-visible at a compatible checkpoint; a bare transport acknowledgment never removes the prediction (R6/R7).

On rejection, preserve the rejected intent and diagnostic in client-local history for correction/export; remove its prediction and replay later commands in one receive transaction. Do not silently rewrite or resubmit it with a new ID. Client prediction failure and authoritative rejection are distinct statuses.

### C. Subscribe, disconnect, resume/resync

A scope subscription binds authorization, projection identity and initial snapshot at one authoritative transaction boundary (R2). Stream changes only after that boundary. Materialize/stage the snapshot at that basis and release database locks before waiting on the network; never hold a write transaction for a slow download. Changes may be sent while a multi-part snapshot is downloading, but the server retains/queues the cutover stream; the client stages parts until the complete marker and validates all limits before an atomic switch.

A stream frame names an epoch and opaque `from`/`to` cursors, scoped to the authorized projection. The client never advances the durable cursor before storing the corresponding data and outcomes. Same applied cursor is a duplicate; a wrong base, missing part or unknown epoch triggers named resume/resync, not best-effort patching. Interrupted staging leaves the live database intact.

A full resync replaces only confirmed scope data and replays pending commands. It preserves local-only data, command IDs and rejected intent. The snapshot includes the authenticated stream's processing high-water marks and required outcomes so a processed command is not predicted or executed twice. Query overlap must not duplicate rows; first V1 subscriptions are whole declared scopes, not an invented general-purpose IVM engine.

Bound the retained delta log and staging buffers. Expired delta history causes a full snapshot, not loss of user intent. Retain terminal mutation outcomes until the client durably observes them; retain processed sequence high-water marks after receipt compaction. Enforce per-stream quotas and explicit stream retirement rather than forgetting identities and retrying effects. If processing history is lost after disaster recovery, report `outcome_unknown` and stop automatic submission of that stream; never guess that its commands were unprocessed.

### D. Identity, permissions and versions

A local namespace includes backend identity, app, authenticated issuer/subject and sync scope. Changing tokens is not a database rename. Principal change closes the old connection/query owners and locks its pending queue; no old-user command is replayed under the new user (R8). A same-user token refresh resumes only after server verification.

Server policy protects both downloaded projections and writes, including joined data, removals and subscription membership. Private tables/fields are never added to a public scope or error payload. Opaque projection cursors avoid exposing a raw global private-transaction counter. Scope revocation known to the client closes reads and quarantines pending commands. A server cannot retroactively erase bytes from an offline or malicious device; applications requiring immediate revocation cannot promise unrestricted offline access to that sensitive scope.

Negotiate wire protocol, application schema and mutation contract versions separately. Local persistence-format migration is another axis (R8). Commands retain their original mutation ID/version/arguments across app updates. Deployments retain compatible handlers; clients retain compatible predictors for outstanding versions. Missing handlers, incompatible schema and unsupported protocol produce `needs_update` without deleting the queue or substituting a no-op (unlike R4's missing-mutator fallback).

Migrations must preserve pending intent and local-only tables or fail before switching the active database. Use additive compatibility first; destructive schema/code changes need a tested queue migration/export path. An explicit resync may repair confirmed data, not erase application-owned work.

## 6. Protocol baseline

Start with a versioned WebSocket session and a message contract independent of WebSocket. Runtime validation is mandatory on both sides; a TypeScript/MetaScript type declaration is not wire validation.

| Family | Required meaning |
|---|---|
| `hello` / `ready` | negotiate supported versions, authenticated identity, registered stream, limits and capabilities |
| `subscribe` / `snapshotPart` / `snapshotEnd` | bind scope/projection/epoch, snapshot identity and cutover cursor; do not publish partial snapshots |
| `mutate` | stream/sequence identity, registered handler ID/version and typed arguments; principal is server-derived |
| `changeFrame` | projection epoch, base/to cursors, row changes and compatible mutation outcomes; one atomic publication unit |
| `observed` | client has durably stored frame/outcomes; permits bounded log/result retention |
| `resume` / `resyncRequired` | continue a known projection cursor or explicitly replace confirmed data |
| `blocked` / `error` | named auth, compatibility, quota, protocol or storage failure; specify whether retry is safe |

A minimal frame shape, not an implemented codec:

```json
{
  "kind": "changeFrame",
  "scope": "project-42",
  "projection": "opaque-view-id",
  "epoch": "opaque-epoch",
  "from": "opaque-cursor-a",
  "to": "opaque-cursor-b",
  "changes": [{ "table": "projects", "op": "put", "key": "project-42", "row": { "name": "New" } }],
  "outcomes": [{ "stream": "opaque-stream", "sequence": "17", "status": "confirmed" }]
}
```

Client-to-authority writes carry registered commands, not this row-change shape. Server-generated outcomes may contain safe structured rejection details, never private validation inputs. The canonical codec preserves null versus absence, scalar widths and byte values. Use bounded int32 and finite float64 JSON numbers; encode int64/counters as canonical decimal strings at the JSON boundary. Reject malformed, non-finite or out-of-range values. Integer/BigInt mapping into actual MetaScript C/JS bindings remains a conformance gate.

Queries run through the declared engine/ordering semantics on every target. Pin the selected engine version and settings, then validate schema, scalar and query semantics across native and browser. The historical SQLite BINARY versus JavaScript default-sort probe demonstrates why cross-runtime ordering cannot be assumed; it does not select SQLite or prove a replacement engine's behavior.

Limits cover message/row sizes, snapshot staging bytes, pending commands, active scopes, query cost and outbound queues. These are product/runtime settings whose values need measurements; no throughput, cost or unlimited-offline guarantee was established. Backpressure blocks producers or requests a resync; it never drops committed changes silently. Presence is separate best-effort state and cannot hold up durable data.

## 7. Concrete ownership and deployment

The data runtime owns the logical database/query integration, persistence adapters, mutation registry, persistent intent/status, reconciliation, version gates and sync contract. It does not own JSX, native window lifecycle or a new compiler language surface. The editor composes the author workflow; managed provisioning operates the runtime rather than changing its application semantics.

The Neon adapter uses the existing `src/core/signal.ms` `createSignal`, `src/core/cleanup.ms` `onCleanup` and owner lifecycle. A DB publication invalidates active local queries; the pilot can rerun them all and publish one result snapshot instead of building IVM. Dispose cancels subscriptions and fences late results. Do not depend on a new `Host` method or modify signal/JSX contracts. Native/browser owner disposal, scheduling and refresh need real consumer tests; this pass did not prove that bridge.

A process/container running the database module is useful as a local-development or execution-ABI harness, not the production distribution design. The database data path must partition data and workload within one logical application database, with a proven transaction/isolation contract across the supported boundaries. A single database-wide write lock is not an acceptable final architecture; many separately hosted scopes do not prove this requirement. Physical key/index layout, partitioning, distributed query execution and deployment topology remain unselected. Hot-key contention and cross-partition coordination still impose real limits. Managed hosting must add tested backups/restore, isolation, quotas, deployment rollback, logs, authentication and metering before being sold as production service. Do not load untrusted native tenant modules into one shared address space.

Own-backend means either self-hosting the same runtime or implementing its command/receipt/snapshot contract. An adapter must prove transactions, deduplication, authorization and checkpoint consistency; changing an HTTP URL is insufficient. Arbitrary engine interchangeability is not promised. Publish the supported contracts and reference composition so self-hosting does not require a proprietary cloud endpoint. Cloudflare/Vercel-style provisioning and preview UX belong above this contract, not in Neon core.

Standalone local scopes are authoritative on-device and do not need an account. Recommend an explicit attach/import for the pilot: authenticate, create an empty remote scope, import only the declared shared tables through an authorized import mutation, then bind the local projection at the resulting checkpoint. Existing remote identity/data collisions fail without changing the local project. Local-only data stays on-device. This transition requires tests; switching arbitrary existing backends or silently merging histories is not an automatic adapter feature.

## 8. Historical feasibility inventory (2026-10-18)

Inspected Neon `bc9941811ed5f76e3ee4725123748969a859f231`, tree `d264190c04653573f770b6f5f1a8d00545ea4bd9`; installed `msc v0.3.4`, binary/support BUILD `4fe2a5eec`. No MetaScript build/test ran in this pass.

- Existing Neon signal/owner/cleanup seams were read. `AsyncStorage` delegates key-value operations to app services; it is not evidence of an atomic relational database or data/outbox transaction.
- The historical inventory found no SQLite binding in `src/` or installed `~/.metascript/std`; SQLite is now excluded, so this is not a current binding requirement. Std HTTP/WebSocket modules exist by source inventory; no claim of production sync, authentication or TLS validation was measured.
- The SQLite WASM probe establishes only that reference storage path's behavior, not the selected product engine, native `.ms` FFI, shared mutation compilation, packaging, worker ABI or browser/native parity. Non-SQL engine embedding remains unproven.
- The tested SQLite browser configuration needs cross-origin isolation for its OPFS path. Unsupported persistence is a named open failure, not memory mode. Safari/Firefox/mobile browsers, storage eviction, private browsing and encrypted-at-rest behavior were not run.
- First browser implementation should have one database-owner worker. Multiple tabs, lock contention and a SharedWorker owner are not proven by the dedicated-worker probe. Require an explicit `storage_busy` failure for unsupported competing owners rather than racing writers.

This inventory does not establish current non-SQL embedding or end-to-end runtime feasibility and authorizes no compiler change. Any compiler gap is reduced and handed to its owning repository under workspace rules.

## 9. Measurements and reproducibility

These are reference/storage checks from 2026-10-18, **not 25 Neon feature tests** or acceptance evidence for the unselected non-SQL engine. Existing source suites named above were not run. All artifacts below are machine-local investigation files, not shipped tests or platform implementation:

```text
C:/tmp/neon-borderless-design-20261018/
  package.json, package-lock.json, build-reference.mjs, bundle-inputs.json
  reference-browser.mjs, reference-results.json, reference-browser.log
  storage_contract.py, storage-results.json, storage-contract.log
  sqlite-browser.mjs, sqlite-browser-results.json, sqlite-browser.log
```

Commands from this machine:

```sh
npm ci --prefix C:/tmp/neon-borderless-design-20261018 --ignore-scripts --no-audit --no-fund
node C:/tmp/neon-borderless-design-20261018/build-reference.mjs
node C:/tmp/neon-borderless-design-20261018/reference-browser.mjs
python C:/tmp/neon-borderless-design-20261018/storage_contract.py
node C:/tmp/neon-borderless-design-20261018/sqlite-browser.mjs
```

The browser scripts use the checkout's installed `tests/browser/node_modules/playwright-core` and system Chrome. `build-reference.mjs` bundles 123 actual source inputs from the pinned Rocicorp checkout, with test mode off and production background processes enabled. No npm Replicache release was substituted. The browser fixture supplies pull/push results; it is not a real backend/authentication/network-failure integration. Its factory hook only captures the actual implementation to call `persist()` for a control. The harness holds `requestIdleCallback` for every scenario to make delayed persistence reproducible.

Rocicorp source tree for these measurements: `fec900bfe562721906f2659f46ba044bb1d90c88`. Chrome `155.0.8059.82`, Node `24.18.0`, Python `3.11.9`, native Python SQLite `3.45.1`, npm `@sqlite.org/sqlite-wasm@3.53.4-build2` reporting SQLite `3.53.4`. Native/WASM SQLite versions are different; the checks below do not establish general version parity.

| Check group | Result | What it establishes |
|---|---|---|
| actual Replicache source in Chrome | `12/12 PASS` | mutation args/identity, prediction/replay, duplicate-cookie no-op, compatible ack, throwing replay, version error and separate namespaces |
| SQLite primitive/codec contracts | `8/8 PASS` | process-exit rollback/commit, atomic data/outbox and receive boundaries, native WAL snapshot, field preconditions, numeric/order counterexamples |
| actual SQLite WASM + OPFS | `5/5 PASS` | persistent worker DB, int64 string boundary, BINARY order, restart/termination behavior and named unavailable-persistence control |

Important outputs:

```text
local completion before held idle persistence: visible=7, pending=1, store=idb
browser restart without explicit persist negative control: value=null
browser restart after actual source persist: value=7, pending=[put(7)]
replay pending mutation on new server basis: n=12, reducer runs=2
throwing replay retains intent and later replay proceeds: n=21, pending=[guarded,add]
schema mismatch keeps pending data and reports update: n=22, pending=1
SQLite crash before enqueue COMMIT: value=0, outbox=0
SQLite crash after enqueue COMMIT: value=7, outbox=1
SQLite crash before receive COMMIT: value=7, outbox=1
SQLite crash after receive COMMIT: value=9, outbox=0
native WAL reader snapshots: [0,0,11]
SQLite int64: 9007199254740993; JSON number in JS: 9007199254740992
SQLite BINARY order: U+E000,U+1F600; JS default sort: U+1F600,U+E000
browser SQLite: requested WAL, returned delete
OPFS restart: committed value=7/outbox=device:1; terminated uncommitted value=9/device:2 absent
without cross-origin isolation: persistent open rejected, no memory substitution
```

The persistence A/B uses the same payload `7`, key, mutator, held-idle scheduler, source, schema and browser profile across restart. Differing variables are isolated database names, generated client IDs, execution order and the explicit `persist()` call in the persisted case. Source R4 identifies the separate persistence path; the comparison does not isolate every storage-timing variable. It proves that completed mutation is not that reference's durable receipt, not that normal browser scheduling always loses writes. The SQLite process exits do not model physical power loss. The worker test does not prove multi-tab recovery or Neon integration.

### Approaches rejected or deferred

- Thin SpacetimeDB-style cache alone: disconnected reducer calls do not provide autonomous writes (R3).
- Treating `await mutate` or local visibility as automatically durable: reference A/B disproves the equivalence (R4).
- Memory fallback or missing-mutator no-op as recovery: incompatible with explicit durability and preserved-intent contracts (R4/R9).
- Blind SQLSync port: different storage/replication and unresolved crash boundary; its own guide disclaims production readiness (R10).
- SQLite as the product substrate: superseded by the explicit no-SQL-engine requirement. Its probes remain historical comparative evidence, not an implementation recommendation.
- SQLite native WAL as a universal browser assumption: the OPFS probe did not enter WAL (R12).
- Datomic clone, universal CRDT, arbitrary backend adapters, query IVM and server-driven JSX: none is necessary to prove this product's first data workflow.

## 10. Implementation gates and smallest useful sequence

Every phase below is proposed work requiring implementation approval. Preserve all existing UI/runtime boundaries.

1. **Execution/data/storage selection and spike:** trace the guest/host execution ABI, reusable non-SQL query/index engines and distributed transactional storage candidates; review the choices before implementation. Prove actual MetaScript query/action code executing inside the DB, declared schema/codec, native/browser embedding, local transaction boundaries and explicit persistent-open failure. Run one query corpus including indexed lookup, range/filter and joins; do not substitute generated SQL. Validate scalar conversions, lifetime/thread ownership, worker packaging and sandbox limits. A single-node spike proves only those boundaries, not horizontal scaling; a generic KV adapter proves neither query execution nor transaction semantics.
2. **One local project:** a real Neon task/project app uses local queries and multi-table transactions, survives restart, and shows local durability failures. Attach/detach UI owners without leaked callbacks. No cloud dependency for this phase.
3. **Authority and two clients:** attach/import the small local project without losing local-only data, then run the same declared mutation module under a deployed authority registry; authenticate identities, persist deduplication/outcomes, and sync an authorized scope. Exercise concurrent same-field and independent edits, a rejected mutation followed by a valid one, lost push response, reordered/duplicate frames and snapshot/stream cutover.
4. **Recovery and compatibility:** interrupt each transaction boundary, force snapshot resync with pending work, rotate identity/permissions, and upgrade schema/mutation code while an old client is offline. Keep receipts/outbox/local-only data safe. Unsupported old versions must be recoverable named states, not destructive repair.
5. **Distributed database acceptance:** partition one logical application database across multiple machines, exercise indexed queries and writes against multiple partitions, then add capacity while serving traffic and measure the same workload/isolation settings. Verify rebalancing, replica/owner failure and recovery, and the supported cross-partition transaction invariants. Many independent database instances or faster reads alone are not evidence of write scaling. This is required before claiming the database architecture complete, not an optional response to a later bottleneck.
6. **Packaged golden path:** create a project, sign in, query data, execute an authorized action, see reactive UI updates, preview and publish. Supply the local emulator/data inspector and open-source reference self-hosted composition alongside isolated managed deployment. Include one explicit server-only function, pending/rejected/confirmed logs, export, backup/restore and rollback. Run the same applicable conformance corpus on self-hosted and managed deployments before claiming parity; self-hosting is not a later proprietary-cloud escape patch.

Release acceptance is the real browser/native Neon consumer across these boundaries, not a storage unit test. Test account isolation, private-field projection, tombstones, quota, disk-full, missing OPFS headers, second-tab contention and disposal during sync. Local authoring, native packaging and sync must work on their actual consumers; compiler fixes remain with the compiler owner.

The optional upgrade triggers are concrete: large client working sets or expensive invalidation justify selective replication/IVM; an unsupported query/scalar requires engine conformance work. Distribution and safe admission/execution of untrusted code are baseline requirements, not optional upgrades after a single-writer pilot. Enforceable compile-time replay purity would still be a separate compiler mechanism requiring reference trace and approval. No distributed query planner, VM extension or storage implementation is authorized by this proposal.
