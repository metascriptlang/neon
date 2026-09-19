# Neon — Roadmap

What we build next, in order, and why that order. **Forward-looking only.**

| doc | owns |
|---|---|
| this file | the order of work across the whole framework |
| `docs/STYLE.md` §9 | the style/theme stages (S1-S4) in detail |
| `docs/RENDER-MODEL.md` | the emission tiers, how a site picks one, and the lifecycle |
| `docs/PORT-STATUS.md` | the Nim → MetaScript module map, and history |
| `BUGS.md` | every open bug, compiler or framework |

**Rule for this file** (same as `BUGS.md` and `STYLE.md`): a row moves to *done* only with the
command that proved it. Never layer a correction on a stale row — rewrite the row.

---

## Now

**React surface on the Solid core** (user decision 2026-09-10; execution plan in
`~/.claude/plans/wiggly-wondering-treehouse.md`) — Neon keeps Solid's fine-grained reactivity and React
Native's component/event vocabulary, and uses the compiler to drop the three rules Solid has to teach only
because it is a library. Reactivity is decided by TYPE, never by syntax or by where a read sits. `setCount(v)`
stays; no React hook aliases.

| # | phase | owner | state |
|---|---|---|---|
| 0 | redeploy main; docs; loud-reject fragments; uniform spread walk | neon | done 2026-09-10 (`tests/macros/run.sh` rc=0) |
| 1 | `distinct` nominal, callable over a fn base, one-way widen | compiler | done, re-measured 2026-09-19 on msc v0.2.55 (`probe/rm1_distinct.ms`, `rm1b_nominal.ms`): an `Accessor<string>` reads as `() => string`, the reverse is rejected. The names `typeName` / `BrandWiden` are not in Neon's source — the row described an early shape |
| 2 | `Accessor<T> = distinct (() => T)`; `createSignal`/`createMemo` return it; `accessor()` | neon core | done, re-measured 2026-09-19 (`src/core/signal.ms:46`, `probe/rm1_distinct.ms`): the alias, `accessor()` and `valueOf` are all live |
| 3 | checker reads a value through the `valueOf` protocol where a bare read would fail (replaced the source-typed auto-call 2026-09-14) | compiler | done, re-measured 2026-09-19 (`probe/rm3_valueof.ms`): `const [x] = createSignal(2); x * 2` prints `4` with no call |
| 4 | props contract: every value prop is `Accessor<T>`; the macro wraps every value, literals too | neon macros | done, re-measured 2026-09-19 (`probe/rm4_props.ms`): `label="hi"` enters an `Accessor<string>` prop and `count={n()}` stays reactive (`hi:1` → `hi:2`). `propValueNode` no longer exists — one NeonNode replaced it |
| 5 | `{a && <X/>}` / ternary / `.map` lower to `Show`/`For` | neon macros | done for the three forms, re-measured 2026-09-20: `&&` (`probe/rm5a_and.ms`), `?:` (`rm5b_ternary.ms`) and `{xs.map((v: number): NeonNode => element(<s/>))}` (`rm5h_mapOneParam.ms`) each mount and update. `.map` lowers a row without an index only; a row with an index, `number` or `Accessor<number>`, is refused with a message that names `<For>` (`tests/macros/mapIndexRowRejected.ms`), and `.map(namedFn)` whose callback does not fit `map` is a permanent rejection (`mapNamedRowRejected.ms`), not a parked gap. `||` stays PARKED (BUGS §3). `lowerJsxChild` no longer exists. The macro emits bare `Show` / `For` calls; `src/converters.ms` re-exports them, so the prelude carries them into every file (`tests/render/preludeFlow.test.ms`). `<Index>` as a TAG is rejected at `createComponent` — card in `~/metascript/.inbox/neon/` |
| 6 | error on an implicit accessor read at function-body time (`const d = count * 2`) | compiler | dropped 2026-09-14: with `valueOf` an alias keeps the accessor, and a body-time operand read is an ordinary one-time value |
| 7 | real fragments: flatten in child position; multi-root at top level | neon | done 2026-09-15, root fragment and fragment rows 2026-09-19 with one NeonNode (`msc test tests/render/fragment.test.ms` rc=0 on C and `--target=js`; `tests/macros/run.sh` rc=0) — a fragment child is flattened at compile time, a root fragment places every root in front of `before`, a row may be a fragment, and inside an expression a fragment lowers exactly as an element does (`&&` / `?:` arm → `Show`, prop value or argument → converter) |

Emission is finished and needs nothing further: the tier is picked per JSX site at compile time, on
every target, and no build flag or user-visible knob exists (`RENDER-MODEL.md` §Selection).

