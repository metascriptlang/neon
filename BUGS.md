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

- **OPEN 2026-10-19 — the Android apis and catalog lanes are red on main.** Emulator `emulator-5554`
  (Pixel 9 Pro AVD, headless, launcher force-stopped first), `ANDROID_SERIAL=emulator-5554 sh tests/android/lane.sh
  examples/<app> dev.neon.<App> tests/android/<app>.py`: apis prints `'Neon APIs' never appeared; texts []`, catalog
  prints `timed out waiting for 12 products; texts ['Catalog', 'Search products', 'Offline', 'Loading products']`. Same
  on main 76d8efa1 and on 1e1b8dc4; the emulator reaches 8.8.8.8, so catalog's `Offline` is not the host network. media
  and svg pass in the same run. Not diagnosed.
- **OPEN 2026-10-16 — touches do not reach the sokol canvas.** `src/platform/sokol/input.ms`
  `deliverAppEvent` takes the four `Touches*` events and does nothing with them, so a phone browser cannot
  press, scroll or focus the canvas once events arrive.

- **OPEN 2026-10-15 — `<For key>` keeps showing the old item when a new object arrives under the same key.**
  `<For each={rows()} key={(r: Keyed): number => r.id}>{row}</For>` over `[{id:1,label:"a"},{id:2,label:"b"}]`,
  then `setRows([{id:2,label:"b2"},{id:1,label:"a2"}])`, prints `<ul><li>b</li><li>a</li></ul>`:
  the rows reorder and keep the labels they were built with. Measured with `msc test` and
  `msc test --target=js` on msc v0.3.4 `15b93cbba` over a copy of main `c68683d` `src`. The row receives
  the raw item and is reused by key (`src/macros/ui/flow.ms` `For`, `src/core/array.ms` `mapArrayKeyed`);
  `tests/render/flow.test.ms` checks only the order. `ForList` passes an `Accessor<T>` row and stays
  current (`tests/render/forList.test.ms`), as Solid 2.0's `For keyed={fn}` does. The fix changes the row
  type in `src/macros/ui/element.ms`, a contract that needs a yes before it changes.

