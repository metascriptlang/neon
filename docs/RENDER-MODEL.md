# Render Model — One NeonNode, Tiers Chosen in the Macro

How JSX becomes live UI. Companion to `RENDER-LAYERS.md` (which answers *who paints,
per platform*); this doc answers *how mount code is produced and what runs when*.

## The one concept

```ts
type NeonNode = (host: Host, parent: HostNode, before: HostNode | null) => void;
```

A NeonNode is a function that puts the host nodes it owns into `parent`, in front of
`before` (`src/render/hostTypes.ms`). It is what a JSX expression becomes on every
target, what a component returns, what `children` holds, and what a `For` row callback
yields. There is no description tree and no walker: rendering a node is calling it.

```ts
render(<App/>, host, parent)   // = createRoot(dispose => { node(host, parent, null); return dispose; })
```

`render` (`src/render/host.ms`) owns the mount in a root and returns its `Dispose`. That
root is not a child of the owner that was current when `render` ran (Solid), so the
only way to take a mount down is the dispose `render` handed back.

The shape is Svelte 5's: a fragment function that receives its anchor and inserts
itself in front of it. It is what lets a node own zero, one or many host nodes — a
component, a fragment, a region — without the caller knowing which, and what lets a
row be mounted at its final position instead of being built elsewhere and moved in.

The same thing can be written by hand. `src/render/node.ms` holds the builders for a
tag, an attr list or an event list only known at runtime (`hostElement`, `el`, `text`,
`dynText`, `mountChild`, `regionNode`); `src/components/primitives.ms` is their user.
They produce NeonNodes too, so hand-built and macro-built nodes compose freely.

Do NOT call the tiers below "model A/B" — `RENDER-LAYERS.md` already uses Layer A/B/C
for reconcile/paint/GPU and the letters collide.

## Selection — per site, at compile time, exposed to nobody

There is ONE macro, `element` (`src/macros/ui/element.ms`), and ONE converter,
`jsxToNode` (`src/converters.ms`), which fires wherever a `NeonNode` is expected — a
component's return, an annotated const, a `render` argument, a row callback. No build
flag, no per-target policy, nothing to call by hand.

Inside the macro a JSX site lowers by what its own shape can support. The axis is not
static vs dynamic; it is *does the SHAPE of this subtree change while it runs?*

| the subtree is | emits as | tier |
|---|---|---|
| lowercase elements, text, attrs, events, style — any number of them reactive (`isPureSubtree`) | a template built once, `cloneNode` per mount, a compile-time walk path to each dynamic spot | **template** |
| that, plus a component tag, a region or a NeonNode-valued `{child}` anywhere inside | one flat inline mount block; the component / region / child parts are NeonNode calls at their position | **flat** |
| a root fragment `<>…</>` | the flat block with every root placed in front of `before` | **flat** |

A dynamic VALUE (`{count()}`, `class={cls()}`, `style={s()}`) never changes the node
count, so a fully reactive element is still template-emitted: six changing text spots
are six effects over a skeleton whose shape never moves. A dynamic STRUCTURE (`<For>`,
`<Show>`, `<Index>`, a component) is a NeonNode produced at run time and called where
it stands; the macro never guesses a node count.

A `{child}` expression is routed by its TYPE (`isNodeType`: a function type whose
parameters are named `host`, `parent`, `before`): a NeonNode or a NeonNode array goes
to `mountChild`, anything else is text — live when the expression is reactive or
accessor-typed, written once otherwise. A number, or an `Accessor` of one, is rendered
through `.toString()`, so `{count}` needs no `+ ""`. A NeonNode picked by a reactive condition
(`{cond() ? a : b}` over node values) would mount once and never switch, so it is a
compile error pointing at `<Show>`; the JSX-armed forms `{a && <X/>}`,
`{c ? <A/> : <B/>}` and `{xs.map(row)}` lower to `Show` / `For` before emission.

## The system is 3 parts

```
(1) EMISSION       what the macro emits for JSX      ← template tier / flat tier
(2) RUNTIME CORE   signals, effects, memos, owner    ← shared
                   regions, reconcileArrays,
                   createComponent, context scopes
(3) HOST ADAPTERS  dom / terminal / void / mock      ← shared (Host contract:
                                                        12 required ops + 3 optional)
```

The optional capabilities are `cloneNode`, `setStyleProp` and `setStyleClass`; a host
sets one to `null` and the runtime takes the coarser path with the same result.