Phase 7 dropped `regionNode` from its own description: reading `insertExpression` in
`dom-expressions/src/client.js` showed Solid reserves the effect + `reconcileArrays` path for arrays
holding a FUNCTION, and appends a static array directly. A region for a static fragment applies the
dynamic branch to a static value. Detail and the refutation live in `BUGS.md` §7.

---

## Next

| # | work | state | size |
|---|---|---|---|
| 1 | RN components: Image, ScrollView, Button, Switch, FlatList, Modal, SafeAreaView — after phase 4 so they carry the props contract | not started | medium |
| 2 | `{...props}` semantics, attribute classification, S1b projection caching | after phase 4 | medium |
| 3 | bug 8 (`globalImports` cycle) so the four core style lists are generated from `STYLE_TABLE` instead of `tests/style/fields.sh` guarding five hand edits | compiler | medium |
| 4 | `_hover` / `_before` / `_classNames`, then the Animation API | user-chosen 2026-08-18 | large |
| 5 | iOS host, then Android host — not compiler-blocked: gate with `when (ios) { … }` around `@compile`/`@passC`/`@passL`/`@link` over one extern surface, the shape `void/src/sokol/gpu.ms` ships | not started | large |
| 7 | numbers in text and attribute slots, and how the macro asks for a type — PARKED on the compiler: `as<T>` and `valueOf` are being reworked in a parallel recompiler session (2026-09-19). Brief with every measurement: `~/metascript/.inbox/compiler/2026-09-19-design-typed-slots-value-read-and-text-coercion.md`; bug card beside it (`…-union-into-string-slot-accepted.md`). Measured there: `asString(this n: int32)` already carries a number into every `string` slot and chains after `valueOf`; the open question is scope. Decided by the user 2026-09-19: `null` and `boolean` children are to become displayable too, through the same general protocol or design, never through a Neon-only patch. When it settles: drop `isNumberTyped` / `asText` from `element.ms` (`07bb579`) if the language covers it, give attributes (`tabIndex={n}`) the same rule instead of copying the patch, replace the name matching in `isAccessorTyped` / `isNodeType`, sweep `{x() + ""}`. After any msc sync that touches the protocols run `bash tests/run.sh`: `tests/render/bareAccessor.test.ms` and the two "a numeric child renders as text" cells in `emit.test.ms` are the guard | waiting on compiler | small |

---

## Later

In rough priority order, once the above is standing:

- breakpoints / media queries, and the runtime object (`rt`: insets, dimensions, orientation)
- pseudo-states beyond variants — hover/focus join `when`, not a separate `states:` block
- animation — the largest single module in the Nim original (~2055 LOC), deliberately last
- from the Nim original and not yet ported: `resource` / `http` / `async` (the MS idiom is
  `Promise<Result<T,E>>` + `try await`, not a port of the Nim shape), `error_boundary`, `config`
- `VAttr.value: string | null` so `removeAttr` becomes reachable
- native timer for the void and terminal hosts (long-press runs on browser + mock only)
- arrow-defined components and module-level snapshots under the phase-6 diagnostic

---

## Recently done

- **tail of one NeonNode** (2026-09-19) — what the merge left behind. `on*` is an event by ONE rule,
  `on` + an uppercase letter, for a tag, a spread field and a component prop (`isEventName`; `<p once="x">`
  did not compile before). A function-typed value is a row and a raw child, so `<For>{namedRow}</For>`
  works. An `Accessor<string> | null` attribute and a `NeonNode | null` child attach only when present,
  `{maybe ?? <X/>}` lowers to `Show`, and View / Text / Pressable are written in JSX — which fixed a
  reactive `class` that froze at its first value on the whole vocabulary. Proved: `bash tests/run.sh`
  rc=0 — macros 17, apps 3, native 40, js 38 + 2 deliberate skips, browser 80/80;
  `msc build examples/counterDom.ms --target=js` and `msc run examples/counter.ms` rc=0. Left on the
  compiler: `{a || <X/>}` (rides Next 7). BUGS §3 has the measurements.
- **bare JSX catches up with `element(...)`** (2026-09-20) — after recompiler `0f1e6735`, `76a6a9bd`,
  `0b283fd4` reached the installed `msc` (`7f80b93b`). Every nullable slot (handler, ref, style,
  `Accessor<string> | null` attribute, `NeonNode | null` child) works in bare JSX; `Show` and `For` are in
  the prelude, so `&&` / `?:` / `??` / `.map` need no import. `.map` lowers a row without an index only:
  a callback that does not fit `map` is an error by the person's ruling, and a For row's index is an
  `Accessor<number>`, so a row with an index is refused with a message that names `<For>`. Proved:
  `bash tests/run.sh` rc=0 (see the land commit); the four "— bare JSX" cells in `emit.test.ms`,
  `preludeFlow.test.ms`, `tests/macros/mapIndexRowRejected.ms`.
