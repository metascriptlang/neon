# Neon — bug rows still being carried

Open framework bugs of Neon itself. A compiler bug is NOT written here: it is a card in
`~/metascript/.inbox/compiler/` and, once registered, an `L<n>` entry in
`~/metascript/recompiler/docs/KNOWN-ISSUES.md`. The 136 compiler rows this file used to carry were
handed over on 2026-09-20 —
`~/metascript/.inbox/compiler/2026-09-20-neon-bugs-md-compiler-rows-handover.md`, full text at
`git show c00bd2b:BUGS.md`.

Toolchain facts are not written down here: `msc --version` and `cat ~/.metascript/BUILD` answer
them. What the suite passes is not written down here either: `bash tests/run.sh`, read by its exit
code, answers that.

**Rule for this file:** every number is a measurement with the command that produced it. A row that
cannot be reproduced is re-measured and rewritten, never corrected on top.

---
## §3 — Neon-side and environment

- **~~`Index` never mounts a row appended to the list~~ ✅ CLOSED 2026-09-18 (Lát 4c, Neon `8644587`
  fix + `b1cfb19` guard) — the suspected root was WRONG, and `src/core/array.ms` was never touched.**
  Filed by Lát 1.1 as "suspect `indexArray` pushes onto a value-copied array parameter". Measured:
  `indexArray` grows correctly on its own (`probe/l4c/indexAppend.ms` — 1 → 2 → 3 rows). The real
  root is an ALIAS across the producer/consumer boundary: `indexArray` mutates the very array it
  handed out last time (`mapped.push(row)` then `mapped = mapped.slice(0, newLen)`), while
  `mountRegion` (`src/render/host.ms`) kept `current = next`. `probe/l4c/aliasCheck.ms` prints it:
  after one append the array returned by the PREVIOUS call has length 2 for `indexArray` and 1 for
  `mapArray` (which rebuilds `nextMapped` fresh). So `reconcileArrays(host, parent, current, next,
  anchor)` was handed `a === b`, matched every row, and did nothing. Solid has the same producer
  behaviour (`array.ts:243` `return (mapped = mapped.slice(0, len))`) and is safe only because its
  consumer never keeps the memo's array — `insertExpression` holds a normalized DOM-node array. Fix
  is therefore on the consumer, one line: `current = next.slice(0, next.length)`. Guard
  `tests/render/flow.test.ms` "Index grows and shrinks with the list" (append, second append, shrink),
  proven RED on the line before the fix.