- **OPEN 2026-10-15 — a server render writes a caught error's message into the page.**
  `<ErrorBoundary fallback={(err: Error, reset: () => void): NeonNode => <p>{err.message}</p>}>` around a
  component that throws `new Error("db password=hunter2 at 10.0.0.5")` renders
  `<p>db password=hunter2 at 10.0.0.5</p><!----><!---->` through `renderToString` on C, `--target=js` and
  `-d:server` (msc v0.3.4 `15b93cbba`, copy of main `c68683d` `src`). The boundary hands its fallback the
  thrown `Error` on the server as on the client (`src/macros/ui/flow.ms` `ErrorBoundary`). Solid 1.x leaks
  the same way (solid issue #3468); Solid 2.0 replaces the error with a generic "Internal Server Error"
  before the fallback renders outside a dev build and serializes that same record for hydrate
  (`~/projects/solid-next` `84dada77`, `documentation/solid-2.0/12-ssr-http.md:139-145`).

- **OPEN 2026-10-15 — a read inside `runWithOwner` subscribes the effect that called it.**
  `createRenderEffect(() => { runs += 1; runWithOwner(owner, (): number => a()); })`, then `setA(1)`,
  prints `runs 2` on C and `--target=js` (msc v0.3.4 `15b93cbba`, copy of main `c68683d` `src`).
  `runWithOwner` (`src/core/owner.ms`) swaps the owner and keeps the listener; Solid 1.x
  (`~/projects/solid` `25138e1c`, `reactive/signal.ts:1055-1059`) and 2.0 clear the listener, so the
  same program runs the effect once.

- **OPEN 2026-10-15 — an effect that feeds itself stops without an error.**
  `createRenderEffect(() => { const v = n(); if (v < 3000000) { setN(v + 1); } })` leaves `n` at
  `1000001` and throws nothing, on C and `--target=js` (same build and copy). `runQueue`
  (`src/core/runtime.ms`) leaves its loop at 1 000 000 passes with work still queued; Solid 2.0
  throws at 100 000 (`~/projects/solid-next` `84dada77`, `packages/signals/src/core/scheduler.ts:1309-1315`).

- **OPEN 2026-10-12 — a component tag that omits a required prop compiles and then crashes.**
  `interface BadgeProps { label: Accessor<string>; suffix: Accessor<string>; }` mounted as
  `<Badge label="a" />` builds on msc `e8c024c8` (C) and the test binary ends with status
  `0xC0000005` when the body calls `props.suffix()`. Found by the refresh edit battery: adding a
  prop to a props interface before the parent passes it was accepted. Not reduced past this
  program; not measured on JS or for a `string` prop. The props object is built by
  `src/macros/ui/element.ms`, a contract that needs a yes before it changes.

- **OPEN 2026-10-08 — a component without props cannot be a JSX tag.** `function Tally():
  NeonNode { return <p>t</p>; }` used as `<Tally />` stops `msc run` (msc `99a851d7`, C) with
  `Argument type mismatch in 'createComponent' arg 0: got function, expected function`: every
  capitalized tag lowers to `createComponent<P>(Comp: (props: P) => NeonNode, props: P)`
  (`src/render/component.ms` `createComponent`), which takes a one-parameter function. Examples
  mount such a component by calling it (`App()` in `examples/voidWindow.ms`). The fix is in
  `src/macros/ui/element.ms`, a contract that needs a yes before it changes.

- **OPEN 2026-10-13 — a context whose value type is an accessor cannot be given one.** With
  `createContext<Accessor<string>>()` and `const [place] = createSignal("a")`,
  `<Here value={place}>` stops at the checker: `Type 'string' is not
  assignable to type 'Accessor<Accessor<string>>'` (re-measured 2026-10-16 on msc v0.3.4
  `cb45fe201` with `msc test` on C, at the tip of `wt/neon-solid2`). The element macro reads an accessor in a
  prop position as a reactive expression of its result, so `value` is offered a `string`; the
  message names neither the rule nor the way out. `useContext` returns the value as it was
  when the reader mounted, so a signal has to travel inside the value: as a field
  (`value={{ here: place }}`, pinned by `tests/render/context.test.ms`) or as an arrow with
  `T = () => string`. Found by Geass (`web/src/docs.ms`, the current docs page). Solid passes
  the accessor itself.

- **OPEN 2026-10-13 — `tests/platform/nativeWidgets.test.ms` reads the Collapsible before it has finished opening.**
  The native cell loops the UI for 400 ms of wall time after `setCollapsed(false)` on a 64 ms
  animation and then asserts `box === 120`; some runs stop at `the box opened: 118`. Measured
  with `msc test tests/platform/nativeWidgets.test.ms` on msc v0.3.2 `ea7ae4d17`: an export of
  main `eb16a9c` failed 1 of 8 runs at load 8; `wt/rn-navigation-prod` at `1d775db` failed 2 of 3
  right after a full gate and 0 of 8 afterwards; in the gate on `70b1387` (load above 20) the
  cell was red. The last frame of the animation is not guaranteed inside a wall-clock window,
  so the cell is red by timing, on main and on a branch alike. Not yet traced to whether the
  animation driver drops its final frame or the test should wait for the end event.

- **OPEN 2026-10-13 — `renderToString` writes `image`, `modal`, `slider`, `picker`,
  `datetimepicker`, `svg` and the media tags as unknown or attribute-heavy elements, and
  `hydrate` refuses them.** `ScrollView`, `Text numberOfLines`, `Switch`, `ActivityIndicator` and
  multiline `TextInput` were closed on this branch (`tests/browser/ssrMarkup.test.ms`,
  `tests/browser/hydrate.test.ms`). Measured in Chrome with `renderToString` against `domHost()`:
  `image` server `<image source resizeMode aria-label>` against `<img class="neon-image" src
  data-resize alt aria-label>`; `modal` `<modal visible animationType>` against `<div
  class="neon-modal" role="dialog" aria-modal="true">`; `slider` `<slider value minimumValue …>`
  against `<input type="range" min max step>`; `picker` `<picker items selectedIndex>` against
  `<select><option>…`; `datetimepicker` against `<input type="time">`; `svg` `<svg displayList>`
  against `<svg class="neon-view" data-neon-svg>` with its markup; `video`, `webview`, `camera`
  against `<video class="neon-video" playsinline src>`, `<iframe class="neon-webview">`,
  `<video class="neon-camera" playsinline muted autoplay>`.

- **OPEN 2026-10-13 — `ActivityIndicator color` never reaches the element.** `writeControlAttr`
  sets `el.style.color`, and the colour is gone after the mount (not traced to the write that
  clears it; the style the component always passes is the suspect): in `tests/browser/ssrMarkup.test.ms` the DOM
  host builds `style="justify-content: center; align-items: center; width: 36px; height: 36px;"`
  for `<ActivityIndicator color="#c00" size="large" />`. The server writes the same, so the two
  agree, and the colour is lost on both until this is fixed in `src/platform/browser/dom.jms`
  (for example a class per colour, as `hitSlop` does).

- **OPEN 2026-10-07 — a raw tag with an `Accessor<boolean> | null` attribute dies on C.** In
  `probe/apps/boolAttr.ms` (`wt/rn-apps`), `function Tag(props: { on?: Accessor<boolean> | null })`
  returning `element(<text accessible={props.on}>hi</text>)`, mounted as `<Tag on={true} />` on
  `mockHost()`, `msc run` exits 133 (`EXC_BREAKPOINT` in `mfm_free`, a double free) and prints
  nothing; the same shape with `Accessor<string> | null` prints the attribute. `Text` and
  `Pressable` therefore pass `accessible` as an `Accessor<string>` (`accessibleText` in
  `src/components/primitives.ms`). Not reduced to the macro or the compiler yet.

- **OPEN 2026-10-03 — Android: the list examples' `offset` label draws "offset" without its
  number.** Seen on the Seeker in the `list-pressed.png` screenshot that `tests/android/list.py`
  writes, in two runs: 15:40, before `c12ed39`, and 16:25, after it. In the same runs the
  `uiautomator` dump reads the label as `offset 1577`, so the `TextView` holds the full text and
  only its drawn width is short. The label is a `Text` with `fontSize: 16` whose text grows on every
  scroll (`examples/components/scrollList.ms`). Not investigated.

- **OPEN 2026-10-03 — Android: on a fast hand swipe, rows entering the screen first draw small
  text, then the styled size** (the person's report, Seeker, FlatList build of 16:25). Not
  reproduced by machine: two screen recordings of `adb shell input swipe 600 2300 600 700 40` and
  `… 600 2500 600 300 15` flings (355 and 252 frames) were scanned for the height of every bright
  text run in the label column, and every run measured the 37 px median. `hostElement`
  (`src/render/node.ms`) binds the style, a render effect (`bindStyleAll`, `src/render/bind.ms`), before it
  mounts the children, so `setStyle` runs before the row's label exists, and `niTextCreate`
  starts a label at 17 sp, so a late style is ruled out. Next: record the screen while a hand
  swipe reproduces it.

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
  rejected. Measured on an export of main `ecfbcc7` with msc `227ebc34`, and again on an export of
  main `4e33c9e` with msc `013853dd` (2026-09-30); `2f306532` reported the macro lane ok. The pinned message is part of the JSX contract (`CLAUDE.md`), so changing it needs a
  yes.

- **OPEN 2026-09-26 — the gate's Chrome lane finds no bundle.** `tests/browser/run.sh` prints
  `COMPILE FAILED — no test bundle emitted at tests/browser/out/debug/_test/main.js`: on msc
  `227ebc34` (macOS) `msc test --target=js tests/browser/dom.test.ms` writes
  `out/debug/_test/main.js` under the working directory, the checkout root, not beside the test
  file where `run.sh` reads it. Measured on an export of main `ecfbcc7`, and again on an export of
  main `4e33c9e` with msc `013853dd` (2026-09-30); the Windows run on `2f306532` found it beside the
  test file. Not yet known whether msc moved it on purpose.

- **OPEN 2026-10-07 — the Ion window host builds on Windows only.** Void exports its embed view
  (`embedRegister`, `viewCreate` in `void/src/sokol/gpu.ms`) only under `windows || ios || android`,
  so `src/platform/ion/window.ms` cannot build on macOS or Linux whatever Neon does. On Windows it
  builds and runs again. Measured 2026-10-13 with `examples/voidWindow.ms` on void `5dbcb662` and
  ion `7463096`, at 96 DPI, driven by window messages posted to the Ion window: three clicks logged
  `press count=3`; `ab cd`, Backspace and Enter logged each `changetext` and `submit "ab c"`; a
  resize from 624×321 to 884×461 re-ran `onLayout` (header 576 → 836 wide); closing the window
  exits 0. Re-measured 2026-10-15 after the move to Ion's window-content API (ion `b8d739d`, void `640ed0ea`,
  msc `9cf5708c`, 96 DPI, same driver): the same log, `layout header 576x32` then `836x32` for a resize
  from 624×321 to 884×461, exit 0, and the background, button and field colours read back from
  `PrintWindow` at the start, after typing and after the resize. Not run: an IME, a DPI change.
  `tests/run.sh` builds the example on a Windows host and skips it by name elsewhere.

- **OPEN 2026-10-16 — a navigation issued while a rewrite's browser `go` is in flight misorders history.**
  The session has one landing slot and Chrome's `go` is asynchronous: in `tests/browser/routerLevels.test.ms`
  back from `/inbox/8` stayed on `/inbox/8` until the test waited 100 ms after a tab switch. Decompose
  swaps one popstate listener the same way (`WebHistoryNavigation.kt` `onPop`/`onRewrite`); the fix is
  not traced yet.

- **PARKED 2026-10-16 — the sokol canvas receives no input, and Escape ends it.** Not Neon's: Void's window
  driver (`void/src/sokol/bridgeWin.c` and `bridgeWeb.c`, `_event`) keeps every `sapp_event` to itself, and
  `voidRun` takes only `init` and `frame`, so no key, char, pointer, wheel or focus reaches MetaScript. The
  same `_event` calls `sapp_request_quit()` on Escape: in headless Chrome, after a click and an Escape press,
  the frame callback stopped at 178 calls and never ran again. sokol_app also reports no IME composition on
  any platform, so `onPreedit` cannot fire there. Neon's half is `src/platform/sokol/input.ms`
  (`deliverAppEvent`, `flushKey`), pinned by `tests/platform/sokolInput.test.ms`. Parked at
  `src/platform/sokol/canvas.ms` `runCanvas`, which calls `voidRun` with no event closure. Note
  `~/metascript/.inbox/void/2026-10-16-sokol-window-driver-for-neon-canvas.md`.

- **PARKED 2026-10-16 — the native sokol canvas draws every frame.** Not Neon's: sokol_app presents after
  every frame callback, and a skipped frame flips the window between the last two drawn frames (measured in
  docs/RENDER-LAYERS.md). Parked at `src/platform/sokol/canvas.ms` `skippedFrameKeepsPicture`, false natively.
  Same Void note as the row above.

- **PARKED 2026-10-16 — `runCanvas` does not build for the browser from the repo.** Not Neon's. Yoga links under
  `--os=emcc` since yoga `b2d4f7e`, and the derived-interface upcast at `src/components/primitives.ms` is a
  typed C cast since recompiler `20d78d7d3`; neither has been run through `runCanvas` under emcc yet. Still open:
  `setTimeout` does not link under `--os=emcc`, `wasm-ld: undefined symbol: msSetTimeout`, because only the
  native runtime's `dispatchFull.c` defines it
  (`~/metascript/.inbox/compiler/2026-10-16-settimeout-does-not-link-under-emcc.md`). With these and yoga worked
  around outside the repo, the canvas draws in Chrome (docs/RENDER-LAYERS.md). Parked at `examples/voidCanvas.ms`,
  built natively only.

- **PARKED 2026-10-15 — `tests/platform/voidInput.test.ms` aborts on C.** Not Neon's: after `default font
  assets/font.ttf did not load`, the native run panics with signal 6 in Void `wrapText`
  (`void/src/void2d/textLayout.ms:1366`), the empty-slice-to-`Span` case of compiler card
  `~/metascript/.inbox/compiler/2026-10-16-empty-array-range-slice-null-payload.md`. It arrived with
  the origin commits pulled at `4718a2f`, and it is red on `fb2285e` alone. Measured by the navigation session's gate on
  `1ad74a7`, msc `15b93cbba` (`~/metascript/.wt/artifacts/rn-navigation-prod/gate-navmodels-fb2285e/gate.log`).
  2026-10-18, Void `215c3e2`, msc `9029133ef`, an export of main `9c3c659`: no abort any more, 342 pass and 2 fail,
  "the rect follows the signal: 23" (`voidInput.test.ms` imeRect cell) and "after the ops only the pushed row's label
  is new: 0" (the 60-row ForList scroll cell). Not traced to Neon or Void yet.

- **PARKED 2026-10-15 — `tests/platform/ionAudio.test.ms` cannot resolve Ion's audio module on this machine.**
  Not Neon's: native `Cannot resolve module '../../../../ion/src/audio'`, because local Ion main `1b3d40c`
  lacks the audio API, which is on Ion origin `a853b2e`. Ion note
  `~/metascript/.inbox/ion/2026-10-15-local-main-diverged-from-window-content.md`. Same gate log as the row above.

- **PARKED 2026-10-14 — an Ion project manifest inside Neon cannot be evaluated.** Not Neon's: Ion's
  generator runs the manifest with `msc run --target=raiser` beside it, Neon's `build.ms`
  `globalImports` brings in `src/core/runtime.ms`, and Raiser has no `String.fromCharCode`, so even a
  one-line `console.log` under Neon's root stops at type check (msc `26150233`). Blocks building
  `examples/voidWindow.ms` from an Ion-generated Visual Studio project, and since `createUniqueId`
  (`runtime.ms:121`) every device lane: `bash tests/ios/run.sh` stops at step `generate` on msc
  `a7b08f008` (2026-10-15). Card
  `~/metascript/.inbox/compiler/2026-10-15-raiser-has-no-string-fromcharcode.md`.
  Answered on the Windows machine: the card is fixed and gone from the inbox. On msc `a2b3e36a`,
  `String.fromCharCode(72)` runs under `--target=raiser` from Neon's root, and an Ion-generated project of
  `examples/voidWindow.ms` builds (`32c2643`). The device lanes were not re-run there.

- **PARKED 2026-10-11 — `tests/render/flatList.test.ms` and `tests/components/flutterListsApp.test.ms` do not compile.**
  Not Neon's: an array-destructured local of an arrow passed as a JSX attribute
  (`const [focused, setFocused] = createSignal<boolean>(false)` in a `renderItem`) is refused as
  `a local of another function` when an element macro nested in that arrow reads it, and the
  explicit type argument as `Wrong number of type arguments … expected 0, got 1`
  (`moved<Song>(…)` in `examples/components/flutterLists.ms`). Native and JS, on the compiler built
  from recompiler origin `f421de59` alone and on `89005562`, with Neon at origin `1b7ce77`. Card
  `~/metascript/.inbox/compiler/2026-10-11-destructured-local-in-attribute-arrow-read-by-nested-macro.md`.
  Parked at those two files.

- **PARKED 2026-10-14 — `createStyles` takes no breakpoint table.** Decided 2026-10-15 (StyleX's
  form): `export const screen = createBreakpoints({ wide: 900 })`, and a sheet names it as a key,
  `createStyles({ sidebar: { when: { [screen.wide]: { … } } } })`, so the checker sees `screen.wide`
  and the macro reads 900 at expansion. Written on branch `park/breakpoints` (`89b2050`: web
  `@media`, native and inline styles bound to the window width, blocks kept through `mergeStyle`).
  Blocks it: `Style` becomes recursive (`media: StyleMedia[]`, `StyleMedia.style: Style`), and
  `getTypeImpl` throws "unnamed or alias type cycle (Ref)" on a non-generic interface whose field
  reaches a recursive one, so a provider tag stops compiling (`<Ctx.Provider>` when measured; the 2.0 tag `<Ctx value>` is not re-measured) (`tests/render/ssr.test.ms`, msc
  `682b18673`). Card `~/metascript/.inbox/compiler/2026-10-07-element-macro-type-cycle-on-generic-interface-field-without-its-parameter.md`.
  Parked at that branch; `src/macros/ui/style.ms` `createStyles` on main has no breakpoints.

- **PARKED 2026-10-10 — Vite refresh: an edit that adds a new generic instance reloads the page.**
  Adding `createSignal(false)` to an accepted component module emits the `…__boolean` instance into
  the runtime's `signal` module, which is not an HMR boundary. Measured again 2026-10-12: adding a
  signal and reading it in the template reloads the page too, because the template's capture type
  changes and `refreshRegion<E>` / `TemplateSlot<E>` are instantiated in `render/refresh`. On native
  HCR the same edit reloads with state kept. Design card
  `~/metascript/.inbox/compiler/2026-10-10-js-generic-instance-emitted-into-defining-module.md`.

- **PARKED 2026-10-03 — `(st.width ?? 0.0) === 320.0` does not compile.** Not Neon's: with
  `st.width: float32 | string | null` the fallback joins as a new `float64` member and the present
  value is refused against it on C and JS; with a written target type the `===` against a number then
  fails in clang. Card and the five-file matrix:
  `~/metascript/.inbox/compiler/2026-10-03-nullish-coalesce-union-into-its-superset-rejected.md`.
  Parked at `tests/platform/void.test.ms`, the "parseFlexStyle maps numeric + enum keys" cell; the file
  fails to compile on that cell alone, so `msc test tests/platform/void.test.ms` stays red until the card lands.

- **PARKED 2026-09-30 — `tests/platform/native.test.ms` dies at module load on the JS lane.** Not
  Neon's: Yoga `dba68fd` re-exports its enums from `Yoga.h`, and msc `013853dd` emits
  `export var YGAlign_YGAlignAuto` beside an export list that names `YGAlignAuto`, so node stops at
  `SyntaxError: Export 'YGAlignAuto' is not defined in module`. The same on an export of main
  `4e33c9e`; the file was not in the known-red set of msc `227ebc34` with Yoga `f5a811d`. The first card
  left the inbox while the bug stayed; still red on msc `0f8278bc`, where a direct import from the header
  fails too. Card and repro: `~/metascript/.inbox/compiler/2026-10-16-js-header-enum-member-unbound.md`.
  Parked at that file's JS lane; nothing in Neon changes.

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
  (ROADMAP Next 7); no Neon-side name matching is added meanwhile. Measured again 2026-10-03 on msc
  `e5e932d0`: `function Card(props: { style?: Accessor<Style> | null }) { return <View style={props.style} />; }`
  fails with `Type 'Accessor<Style> | null' is not assignable to type 'Style'`; with `style: Accessor<Style>` it
  passes. A wrapper component cannot forward an optional style through JSX. Site parked on it:
  `src/components/flatList.ms` builds its `ScrollView` by a direct call.
## §7 — Small debts of Neon itself

A compiler debt is not one of these: the twelve this section used to carry moved to
`~/metascript/.inbox/compiler/2026-09-20-neon-bugs-md-compiler-rows-handover.md` on 2026-09-20.

- **Neon `probe/` housekeeping** — `macro_disambig` / `macro_lenval` still assert the formerly-WRONG
  values (deliberate RED bracket-tests); `macro_narrow` N1 is red BY DESIGN (Nhịp-2 marker). Rewrite
  truth-only or delete at leisure, but do not read them as failures.
