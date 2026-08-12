# Render Model — Emission Tiers over One Runtime Core

How JSX becomes live UI. Companion to `RENDER-LAYERS.md` (which answers *who paints,
per platform*); this doc answers *how mount code is produced and what runs when*.

**Naming.** The two ways the mount plan is produced:

- **Tree emission** — the `element` macro emits a NeonNode *description tree*;
  the shared walker (`renderNode`, `src/render/host.ms`) mounts it at runtime.
  Default today, on every host.
- **Direct emission** — the macro emits the *mount instructions themselves*,
  specialized per JSX site. V1+D1+D2+D3 landed (`src/macros/ui/direct.ms`, differential-pinned
  by `tests/render/direct.test.ms`): lowercase elements, attr classification
  (string literal → one setAttr, `on*` → addEvent, any other expr → one
  setAttr effect per spot — D2, mirroring element.ms), the typed style channel
  (`host.setStyle` behind a bound temp, same S4 field validation as element.ms),
  static+dynamic text, nested lowercase elements flattened INLINE into the one
  mount block (D3 — a single statement list, temps numbered across the whole
  tree `_r0/_r1/…`, child subtree emitted depth-first then appended; no
  per-level closure or call), component tags + `Show`/`For` interleaving — a
  capitalized tag emits the element.ms `createComponent` contract and mounts
  through the runtime seam (`renderToHost(_k, host, _rN)` in child position =
  the renderNode child loop's peel/region/append dispatch; `renderNode(_k,
  host)` in root position, which throws loudly if the component expands to a
  region). Components/`Show`/`For` do not flatten by design: their structure
  changes at runtime. **D4 landed — template-clone**: a subtree of nothing but
  lowercase elements/text/attrs/events/style has a static skeleton, so the macro
  emits `mountTemplate(createTemplate(build), wire)` — the skeleton is built once
  and duplicated per mount (`host.cloneNode`), and each dynamic spot is reached
  by a walk path computed at COMPILE time (`childOf`/`siblingOf` steps, pruned to
  the branches that actually carry a dynamic spot). A subtree containing a
  component tag or a region keeps the D3 flat emission unchanged. Two rules make
  the differential hold: a dynamic attr keeps its SOURCE slot in the skeleton with
  an empty value (the per-instance effect upserts it, so markup order matches tree
  emission), and events/style are applied per instance, never baked into the
  skeleton. Not yet: `<Index>` differential cells, HTML-string fast path for the
  DOM skeleton (Solid's one-time `innerHTML` parse — the contract already allows
  it), `build.ms` selection (browser first).

Do NOT call these "model A/B" — `RENDER-LAYERS.md` already uses Layer A/B/C for
reconcile/paint/GPU and the letters collide.

## The system is 3 parts; emissions differ in ONE

```
(1) EMISSION       what the macro emits for JSX      ← tree vs direct differ HERE ONLY
(2) RUNTIME CORE   signals, effects, memos, owner    ← shared, emission-agnostic
                   Show/For regions, reconcileArrays,
                   createComponent
(3) HOST ADAPTERS  dom / terminal / void / mock      ← shared (Host contract, 12 ops)
```

Tree-emission-specific code is small and permanent: the NeonNode structs
(`node.ms`), the mount walker (`host.ms:renderNode`), and `renderToString`.
Everything else is shared infrastructure both emissions stand on.

## Lifecycle — five phases

```
COMPILE ──► BUILD ──► MOUNT ──► UPDATE (×n) ──► DISPOSE
 macro      run       walk       effects fire     owner tree
 expand     App()     ONCE       individually     kills subtree
```

- **COMPILE** (macro): JSX → calls. Static facts (tags, static attrs, which spots
  are dynamic) are decided here, never re-derived at runtime.
- **BUILD** (run `App()`): construct the description tree — pure data, zero host
  calls, zero signal reads. Deferred things hold closures unrun: components
  (`componentFn`), regions (`region`), dynamic text (`dyn`).
- **MOUNT** (`renderToHost`): walk once. Static text/attrs applied and never
  touched again; every dynamic spot plants ONE effect whose first run subscribes
  it to the signals it reads; components run their body exactly once (untracked,
  under the mounting owner); regions plant an anchor + a reconcile effect.
- **UPDATE**: no render. A signal notifies exactly its subscribed effects; each
  performs one host op. Cost = number of spots that actually changed,
  independent of tree size.
- **DISPOSE**: owner-tree teardown — deterministic, recursive, fires `onCleanup`,
  kills every subscription underneath. Never waits for GC.

Under direct emission, BUILD+MOUNT fuse into one step (the emitted code builds
host nodes directly); the other phases are identical.

## After mount: the wire graph

The description tree has done its job; what stays alive is wiring:

```
   SIGNALS                 EFFECTS                      HOST TREE
 ┌──────────┐  subscribe ┌────────────────────┐  1 op ┌─────────────────────┐
 │  n = 0   │ ─────────► │ #1: setText(t, …)  │ ────► │ text node inside <p>│
 └──────────┘            └────────────────────┘       ├─────────────────────┤
 ┌──────────┐            ┌────────────────────┐       │ region span         │
 │ on = true│ ─────────► │ #R: reconcile span │ ────► │ (before its anchor) │
 └──────────┘            └────────────────────┘       └─────────────────────┘