- **~~OPEN Neon (2026-09-18, found by Lát 3 of the one-NeonNode arc) — a range of more than one node
  does not survive the reconciler's replace branch.~~ ✅ CLOSED 2026-09-19 (one-NeonNode arc: fix Lát 4b
  `df93941`+`9f23709`+`facb35b`, guard Lát 5 `e3d87ae`).** `reconcileArrays` (`src/render/reconcile.ms`)
  was rewritten on the Svelte model settled below: there is no replace branch, a row that survives is
  never detached, a row not in the host yet is mounted at its final position (`mountAt`), and the
  destination is the start of the row occupying the slot in the NEW order, or the region anchor.
  Measured: the fuzz of this row ported to the `Row` API with FRAGMENT rows of 1–3 nodes between a
  leading sibling and a trailing anchor — 2400/2400 steps, 1301 multi-node rows, 0 lost or misplaced,
  on C and `--target=js` (`msc run probe/l3_rangeFuzz/mainRowApi.ms`; `main.ms` beside it still speaks
  the retired `Range` API and no longer compiles). It is now
  a cell of `tests/render/reconcile.test.ms`, "fragment rows of one to three nodes survive random
  reorder, drop and remount", proven RED by making `moveRow` carry only the first node of a span
  (4 of 6 cells red, this one included) and green on restore. The record of the failure follows.
  `reconcileArrays` (`src/render/reconcile.ms`)
  now runs on `Range {start, end}`; every range operation walks `start → end` by `nextSibling`.
  udomdiff's map-fallback `replaceChild` detaches `a[aStart]` even though the map proves it reappears
  later in `b`, and re-inserts it from the caller's array on a later step. A detached single node is
  still insertable; a detached RANGE is not — `nextSibling(start)` is null, so only the first node
  comes back and the rest are lost. Measured with `probe/l3_rangeFuzz/main.ms` (400 trials × 6 steps,
  ranges of 1–3 nodes): **0 failures with every range `{n, n}`** (2400/2400, so the port is faithful
  for today's rows), and an immediate loss of nodes as soon as a range holds two. Not a regression:
  rows are `{n, n}` until Lát 4b. **Direction settled 2026-09-18 against the Svelte source** (cloned
  to `~/projects/svelte`, `packages/svelte/src/internal/client/dom/blocks/each.js`): `reconcile` there
  NEVER detaches a row that survives — a live row is always `move(effect, next, anchor)`, and only
  rows in `to_destroy` are removed. `move` itself matches this port line for line (next sibling read
  BEFORE the insert, stop at `end`) with ONE difference that is the whole answer: its destination is
  `next.nodes.start` — the start of the row that follows in the NEW order — not `nextSibling` of the
  row that precedes in the OLD tree, which is what udomdiff's ref node is. So 4b should drop the
  replace branch and move to a next-row destination. The measured failure of a naive "move, do not
  remove" (32/2400 even for single-node rows) does NOT contradict this: that variant kept udomdiff's
  old-tree ref node, so it was a hybrid of the two models, not Svelte's.

- **NOT A BUG — deliberate, decided 2026-09-18 after reading both references: `ref` follows REACT,
  not Solid.** `ref` is component/event surface, and the standing rule is reactivity = Solid,
  component/event surface = React Native. React attaches refs innermost-first, after the subtree is
  built: `~/projects/react/packages/react-reconciler/src/ReactFiberCommitWork.js` runs
  `recursivelyTraverseLayoutEffects` (`:682`, `:627`) BEFORE `safelyAttachRef` (`:700`, `:641`).
  Neon does the same on both emissions, and the older cell pinning that a `ref` already sees a bound
  reactive child follows from it. Solid is the one that differs — `dom-expressions`
  (`~/projects/dom-expressions`, `packages/babel-plugin-jsx-dom-expressions/src/dom/element.js`)
  `unshift`s a `use(ref, el)` onto that element's own `exprs` (`:676`, `:694`, `:704`) while
  `transformChildren` `push`es each child's `exprs` afterwards (`:1122`), and attributes are
  transformed before children (`:171` before `:188`). A parent's `ref` therefore runs BEFORE any
  child's `ref`, and before the `insert(...)` that binds a dynamic child. Neon runs React's order:
  `tests/render/ref.test.ms` pins innermost-first, and an older cell pins that
  a `ref` already sees a bound reactive child (`"<p>7</p>"`) — both stay. What all three agree on:
  `ref` fires before the site root is placed (Solid calls `use` inside the IIFE, before
  `return _el$`). Lát 4d only has to keep this order when the two emitters merge into one.
- ~~**OPEN 2026-09-15 — direct emission FREEZES a whole-style call SILENTLY, and rejects the per-field
  reactive styles that tree emission supports.**~~ ✅ **CLOSED 2026-09-17 by Lát 0 of the one-NeonNode
  arc, every table row now a differential cell in `tests/render/direct.test.ms` (47/47 native and
  `--target=js`):** whole-style call → `bindStyleAll` `8ad2bb8` (0.1); object literal → static
  fields once + `bindStyleProp` per reactive field `0dc155e` (0.2); layer array → compile-time merge
  or `layerStyles` `ff0a42e` (0.4); static sheet → `applyStaticStyle`, the CSS-class route `9cce2b6`
  (0.5); a reactive layer is rejected at expansion on BOTH macros `ec2d383` (0.8). The stale docs
  sentence ("same S4 field validation") is corrected in `direct.ms` and RENDER-MODEL.md by 0.10.
  Was: measured on the installed msc (deployed 2026-09-15
  12:09) with Neon at `ee953bc`, every probe in `probe/` (gitignored), tree emission as the oracle:

  | `style=` | tree (`element.ms`) | direct (`direct.ms`) | probe |
  |---|---|---|---|
  | `{s()}`, `s` reads a signal | `padding:10px` → `20px` | **stays `10px`, no diagnostic** — D4 and D3, native and `--target=js` | `styleWholeCall.ms`, `styleWholeCallD3.ms` (a `<Text>` child forces the flat tier) |
  | `{{ padding: w }}`, bare accessor | reactive, `10px` → `20px` | compile error `Argument type mismatch in 'setStyle' arg 1: got __anon1__paddingx, expected Style` | `styleTreeReactive.ms`, `styleBareAccessor.ms` |
  | `{{ padding: w(), margin: 4 }}` | split at COMPILE time: `padding` one effect, `margin` one constant | macro error `a style field cannot call a function … (reactive style fields land in S4)` — stale, S4 landed in `element.ms:330-352` | `styleTreeReactive.ms`, `styleCallField.ms` |
  | a static sheet style | constant, CSS-class route (`cssId` → `setStyleClass`, `dom.ms:174`) | always inline `setStyle` (`applyCss`, `dom.ms:168`) | code reading |

  Cause: `direct.ms` binds `const _s = <expr>` and calls `host.setStyle(_r, _s)` ONCE — D4 wire
  (~352-364) and D3 `emitEl` (~564-581) — with no `isReactiveExpr`/`isAccessorTyped` test, while
  `element.ms:406-414` routes the same whole-style expression to `withDynStyleAll` (one whole-style
  effect) and `:330-352` peels reactive fields into `withDynStyle`. The runtime pieces direct would
  emit already exist (`bindStyleAll` / `bindStyleProp`, `host.ms:126-132`).
  Why nothing caught it: `direct.test.ms` has no cell with a reactive style, so the differential never
  compared one. Same asymmetry as fragments — tree gained S4 and it was never mirrored, and the docs
  claim otherwise: RENDER-MODEL §Selection lists `style={s()}` under "direct — one effect per spot",
  and §Naming says direct has "the same S4 field validation as element.ms".
  Fix direction: port `element.ms`'s three-channel style classification into direct (whole reactive →
  `bindStyleAll`, reactive field → `bindStyleProp`, static → constant + class route, compile-time
  layer merge), differential cells red first. It belongs to the "one NeonNode" merge (the merged macro
  must carry the UNION of both macros' compile-time analyses), but a silent freeze should not wait on
  that arc if it slips.
- **~~PARKED 2026-09-17 (one-NeonNode arc, outside Lát 0) — `on*` is classified two ways.~~ ✅ CLOSED
  2026-09-19 (`447ed07`): one predicate, `isEventName` in `reactive.ms` — `on` + an uppercase letter,
  React's rule — decides it for a tag, a spread field and a component prop.** Measured before the fix:
  `<p once="x" online={v()}>` did not compile on either tier ("Argument type mismatch in 'addEvent'
  arg 2: got string, expected function"). Pinned by the two "once and online are attributes, not
  events" cells in `emit.test.ms` (`msc test tests/render/emit.test.ms` rc=0 on C and `--target=js`;
  `grep -rn 'startsWith("on")' src` prints the predicate alone). Was: on a lowercase tag both macros
  tested `startsWith("on")`; a component prop needed `on` + an uppercase letter.
- **PARKED 2026-09-20 — `<Index each={xs()}>{row}</Index>` is refused at `createComponent`, so the
  index-keyed list has no JSX surface.** Not Neon's: reduced to 11 lines with no JSX and no Neon
  import — a generic callee passed as a value argument cannot bind its own type parameter through a
  `distinct` alias. Three green controls isolate it (explicit `T`; the same structure with a
  NON-distinct alias; a `T[]` wrapper). `<For>` is green as a tag because its row carries `T` bare,
  while `Index<T>`'s carries `Accessor<T>` and `Accessor<T> = distinct (() => T)`. Card, park site and
  the controls: `~/metascript/.inbox/compiler/2026-09-20-generic-callee-type-param-through-distinct-alias.md`.
  Parked at `tests/render/flow.test.ms` above the two `Index<number>({…})` cells; nothing worked
  around in `src/`.

- **PARKED 2026-09-17 (one-NeonNode arc) — flow lowering does not cover `||`, `??` or
  `.map(namedFn)`.** Only `&&`, the ternary and `.map(arrow)` are lowered (`lowerFlowTree` in
  `element.ms`). Measured 2026-09-19 on msc v0.2.55 (`bce99dbf`), each form on its own:
  - `{xs.map(namedRow)}` — ✅ CLOSED 2026-09-20 as a rule, not a feature. The person ruled 2026-09-19
    that a callback which does not fit `map` is an error, arrow or named; recompiler `76a6a9bd` +
    `0b283fd4` (installed `7f80b93b`) closed the hole that let the arrow through. A For row takes an
    `Accessor<number>` index, which is never `map`'s callback, so `.map` lowers only a row WITHOUT an
    index (`preludeFlow.test.ms`); a row with an index, `number` or `Accessor`, arrow or named, is
    refused and pointed at `<For>` (`3af6f81`: "a .map row that takes an index is written
    <For each={xs}>…"; before it, a `number` index failed as "Type 'function' is not assignable to type
    'function' for field 'children'"). Measured 2026-09-20 under that commit: a `number` index compiles
    for `map` and only the macro message stops it, an `Accessor<number>` index collects both that message
    and the checker's "Argument type mismatch in 'map' arg 0" — so ONE fixture, the `number` one, pins the
    rule. Permanent rejection fixtures: `tests/macros/mapIndexRowRejected.ms`,
    `tests/macros/mapNamedRowRejected.ms`. A function-typed value is a row and a raw component child,
    so `<For each={xs()}>{namedRow}</For>` works (`flow.test.ms` "For takes a named row function as its
    child"). A named row that ignores the index waits on the design card
    `…/2026-09-19-named-function-with-fewer-params-rejected.md`.
  - `{ready() || <i>wait</i>}` — "JSX expression must be consumed by a macro". The left arm is a VALUE
    that renders when truthy (a string, a node; a `true` renders nothing), so the lowering is
    `<Show when={a} fallback={<X/>}>{a}</Show>` and needs a boolean / nullable value as a child:
    PARKED with ROADMAP Next 7 on
    `~/metascript/.inbox/compiler/2026-09-19-design-typed-slots-value-read-and-text-coercion.md`
    (the user ruled 2026-09-19 that `null` and `boolean` children come from that design, not from a
    Neon patch). No boolean-only shortcut is added meanwhile.
  - `{maybe ?? <i>none</i>}` with `maybe: NeonNode | null` — ✅ CLOSED 2026-09-19 (`c1920fa`) through
    `element(<jsx/>)`: it lowers to `<Show when={maybe !== null} fallback={<X/>}>{maybe}</Show>`, the
    nullable node mounts through the new `NeonNode | null` child (`5291f67`); a reactive left arm is
    rejected with the "picked by a reactive condition" message. Pinned by `flow.test.ms`
    "a ?? <X/> child mounts the node when present and the JSX arm when null" (element arm and fragment
    arm; `msc test tests/render/flow.test.ms` rc=0 on C and `--target=js`). In bare JSX too since
    2026-09-20: `preludeFlow.test.ms` "bare JSX lowers ?? over a nullable node".
- **✅ CLOSED 2026-09-20 (recompiler `0f1e6735`, installed `7f80b93b`) — every nullable slot was red in
  BARE JSX and green through `element(<jsx/>)`.** Pinned by the four "— bare JSX" cells at the end of
  `emit.test.ms` (`msc test tests/render/emit.test.ms` rc=0 on C and `--target=js`); the fixture
  `bareNullableChildRejected.ms` is gone. Found with it: the lowering names `Show` / `For`, which the
  prelude did not export, so bare JSX with `&&`, `?:`, `??` or `.map` failed with "Undefined variable
  'For'" unless the file imported them — `src/converters.ms` exports `For`, `Index` and `Show` since `bd295d2`
  (`preludeFlow.test.ms`). Was: A nullable `on*` / `ref` / `style` (Lát 0.11), an `Accessor<string> | null`
  attribute and a `NeonNode | null` child all emit `const _o = v; if (_o !== null) { f(_o); }`. Called
  as `element(...)` the `if` narrows `_o`; when the converter `jsxToNode` builds the same
  `MacroInvocation` it does not ("Argument type mismatch in 'addEvent' arg 2: got Maybe_fn…", "No
  matching overload for 'mountChild'"). Reduced outside Neon — a 35-line macro + converter, same
  split. Every cell that pins these features calls `element(...)`, which is how it went unseen since
  Lát 0.11.
- **✅ CLOSED 2026-09-19 (`0daeddb`) — a reactive `class` on View / Text / Pressable / TextInput froze at
  its first value, silently.** `primitive()` read it once (`attr("class", props.class as string)`).
  Measured before the fix: `<View class={cls()}>` kept `class="a"` after `setCls("b")` on all four.
  View, Text and Pressable are now written in JSX (`<view class={props.class} style={props.style}
  ref={props.ref}>{props.children}</view>`; Pressable hands its gesture handlers over as nullable
  `on*`), which needed two macro additions: an `Accessor<string> | null` attribute binds when present
  and leaves no attribute when null, and a `NeonNode | null` child mounts when present (`5291f67`,
  pinned on both tiers in `emit.test.ms`). TextInput keeps `hostElement` with `class` as a `dynAttr`:
  its nullable `onChangeText` is what the macro rejects until `const` narrowing survives a closure
  (the KNOWN-ISSUES L47 row in §2; fixtures `optChangeText{Template,Flat}Rejected.ms`). Pinned by
  `universalTags.test.ms` "a reactive class follows its signal on every component of the vocabulary"
  (rc=0 on C and `--target=js`; importers `press`, `ref`, `fragment`, `tests/platform/terminal`,
  `tests/platform/void`, `tests/style/style` rc=0).
- **~~PARKED 2026-09-17 (one-NeonNode arc) — a fragment inside a prop of a NESTED element is reported
  as "inside an expression".~~ ✅ CLOSED 2026-09-19 (`d9a46c8`): the message and `findFragment` are gone;
  a fragment prop value lowers through the converter (`fragment.test.ms` "a fragment is a fallback").** Code reading: `findFragment` walks every child subtree attrs included
  (`reactive.ms:76`), so a fragment that is a prop VALUE gets the expression-container message.
- **PARKED 2026-09-17 (one-NeonNode arc) — `isAccessorTyped` ~~exists twice (`element.ms`,
  `direct.ms`) and~~ matches neither a type alias of `Accessor<T>` nor `Accessor<T> | null`.** The
  duplicate is ✅ CLOSED 2026-09-19 by the macro merge (`direct.ms` is gone;
  `grep -rn "function isAccessorTyped" src` prints one line, `element.ms`). The alias and nullable
  arms stay PARKED on the compiler: how a macro asks for a type is part of
  `~/metascript/.inbox/compiler/2026-09-19-design-typed-slots-value-read-and-text-coercion.md`
  (ROADMAP Next 7); no Neon-side name matching is added meanwhile.
- **~~PARKED 2026-09-17 (one-NeonNode arc, Lát 0.9 cleanup) — the component-children wrapping block
  exists three times:~~ ✅ CLOSED 2026-09-19 by the macro merge.** `direct.ms` is gone and the block
  lives once, in `componentCall` (`grep -c 'keys.push("children")' src/macros/ui/element.ms` = 3, the
  three arms of that one block). Children that are not a single raw value or a single element lower
  through a root fragment, so a static `{expr}` child reaches `mountChild` as text — pinned by
  `emit.test.ms` "a static string expression as a component's only child mounts as text"
  (`msc test tests/render/emit.test.ms` rc=0 on C and `--target=js`). Was: `direct.ms` root (~:259)
  and nested component (~:903), plus `element.ms`.
- **`voidHost`** — ✅ **GREEN (3/3).** Both problems recorded here were MIS-DIAGNOSED; see §5 for the
  four real roots. Corrections worth carrying forward:
  - **"env: sokol_gfx.h not present" was WRONG.** `sokol_gfx.h` was on disk the whole time at
    `void/deps/sokol/`. The header was unreachable because `@passC("-Ideps/sokol")` is resolved
    against the **process CWD**, and Neon builds from its own root — a compiler bug, not a missing
    dependency. **Nothing was ever installed to fix this.**
  - **The `renderToHost arg 0: got string` type error no longer existed** when re-measured; it had
    been fixed by an earlier session's compiler work and the row was never re-measured. Per this
    file's own rule: re-measure before repeating a claim.
- **`terminal`** — ✅ FIXED 2026-07-21, Neon-side, stays green (284/284). Was "two short texts in a row
  render as 1 line". Two fixes in `src/platform/terminal/paint.ms`: tag `"row"` now defaults
  flexDirection to row; `getAttr`/`getAttrNum` guard with `.has(name)`.

---

## §7 — Small debts (not bugs, but owed)

Each is cheap, none blocks anything, all were surfaced by the sessions that closed §1.

- **`imported but never used` is a FALSE POSITIVE for names used only in a MACRO BODY** (2026-09-03,
  the import-hygiene sweep). `src/macros/ui/style.ms` imports `SourceLocation` from `std/meta` and
  uses it only inside the `createStyles` macro body; the warning pass does not read macro bodies, so
  it reports the name dead. Acting on it breaks expansion for every consumer:
  `Macro 'createStyles' body: Unresolved type 'SourceLocation'` + `evaluator unavailable` → 9 red
  files across both lanes, measured. **Never trust the warning in a module that declares a macro** —
  the working rule now is: only remove an import the warning flags in BOTH lanes AND whose module
  declares no macro, then re-sweep. Compiler-side fix would be to walk macro bodies in the same
  aliveness pass.

  **That rule is not sufficient — TYPE-position uses are missed too** (2026-09-07, the barrel
  sweep). `src/render/context.ms` declares no macro, yet the warning flags `Computation`, which is
  used at `context.ms:43` as the annotation of `const scope: Computation = {…}`. Same shape in
  `src/macros/ui/style.ms:153` (`let locs: SourceLocation[]`). So the aliveness pass counts only
  VALUE positions: an import reachable solely through an annotation reads as dead. Removing on the
  warning's word yields an unresolved type, not a cleanup. Until the pass walks type positions as
  well as macro bodies, the warning is advisory only — grep the name before touching the import.

- **fn VALUES don't get arity subsumption — only literals do** (2026-09-03, the event arc).
  msc v0.2.53 pads a LITERAL lambda to its slot's arity (`onClick={() => …}` works), but a 0-arg
  fn passed by NAME (`const inc = () => …; onClick={inc}`) is still a loud
  `Argument type mismatch` — the strict `isFunctionAssignable` relation was kept for values on
  purpose (no conversion exists to materialize; an adapter closure through the lifter is a real
  arc — "Stage 2" in the bug118 design). Workaround, used in `counter.test.ms`/`direct.test.ms`:
  annotate the decl (`const inc: (e: NeonEvent) => void = () => { … }`) so the literal is padded
  at its own check site. TS allows the value form, and RN idiom (`const onPress = …`) hits it —
  promote Stage 2 when the starter components go RN.

- **The type-owner registries are process-global and never reset** (2026-08-17, the TypeInfo arc).
  `recordGlobalTypeOwner` / `recordGlobalTypeShape` (`src/checker/context.ms`) accumulate for the
  life of the PROCESS, so in a test binary they carry entries across independent in-process
  compiles. That leaked once already: the `types.ms` unit cells ("enum emits typedef and defines",
  "interface emits struct") build synthetic types with no `sym` and expect the bare `Color`/`Point`,
  but picked up an owner recorded by an earlier snippet compile and got a qualified name. Shipped
  fix gates the fallback on `g.checkerCtx !== null` — synthetic types stay bare — which is correct
  but indirect. The honest shape is a per-compilation reset (idiom already in the tree:
  `resetGenDestroyHooks()` / `resetGenericTypeInsts()`); do it the next time that code is touched,
  and note that the expectations were NOT edited to accept the new spelling.

- **JSX fragment `<>…</>` is silently dropped by BOTH emissions** (NEW 2026-08-09, found
  auditing D3 solidity before D4): `element(<><p>a</p><p>b</p></>)` AND
  `direct(<>…</>)` both compile clean and mount NOTHING — `probe/fragProbe.ms` prints
  `<root></root>` for both. Parity holds (differential can't catch it) but semantics are
  wrong vs Solid, and there is zero diagnostic. Tree = spec is affected too, so per the
  arc rule the fix goes tree-first through `element.ms` (sacred — needs design + approval):
  either a real fragment branch (multi-root NeonNode) or a loud macro error rejecting
  fragments until then. `direct.ms` mirrors afterward. Not a D4 blocker (template-clone
  operates on elements).
  **2026-09-10: loud rejection LANDED** — `findFragment` (`src/macros/ui/reactive.ms`) walks every child,
  both macros `error("fragments are not supported yet")`; gate `tests/macros/fragmentRejected.ms` proven red
  without the guard. Real fragments = plan phase 7 (flatten in child position, multi-root over `regionNode`).

  **2026-09-13: real fragments LANDED in the TREE emission** (phase 7, tree-first — `direct.ms` still
  rejects and is the remaining half). `tests/render/fragment.test.ms` = 5 cells, green on C and js;
  `tests/macros/fragmentRejected.ms` is gone (its contract is obsolete) and
  `tests/macros/fragmentInExprRejected.ms` replaces it.

  **The `regionNode` route named above was REFUTED by reading Solid.** `insertExpression`
  (`dom-expressions/src/client.js`) flattens nested arrays in `normalizeIncomingArray` and sets
  `dynamic` only when an item is a FUNCTION; a static array takes `appendNodes(parent, array)` — no
  effect, no anchor, no `reconcileArrays`. Routing a static fragment through `regionNode` would apply
  Solid's DYNAMIC branch to a static value: it buys an anchor text node plus an effect, and
  `renderToString` throws on regions, so it would also break SSR. The Nim original is no reference
  here — its `Fragment` (`src/core/component.nim:111`) is dead code, called from nowhere, and
  `render*(container, elementProc: proc(): Element)` is single-root.

  Shipped shape: the macro flattens fragments at COMPILE time (`flattenFragments`, matching
  `normalizeIncomingArray`'s recursion), a root fragment emits `fragmentNode([...])`, and `mountInto`
  splices its children into the parent — Solid's static `appendNodes`. `renderNode` throws on one (it
  must return exactly one host node) exactly as it does for a region.

  `NeonNode` gained `isFragment: boolean`. The first cut inferred the variant instead
  (`tag === ""` with non-empty `children`) and that was the wrong call twice over. It broke a
  degenerate case — `fragmentNode([])` is byte-identical to `text("")`, so a bare `element(<></>)`
  mounted one stray empty text node where Solid mounts none — and, worse, it made fragments the only
  variant in the type with no field of its own, readable solely by elimination, so any future text
  node carrying children would silently become a fragment. Every other variant already declares
  itself (`isDyn`, `region`, `componentFn`, `scope`), and `isDyn` is precedent for a bare boolean, so
  the field IS the house model and the inference was the improvisation. Only `node.ms` builds these
  literals, so the change is 7 literals plus the interface line; the three readers
  (`renderToString`, `renderNode`, `mountInto`) now test the field.

  **2026-09-15: the DIRECT half LANDED — phase 7 closed.** `direct.ms` carries the same
  `kidsOf`/`flattenFragments` pair as `element.ms`, so a fragment child is folded into the parent's
  op sequence at compile time and emits nothing of its own; nested fragments and `<></>` erase the
  same way. Nothing in the runtime moved: flattening happens entirely inside the macro, and a
  component that returns a fragment already mounted correctly through the child seam
  (`renderToHost(_kN, host, _rN)` → `mountInto` → `isFragment`).

  A root fragment is REFUSED at compile time, and that is the design, not a missing feature. Direct
  emission is `renderNode` partially evaluated (RENDER-MODEL §Direct emission), a mount closure IS a
  `NeonView`, and `NeonView` returns exactly one `HostNode` — the same wall `renderNode` hits at run
  time. The macro raises it one phase earlier with the escape hatches named:
  `"a fragment has no single host node to return: wrap the children in one element, or build it with
  element() and mount via renderToHost"`. `Host` has no fragment primitive to return instead
  (`hostTypes.ms` is create/append/insertBefore only — terminal and void have no `DocumentFragment`),
  so inventing one would be a mechanism with no model behind it.

  The blanket `findFragment(node)` guard is gone from `direct.ms`; the narrower stray check it was
  replaced by (`kidsOf` loop, byte-identical to `element.ms`) is pinned by
  `tests/macros/fragmentInExprDirectRejected.ms`, and the root refusal by
  `tests/macros/fragmentDirectRootRejected.ms`. `tests/render/fragment.test.ms` gained 6 cells, five
  of them differential against tree emission (the oracle), covering child flatten, nested flatten,
  empty-fragment erasure, a fragment under a component tag, a reactive spot inside a flattened
  fragment, and a component returning a fragment.

  **✅ CLOSED 2026-09-19 (one-NeonNode arc) — the root fragment, the fragment row, and (a) the
  fragment inside an expression (`d9a46c8` + cells `ea92f08`).** (a): an `&&` or `?:` arm that is a
  fragment lowers to `Show` exactly as an element arm does (`lowerFlowTree` runs before
  `flattenFragments`), a fragment prop value or call argument lowers through the converter, and the
  fragment-specific rejection plus `findFragment` are DELETED — measured with the check off, a
  fragment and an element behave identically in every expression position: both work as a call
  argument, both are rejected by the COMPILER under `??` and in a ternary mixed with a string ("JSX
  fragment must be consumed by a macro", pinned by `tests/macros/fragmentNullishRejected.ms`). Seven
  cells in `tests/render/fragment.test.ms` (&& between siblings, fragment/fragment, fragment/null,
  null/fragment, fragment/element, nested condition + live spot, static condition, `fallback`, call
  argument), RED before the change with the old message; `bash tests/run.sh` rc=0 on all four lanes.
  The first half of this note, as written before (a) landed:
  **the root fragment and the fragment row CLOSED; only (a) below was left, and it was loud.** A NeonNode is `(host, parent, before) => void`, so it may own any number of
  host nodes: a root fragment lowers through the flat tier with every root placed in front of
  `before`, and a region row records the span `place` produced, so a row may be a fragment.
  `tests/macros/fragmentDirectRootRejected.ms` is gone with the refusal. Measured on msc v0.2.55:
  `msc test tests/render/fragment.test.ms` rc=0 on C and `--target=js` ("a top-level fragment mounts
  as siblings under one parent", "a fragment row moves and leaves as one span", "a row that opens
  with a closed region still moves with its span"), plus the fuzz cell named in §3. What follows is
  the 2026-09-15 record; its (b) and its root-fragment case no longer hold.

  Still open, and the honest gap vs Solid — ONE family, every case loud, none silent: a fragment
  only works where a parent is already in hand. (a) Inside an expression container
  (`{cond && <>…</>}`) BOTH macros reject it at compile time. (b) Through `viewOf` — hence as a `For`
  row, since `For` mounts rows with `mountView` — it throws at run time, because a `NeonView` must
  return exactly ONE host node; a root fragment handed to `direct()` is the SAME case, caught at
  compile time instead. All of it is Solid's dynamic-array branch, the one place `regionNode`
  really is the right machinery; closing them means teaching a region that a row may expand to n
  nodes, which is `reconcileArrays` work, not macro work.

- ~~**JS std string is ~19 exports behind cms**~~ **CLOSED 2026-07-29 (night)**: 18 exports ported
  as pure-MS byte loops matching `runtime/core/string.c` semantics + `lastIndexOf` gained
  `startIdx`/int64 (silent signature drift). Same pass fixed FOUR cross-backend divergences —
  same source, different answers per backend: `toLowerCase/toUpperCase` (JS Unicode vs C ASCII
  `tolower`; `"ÉÀ"` repro), `replace` (JS interprets `$&`/`$1`/`$$`, C is literal), `split("")`
  (UTF-16 chars vs BYTES), `byteLength` (int32 vs int64). Surface guard in `src/test/js/basic.ms`
  (red-proven); semantics verified by dual-backend probe — one source under `./msc run` vs `node`,
  59/59 values identical (the suite has no C-vs-JS runner, so the probe is the only guard for this
  class). ⚠ Two traps for future `.jms` work: a `.jms` export SHADOWS the JS global of the same
  name (`parseFloat` recursed into itself — use `Number.*`), and the with-std harness checks std
  export signatures only, NOT bodies (three int64/int32 errors passed a green suite). Committed
  recompiler `5d7b0dc`+`80d12da`. Still open: `String<T>` (`String(42)` is a type error on JS —
  collides with `extern class String`; needs a design call, see the same-scope redeclaration row).
  Follow-up: single-source std string blocked only by the §2 asBytes row.
- ~~**The gen-20 two-phase fix has NO automated guard.**~~ **CLOSED 2026-07-29 (late evening,
  gen-21 session)**: `compileProjectToJS` refactored to two-phase (`emitJSTwoPhase` — expand ALL,
  then transform ALL, macro diags surfaced as `ERROR: expand [mod]`), new
  `compileProjectToJSWithStd` (std from disk, `.jms`), and the jsxmacMod/jsxmacUse pair baked into
  `src/test/js/basic.ms`. Guard proven RED the honest way: with expansion merely *skipped* it stays
  green (gen-19 made check-time expansion cover the all-checks-first order) — the toggle that
  reproduces gen-20 is re-adding an INTERLEAVED `transformProgram` inside the check loop (exactly
  1 fail in 2769). js/basic closure 2769/2769, js/result closure 2766/2766.
- **cmdRunRaiser and the C build loops still interleave transform with expansion** — same hazard
  family as gen-20 root 1. C survives today because its expansion runs post-mono inside the same
  iteration, before that module's OWN transform; whether the engine tolerates every C-transformed
  helper body is unproven. Align on the two-phase shape when next touched.
- **`instantiateClassConstructor` still fails silently.** #6 was invisible for weeks because the
  function `return`s when it cannot reach the ClassDecl. With the fix the reachable path is correct,
  but a genuinely unreachable declaration should be a loud checker error, not silence. Not done in
  the #6 commit on purpose: the `pickBodyCtx` fallback also fires when the defining module's ctx is
  not registered yet (import cycles), so a hard error could fire on shapes that work today —
  **it needs a battery measurement before it is turned on**, not a guess.
- **fn-repr diagnostics print `function vs function`** (2026-08-08, component arc): the invariance
  error on e.g. a `() => int32` getter into a `() => number` field reads `Type 'function' is not
  assignable to type 'function'` — correct verdict, useless words. Print the signatures
  (`() => int32` vs `() => number`). QoL only, checker diagnostic formatting; repro = 
  `probe/thunkProps3.ms` S1.
- **LANG.md never specifies optional fields.** `field?: T` is accepted on both the interface token
  path and (since `c41f1a3`) the anon-object string path, and on both it is **cosmetic**: no
  missing-key check exists anywhere, an omitted field is zero-init (`ref → NULL`, value-Maybe →
  `present = false`). That de-facto rule should be written down, or deliberately tightened.
- **`msc test src/test/index.ms` is broken on a pristine tree** (74 type errors, reproduced on
  installed-pristine as well). It is a stale aggregator, not a regression — but while it is broken
  the handoff guards only run standalone, so a future session can silently skip them. Either fix it
  or delete it.
- **Neon `probe/` housekeeping** — `macro_disambig` / `macro_lenval` still assert the formerly-WRONG
  values (deliberate RED bracket-tests); `macro_narrow` N1 is red BY DESIGN (Nhịp-2 marker). Rewrite
  truth-only or delete at leisure, but do not read them as failures.
- **"Yoga vendoring never happened / `deps/` is EMPTY" was FALSE** (corrected 2026-07-27 late).
  `deps/yoga -> ../../yoga/deps/yoga` exists and resolves to a real checkout — it is what `voidHost`
  links against, and the yoga port in `~/metascript/yoga` is a working MS binding (`FlexStyle`,
  `applyStyle`, `layoutPass`). What is missing is only a *vendored in-repo copy*; the dependency
  itself is present and used. CLAUDE.md still lists `src/yoga/` as an empty TODO — also stale, the
  layout engine lives in its own repo.
- **`src/test/guard/run.sh` is 6/7 unbuildable here** — zig cannot parse the macOS SDK `.tbd` stubs
  (`failed to parse TBD file: NotLibStub`), so most nim-guards cannot run in either gc mode and the
  new one could only be verified under drc. Either pin a working SDK/zig pair or teach run.sh to fall
  back to `--cc=clang`. Until then the guard suite reports environment noise, which is how a genuinely
  red guard can hide in it.
- **`src/test/guard/asyncRethrowPropagates.ms` is RED and UNTRACKED.** Deterministic
  `DOUBLE-DESTROY of Error`; written by an earlier session, never committed, red before 2026-07-27.
  Its header already names the trace target (`buildExcRouting` in generatorLower.ms + the ThrowStmt arm
  of analyzer/inject.ms). Commit it or delete it — an uncommitted red guard is invisible to everyone.
- **`Map<unknown, V>` does not own its keys, and nothing says so.** Row 57 makes `unknown` RC-inert by
  design (Nim `pointer`), so this is correct — but `type HostNode = unknown` means Neon's whole host
  layer relies on it silently. A cache keyed by `unknown` that outlives its keys dangles with no
  diagnostic. Guarded now (`unknownKeyIsBorrowed`) + NIM-REF row added; still owed a line in LANG.md
  and in Neon's `hostTypes.ms` stating the borrow contract.
- **`@passC`/`@compile` project-root-relative paths are a trap for any cross-project import.**
  Root 1 in §5 fixed `@passC`'s `./`+`../` forms, but `void/src/sokol/gpu.wms` still carries
  `@compile("src/sokol/bridge.c")` (project-root-relative), which breaks identically from another
  CWD. Not fixed here because the wasm path is unexercised — fix when it surfaces.
