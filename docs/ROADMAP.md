# Neon — Roadmap

What we build next, in order, and why that order. **Forward-looking only.**

| doc | owns |
|---|---|
| `docs/VISION.md` | the goal the order serves: one interface over every kind of rendering |
| this file | the order of work across the whole framework |
| `docs/STYLE.md` §9 | the style/theme stages (S1-S4) in detail |
| `docs/RENDER-MODEL.md` | the emission tiers, how a site picks one, and the lifecycle |
| `docs/PORT-STATUS.md` | the Nim → MetaScript module map, and history |
| `BUGS.md` | open FRAMEWORK bugs of Neon, and the sites parked on a compiler card — 157 lines, read it whole. A compiler bug is a card in `~/metascript/.inbox/compiler/`, never a row here |

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
| 5 | `{a && <X/>}` / ternary / `.map` lower to `Show`/`For` | neon macros | done for the three forms, re-measured 2026-09-20: `&&` (`probe/rm5a_and.ms`), `?:` (`rm5b_ternary.ms`) and `{xs.map((v: number): NeonNode => element(<s/>))}` (`rm5h_mapOneParam.ms`) each mount and update. `.map` lowers a row without an index only; a row with an index, `number` or `Accessor<number>`, is refused with a message that names `<For>` (`tests/macros/mapIndexRowRejected.ms`), and `.map(namedFn)` whose callback does not fit `map` is a permanent rejection (`mapNamedRowRejected.ms`), not a parked gap. `||` stays PARKED (BUGS §3). `lowerJsxChild` no longer exists. The macro emits bare `Show` / `For` calls; `src/converters.ms` re-exports them, so the prelude carries them into every file (`tests/render/preludeFlow.test.ms`). `<Index>` as a TAG is rejected at `createComponent`, reduced 2026-09-20 to a generic callee that cannot bind its own type parameter through a `distinct` alias — card `~/metascript/.inbox/compiler/2026-09-20-generic-callee-type-param-through-distinct-alias.md` |
| 6 | error on an implicit accessor read at function-body time (`const d = count * 2`) | compiler | dropped 2026-09-14: with `valueOf` an alias keeps the accessor, and a body-time operand read is an ordinary one-time value |
| 7 | real fragments: flatten in child position; multi-root at top level | neon | done 2026-09-15, root fragment and fragment rows 2026-09-19 with one NeonNode (`msc test tests/render/fragment.test.ms` rc=0 on C and `--target=js`; `tests/macros/run.sh` rc=0) — a fragment child is flattened at compile time, a root fragment places every root in front of `before`, a row may be a fragment, and inside an expression a fragment lowers exactly as an element does (`&&` / `?:` arm → `Show`, prop value or argument → converter) |

Emission is finished and needs nothing further: the tier is picked per JSX site at compile time, on
every target, and no build flag or user-visible knob exists (`RENDER-MODEL.md` §Selection).

Phase 7 dropped `regionNode` from its own description: reading `insertExpression` in
`dom-expressions/src/client.js` showed Solid reserves the effect + `reconcileArrays` path for arrays
holding a FUNCTION, and appends a static array directly. A region for a static fragment applies the
dynamic branch to a static value. Detail and the refutation are in this file's history:
`git show c00bd2b:BUGS.md`, §7.

---

## Next — app deliverability before full parity

Approved 2026-10-05: "chốt hướng, đi rồi mình sẽ bắt tay vào làm trong session mới".
The goal is an app author completing an ordinary app, not cloning the RN or Flutter catalog.
“20/80” is a prioritization hypothesis based on screen reach, not measured API coverage,
implementation size, or a promise that 80% of apps already work.

Keep the RN component surface and Solid's fine-grained model. Borrow Flutter's app contracts
where they expose missing behavior; do not import its widget-rebuild model. The order below
supersedes the earlier style-first and full-list-parity-first order.