## Lifecycle — four phases

```
COMPILE ──► MOUNT ──► UPDATE (×n) ──► DISPOSE
 macro      call       effects fire     owner tree
 expand     ONCE       individually     kills subtree
```

- **COMPILE** (macro): JSX → a NeonNode. Static facts (tags, static attrs, which spots
  are dynamic, the walk path to each) are decided here, never re-derived at runtime.
- **MOUNT** (`render`, or a parent node calling a child): the node runs once. Static
  text/attrs are applied and never touched again; every dynamic spot plants ONE effect
  whose first run subscribes it to the signals it reads; a component runs its body
  exactly once (untracked, under the mounting owner) and its result is called at the
  same position; a region plants an anchor + a reconcile effect; a fragment owns no
  host node and places each of its roots in front of `before`.
- **UPDATE**: no render. A signal notifies exactly its subscribed effects; each
  performs one host op. Cost = number of spots that actually changed, independent of
  tree size.
- **DISPOSE**: owner-tree teardown — deterministic, recursive, fires `onCleanup`,
  kills every subscription underneath. Never waits for GC.

Building the node (evaluating the JSX expression) allocates a closure and performs no
host op and no signal read; there is no separate BUILD phase producing data.

## After mount: the wire graph

What stays alive after mount is wiring:

```
   SIGNALS                 EFFECTS                      HOST TREE
 ┌──────────┐  subscribe ┌────────────────────┐  1 op ┌─────────────────────┐
 │  n = 0   │ ─────────► │ #1: setText(t, …)  │ ────► │ text node inside <p>│
 └──────────┘            └────────────────────┘       ├─────────────────────┤
 ┌──────────┐            ┌────────────────────┐       │ region rows         │
 │ on = true│ ─────────► │ #R: reconcile rows │ ────► │ (before its anchor) │
 └──────────┘            └────────────────────┘       └─────────────────────┘
```

No background walker, no whole-tree diff scheduler. Two update paths only:

- **thin** — `setN(5)` → effect → `host.setText`. Done.
- **structural** — a region's source flips → its effect re-runs → the memo yields a new
  row list → `reconcileArrays` mounts, moves and removes rows in front of the region's
  anchor → a dropped row's owner is disposed (effects die, `onCleanup` fires). Diffing
  exists ONLY here: one region's own rows, never recursive, only when that region's
  source changed.

## Emission — mechanics

**Flat tier.** One statement list, temps numbered across the whole subtree (`_r0/_r1/…`
elements, `_t0/…` dynamic texts, `_k0/…` component children, `_s0/…` style temps), a
child subtree emitted depth-first then appended to its parent — no per-level closure,
no per-level call. Only the roots are inserted with `place(host, parent, node, before)`;
everything below a root is a plain `host.append`:

```ts
<div class="box"><p>hello {name()}</p><Badge n={n()}/></div>
// lowers to
(host, parent, before) => {
  const _r0 = host.createElement("div");
  host.setAttr(_r0, "class", "box");
  const _r1 = host.createElement("p");
  host.append(_r1, host.createText("hello "));
  const _t0 = host.createText("");
  bindText(host, _t0, () => name());
  host.append(_r1, _t0);
  host.append(_r0, _r1);
  const _k0 = createComponent(Badge, { n: accessor(() => n()) });
  _k0(host, _r0, null);
  place(host, parent, _r0, before);
}
```

