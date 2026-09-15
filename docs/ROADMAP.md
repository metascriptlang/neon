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
| 1 | `distinct` nominal (`typeName`), callable over a fn base, one-way widen (`BrandWiden`) | compiler | |
| 2 | `Accessor<T> = distinct (() => T)`; `createSignal`/`createMemo` return it; `accessor()` | neon core | |
| 3 | checker reads a value through the `valueOf` protocol where a bare read would fail (replaced the source-typed auto-call 2026-09-14) | compiler | |
| 4 | props contract: every value prop is `Accessor<T>`; the macro wraps every value, literals too; one `propValueNode` replaces three copies | neon macros | |
| 5 | `{a && <X/>}` / ternary / `.map` lower to `Show`/`For` through one `lowerJsxChild` | neon macros | |
| 6 | error on an implicit accessor read at function-body time (`const d = count * 2`) | compiler | dropped 2026-09-14: with `valueOf` an alias keeps the accessor, and a body-time operand read is an ordinary one-time value |
| 7 | real fragments: flatten in child position; multi-root at top level | neon | done 2026-09-15 (`msc test tests/render/fragment.test.ms` 308 C / 72 js, 5 of the new cells differential vs tree; `tests/macros/run.sh` rc=0) — tree emission 2026-09-13, direct emission 2026-09-15: same compile-time flatten, root fragment refused because a mount closure returns one `HostNode` |

Emission is finished and needs nothing further: the tier is picked per JSX site at compile time, on
every target, and no build flag or user-visible knob exists (`RENDER-MODEL.md` §Selection).

Phase 7 dropped `regionNode` from its own description: reading `insertExpression` in
`dom-expressions/src/client.js` showed Solid reserves the effect + `reconcileArrays` path for arrays
holding a FUNCTION, and appends a static array directly. A region for a static fragment applies the
dynamic branch to a static value and breaks SSR (`renderToString` throws on regions). Detail and the
refutation live in `BUGS.md` §7.

---

## Next

| # | work | state | size |
|---|---|---|---|
| 1 | RN components: Image, ScrollView, Button, Switch, FlatList, Modal, SafeAreaView — after phase 4 so they carry the props contract | not started | medium |
| 2 | `{...props}` semantics, attribute classification, S1b projection caching | after phase 4 | medium |
| 3 | bug 8 (`globalImports` cycle) so the four core style lists are generated from `STYLE_TABLE` instead of `tests/style/fields.sh` guarding five hand edits | compiler | medium |
| 4 | `_hover` / `_before` / `_classNames`, then the Animation API | user-chosen 2026-08-18 | large |
| 5 | iOS host, then Android host — not compiler-blocked: gate with `when (ios) { … }` around `@compile`/`@passC`/`@passL`/`@link` over one extern surface, the shape `void/src/sokol/gpu.ms` ships | not started | large |

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
- **the JSX boundary stopped being per-target** (2026-09-03) — `NeonView` is a mount closure
  everywhere, `jsxToView` picks `direct` and `jsxToNode` picks `element`, and both `when (js)` blocks
  (`render/host.ms`, `converters.ms`) are gone. This did **not** make everything direct-emitted: what
  a site emits still depends on whether its SHAPE changes at run time, so regions, component bodies
  and SSR stay tree-emitted on every target (`RENDER-MODEL.md` §Selection). Justified by the C-lane
  measurement nobody had taken:
  2.6-2.8x static, 2.0x half-dynamic, 1.5x all-dynamic (`probe/nativeEmit_q4m.ms`, release, min of 3
  rounds × 3 runs), which refutes the "small — allocations only" prediction in `RENDER-MODEL.md`.
  Two Neon bugs fell out and are fixed: `direct.ms` wrapped a component tag's JSX children in
  `element(...)` — the exact thing `element.ms`'s own comment forbids, because it pre-picks tree
  emission — and `direct.test.ms` typed its `For` row callbacks `NeonNode` where `For.children` is
  `NeonView`. (The "27 files bad=0" sweep recorded here at the time was later found false-green —
  broken zsh harness; the honest gate is the 2026-09-03 sweep above.)
- **theme tokens, static and swapped** — `createTheme` bakes one `:root` rule, `createStyles` spells
  `var(--token)` with the unit applied at the use site, `setTheme({…})` replaces the rule by key.
- **`variants`** (2026-09-02) — the caller picks at the use site; `when` stays for what the
  environment picks. `msc test tests/render/styleVariants.test.ms` + `styleVariantsDyn.test.ms`,
  both lanes.
- **sheet lifecycle** (2026-09-02) — `flushSheet` rewrites the whole `<style>` on every change
  (browser), `renderToString` resolves the three style channels exactly as `renderNode` does and
  registers the rule it uses, `mountSheet()` prints the registry as one block for SSR.
  `msc test tests/render/ssrStyle.test.ms` and `--target=js`, both green, both `when` branches
  proven live by mutation.

---

## Not our queue

`tests/render/style.test.ms` and `voidHost.test.ms` do not link without zig/yoga/sokol present, and
they **hang** rather than fail (measured 2026-09-03: 24 minutes, no progress) — exclude them from a
sweep instead of waiting. Everything else in `tests/core`, `tests/render` and `tests/platform` is
green on both lanes, 27 files each, so measure against that before attributing a red to new work.

The long-standing "one JS-lane red that belongs to the compiler" claim was wrong and is gone: it was
two Neon bugs, both fixed 2026-09-03 (`direct.ms` pre-picking tree emission for a component's JSX
child, and a row callback in the test annotated `NeonNode` where `For.children` is `NeonView`).
