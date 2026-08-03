# Render Model — Emission Tiers over One Runtime Core

How JSX becomes live UI. Companion to `RENDER-LAYERS.md` (which answers *who paints,
per platform*); this doc answers *how mount code is produced and what runs when*.

**Naming.** The two ways the mount plan is produced:

- **Tree emission** — the `element` macro emits a NeonNode *description tree*;
  the shared walker (`renderNode`, `src/render/host.ms`) mounts it at runtime.
  Default today, on every host.
- **Direct emission** — the macro emits the *mount instructions themselves*,
  specialized per JSX site. Planned per-target optimization tier (browser first),
  selected in `build.ms`. Not implemented yet.

Do NOT call these "model A/B" — `RENDER-LAYERS.md` already uses Layer A/B/C for
reconcile/paint/GPU and the letters collide.

## The system is 3 parts; emissions differ in ONE

```
(1) EMISSION       what the macro emits for JSX      ← tree vs direct differ HERE ONLY
(2) RUNTIME CORE   signals, effects, memos, owner    ← shared, emission-agnostic
                   Show/For regions, reconcileArrays,
                   createComponent
(3) HOST ADAPTERS  dom / terminal / void / mock      ← shared (Host contract, 9 ops)
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

**DOM-only extra:** static fragments can compile to an HTML template string,
mounted via `template.cloneNode(true)` + direct pointers to the dynamic holes —
one native parse instead of N `createElement` calls. This (Solid's core trick)
is the main reason direct emission pays on the browser.

## Per-platform economics — why direct is opt-in, not default

Direct emission removes description-tree allocation + the interpreter loop at
mount. What that removal is worth depends on the platform:

| Platform | Tree walk runs as | Direct-emission win |
|---|---|---|
| Browser (JS backend) | interpreted/JIT JS | **large** — per-op JS cost is high, and the template-clone trick exists only here |
| Terminal / Void / iOS (C backend) | compiled C | **small** — the walk is already cheap native code; mount is dominated by layout/paint/GPU; the win is allocations only |
| Embedded / IoT | compiled C | **possibly negative** — unrolled mount code at every JSX site grows the binary; one shared ~30-line walker is smaller and icache-friendlier |

Policy: tree emission everywhere until, per target, (1) the compiler's closure
codegen debts are closed (BUGS.md §2: loop+nested-closure snapshot,
expr-bodied-arrow env — direct emission generates exactly that code shape),
(2) attribute classification exists in the macro (without it, direct emission
is just createElement chains — marginal), and (3) a benchmark on that target
shows a real gap. Then direct emission lands behind a `build.ms` switch,
browser first. User code and types change zero characters.

## Invariants — the contract every emission must satisfy

1. **Build is pure** — no signal reads while constructing the description
   (style macro already errors on this; S4 will lift it properly).
2. **A component body runs exactly once** — any second run is a serious bug
   (`bodyRuns`-counter test pattern).
3. **Every dynamic spot = one effect, created at mount, under the mounting
   owner** — never at build time.
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