```

No background walker, no whole-tree diff scheduler. Two update paths only:

- **thin** — `setN(5)` → effect → `host.setText`. Done.
- **structural** — a region's source flips → its effect re-runs → the memo
  yields a new host-node list → `reconcileArrays` splices minimally between the
  anchor bounds → the dropped subtree's owner is disposed (effects die,
  `onCleanup` fires). Diffing exists ONLY here: real host nodes, one region's
  direct span, never recursive, only when that region's source changed.

## Direct emission — mechanics

Direct emission is `renderNode` **partially evaluated at compile time** over the
static structure. Every `if`/`for` of the walker is answered during macro
expansion; what remains is the straight-line op sequence:

```ts
// tree emission (data + shared walker):        // direct emission (the walk, pre-run):
el("div", [attr("class","box")], [], [          (host) => {
  el("p", [], [], [                               const d = host.createElement("div");
    text("hello "),                               host.setAttr(d, "class", "box");
    dynText(() => name()),                        const p = host.createElement("p");
  ]),                                             host.append(p, host.createText("hello "));
])                                                const t = host.createText("");
                                                  createEffect(() => host.setText(t, name()));
                                                  host.append(p, t); host.append(d, p);
                                                  return d;
                                                }
```

Same host ops, same order, same effects. `renderNode` is therefore the **spec**
for what direct emission must generate, and the tree-emission test suite is the
**oracle**: the differential test for direct emission is "same JSX, both
emissions, identical host-op sequence".

**Interleaving.** Static fragments unroll; every dynamic boundary is a call into
the runtime core, handing it a direct-emitted closure as the child template —
and the core calls back into that closure when (re)building:

```
mount:  [direct] build <div>
        [direct] mountShow(…) ──► [core] anchor + memo + effect
                                  [core] when=true → children(host) ──► [direct] build <p>
                                  [core] reconcileArrays splices it