- **twin test cells folded** (2026-09-19) — no test compares `element` against itself any more. A cell
  that repeated another cell's JSX and assertion is deleted (`fragment` 6, `spread` 4, `ref` 2, `event` 1,
  `context` 1); a cell that pinned something of its own keeps a hand-written golden under a name that says
  what it pins (`ref`, `event`, `spread`, `host`, and the `treeRoot` halves of `emit.test.ms`). Proved:
  `grep -rnE '^test ".*(direct emission|tree emission|tree and direct|under direct)' tests` and
  `grep -rn treeRoot tests` both print nothing; `msc test` rc=0 on C and `--target=js` for each of the
  seven files.
- **one NeonNode** (2026-09-19) — a JSX expression is `(host, parent, before) => void` on every
  target: a function that puts the host nodes it owns into `parent`, in front of `before` (Svelte 5's
  shape). The description tree, its walker, the second macro and the second boundary type are gone;
  ONE macro picks the template tier or the flat tier per site, and component bodies, region rows,
  root fragments and `renderToString` all go through it. `render` owns the mount in a root and returns
  its dispose; `children` is always one NeonNode; the reconciler mounts a row at its final position
  and never detaches a live one (`RENDER-MODEL.md`). Proved at `e93dcdb`: `bash tests/run.sh` —
  macros 16, native 40, js 38 + 2 deliberate skips, browser 80/80 in real Chrome (in a worktree the
  browser lane needs `NEON_PLAYWRIGHT` pointed at the main checkout's playwright). Measured
  (`bench/nativeEmit.ms`, `RENDER-MODEL.md` §Gate): a component body mounts 2.3–2.7x faster, every row
  1.6–2.0x faster than the tree, void not slower; against the retired per-site emitter, rows with
  static attributes read up to 1.1 µs per mount slower on the no-clone mock host, unattributed and
  inside the bench's noise (accepted by the user 2026-09-19). `examples/counterDom.ms` builds `--target=js`
  and the vite-counter check is green in real Chrome: render, two clicks, sourcemap, edit → reload, zero
  console errors (`8ddfc0e`).
- **a numeric child renders as text** (2026-09-19) — `{count}` over an `Accessor<int32>`, `{n()}`,
  `{n() + 1}` and a plain `{k}` were all type errors ("expected string, got int32"), which is why the
  suite is full of `{count() + ""}`. The macro now emits `.toString()` when the child's type, or the
  payload of its `Accessor<T>`, is a number type. `msc test tests/render/emit.test.ms` rc=0 on C and
  `--target=js`, both tiers, red first; `bash tests/run.sh` rc=0 at `8036e96`.
- **Pressable runs RN's gesture machine** (2026-09-03) — `onPressIn`/`onPressOut`/`onLongPress`
  ported from `Libraries/Pressability/Pressability.js`: long press at 500ms (`delayLongPress`
  overrides), a minimum 130ms held state so a fast tap still shows feedback, and RN's
  `isPressCanceledByLongPress` rule — a gesture that fired `onLongPress` does NOT also fire
  `onPress`. Two tiers picked from the props actually declared: `onPress` alone stays ONE click
  listener (unchanged cost and behaviour), any gesture prop opts into pointer tracking
  (down/up/leave/cancel) where the machine owns the press. Timing is the LANGUAGE's, not a host
  capability: `Pressable` calls the std JS-shaped `setTimeout`/`clearTimeout` (std/core/system,
  msc ≥ 7f3d58bd) directly — every lane has a clock, `Host` carries no timer seam, and the
  earlier `Host.setTimer`/`NeonNode.mount` experiments were removed again. Tests use the real
  timer with small delays + wide margins (`delayLongPress={120}`, await `sleepAsync`), pinned by
  `tests/render/press.test.ms` (8 cells, both lanes). A fix fell out: both macros wrapped EVERY
  non-string prop in a thunk, so `delayLongPress={200}` against a flat `number` field miscompiled
  on C — constants now cross RAW, which is what the call-based reactive law already implied.
  Native hosts have no clock yet, so long press does not fire there (BUGS.md §7).
- **the universal component vocabulary** (2026-09-03, user decision — div/span are HTML-isms
  users must not meet) — `View`/`Text`/`TextInput`/`Pressable` are real components
  (`src/components/primitives.ms`, the createComponent seam) rendering lowercase WIRE tags; every host
  translates in its own createElement (browser + SSR: `htmlTagFor` — view→div, text→span,
  textinput→input, pressable→button; terminal: box; void ignores tags; mock records as
  written; unknown tags pass through as the escape hatch). Two prop-contract rules landed with
  them: arrow-literal attrs cross RAW and take the field's flat type (handlers declare
  `(e: NeonEvent) => void`; withDynStyleAll keeps style thunks — the call-based law), and
  children rules in BOTH macros (starter tags wrap a single child as `[element(…)]`/text
  arrays; arrows stay raw for For/Show; non-arrow expressions are dynText). `class` is the
  RN-web escape hatch. Starter counter/todoList + counterDom/showcaseDom migrated — no div in
  the public surface. Sweep: C 29/29, JS 28/29 (same single pre-existing red). Two compiler
  debts filed (BUGS.md §2): engine-synthesized thunks around user arrows, and the converter
  registry's array-target gap.
