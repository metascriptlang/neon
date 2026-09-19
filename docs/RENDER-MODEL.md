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
accessor-typed, written once otherwise. A NeonNode picked by a reactive condition
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
  session — between 0.2 µs faster and 1.1 µs slower across the five, slower in most —
  and that is not attributed.** Ruled out by measurement: the extra parent node (one shared
  parent per round changes nothing), `insertBefore` vs `append` for the root, the
  compiler version (the baseline rebuilt on v0.2.55 is, if anything, faster than its
  v0.2.54 binary), and the mock host's `setAttr`, which did get dearer when an attribute
  value became nullable but only by ~0.01 µs per attribute. The same rows WITHOUT
  static attributes read equal to the old emitter within 5% (1.66 / 2.89 / 3.89 now,
  1.65 / 2.74 / 3.69 before), and the macro emits the same `setAttr` calls it did. Two
  baseline binaries doing equivalent work differed by up to 30% in the same session,
  so the residue sits inside what this bench can resolve on this machine.

Caveats, so the numbers are not over-trusted: every session ran under load 6–19 from
parallel builds (ratios held across sessions, absolutes did not); the mock host does
less work per op than a real one, which inflates every ratio; `void3` is dominated by
the void host's linear parent-link registry, not by emission. Raw logs:
`probe/l5/bench-*.txt` in the arc's worktree (gitignored).

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