flip:                             [core] memo flips → reconcile removes, owner disposes
flip back:                        [core] calls children(host) again ──► [direct] fresh <p>
```

Components, `Show`, `For` are runtime calls in BOTH emissions — structure that
changes at runtime cannot be unrolled at compile time.

**Template-clone (D4, landed).** A pure subtree is emitted as a skeleton built
once plus a per-instance walk, so mount N costs one native copy instead of N
create/append calls:

```ts
mountTemplate(
  createTemplate((h) => {                  // built ONCE, lazily, per direct() site
    const r0 = h.createElement("div");
    h.setAttr(r0, "class", "box");
    h.setAttr(r0, "title", "");            // dynamic attr keeps its SOURCE slot
    h.append(r0, h.createText(""));        // dynamic text slot
    return r0;
  }),
  (host, p0) => {                          // per instance
    const p1 = childOf(host, p0);          // walk path resolved at COMPILE time
    createEffect(() => host.setText(p1, name()));
    createEffect(() => host.setAttr(p0, "title", t()));
  },
)
```

The skeleton carries structure, static attrs and placeholders only — events and
style are applied per instance (DOM `cloneNode` does not copy listeners, and the
mock oracle mirrors that rule exactly).

`cloneNode` is an **optional capability** on the Host contract: a host that
cannot duplicate a subtree cheaply sets it to `null` and `instantiate` runs the
builder again — same markup, no clone, nothing for that host to implement
(terminal and void ship exactly this). `firstChild` is required and trivial
everywhere, mirroring the existing `nextSibling`.

Still open for the DOM host: materialising the skeleton from an HTML string
(Solid's one-time `innerHTML` parse). The contract already permits it — only the
`createTemplate` builder body would change — and it buys startup cost, not
per-mount cost, which is why it was not required to land D4.

## Per-platform economics — why direct is opt-in, not default

Direct emission removes description-tree allocation + the interpreter loop at
mount. What that removal is worth depends on the platform:

| Platform | Tree walk runs as | Direct-emission win |
|---|---|---|
| Browser (JS backend) | interpreted/JIT JS | **large** — per-op JS cost is high, and the template-clone trick exists only here |
| Terminal / Void / iOS (C backend) | compiled C | **small** — the walk is already cheap native code; mount is dominated by layout/paint/GPU; the win is allocations only |
| Embedded / IoT | compiled C | **possibly negative** — unrolled mount code at every JSX site grows the binary; one shared ~30-line walker is smaller and icache-friendlier |

Policy: tree emission everywhere until, per target, a benchmark shows a real
gap. Gates (1) and (2) are CLOSED: the closure codegen debts direct emission
leans on (loop+nested-closure snapshot, expr-bodied-arrow env) were fixed
2026-08-07/08, and attribute classification landed in both emissions
(D2, 2026-08-09). What remains per target is (3) the benchmark; then direct
emission lands behind a `build.ms` switch, browser first. User code and types
change zero characters.

### Gate (3) — MEASURED 2026-08-11, and it changes the plan above

The `build.ms` switch is **superseded**. Measurements below say the choice is
per-JSX-SITE and fully decidable at compile time, so nothing should be exposed —
not a build flag, and not a `direct()` call in user code.

Prerequisite that made the benchmark meaningful at all: before template hoisting
landed (recompiler `1840976`), the per-site cell was *slower than tree* (19.00 vs
18.00 host-ops/mount), so gate (3) would have concluded "don't use direct". With
hoisting it is 3.016, equal to the hand-hoisted cell. `probe/bench.ms`.

**Real DOM, headless Chrome, ms per 1000 row mounts inside a real `For` region**
(`probe/sweep6.ms`, `probe/sweep12.ms`; ratio = tree ÷ direct, >1 means direct wins):

| dynamic spots | 6-cell row | 12-cell row |
|---|---|---|
| 0% | 2.31 | 2.57 / 2.50 / 2.56 |
| 25% | — | 1.94 / 1.77 / 2.03 |
| 33% | 1.95 | — |
| 50% | 1.67 | 1.71 / 1.63 / 1.56 |
| 75% | — | 1.60 / 1.51 / 1.38 |
| 100% | 1.38 | 1.44 / 1.45 / 1.36 |

Three things follow, and the first two were surprises:

1. **There is no crossover.** Direct wins at every level, 2.5x on fully static
   markup down to ~1.4x when every cell is dynamic. An earlier run of this same
   sweep reported direct LOSING at 100% dynamic (0.74x); that was an artifact of
   summing timed rounds, where one CPU-stolen round dominates a cell. Reported
   here as the MIN across rounds. Do not reinstate a "mostly static only"
   threshold on the strength of the retracted number.
2. **The rule tracks the RATIO of dynamic spots, not row size.** At 50% dynamic a
   6-cell row gives 1.67 and a 12-cell row 1.63. So no absolute static-cell count
   is needed in the decision.
3. **Rows are where this matters, and they cannot reach it today.** `For.children`
   is typed `=> NeonNode` while `direct()` yields `(host) => HostNode`, and there
   is no adapter — `tests/render/direct.test.ms:446` builds the row with
   `element(...)` in BOTH of its cells. So the win currently applies to one shell
   mount, not to the N rows under it. `probe/rowDirect.ms` measures the widened
   form at **1.9x per row**, and `probe/rowDirectParity.ms` shows it produces a
   byte-identical tree through initial → reorder → append → shrink on C and JS.

Direction, therefore: keep both emissions (tree stays the substrate — the direct
emitter itself calls `element`/`text`/`createComponent`/`renderNode`/
`renderToHost` by name for components and regions), and make template+clone the
DEFAULT inside `element` for any subtree `isPureSubtree` already accepts. That
turns `direct()` from a user-facing macro into an internal emission strategy, and
subsumes the row question: the region API needs to accept a mount closure, but no
app code changes. Blocked on the C-backend defect in §2 — the region body is
literally `f(x)(y)`, which that backend cannot emit.

Caveats on the numbers, so they are not over-trusted: measured on a machine under
load 4–54 from a parallel build (ratios were stable across runs, absolute values
were not — the 6-cell runs 2 and 3 are inflated 3x and were discarded); rows are
built into a DETACHED box, so layout and paint are excluded; a row carrying event
handlers was not measured. Good enough to choose an architecture, not yet the
number to publish.

## Rows — the boundary type carries the emission (LANDED 2026-08-12)

`For.children` used to be typed `=> NeonNode`, so a row was always a description
the walker mounts — even under a direct-emitted shell. Rows are the hottest mount
path in a real app, so the emission win applied to one shell and not to the N rows
under it.

`For` / `Index` / `Show` now take **`NeonView`** — the same boundary type the JSX
converter selects on (`src/converters.ms`), defined per target in
`src/render/host.ms`:

| target | `NeonView` | `mountView` |
|---|---|---|
| js | `(host: Host) => HostNode` | calls it |
| native | `NeonNode` | `renderNode` |

Nothing is exposed and nothing is chosen by hand: a bare JSX row hits the
converter at the `NeonView` boundary and lowers to the target's emission. The row
callback is the only line that changed inside `For`:

```ms
- mapArray(..., (item, idx) => renderNode(props.children(item, idx), host))
+ mapArray(..., (item, idx) => mountView(props.children(item, idx), host))
```

`viewOf(node)` adapts a hand-built description (`el(...)`, `element(...)`) where a
view is expected; bare JSX never needs it.

**Measured through the public api** — `probe/rowSweep.ms`, real DOM in headless
Chrome, 500 rows, 6 spans per row, **min of 3 runs** (a mean hides it: one run put
`dyn=6` direct at 6.33 vs tree 5.67, i.e. slower, which averaging would have baked
into the answer):

| dynamic spots / 6 | tree | direct | ratio |
|---|---|---|---|
| 0 | 2.77 | 0.97 | **2.86x** |
| 1 | 2.67 | 1.33 | 2.00x |
| 3 | 3.03 | 1.87 | 1.63x |
| 6 | 5.67 | 4.67 | 1.21x |

Same numbers as the private `ForDirect` cell that measured this before the api
could express it, so the widening delivers the win rather than a version of it.

**Not widened, on purpose:** `createComponent` still takes and returns `NeonNode`,
so a component's INTERNALS stay tree-emitted on every target. That is a separate
arc with its own measurement — a component row written as bare JSX already reaches
direct emission, because the macro lowers a capitalized tag to
`createComponent` + `renderToHost` inside the mount closure.

## Invariants — the contract every emission must satisfy

1. **Build is pure** — no signal reads while constructing the description
   (style macro already errors on this; S4 will lift it properly).
2. **A component body runs exactly once** — any second run is a serious bug
   (`bodyRuns`-counter test pattern).
3. **Every dynamic spot = one effect, created at mount, under the mounting
   owner** — never at build time.
3a. **Only a spot that can observe something gets a computation.** Solid's rule
   (`babel-plugin-jsx-dom-expressions`): an expression carrying a call or a
   property read is reactive; a bare identifier or literal is resolved once at
   mount, so wrapping it would allocate an effect that can never re-run.
   `isReactiveExpr` (`src/macros/ui/element.ms`) is the single classifier both
   emissions consult, and it is deliberately conservative — anything it does not
   recognise as inert stays reactive, because a wasted computation is cheap and a
   missed update is not. Tree emission pins the rule structurally (`isDyn` on the
   NeonNode, `element.test.ms`); direct emission has no such surface and stays
   pinned only by the shared differential until macro-expansion output can be
   inspected the way Solid snapshots its compiled JSX.
3b. **A spot writes the host only when its value actually changed.** The signal
   already drops a set to an equal value, but a derived expression maps many
   source values onto one output (`n() > 5 ? "big" : "small"`), so the last
   written value is kept and an identical recomputation is dropped. Both
   emissions bind through `bindText`/`bindAttr` (`src/render/host.ms`) — one
   implementation is what keeps their host-op sequences identical, and
   `mockToString` cannot see the difference, so the test for it counts writes
   on a counting host.
4. **Structural change goes through a region + anchor only** — nothing else
   inserts/removes host nodes except `reconcileArrays`.
5. **Dispose is total** — after unmount, signal writes reach zero effects
   (`tests/core/dispose.test.ms`).
6. **A Host adapter matches mock-host semantics op for op** — e.g.
   `insertBefore` detaches first (DOM move semantics). `mockHost()` is the
   reference implementation of the contract.

The existing test suite is these invariants encoded; keep it that way — every
new render feature should land with the invariant it preserves named in its
test.

## Props typing — DX decision (user, 2026-08-08)

The component's props interface is the **single source of truth**; the macro
inserts **no coercion**. `createSignal` stays generic — `createSignal(0)`
inferring `Signal<int32>` is correct; want another type, annotate
(`createSignal<number>(0)`, `0 as float32`, …). A repr mismatch — e.g. a
`() => int32` getter into a `() => number` field — is a **checker error by
design**, not a bug (function types are invariant). Note the asymmetry: the
element macro wraps expression props in thunks (`count={n()}` → `() => n()`),
so the returned VALUE widens and int32 signals flow into number fields fine
through JSX; only passing a getter's function value directly
(`{ count: n }`) trips invariance. Negative probe: `probe/thunkProps3.ms` S1.

## References

- `src/render/node.ms` — NeonNode, `createComponent` seam (`component.ms`),
  `renderToString`
- `src/render/host.ms` — Host contract, `renderNode` walker, `mountRegion`,
  `mockHost` reference
- `src/render/reconcile.ms` — region list reconciliation
- `src/macros/ui/element.ms` — the emission frontend (tree emission today)
- `docs/RENDER-LAYERS.md` — reconcile/paint/GPU ownership per platform
- PORT-STATUS.md "Design LOCKED 2026-07-30" — the component/JSX contract this
  doc's emission-tier plan belongs to
