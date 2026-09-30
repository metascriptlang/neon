# Neon — bug rows still being carried

Open framework bugs of Neon itself. A compiler bug is NOT written here: it is a card in
`~/metascript/.inbox/compiler/` and, once registered, an `L<n>` entry in
`~/metascript/recompiler/docs/KNOWN-ISSUES.md`. The 148 compiler rows this file used to carry were
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

Open Neon-side rows first, then sites parked on a card in another repo's inbox; each parked row
names the card and the site, and nothing is worked around in `src/`. Rows closed before
2026-09-20 were dropped with §2 — they are in this file's history at `git show c00bd2b:BUGS.md`,
and the invariants that outlived them were moved to the head of the test that pins each one.

- **OPEN 2026-09-26 — Android: the first landscape can lay the app out under the display
  cutout.** Neon's host: `Java_dev_metascript_app_NativeApp_resize` in
  `src/platform/android/bridge.c` reads `getRootWindowInsets` when Ion's bootstrap forwards a new
  size and places the container once. In 1 of 3 runs of `bash tests/android/run.sh` on 2026-09-26
  (the first after install; `docs/ANDROID.md` §9) the first landscape centred the title on the
  full 2856 px, `[1242,228][1614,309]`, instead of on the visible frame `(156,156;2856,1208)`,
  `[1320,228][1692,309]`. Again on 2026-09-27 (Neon `4e33c9e`, msc `013853dd`, Ion `4198106`, the
  first run after install): first landscape `[1242,228][1614,309]`, the landscape after the press
  `[1320,228][1692,309]`. Not seen on the Seeker on 2026-09-30 (`docs/ANDROID.md` §10, the first
  landscape of a fresh process but not the first run after install): the title was centred on the
  visible frame `(78,110;2670,1128)`, `[1188,182][1560,263]`. The lane stays green because
  centred text still lies inside the frame: it checks text bounds, not the container's frame, so nothing shows this yet. Assumed, not
  measured: the new insets reach the view after the resize, and nothing re-places the container
  when they change.

- **OPEN 2026-09-26 — the gate's macro lane: `tests/macros/mapNamedRowRejected.ms` is rejected
  with another message.** `bash tests/macros/run.sh` prints `FAIL
  tests/macros/mapNamedRowRejected.ms: rejected for another reason`: the element macro now refuses
  `.map(row)` with its own "a .map row that takes an index is written <For each={xs}>…" before the
  checker's `Argument type mismatch in 'map' arg 0`, which `run.sh` pins. The program is still
  rejected. Measured on an export of main `ecfbcc7` with msc `227ebc34`; `2f306532` reported the
  macro lane ok. The pinned message is part of the JSX contract (`CLAUDE.md`), so changing it needs a
  yes.

- **OPEN 2026-09-26 — the gate's Chrome lane finds no bundle.** `tests/browser/run.sh` prints
  `COMPILE FAILED — no test bundle emitted at tests/browser/out/debug/_test/main.js`: on msc
  `227ebc34` (macOS) `msc test --target=js tests/browser/dom.test.ms` writes
  `out/debug/_test/main.js` under the working directory, the checkout root, not beside the test
  file where `run.sh` reads it. Measured on an export of main `ecfbcc7`; the Windows run on
  `2f306532` found it beside the test file. Not yet known whether msc moved it on purpose.

- **PARKED 2026-09-26 — `tests/platform/void.test.ms`, `tests/platform/voidInput.test.ms` and
  `tests/style/style.test.ms` do not compile on the native lane.** Not Neon's: Yoga types its node
  handle as `Ptr<YGNode>` since Yoga `f5a811d`, and Void's `Node2D` still holds `Ptr<void>`, which
  `layoutPass<Node2D>` and `freeLayoutTree<Node2D>` refuse (2 errors per file; same on an export of
  main `ecfbcc7`). Void's half: `~/metascript/.inbox/void/2026-09-26-yoga-typed-handle.md`. Parked at
  those three files; nothing in Neon changes.

- **PARKED 2026-09-25 — `tests/render/reconcile.test.ms` does not compile on the native lane since
  msc `2f306532`.** Not Neon's: `span` pushes a `HostNode` (`unknown`) into a `HostNode[]`, and the
  checker now answers `Argument 0: unknown is not assignable to <kind:Sink>`; it compiled and passed on
  `a5e1bc69`. Card: `~/metascript/.inbox/compiler/2026-09-25-push-unknown-into-unknown-array-rejected.md`.
  Parked at `span` in that file; the JS lane still runs it.