| order | capability bundle | what it unlocks | owner / boundary |
|---|---|---|---|
| 1 | ordinary SDK consumption: normal browser bundles, named renderers, contextual props, signal types, typed text/attribute slots and public exports | app code written normally, without compiler-avoidance rewrites | compiler fixes only from recompiler; Neon validates real consumers and its public entrypoint |
| 2 | native forms and app environment: TextInput, focus/IME/selection, text measurement/truncation, dimensions/insets/keyboard, lifecycle after mount | search, login, settings and property inspection | Neon components/hosts; runtime scheduling reuses std before any new Host timing API |
| 3 | everyday UI: Image, Button, Switch, loading indicator, Modal/Portal; accessibility and keyboard/focus behavior included | content screens, forms, dialogs and menus | Neon; reuse Ion resource/packaging/runtime facilities rather than duplicating them |
| 4 | real-data path: store/reconcile, resource loading/error/cancellation/lifetime; variable-height FlatList, timed batching, Header/Footer/Empty/Separator and scroll-to-index failure handling | refetched data keeps row identity; a feed does not require fixed-height rows | Solid concepts localized to MetaScript; shared list engine, not a second list convention |
| 5 | developer loop and common feedback: build/run/deploy diagnostics with source locations, Neon refresh integration, opacity/transform/press feedback and common transitions | short iteration and understandable failures; responsive-feeling UI | compiler HCR and Ion foundations, Neon integration; no whole-engine animation port by default |

A compiler-blocked item is reduced, recorded and parked; it is never “completed” by making
the app author rewrite valid code. Continue reachable work in the next bundle while the
owning compiler session fixes it. Shared-contract changes and genuinely new mechanisms
retain their approval gates; this order does not grant land/push permissions.

On 2026-10-06 the user expanded the list part of bundle 4 to grid and inverted chat lists,
SectionList, sticky headers, viewability, public VirtualizedList and the deeper RN list
reference catalog. These are current scope, not a prerequisite to port the full RN/Flutter
ecosystem. Component and element slots both use declared-type JSX lowering; invalid initial
indices must clamp with a warning on every backend, not a native-only silent fallback.