- **the event surface speaks React Native** (2026-09-03, user decision — mobile-first) —
  `onPress` replaces `onClick` everywhere; `e.type` uses the neon spelling ("press",
  "changetext") and the browser host alone projects it onto DOM listeners (press→click,
  changetext→input). `onChangeText` hands the handler the TEXT, not the event: both macros wrap
  the user handler at the emit site (`__msCte` param, inline in each macro body — flat Node
  fields only type inside macro bodies), so the Host contract stays `(e: NeonEvent) => void` on
  every host. Pressable semantics beyond the name (pressIn/Out/LongPress) come with the starter
  RN components. Sweep: C 28/28, JS 27/28 (same single pre-existing red).
- **events carry a typed object** (2026-09-03) — `Host.addEvent` handlers take `NeonEvent`
  (flat v1: `type`/`value`/`x`/`y`/`key`, zero-filled where a host can't supply a field; built by
  `neonEvent`/`eventType` in `src/render/event.ms`); all four hosts construct it, the browser host
  maps `input`/`key*`/`mouse*` DOM fields, the mock host fires through `fireEventWith`. Shipping
  this exposed a compiler miscompile: a zero-arg arrow into an `(e) => void` slot type-checked at
  param position but called through the SLOT's ABI on C (garbage frame → double-free in the event's
  destructor) and was rejected at field position. Fixed at the root in msc **v0.2.53**
  (`padLiteralParams` — a literal lambda pads to its slot's arity at its own contextual-typing
  site; recompiler bug118). Fn VALUES keep strict arity (BUGS.md §7 — annotate the decl). Sweep:
  C 28/28, JS 27/28; the one JS red is a PRE-EXISTING int64→number return-conversion drop
  (BUGS.md §2, A/B-proven against a self-built v0.2.52 control).
- **the JSX boundary stopped being per-target** (2026-09-03) — both `when (js)` blocks (`render/host.ms`,
  `converters.ms`) are gone: a native build reaches the same per-site emission a browser build does.
  Justified by the C-lane measurement nobody had taken: 2.6-2.8x static, 2.0x half-dynamic, 1.5x
  all-dynamic (`probe/nativeEmit_q4m.ms`, release, min of 3 rounds × 3 runs), which refuted the "small —
  allocations only" prediction. Regions, component bodies and SSR stayed on the description tree until
  one NeonNode removed it (2026-09-19, above). (The "27 files bad=0" sweep recorded here at the time was
  later found false-green — broken zsh harness; the honest gate is the 2026-09-03 sweep above.)
- **theme tokens, static and swapped** — `createTheme` bakes one `:root` rule, `createStyles` spells
  `var(--token)` with the unit applied at the use site, `setTheme({…})` replaces the rule by key.
- **`variants`** (2026-09-02) — the caller picks at the use site; `when` stays for what the
  environment picks. `msc test tests/render/styleVariants.test.ms` + `styleVariantsDyn.test.ms`,
  both lanes.
- **sheet lifecycle** (2026-09-02) — `flushSheet` rewrites the whole `<style>` on every change
  (browser), `renderToString` resolves the three style channels exactly as a mount does and
  registers the rule it uses, `mountSheet()` prints the registry as one block for SSR.
  `msc test tests/render/ssrStyle.test.ms` and `--target=js`, both green, both `when` branches
  proven live by mutation.

---

## Not our queue

The gate is `bash tests/run.sh`, read by its exit code: `tests/macros/run.sh`, every test file native,
every test file `--target=js` except the two that import the C-only Void host
(`tests/style/style.test.ms`, `tests/platform/void.test.ms`), then `tests/browser` in real Chrome. It was
green on all four lanes on 2026-09-19 (`e93dcdb`), so measure against that before attributing a red to
new work.