- **PARKED 2026-09-21 — `setX(v)` with a local `number` is silently dropped on native.** Not Neon's: a
  value argument to a union parameter (`Setter<T> = (v: T | ((prev: T) => T)) => void`) is passed by raw
  address on the C backend, so the callee reads the union tag out of the double's bits. `msc run
  probe/m/setterLocalArg.ms` prints `local want 6 got 0` through neon's own `createSignal`, while a
  literal and a parameter argument are correct and `--target=js` is correct everywhere; `string` is
  correct through `createSignal` and an error in the standalone probe. Card, four repros and the
  controls: `~/metascript/.inbox/compiler/2026-09-21-value-into-a-union-parameter-passes-the-raw-address.md`.
  Parked at `src/core/list.ms` and `src/render/listRegion.ms`, whose version cell and per-row value cell
  are `Signal<T>` fields with `.get()` / `.set()` — the class method takes a plain `T` and is correct —
  instead of the `[Accessor, Setter]` pair every other module takes from `createSignal`.

- **PARKED 2026-09-21 — a helper returning `HostNode | null` called from a generic region function
  segfaults on native.** Not Neon's: an `unknown | null` value returned by a call is mis-represented when
  the CALLER is generic; two byte-identical bodies differ only by `<T>` and only the generic one crashes
  (`msc run probe/m/nullableUnknownReturnInGeneric.ms`, JS correct). Reading the field inline is correct,
  hoisting the callee out of the generic is not enough. Card with the ten-row matrix of what flips it:
  `~/metascript/.inbox/compiler/2026-09-21-nullable-unknown-return-value-in-a-generic-caller.md`.
  Parked at `src/render/listRegion.ms`, where every step takes a `Region<Item>` object and the anchor is
  read through `anchorAt<Item>(g, i)` of the same instantiation.

- **PARKED 2026-09-21 — `<ForList each={list}>` cannot be written as a tag.** Same root as `<Index>`
  below: a `ForList` row carries `Accessor<T>`, and a generic callee cannot bind its type parameter
  through a `distinct` alias at `createComponent`. Third sighting on
  `~/metascript/.inbox/compiler/2026-09-20-generic-callee-type-param-through-distinct-alias.md`. Parked at
  `tests/render/forList.test.ms`, whose cells take the call form `ForList<T>({ each: l, children: row })`;
  nothing worked around in `src/`.

- **PARKED 2026-09-21 — `<For each={xs} fallback={<li/>}>` cannot be written as a tag.** Not Neon's: a
  JSX value in an attribute of a GENERIC component tag never lowers, while the identical attribute on a
  non-generic tag does — `<Show fallback={<b/>}>` is green because `Show` is not generic. Two controls in
  one file isolate it (`Plain` non-generic builds, `Gen<T>` with the same attribute and the same child
  errors "JSX expression must be consumed by a macro"); the child's shape is irrelevant. Second sighting
  on `~/metascript/.inbox/compiler/2026-09-19-jsx-converter-skipped-in-generic-call-inside-macro-arg.md`.
  Parked at `tests/render/flow.test.ms`, the two fallback cells, which use the call form
  `For<T>({ …, fallback: <li/> })` instead; nothing worked around in `src/`.

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
- **PARKED 2026-09-17 (one-NeonNode arc) — `isAccessorTyped` ~~exists twice (`element.ms`,
  `direct.ms`) and~~ matches neither a type alias of `Accessor<T>` nor `Accessor<T> | null`.** The
  duplicate is ✅ CLOSED 2026-09-19 by the macro merge (`direct.ms` is gone;
  `grep -rn "function isAccessorTyped" src` prints one line, `element.ms`). The alias and nullable
  arms stay PARKED on the compiler: how a macro asks for a type is part of
  `~/metascript/.inbox/compiler/2026-09-19-design-typed-slots-value-read-and-text-coercion.md`
  (ROADMAP Next 7); no Neon-side name matching is added meanwhile.
## §7 — Small debts of Neon itself

A compiler debt is not one of these: the twelve this section used to carry moved to
`~/metascript/.inbox/compiler/2026-09-20-neon-bugs-md-compiler-rows-handover.md` on 2026-09-20.

- **OPEN 2026-09-21 — removing half a list is 1,6x SLOWER when the row has no index.** Measured
  `probe/m/indexFlagCost.ms`, 5000 rows, release, min of 10 rounds with both variants interleaved in
  one process: every other cell gets 22–33% faster when `mapArray` is told the row never reads its
  index (build 1,10 → 0,82 ms, swap 0,286 → 0,219, reverse 0,262 → 0,205, move-1 0,290 → 0,204,
  add-1 0,060 → 0,040) while remove-half goes 0,273 → 0,440. Remove-half is the only cell that
  DISPOSES rows (2500 of them), so a root that holds fewer closures appears to cost more to dispose,
  which is backwards. Three hypotheses tested and refuted, each in its own interleaved run: a shared
  `unreadIndex` accessor captured by every row (per-row accessor inverts the same way), the
  zero-length setter arrays (full-length arrays invert the same way), and run order. Not reduced below
  Neon, so it is not a compiler card yet. The arc `row-reconcile-moves` hit the same inversion on
  2026-09-20 with a hand-copied index-free `mapArray`, which makes this an independent second sighting,
  not an artefact of one implementation.

- **Neon `probe/` housekeeping** — `macro_disambig` / `macro_lenval` still assert the formerly-WRONG
  values (deliberate RED bracket-tests); `macro_narrow` N1 is red BY DESIGN (Nhịp-2 marker). Rewrite
  truth-only or delete at leisure, but do not read them as failures.