Attr classification: a string literal is one `setAttr`, `on*` is `addEvent`, any other
expression is one `bindAttr` effect per spot (a `null` value removes the attribute).
The typed style channel splits by shape: an object literal writes its static fields
once and plants `bindStyleProp` per reactive field; a layer array merges at compile
time or goes through `layerStyles` (a reactive layer or field is rejected); a reactive
expression is `bindStyleAll`; anything else is `applyStaticStyle`. A `ref` runs
innermost-first, before the root is placed (React's order).

**Template tier.** A pure subtree has a static skeleton, so it is built once and
duplicated per mount, and each dynamic spot is reached by a walk path computed at
COMPILE time (`childOf` / `siblingOf` steps, pruned to the branches that carry a
dynamic spot):

```ts
const _tpl12_9 = createTemplate((h) => {   // static storage: built ONCE per site, lazily
  const r0 = h.createElement("div");
  h.setAttr(r0, "class", "box");
  h.setAttr(r0, "title", "");              // a dynamic attr keeps its SOURCE slot
  h.append(r0, h.createText(""));          // dynamic text slot
  return r0;
});
mountTemplate(_tpl12_9, (host, _p0) => {   // per instance
  const _p1 = childOf(host, _p0);          // walk path resolved at COMPILE time
  bindText(host, _p1, () => name());
  bindAttr(host, _p0, "title", () => t());
})
```

`mountTemplate` (`src/render/template.ms`) returns the NeonNode: instantiate, wire,
`place`. The skeleton carries structure, static attrs and placeholders only — events
and style are applied per instance (DOM `cloneNode` does not copy listeners, and the
mock host mirrors that rule exactly).

`cloneNode` is an **optional capability** on the Host contract: a host that cannot
duplicate a subtree cheaply sets it to `null` and `instantiate` runs the builder again
— same markup, no clone, nothing for that host to implement (terminal and void ship
exactly this). `firstChild` is required and trivial everywhere, mirroring
`nextSibling`.

Still open for the DOM host: materialising the skeleton from an HTML string (Solid's
one-time `innerHTML` parse). The contract already permits it — only the
`createTemplate` builder body would change — and it buys startup cost, not per-mount
cost.

**Components.** A capitalized tag emits `createComponent(Comp, props)`
(`src/render/component.ms`), which is
`(host, parent, before) => untrack(() => Comp(props)(host, parent, before))`: the body
is deferred to mount, runs once, and whatever it returns mounts at the component's own
position. `children` is always ONE NeonNode — a single child is passed as is, several
are wrapped in a root fragment — so a component places them with `{props.children}`.
A `Context.Provider` is the same shape with the call wrapped in the provider's scope.

**Fragments.** `<>…</>` owns no host node. In child position it is not emitted at all:
the macro splices its children into the parent's child list at COMPILE time
(`flattenFragments`, recursive, matching Solid's `normalizeIncomingArray`), and `<></>`
erases. At the ROOT it lowers through the flat tier with every root placed in front of
`before`, in order. Inside an expression a fragment is JSX like any other: an `&&` or `?:` arm
lowers to `Show` with the fragment as its children, and a prop value or a call argument
lowers through the converter to a multi-root NeonNode. There is no fragment-specific
rule left — where no NeonNode is expected (`a ?? <>…</>`) the compiler rejects a fragment
with the same error it gives an element there.

**Regions.** `For` / `Index` / `Show` (`src/macros/ui/flow.ms`) each return
`regionNode(fn)` (`src/render/node.ms`): an anchor text node placed at the region's
position, plus one effect that reconciles the region's rows in front of that anchor.
A `Row` (`src/render/reconcile.ms`) is a NeonNode plus the span of host nodes it
produced (`start`…`end`) and the owner it was created under. `reconcileArrays` mounts
a row that is not in the host yet directly at its final position (`mountAt`), moves a
live row by re-inserting its span, and removes only a row absent from the next list —
insertion targets come from the NEW order (Svelte `each.js`), so a live row is never
detached. While a row mounts, `place` records the first and last host node it put
into the region's parent, which is how a row made of a fragment, a component or a
nested region gets a span without anyone counting nodes; an empty row gets one empty
text node so it still has a position.

**Server rendering.** `renderToString` (`src/render/ssr.ms`) renders the node on a mock
host whose `setStyleClass` registers the rule in the sheet registry, serializes the
result, and disposes the mount. Regions, fragments, components and context scopes
serialize through the same path every host uses (`tests/render/ssr.test.ms`).

## Per-platform economics

What a site gains depends on the platform, and the tier never does: it is a property
of the SITE (see *Selection*).

| Platform | What dominates a mount | Template tier |
|---|---|---|
| Browser (JS backend) | per-op JS cost | one native `cloneNode` replaces the create/append calls |
| Terminal / Void / iOS (C backend) | allocation, then layout/paint/GPU | no cheap clone today — the builder re-runs, same ops as the flat tier |
| Embedded / IoT | binary size | the flat tier unrolls mount code at every site; the template tier shrinks per-site code |

## Gate — measured

The measurements that chose this model, then the one that guards it. Every table is ms
for N mounts of a 6-cell row (N = 1000 unless the table says otherwise), MIN across
rounds and runs (a mean bakes one CPU-stolen round into the answer). Until 2026-09-19 Neon had two
emitters — a description tree mounted by a shared walker ("tree") and mount
instructions emitted per site ("direct") — and the first two tables compare them.

### 2026-08-11/12 — real DOM, headless Chrome

500 rows mounted inside a real `For` region through the public api (`probe/rowSweep.ms`);
ratio = tree ÷ direct.

| dynamic spots / 6 | tree | direct | ratio |
|---|---|---|---|
| 0 | 2.77 | 0.97 | **2.86x** |
| 1 | 2.67 | 1.33 | 2.00x |
| 3 | 3.03 | 1.87 | 1.63x |
| 6 | 5.67 | 4.67 | 1.21x |

There is no crossover — per-site emission wins at every level — and the ratio tracks
the SHARE of dynamic spots, not the row size (a 12-cell row gave the same curve). An
earlier run reported a loss at 100% dynamic (0.74x); that was an artifact of summing
timed rounds. Do not reinstate a "mostly static only" threshold on the strength of it.

### 2026-09-03 — native, mock host with `cloneNode: null`

Release build (`probe/nativeEmit_q4m.ms`). `cloneNode: null` is what terminal and void
advertise, so the template tier re-runs its builder and issues
exactly the ops the tree did; everything won is allocation and the walker's loop.

| dynamic spots / 6 | tree | direct | ratio |
|---|---|---|---|
| 0 | 3.81–4.46 | 1.44–1.60 | **2.6–2.8x** |
| 3 | 4.59–5.28 | 2.27–2.59 | **2.0x** |
| 6 | 6.14–7.24 | 4.04–4.57 | **1.5x** |

Same shape as the browser, which refuted the prediction that the C lane would gain
"allocations only, small". That closed the last per-target branch; what remained
tree-emitted — every component body, every region row built by hand, SSR — is what the
one-NeonNode arc removed.

### 2026-09-19 — one NeonNode against the two emitters it replaced

`bench/nativeEmit.ms`, msc v0.2.55. "Before" is the P0.5 baseline source (`5c2802e`)
REBUILT with the same compiler and made to insert each root into a fresh parent, as
the new bench must — the baseline as first recorded returned a detached node. Six
interleaved runs, min of 6×3. `comp3` is the dyn3 row as the body of a component,
`void3` is dyn3 mounted into one void host root.

| cell | before: tree | before: direct | now, `cloneNode: null` | now, with clone |
|---|---|---|---|---|
| comp3 | 6.87 | 5.76 | **2.54** | 2.63 |
| dyn0 | 4.09 | 1.46 | 2.05 | 1.63 |
| dyn3 | 5.05 | 2.28 | 2.61 | 2.63 |
| dyn6 | 7.08 | 3.18 | 4.26 | 3.41 |
| void3 | 374.0 | 366.3 | **318.8** | — |

- **A component body is 2.3–2.7x faster.** It used to be tree-emitted on every target
  whatever the call site did; it now goes through the same tiers as any other site.
  This is the case the arc was for.
- **Against the tree, every cell is 1.6–2.0x faster**, and void is not slower in any of
  the five sessions measured (229–319 now, 259–374 before).
- **Against the retired direct emitter the rows read 0.3–1.1 µs per mount slower in this
  session, under load 6–19.** 2026-09-20 below re-measures it at lower load and
  attributes it: 0.07–0.3 µs per row remain, the emitted C per row is identical, and the
  named extra work is `place()` and the nullable `setAttr`.

Caveats, so the numbers are not over-trusted: every session ran under load 6–19 from
parallel builds (ratios held across sessions, absolutes did not); the mock host does
less work per op than a real one, which inflates every ratio; `void3` is dominated by
the void host's linear parent-link registry, not by emission. Raw logs:
`probe/l5/bench-*.txt` (gitignored).

### 2026-09-20 — the merge measured whole: mount, update, reorder, remove, memory, size

How it was measured. msc v0.2.55, binary `7f80b93b`. "Old" is `git archive 5c2802e` (the
last commit with both emitters) built with the same compiler beside the current tree; old
and new binaries run alternately in one session, and every cell is the MIN over all runs
and rounds. Load average (1 min) is written beside each table; no step started above 14.
Every time is in ms, **lower is better**. Probes and raw logs are in `probe/m/`
(gitignored): `run.sh` → `measure.log`, `ops.sh` → `ops.log`, `residue.sh` → `residue.log`.

**Size.** Bytes, lower is better. Native: `__text` of one 8-site app (`probe/m/sizeApp.ms`
and its old twins), all three printing the same 728-character markup. JS: gzip -9 of
`examples/showcaseDom.ms`.

| build | old: tree | old: direct | new |
|---|---|---|---|
| native app, `__text` | 328 164 | 309 884 | **301 232** |
| showcaseDom JS, gzip | 33 517 (both emitters shipped) | — | **33 490** |

Verdict: the one emitter is smaller than either old emitter alone.

**Mount, native.** `bench/nativeEmit.ms` against `nativeEmitFair.ms` in the old tree: one cell is
1000 rows of 6 spans, each into a fresh parent, on the mock host; dynN = N of the 6 spans
bound to a signal; `comp3` = the dyn3 row as a component body; `void3` = dyn3 into one void
root. "No clone" = host with `cloneNode: null` (terminal, void); "clone" = mock with
`cloneNode`. 10 interleaved runs × 3 rounds, load 6.5–13.

| cell | old: tree | old: direct | new, no clone | new, clone |
|---|---|---|---|---|
| dyn0 | 3.48 | **1.20** | 1.50 | 1.29 |
| dyn3 | 4.12 | **1.93** | 2.01 | 2.03 |
| dyn6 | 5.74 | 3.35 | 3.44 | **2.49** |
| comp3 | 4.36 | 4.32 | 2.19 | **2.10** |
| void3 | 228.7 | 234.6 | 233.0 | — |

Verdict: against the tree every cell is 1.7–2.3x faster, a component row is 2x faster
than either old emitter, and against the old direct emitter a plain row costs 0.07–0.3 µs
more without clone (see *Residue*). `void3` is equal in all three: it is the void host's
O(N²) parent registry (arc `void-host-links`), not emission.

**Mount, Chrome.** `probe/m/domSweep.ms`: 500 rows in a `For` through the public api,
headless Chrome, ms per 1000 rows, 5 interleaved page loads × 7 rounds, load 11–23.
Chrome's timer is coarsened to ~0.1 ms, so cells closer than 0.2 are equal.

| dynamic spans / 6 | old: tree | old: direct | new |
|---|---|---|---|
| 0 | 4.8 | 2.0 | 2.2 |
| 1 | 5.4 | 2.6 | 2.6 |
| 3 | 6.0 | 3.4 | 3.6 |
| 6 | 7.0 | 5.2 | 5.2 |

Verdict: the new emitter equals the old direct emitter within timer resolution and is
1.3–2.2x faster than the tree.

**After mount, Chrome.** `probe/m/opsDom.ms`: 1000 rows in a `For`, each row the dyn3 row;
"plain" writes the row inline, "comp" writes it as a component. One cell is ms per
operation: *mount* the 1000 rows; *update* one set of the shared signal (3000 text writes,
batch of 20); *reverse* the list (batch of 20); *swap* rows 1 and 998 (batch of 20);
*remove half* (the last 500 rows, mean of 5 fresh mounts). 5 interleaved page loads × 7
rounds, load 3–12.

| op | old: tree | old: direct | new | new ÷ best old |
|---|---|---|---|---|
| mount, plain | 4.00 | 2.30 | **1.90** | 0.83 |
| mount, comp | 3.60 | 3.70 | **2.00** | 0.56 |
| update, plain | 0.945 | 0.805 | **0.720** | 0.89 |
| update, comp | 0.995 | 0.975 | **0.720** | 0.74 |
| reverse, plain | 0.685 | **0.645** | 0.935 | **1.45** |
| swap, plain | 0.385 | **0.365** | 0.625 | **1.71** |
| remove half, plain | 0.260 | 0.220 | 0.220 | 1.00 |

The comp rows of reverse, swap and remove read the same as the plain ones on both sides.
Verdict: mount and update got faster; **reorder regressed — swap 1.7x, reverse 1.45x
slower** — and remove is unchanged.

**After mount, native.** `probe/m/opsNative.ms`, the same five operations on the mock host
with `cloneNode: null`, ms per operation, 6 interleaved runs × 5 rounds, load ~3. The mock
host's `insertBefore` and `removeChild` search the child array, so every move costs O(rows)
here and reorder cells are inflated against a real host.

| op, plain row | old: tree | old: direct | new |
|---|---|---|---|
| mount | 5.51 | **3.15** | 3.54 |
| update | **0.437** | 0.488 | 0.442 |
| reverse | **0.859** | 1.013 | 2.064 |
| swap | **0.060** | 0.069 | 1.419 |
| remove half | 0.672 | **0.595** | 0.990 |

Verdict: update is equal; reverse 2–2.4x, swap ~20x and remove 1.7x slower — the same
regression as Chrome, magnified by a host whose moves are linear.

**Why reorder regressed.** Host calls counted by a wrapping host (`probe/m/movesCount.ms`),
1000 rows. Exact counts, not timings.

| op | old: direct `insertBefore` | new `insertBefore` |
|---|---|---|
| reverse | 1000 | 999 |
| swap rows 1 and 998 | **2** | **997** |
| remove half | 1 (+500 `removeChild`) | 1 (+500 `removeChild`) |

The merge replaced the udomdiff reconciler over host nodes with `reconcileArrays` over rows
(`src/render/reconcile.ms`), which mounts a new row in place. It walks the new order and
moves every row whose slot is taken by another, so a swap moves every row between the two
positions; and it finds each row with a linear scan plus a `splice`, O(n²) in the list
length even when the move count is right (reverse). Remove is not affected. Open as its
own arc; nothing in the emitter is involved.

**Memory per mounted row.** The runtime has no allocation counter. Chrome: `usedJSHeapSize`
after two forced GCs (`--enable-precise-memory-info --js-flags=--expose-gc`), before and
after mounting 5000 retained rows, divided by 5000. Native: macOS peak memory footprint
(`/usr/bin/time -l`) of a process retaining 21 000 rows minus one retaining 1000, divided
by 20 000; this includes the mock host's nodes and malloc slack. Bytes per row, lower is
better, min of 5 (Chrome) and 3 (native) runs.

| row | old: tree | old: direct | new |
|---|---|---|---|
| Chrome, plain | 2370 | **1785** | 1889 |
| Chrome, comp | 2440 | 2440 | **1936** |
| native, plain | 9658 | **8163** | 8425 |
| native, comp | 9812 | 9837 | **8577** |

Verdict: a component row is 13–21% smaller than with either old emitter; a plain row is
3–6% larger than the old direct emitter's (100–260 bytes) and 13–20% smaller than the tree's.

**Residue — the native plain-row gap, attributed.** The C that the release build emits for
one `dyn0` row and for one `dyn6` row (the template builder and the wire function) is
identical between old direct and new after renaming; `bindText` is unchanged. What differs
is the runtime around it, each piece timed alone (`probe/m/hostOpsAlone.ms`,
`placeAlone.ms`, 4 interleaved runs × 3 × 200 rounds, load 7.5–7.8), µs per row:

| extra work in the new path | old | new | cost per row |
|---|---|---|---|
| attach the root: `append` → `place()` (`insertBefore` + row bookkeeping) | 0.011 | 0.021 | +0.01 |
| 7 mock `setAttr` (the attribute value became `string \| null`) | 0.242 | 0.284 | +0.04 |
| 7 × `createElement` + `append` | 0.457 | 0.451 | 0 |

Verdict: ~0.05 µs of the 0.07–0.3 µs is named. The rest (up to 0.25 µs, dyn0 only) is inside
this bench's spread: the same old binary's dyn0 ranged 1.20–1.62 ms across the 10 runs.
The "~1 µs per row" of the 09-19 session and of the first 09-20 run was load (6–60);
it does not reproduce at load 7.

**The void host's parent registry.** `bench/voidMount.ms`: rows of 6 spans mounted into ONE void root, µs per row,
lower is better; "append" calls the row node directly, "for" mounts the same rows through a `For`. Before =
`cfd0d9a` (parent links in an array scanned linearly), after = `edd2cf2` (a `Map<Node2D, Node2D>`), same compiler, the
two binaries run alternately, 3 runs, min; load 11.6–15.2. The last row is the `void3` cell of `bench/nativeEmit.ms`
(1000 rows, dyn3), the one the tables above carry.

| cell | rows | before | after | after ÷ before |
|---|---|---|---|---|
| append | 1 000 | 266.3 | 207.5 | 0.78 |
| append | 5 000 | 1 140.3 | 330.5 | 0.29 |
| append | 20 000 | 15 133.6 | 463.2 | **0.03** |
| `For` | 1 000 | 397.2 | 192.6 | 0.48 |
| `For` | 5 000 | 1 859.7 | 362.8 | 0.20 |
| `nativeEmit` void3 | 1 000 | 229.2 | 202.6 | 0.88 |

Verdict: the O(N²) parent scan is gone — 20 000 rows cost 32.7x less per row — but the cost per row is NOT flat yet
(207 → 463 µs from 1 000 to 20 000 rows). `sample` puts ~94% of what is left inside the std `Map` lookup on a ref key
(an entry copy at every probe step, then ORC cycle-candidate registration and collection); reduced without neon or void
and carded at `~/metascript/.inbox/compiler/2026-09-20-map-ref-key-entry-copy-per-probe.md`, which this arc is parked on.
Two sibling-linear paths are also untouched and keep a `For` into one void root quadratic in principle: `childIndexOf`
here, and void's `addChildAt` / `removeChild`, which rebuild the children array.

Not measured, and why: reorder and memory on the void and terminal hosts (the terminal host has no bench; the void
host's own mount cost is the table above and still dominates a row); memory as live bytes on native (no runtime counter; the
footprint delta is an upper bound that includes allocator slack).

## Invariants — the contract every tier and every hand-built node must satisfy

1. **Evaluating JSX is pure** — it allocates the NeonNode and performs no host op
   and no signal read; everything happens when the node is called.
2. **A component body runs exactly once** — any second run is a serious bug
   (`bodyRuns`-counter test pattern).
3. **Every dynamic spot = one effect, created at mount, under the mounting
   owner** — never at build time.
3a. **Only a spot that can observe something gets a computation.** Solid's rule
   (`babel-plugin-jsx-dom-expressions`): an expression carrying a call or a
   property read is reactive; a bare identifier or literal is resolved once at
   mount, so wrapping it would allocate an effect that can never re-run.
   `isReactiveExpr` (`src/macros/ui/reactive.ms`) is the single classifier both
   tiers consult, and it is deliberately conservative — anything it does not
   recognise as inert stays reactive, because a wasted computation is cheap and a
   missed update is not. Pinned by counting host writes across a signal change
   (`element.test.ms`, "an inert expression is classified static, a call stays
   dynamic"), since macro-expansion output cannot yet be inspected the way Solid
   snapshots its compiled JSX.
3b. **A spot writes the host only when its value actually changed.** The signal
   already drops a set to an equal value, but a derived expression maps many
   source values onto one output (`n() > 5 ? "big" : "small"`), so the last
   written value is kept and an identical recomputation is dropped. Both tiers
   and the hand-written builders bind through `bindText`/`bindAttr`
   (`src/render/bind.ms`); `mockToString` cannot see the difference, so the test
   for it counts writes on a counting host (`emit.test.ms`).
4. **Structural change goes through a region + anchor only** — after mount,
   nothing inserts/removes host nodes except `reconcileArrays`.
5. **Dispose is total** — after unmount, signal writes reach zero effects
   (`tests/core/dispose.test.ms`).
6. **A Host adapter matches mock-host semantics op for op** — e.g.
   `insertBefore` detaches first (DOM move semantics). `mockHost()` is the
   reference implementation of the contract.

The existing test suite is these invariants encoded; keep it that way — every
new render feature should land with the invariant it preserves named in its
test.

## Props typing — DX decision (user, 2026-08-08; contract widened 2026-09-10)

The component's props interface is the **single source of truth**; the macro
inserts **no type coercion**. `createSignal` stays generic — `createSignal(0)`
inferring `Accessor<int32>` is correct; want another type, annotate
(`createSignal<number>(0)`, `0 as float32`, …). A repr mismatch is a **checker
error by design**, not a bug (function types are invariant).

**Contract (uniform, 2026-09-10):** every value prop is declared `Accessor<T>`
(optional: `x?: Accessor<T> | null`). `children`, `ref`, `on*` and function-typed
props stay raw. At the call site the macro wraps every value prop — expressions
AND literals — as `accessor(() => expr)`, so the field type matches nominally and
a signal expression can never land as a snapshot. Inside the component a read of
`props.x`, or of `x` after `function C({ x }: Props)`, is an accessor read and
goes through `valueOf` where a value is needed (§Accessor). A value already typed
`Accessor<T>` (`label={props.label}`, `class={count}`) crosses raw, so a prop passed
down never nests as `Accessor<Accessor<T>>`. Negative probe: `probe/thunkProps3.ms` S1.

**Landed 2026-09-12 (phase 4.1).** `isRawPropValue` (macros/ui/reactive.ms) is the
one decision every call site goes through: an arrow/function literal, a JSX-valued prop,
`ref` and `on*` cross raw; everything else is emitted as `accessor(() => v)`
(the node literal stays inline in the macro — a helper that builds nodes
outside a macro body is not available yet, LANG-METAPROGRAMMING "No helper
functions"). `View`/`Text`/`Pressable`/`TextInput` declare `style?: Accessor<Style>
| null`, `class?: Accessor<string> | null`, `delayLongPress?: Accessor<number> |
null`, `value?: Accessor<string> | null`; `Context.Provider` takes `value:
Accessor<T>` and widens it into `provideScope`'s thunk. An object-literal prop is
stamped by the field's payload type (`style={{ gap: 12 }}` against
`Accessor<{ gap: number }>`), which is why a value prop must be `Accessor<T>` and
not a bare `() => T`: a plain thunk field gives the literal no expected type.
`function C({ label, count }: Props)` binds each field as an accessor (compiler
4.0); a pattern without an annotation is a compile error, not a silent snapshot.

## Accessor — reactivity decided by type (2026-09-10)

`Accessor<T> = distinct (() => T)` (src/core/signal.ms). `createSignal` returns
`[Accessor<T>, Setter<T>]` with `Setter<T> = (v: T | ((prev: T) => T)) => void` — a
function argument is always an updater applied to the current value without
tracking (Solid), so when `T` is itself a function type only the updater form
exists — `createMemo` returns `Accessor<T>`, and
`accessor(f)` brands a thunk at zero cost. An `Accessor<T>` widens one-way into
any `() => T` slot (`mapArray`, `For.each`, `Show.when`, a hand-written
callback); a `() => T` never narrows into an `Accessor<T>`.

**Read rule (checker, both backends, 2026-09-14):** `signal.ms` declares
`valueOf(this a: Accessor<T>): T`, the compiler's `valueOf` protocol (LANG.md), so
a bare accessor is read only where the read would otherwise be a type error: a
typed slot, an operand, a condition, a missing member (`count.toString()`), an
index, `switch`, `as`. Wherever the accessor itself fits it stays the accessor:
`const d = count`, `id(count)`, `[count]`, a `() => T` or `Accessor<T>` slot, a
generic parameter, the callee of `count()`. A union such as `Accessor<T> | null`
is not an accessor until narrowed, so `props.x !== null` compares the handle and
the branch body reads the value. The protocol follows import visibility: a module
that reads bare imports something from `core/signal` or from the `src/index.ms`
hub. Positions that take any type do not read: `console.log(count)` and
`String(count)` print the handle — write `${count}` or `count.toString()`. An
overloaded call never reads: it needs a candidate that takes the accessor, or an
explicit `count()`.
`setCount(v)` remains the only way to write.

**Consequences for the macro:** `element` runs after the checker. A
read that had to become a value arrives as a call (`{count * 2}`,
`{props.label + "!"}`) and `isReactiveExpr` classifies it reactive; a bare
`{count}` or `class={props.label}` fails nothing, so it arrives as the accessor,
and the macro reads its `nodeType` (`isAccessorTyped`) to emit a live spot
instead of a one-time write. `{a && <X/>}`, `{c ? <A/> : <B/>}` and
`{xs.map(fn)}` lower to `Show`/`For` (phase 5). **Body-time read:** `const d =
count * 2` at the top of a component body reads once; read it in JSX or
`createMemo` to keep it live.

## References

- `src/render/hostTypes.ms` — the `NeonNode` type and the Host contract
- `src/render/host.ms` — `render`, `mockHost` (the reference implementation of the
  contract)
- `src/render/node.ms` — the hand-written builders, `mountChild`, `regionNode`
- `src/render/bind.ms` — one effect per dynamic spot
- `src/render/template.ms` — template instantiation and the walk steps
- `src/render/reconcile.ms` — rows, `place`, `reconcileArrays`
- `src/render/component.ms`, `src/render/context.ms` — component and provider seams
- `src/render/ssr.ms` — `renderToString`
- `src/macros/ui/element.ms` — the emitter; `src/converters.ms` — the JSX boundary
- `tests/render/emit.test.ms` — what the macro emits, pinned by hand-written goldens
- `docs/RENDER-LAYERS.md` — reconcile/paint/GPU ownership per platform
- PORT-STATUS.md "Design LOCKED 2026-07-30" — the component/JSX contract