Preserve Solid item identity when extending grid layout. RN's multi-column row key joins
every item key (`FlatList.js`, `_keyExtractor`, lines 554–569 in the reference checkout),
so regrouping changes row identity. Copying that key model would not establish Solid state
preservation across row parents; cross-parent ownership/reconciliation needs its own
mechanism approval. The reference list cases are in
`packages/virtualized-lists/Lists/__tests__/VirtualizedList-test.js`.
Until that approval, grid is provisional (`WORKAROUND.md` L1): an item keeps its state while
it stays in its row and remounts when regrouping moves it to another row; the grid cases in
`tests/render/flatList.test.ms` and `tests/browser/flatList.test.ms` pin it.
Public `VirtualizedList` (`getItem`/`getItemCount`), viewability (`onViewableItemsChanged`,
`viewabilityConfig`, `viewabilityConfigCallbackPairs`, `recordInteraction`) and
`SectionList`/`VirtualizedSectionList` run on the same engine; their provisional parts are
`WORKAROUND.md` L3–L7. Cases: `tests/render/{virtualizedList,sectionList}.test.ms`,
`tests/components/list/viewability.test.ms`, `tests/browser/sectionList.test.ms`; the invalid
`initialScrollIndex` warning is pinned on native and JS by `tests/apps/listWarnApp.ms`.
`scrollToItem`, `ListItemComponent` and `disableVirtualization` follow RN's cases in the same
files (L8–L9). `maintainVisibleContentPosition` (approved 2026-10-07) is a ScrollView attribute through
`Host.setAttr`, kept by each host around its own write batch the way RN's ScrollView keeps it
around a mount: the native host records the first visible child at or after
`minIndexForVisible` before its yoga pass and shifts the offset by that child's move after it
(`niScrollShift`, `niScrollOffsetX/Y` in `bridge.h`; Android waits for its layout pass and
restarts a running fling, iOS writes `contentOffset`), the DOM host records before the first
host write of a task and shifts in a microtask with CSS `overflow-anchor: none`. The list ports
RN's `getDerivedStateFromProps` window shift and counts the header slot. Cases:
`tests/render/{scrollView,flatList}.test.ms` (RN's two `VirtualizedList-test.js` cases),
`tests/platform/nativeHost.test.ms`, `tests/browser/{scrollView,flatList}.test.ms`; the consumer is
the `chat` mode of `examples/components/bigList.ms`, passing on the iOS simulator
(`docs/IOS.md` §9.1); the Seeker lane is written but not yet run (`docs/ANDROID.md` §11.1).


### Acceptance — three complete author workflows

1. Data list → search → detail → edit/save form, with images, variable-height rows,
   loading/error/empty states and normal source syntax.
2. Settings with input, toggle, adaptive layout/theme, keyboard focus and screen-reader use.
3. A Lightcube slice: select a node → edit a property → observe the canvas update without
   losing state/focus. Pan/zoom, drag/resize, selection, clipboard and undo/redo remain
   product priorities when required by that slice, even if not common mobile-core controls.

State 2026-10-07 (`wt/rn-apps`, msc `8506eaf03`): workflows 1 and 2 run as
`examples/catalog` and `examples/settings`. Proven on the mock host and JS
(`msc test [--target=js] tests/apps/workflows.test.ms`), in Chrome
(`tests/browser/run.sh tests/browser/workflows.test.ms`), on the Seeker
(`tests/android/catalog.py`, `tests/android/settings.py`, exit 0) and on an iPhone 17 Pro
simulator (`CatalogUITests`, `SettingsUITests` in `tests/ios/counterUITests.swift`, run with the
software keyboard), then on the physical iPhone 13 Pro at `18f4baa` (both classes passed in one
7/7 run with the list and scroll classes). Not proven: a screen reader driving the app (the
accessibility tree was read through `uiautomator` and XCUITest; TalkBack's first-run tutorial
covered the app); a system appearance change from XCUITest (`XCUIDevice.appearance` did not reach
the app, `xcrun simctl ui <device> appearance dark` did). Provisional choices are rows A1–A11 of
`WORKAROUND.md`.

Prove each workflow through its real consumer on the declared targets. A public symbol,
mock pass or separate-module test artifact is not proof of the normal packaged app.
The reactive concepts still owed live in `docs/SOLID.md`; they are dependencies of these
workflows, not a separate checklist to finish before writing an app.

### Reference and ownership constraints

- RN's core catalog: `packages/react-native/index.js`, component exports and app/runtime APIs.
  Navigation is a community library, not an omitted RN-core widget
  ([RN navigation](https://reactnative.dev/docs/navigation)).
- Flutter contracts: `packages/flutter/lib/src/widgets/editable_text.dart` `EditableText`,
  `media_query.dart` `MediaQueryData`, `navigator.dart` `Navigator`, `overlay.dart` `Overlay`,
  `async.dart` `FutureBuilder` / `StreamBuilder`, and `basic.dart` `Semantics`.
- Development expectations: [RN Fast Refresh](https://reactnative.dev/docs/fast-refresh)
  and [Flutter hot reload](https://docs.flutter.dev/tools/hot-reload). Existing compiler HCR
  platform support and Neon integration boundaries are in `recompiler/docs/HCR.md`;
  do not confuse the missing mobile/Neon integration with an absent HCR implementation.
- Ion owns the implemented project generator and desktop runtime services:
  `ion/docs/PROJECT-GENERATOR.md`, `ion/src/index.ms`. The older Neon generator design
  is not authority for current implementation ownership.
- Framework layers remain separate: Neon UI/reactivity, Ion runtime/packaging,
  Void rendering, compiler language/toolchain, Lightcube editor/collaboration.
  Camera/auth/storage and similar ecosystem domains enter through concrete consumers,
  not a blanket RN/Flutter API-cloning requirement.

### Carry-forward constraints

The typed-slot protocol question is not dropped: see
`~/metascript/.inbox/compiler/2026-09-19-design-typed-slots-value-read-and-text-coercion.md`.
The author's `null` and boolean children use the same general protocol as numbers,
not a Neon-only special case. Once the language covers it, remove `isNumberTyped` / `asText`,
replace name-based type matching, and give attributes the same rule. Re-run the actual
JSX consumers after a protocol sync.

Do not restart implemented spread/classification or style-table generation from stale
roadmap rows: inspect `tests/render/spread.test.ms` and `src/macros/style/fields.ms`.
ErrorBoundary is existing; `docs/SOLID.md` owns its remaining concepts. Basic typography,
runtime adaptation and accessibility precede more pseudo-state or animation machinery.

Timing is std's `setTimeout`, with no Host timer. The iOS and Android adapters pump the
std event loop from the UI loop (`src/platform/native/loop.c`, armed by a `CFRunLoopTimer` /
`timerfd` on the main looper after every bridge entry, each pass inside the host's layout
batch). Before that pump a held FlatList row read `pressed row 5001` on the iOS simulator
and the Android emulator, with `onLongPress`'s timer never fired. After it, both read
`pressed long row 5001` (2026-10-06, msc `c96ea1d1f`). Physical phones were not run.

---

## Later — retained scope, not current prerequisites

- List ecosystem contracts beyond the RN list reference catalog already approved above.
- Full Material/Cupertino-style catalogs, gesture arbitration, complex animation graphs
  and pseudo-state surfaces beyond the common workflows.
- SSR hydration/resource serialization when a real SSR consumer needs them.
- Terminal parity and GPU embedding across every host; self-sizing Void Text remains
  required for the applicable app/editor workflow, not silently removed.
- Void's own vocabulary inside a Void area (`VISION.md` "Inside a Void area"): `Scene3D`, `Group`, `Mesh`,
  `Light`, `Camera3D` and the HUD over the scene on what Void has now; a `View` drawn into a texture on a mesh
  after Void's items in `void/docs/NEON.md`
- Mobile `<Void>`, desktop native vocabulary, multiple embeds, cross-boundary focus/
  accessibility and shared frame behavior (`docs/VISION.md`, `docs/RENDER-LAYERS.md`).
- Distribution/store acceptance through Ion; broader native-service/plugin domains
  chosen from actual apps.
- Editor/collaboration depth belongs to Lightcube. Preserve the canonical-source and
  render-boundary goals without making all of them gates for ordinary Neon screens.

---

## Recently done

- **Mobile App Foundation, Phase 1** (closed 2026-10-01 by the person) — the tracked Neon counter, generated by Ion and
  compiled by msc, runs signed on a physical iPhone and a physical Android phone with a real finger, through
  rotation, Home and resume. Evidence: `docs/IOS.md` §6.5 (final matrix on msc `013853dd`: iOS simulator and
  Release simulator, Android emulator, generator fixtures all green; full Neon gate 8 known reds, 0 new) and
  `docs/ANDROID.md` §10 (signed Release APK and AAB, Seeker finger and lifecycle). Decided at the close, not
  measured: the physical iOS Release counter and frame were observed by the person; a Distribution `.ipa`
  belongs to store upload, which Phase 1 left out; the mobile lanes re-run as part of each msc sync's
  consumer check (they have not been re-run on `e5e932d0` yet).

- **an Ion window whose content is one full-window `<Void>`** (2026-09-24) — `runWindow` in
  `src/platform/ion/window.ms`, `<Void>` over the optional `Host.voidArea`, React Native's key, focus,
  layout and submit handlers, and a Flutter-style text client for content drawn by hand. Measured on
  Windows 11 (96 DPI, UniKey running in Telex mode) with `examples/voidWindow.ms` driven by synthetic
  input: three clicks on `+1` read `Count: 3`; typing `ab cd`, Backspace and Enter logged each
  `changetext` and `submit "ab c"`; typing `vieetj` through UniKey logged
  `vi → vie → vi → viê → viêt → viê → vi → việ → việt` and drew `việt` with the caret after it; resizing
  the window from 640×360 to 900×500 re-ran `onLayout` (header 576 → 836 wide) and stretched the
  field. Not verified: a TSF IME's preedit (no Vietnamese IME is installed on this box; the composing
  path is pinned by `tests/platform/voidInput.test.ms` only) and a DPI change. The DOM host's key
  fields are pinned in real Chrome by a dispatched `KeyboardEvent` (`tests/browser/dom.test.ms`). The
  void host compiles again: it wrote `"50%"` strings into yoga's `float32` dimensions, which msc 0.2.55
  rejects; a string dimension now fails loud with its field name. The Chrome lane runs on Windows now:
  `playwright-core` driving the installed Chrome, a node static server, and the bundle read from beside
  the test file, where `msc test --target=js` writes it. Re-run after the example on msc `2f306532` and
  void2d's Font API: `xin chaof vieetj` through UniKey → `xin chào việt`.
  Proved: `bash tests/run.sh` on msc `2f306532`, tree `34595404` — macros ok, apps ok
  (`moduleSignalApp` native red, known L46), native 50 files and js 47 + 3 deliberate skips with 0 test
  failures, browser 81/81; exit 1 only on `tests/render/reconcile.test.ms` native, parked on a compiler
  card (`BUGS.md`).

- **tail of one NeonNode** (2026-09-19) — what the merge left behind. `on*` is an event by ONE rule,
  `on` + an uppercase letter, for a tag, a spread field and a component prop (`isEventName`; `<p once="x">`
  did not compile before). A function-typed value is a row and a raw child, so `<For>{namedRow}</For>`
  works. An `Accessor<string> | null` attribute and a `NeonNode | null` child attach only when present,
  `{maybe ?? <X/>}` lowers to `Show`, and View / Text / Pressable are written in JSX — which fixed a
  reactive `class` that froze at its first value on the whole vocabulary. Proved: `bash tests/run.sh`
  rc=0 — macros 17, apps 3, native 40, js 38 + 2 deliberate skips, browser 80/80;
  `msc build examples/counterDom.ms --target=js` and `msc run examples/counter.ms` rc=0. Left on the
  compiler: `{a || <X/>}` (the typed-slot protocol work in the first bundle). BUGS §3 has the measurements.
- **bare JSX catches up with `element(...)`** (2026-09-20) — after recompiler `0f1e6735`, `76a6a9bd`,
  `0b283fd4` reached the installed `msc` (`7f80b93b`). Every nullable slot (handler, ref, style,
  `Accessor<string> | null` attribute, `NeonNode | null` child) works in bare JSX; `Show` and `For` are in
  the prelude, so `&&` / `?:` / `??` / `.map` need no import. `.map` lowers a row without an index only:
  a callback that does not fit `map` is an error by the person's ruling, and a For row's index is an
  `Accessor<number>`, so a row with an index is refused with a message that names `<For>`. Proved:
  `bash tests/run.sh` rc=0 on `4e1602c` — macros, apps, 41 native, 41 js, browser 80/80; the four
  "— bare JSX" cells in `emit.test.ms`,
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
  The native UI loops pump those timers (the first bundle's carry-forward constraint). The older handover is `~/metascript/.inbox/compiler/2026-09-20-neon-bugs-md-compiler-rows-handover.md`.
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
  debts filed (handed over, `~/metascript/.inbox/compiler/2026-09-20-neon-bugs-md-compiler-rows-handover.md`): engine-synthesized thunks around user arrows, and the converter
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
  site; recompiler bug118). Fn VALUES keep strict arity (handed over, `~/metascript/.inbox/compiler/2026-09-20-neon-bugs-md-compiler-rows-handover.md` — annotate the decl). Sweep:
  C 28/28, JS 27/28; the one JS red is a PRE-EXISTING int64→number return-conversion drop
  (handed over, `~/metascript/.inbox/compiler/2026-09-20-neon-bugs-md-compiler-rows-handover.md`, A/B-proven against a self-built v0.2.52 control).
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
