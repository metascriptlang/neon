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
component, a fragment, a region — without the caller knowing which.

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
are six render effects over a skeleton whose shape never moves. A dynamic STRUCTURE (`<For>`,
`<Show>`, `<Repeat>`, a component) is a NeonNode produced at run time and called where
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
 macro      call       flush runs the   owner tree
 expand     ONCE       dirty effects    kills subtree
```

- **COMPILE** (macro): JSX → a NeonNode. Static facts (tags, static attrs, which spots
  are dynamic, the walk path to each) are decided here, never re-derived at runtime.
- **MOUNT** (`render`, or a parent node calling a child): the node runs once. Static
  text/attrs are applied and never touched again; every dynamic spot plants ONE render effect
  (`createRenderEffect`: a compute that reads the signals and subscribes to them, an apply that
  writes the host) whose first run happens at mount; a component runs its body
  exactly once (untracked, under the mounting owner) and its result is called at the
  same position; a region plants an anchor + a reconcile render effect; a fragment owns no
  host node and places each of its roots in front of `before`.
- **UPDATE**: no render. A write marks the computations that read it, and a flush runs the
  marked render effects, then the user effects (`createEffect`, `onSettled`), which never run on
  the server; each render effect performs one host op. A write outside `flush(fn)` drains on the
  next microtask, as in Solid 2.0, so a read right after it still sees the committed value;
  `flush()` drains now, `flush(fn)` drains its writes before it returns, `render` and `hydrate`
  drain once before they return. A host drains before it lays out or draws, and a native
  host drains an event's writes before that event's layout pass, as a browser runs its
  microtask checkpoint after each event callback. A host publish (window size, color scheme,
  app state) applies at once through `flush(fn)`, and a server build flushes every write at
  once, since Solid's server applies a write at once. Cost = number of spots that actually changed, independent of
  tree size.
- **DISPOSE**: owner-tree teardown — deterministic, recursive, fires `onCleanup`,
  kills every subscription underneath. Never waits for GC.

**Refs.** A ref runs innermost-first, after its element's subtree is built and before the
site root is placed (React's order, decided 2026-09-18; `tests/render/ref.test.ms`). A
`ref={[a, b]}` applies its entries in source order, flattening nested arrays and dropping `null`.
A call such as `ref={tooltip(opts)}` is a directive factory: `setupRef` evaluates the call (or the
array, so every factory) in the mounting owner, untracked, and `applyRef` runs the function it
returned untracked, in the mounting owner. dom-expressions runs the apply phase with no owner;
Neon keeps the owner because `StatusBar` and `WebView` register their `createEffect` and
`onCleanup` inside a ref callback. A factory that runs with no owner, such as
`element(<Void ref={f()}/>)` evaluated before `render` opens its root, stops with an error that
names the case, because its `onCleanup` would never run. `<Void>` runs its ref last, after its
children mount, with the `VoidAreaHandle` rather than the host node.

Building the node (evaluating the JSX expression) allocates a closure and performs no
host op and no signal read; there is no separate BUILD phase producing data.

### Refresh: what an edit keeps

An app turns refresh on by naming the pass in its `build.ms`
(`globalImports: [{ from: <neon>/src/converters, modulePass: "refreshPass" }]`) and building with
`-d:refresh` (Vite dev: the plugin's `compilerArgs: ["-d:refresh"]`) or `--hcr`. Without either
define, `src/macros/refresh.ms` `refreshPass` returns every module unchanged, and a production
`vite build` carries no refresh code. The runtime is `src/render/refresh.ms`; the delivery
adapters are `examples/refreshVite/` (Vite + real Chrome), `examples/refreshNative/` (native
HCR on the mock host) and `examples/refreshAndroid/` (HCR in an Android app, `docs/ANDROID.md` §12), each with a driver that edits a copy of its sources.

| edit | what happens | why |
|---|---|---|
| JSX/text/style in a component's final `return` | the template region is rebuilt; the component's signals, the sibling's state and the page or window survive | the returned expression is hoisted into `__refreshTmpl_X<E>(env)`; the rest of the body is `__refreshSetup_X`, which returns `{captured locals}` and is not re-run |
| any other statement of the body (a handler, a new signal) | that component remounts and its signals carry their values over; siblings are untouched. A signal starts from its initial value again when its declaration (name, type argument, initial expression) or its type changed | `__refreshSig_X` covers the setup statements and the captured names. The pass inserts `refreshState(key, get, set)` after each top-level `const [get, set] = createSignal(…)`; the runtime reads the values before the teardown and sets them after the new setup created its signals |
| JSX of a parent, or its setup | the child components under it remount with their signals carried over, matched per component in document order | before a rebuild the runtime walks the host tree under the instance and queues each child component's values under its key |
| a helper module the component imports | Vite: the importer re-evaluates with an unchanged module signature and rebuilds the templates that read an import. Native: the helper's `@afterReload` calls `refreshDependency`, which rebuilds the templates its importers registered with `refreshImports` | state is kept. A handler in the setup that calls the helper keeps the old function on Vite until the component itself is edited; native forwards named functions, so it already calls the new one |
| a compile error | the old UI keeps running and the error is shown (Vite overlay, HCR watch output); the next valid edit applies | the build fails before any module is replaced |
| new code that throws while a component remounts | a red box with the message (`<file>#<Component> did not mount: …`) stands where that component was, and the message is logged with the full key; the rest of the app keeps running, and the component's next edit mounts it with the values it had | the instance's rows memo (`instanceRows`) catches the throw, frees what the failed build placed, builds the box as the instance's row and keeps the values read before the teardown. A remount whose build reads a pending value is not an error: the old view stays until the value settles, and the instances nested under it start from their initial values if that build is retried |

Carried over: signals declared as `const [get, set] = createSignal(…)` at the top level of the
body, and what a helper hands to `refreshKeep(key, read, write)` while it mounts (a navigator
keeps its routes and their params this way, `src/navigation/core.ms` `createCore`; a kept stack
that names a removed screen starts again). A `let`, a memo, an effect and host state (scroll
offset, focus, text typed into an uncontrolled input) start again on a remount. A changed field list of a class or interface
(a prop added to a props interface) is refused by the HCR engine with `restart required`.

Not extracted, so any edit remounts the whole component: a body with an early `return`, a final
`return` of a bare identifier, a template that reads a reassigned `let` (the template would read
a copy and silently stop seeing assignments), and components the pass does not transform at all
(generic, two parameters, a destructured parameter, a return type other than `NeonNode`). A parent
template rebuild remounts the child components it mounts, as Solid Refresh does.

The template's captures are typed without the pass knowing their types: the pass runs before
type checking, so `__refreshTmpl_X` takes one type parameter `E` and re-binds each capture by name
(`const count = __refreshEnv.count;`), leaving the JSX untouched; the element macro expands per
instantiation and sees concrete types. `refreshTemplate(file, id, tmpl, sig, setup)` at the module
tail never calls `setup`: it is the witness that fixes `E`, because a bare generic function
reference cannot be registered at top level (`cannot instantiate: 'T0'`). Slots are typed
(`ComponentSlot<P>`, `TemplateSlot<E>`) and recovered from `Map<string, unknown>` with a checked
class cast. That cast stops the program on a mismatch and cannot be caught, so a slot is stored
under its key plus `refreshTypeKey(fn)`, a macro that names the instantiation's type from inside
the generic function: an edit that changes what a template captures registers a new slot instead of
casting the old one, and `patchModule` remounts the component whose template was registered at
another type. A kept signal value is recovered the same way, only when the type key is equal.

On Vite, a component module accepts its own update (`import.meta.hot.accept()`, emitted on JS when
the module has components and no top-level statement or declaration that calls something). The
entry module renders at top level, so it never self-accepts and an edit to it reloads the page
instead of mounting a second app. Measured: with the entry self-accepting, every edit mounted
one more `<section>`.

**Measured 2026-10-10**, installed msc `5039c014`, tree `e0fda400`:
- `bash tests/refresh/run.sh`: native, `--target=js` and native `-d:hcr`, 7 tests each, green.
- `sh examples/refreshVite/run.sh` (Vite 5.4.21, Chrome 154 headless, playwright-core 1.63): 19 of
  19 checks. Count 8 survives a template text and style edit, one click gives 9; a handler edit
  resets to 0 and the new handler adds 2; four template edits leave one view and one handler; a
  `words.ms` edit shows the new word with the count kept; a type error shows the overlay while the
  old UI still clicks, and restoring the last good source clears it; `vite build` without the
  define has no refresh code and runs. Same session id, zero navigations, same sibling DOM node.
- `bash examples/refreshNative/drive.sh main`: template edits keep count 8 → 9 → 10 → 11 with
  one handler; the `words.ms` reload shows `a:11 pears` before any click; a compile error keeps the
  old code clickable and the fix reloads.

**Measured 2026-10-11**, installed msc `89005562`, tree `edc50166`:
- `bash examples/refreshNative/drive.sh main` and `parentAfterChild`: the setup edit and the parent
  template rebuild after its child's module reloaded both answer `reloaded`, no rollback. Before
  `89005562` both were rolled back, because a generic class instance (`TemplateSlot<E>`) had one
  TypeInfo per HCR generation.
- `APK=<debug apk> bash examples/refreshAndroid/drive.sh` (Android 16 x86_64 emulator, API 26
  images, the dev loop `tools/androidHcr.sh`, a hand-edited Gradle project whose `NativeApp` loads
  `files/hcr/libapp.core.so`): 22 of 22 checks, twice. Three template edits keep the count in one
  process with one view and one handler; a `words.ms` edit shows without a tap; a compile error
  leaves the app tappable and the fix reloads; a setup edit remounts the component with the new
  handler; a core change (a new `std/hash` import) restarts the app on the delivered images with
  no reinstall; an activity recreation after a reload remounts in the same process. Edit to
  reloaded over 14 edits: 1351 to 4322 ms, median 2250 (warm build 1.2 to 2.2 s, delivery 0.14 to
  1.9 s, the app polls every 100 ms). Delivery measured alone is 80 ms of `adb push` plus about
  100 ms for the copy into the app; the 1 to 2 s cases inside the loop are not explained.
  Rejected for a one-call delivery: `adb exec-in` (kills the remote command at EOF) and
  `adb shell -T` (corrupts binaries from Windows). Not run: arm64, a physical device, a release
  build, an app whose project includes Neon as a project module.

**Measured again 2026-10-11 after merging origin `1b7ce77`**, installed msc `89005562`, tree `4d3bbc2b`:
`sh examples/refreshVite/run.sh` 19 of 19; `examples/refreshNative/drive.sh main` six of six edits
reload; `examples/refreshAndroid/drive.sh` 22 of 22, twice, on an APK rebuilt from this tree. With
a compiler built from recompiler origin `f421de59` merged into `c5eeb007` the Android driver
passed 3 of 4 warm runs (one run lost the `HCR reloaded` line after the restart while the app
showed the new view), and the first session after that compiler first ran answered
`restart required` to every edit
(fixed in recompiler `ac34f190a` to `261502336`, pinned by `hcrCoreNative`).

**Measured 2026-10-12**, installed msc `e8c024c8`, tree `45c70f7`:
- `bash tests/refresh/run.sh`: `boundary.ms`, `state.ms` and `navigation.ms` on `--target=js`
  green; native and native `-d:hcr` green for the first two, and for `navigation.ms` only with the
  compiler candidate of recompiler `wt/fix-null-cmp-captured` (the installed msc stops on
  navigation, `BUGS.md`).
- `sh examples/refreshVite/run.sh`: 19 of 19; the handler edit keeps count 9 and the new handler
  makes it 11.
- Native HCR on the mock host, a copy of `examples/refreshNative` edited by hand, one session, all
  answered `reloaded` with the counter and its sibling keeping their values: a new signal read by
  the template; that signal's type changed from `int32` to `string`; a new component in the same
  file mounted by the parent; a new module file imported by the parent; a component removed from
  the parent; a handler edit. Before this tree the first of these stopped with
  `invalid object conversion: TemplateSlot<…> is not TemplateSlot<…>` and left the component
  unmounted. A prop added to a props interface answered `restart required` (`the layout of type
  'CounterProps' in module 'counter' changed`), and so did every later edit of that session.
- `examples/refreshAndroid/drive.sh`: 23 of 23, twice; a setup edit keeps count 7 and the new
  handler makes it 9. Edit to reloaded was 5.4 to 16 s on a machine at 97 % load from four
  compiler builds, so this run says nothing about speed. The first session after the compiler
  changed answered `restart required` to its first edit.
- Not run: a real desktop window, a physical device, kept routes on a device.

**Measured 2026-10-12 (evening)**, installed msc `e8c024c8`, tree `6a5349c`, a setup edit that
throws and then its fix on each adapter:
- `sh examples/refreshVite/run.sh`: 21 of 21; the box shows `counter.ms#Counter did not mount:
  setup failed`, the sibling keeps its node, tally and typed text, no page error is logged, and
  the fix mounts the counter with count 19.
- `bash examples/refreshNative/drive.sh main`: eight of eight edits `reloaded`, twice; the box
  stands between the heading and the tally (`b=5` kept), and the fix shows `a:16`.
- `examples/refreshAndroid/drive.sh`: 25 of 25, twice; a screenshot shows the red box with yellow
  text at the top of the window. Edit to reloaded in the quieter run: 1.9 to 4.3 s over eight
  edits, of which the PC build is 1.5 to 3.1 s and delivery 0.15 to 2.3 s; the second run, beside
  another session's compiler corpus, took 9.9 to 16.5 s.

**A new generic instance applies on Vite without a reload**: split JS writes an instance only other
modules ask for to its own `_inst/` module, so the library's file stays byte-identical
(`examples/refreshVite/drive.mjs` S8, 2026-10-21). An instance whose body assigns its module's
variable, or holds `@emit` text, still lands in the library's file and reloads the page.

Rejected on the way: comparing imported bindings by identity to decide which setup to remount
(Solid Refresh's granular `dependencies`) cannot be emitted, because an imported generic function
(`createSignal`) cannot be passed as a value without type arguments, and C refuses closure
equality (`~/metascript/.inbox/compiler/2026-10-02-function-value-equality-c.md`). Remounting
every setup that reads an import, the first version, reset Counter's count on every `words.ms`
edit, because the setup reads `createSignal`.

On 2026-10-05, installed msc `4573591e`, the JS command
`msc test --target=js tests/render/refresh.test.ms` passed six refresh tests
(67 tests including imported std tests). Explicit template registration kept
count 8; an explicit component registration reset its local count while a sibling
survived. A nested-fragment remount first failed by leaving old child nodes in
the host. Using the reconciler's start-marker/range idiom and retaining the
instance owner made that regression pass through three remounts and final
subscription disposal.
After the exclusive compiler gate handed back admission, the same six refresh
cases passed on native C with the final runtime source:
`msc test tests/render/refresh.test.ms`, 15 files / 304 tests including imported
std tests, on the same installed build. This is a native mock-host control,
not cross-image HCR or native-window callback proof.

These are mock-host lifecycle measurements, not browser/Vite or native-window
HCR proof. The expression-only transform experiment was rejected: a JS
`SpliceMany`/`StaticStorage` registration probe ran its initializer on both
calls of the enclosing function (`1`, then `2`), so the single-call control
did not prove module-evaluation registration. Automatic Refresh requires a
generic module-transform prerequisite. The reference extraction/publication
mechanism is [Solid Refresh](https://github.com/solidjs/solid-refresh),
`src/babel/core/transform-jsx.ts` and `src/runtime/index.ts`.

In real Chrome, an explicit-registration fixture replayed 28 of 28 checks on the pre-rebase
tree `fcceb359` (msc candidate `b87bbaa4`): count 8 kept through a template publication, the new
handler adding 2, four publications leaving one node and one handler, a body publication
resetting only the local count, and a sibling, a textarea, undo and the page session surviving.
The same build without listener cleanup failed 8 of 28 (a detached button kept incrementing).
It was not re-run after the rebase onto origin's DOM host. On that host, extern DOM views must
carry the browser's own class name: a fake name (`DomNode`) fails checked casts in Chromium with
`ReferenceError: DomNode is not defined`.

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
  row list, its new rows built in that compute → `reconcileArrays` moves and removes rows in front of the region's
  anchor → a dropped row's owner is disposed (effects die, `onCleanup` fires). Diffing
  exists ONLY here: one region's own rows, never recursive, only when that region's
  source changed.
- **op** — `<ForList each={list}>` over a `createList` handle (`src/core/list.ms`,
  `src/render/listRegion.ms`). A command on the handle (`push` / `insert` / `move` / `remove` /
  `set`) writes ONE op into each mounted region's queue and bumps the list's version; the region's
  effect compute takes the queue, builds the rows the ops need into the region's holder and updates
  the row array, and queues the host work as steps the effect's apply plays: an insert moves one
  built row before the next row's first node, a move only re-inserts nodes that already exist, a
  remove takes one row's nodes out (its root is disposed in the compute), and a set writes the
  row's own signal and touches no node. A pending read in an inserted row's build leaves that op and
  the ones after it in the queue for the retry. No op reads the list, builds an array or diffs. A row of a `ForList` carries
  `Accessor<T>` rather than bare `T`, which is what lets `set` be a signal write instead of a
  rebuild. `replaceAll` is the escape hatch: it drops the queue, matches each new item to the row
  that carried it — by the optional `keyed` function when one is given, by item identity otherwise,
  like `<For>` — builds the rows no old row carries, and hands the result to `reconcileArrays` in the
  apply, so a reorder still moves nodes and a row
  keeps its DOM, its focus and its scope. A plain array in `<For each={xs}>` keeps the structural
  path untouched.

## Boundaries — `Errored` and `Loading` keep their content behind the fallback

`<Errored>` over `createErrorBoundary` and `<Loading>` over `createLoadingBoundary`
(`errorRows` and `loadingRows` in `src/macros/ui/flow.ms`) mount their children once. While the
fallback shows, the children's host nodes and state stay alive behind it and come back as the
same nodes when the boundary clears; the content is not rebuilt, as in Solid, where the boundary
holds it as a value. Where the nodes wait, and how a region inside them finds its parent,
are `docs/REFERENCE.md` RD-5 and RD-6; this section does not restate them. A reset recomputes only
the effect that failed, and content that never finished mounting is freed, not kept
(`tests/render/erroredKeep.test.ms`). On the server `Errored` sends a generic error outside a dev
build (`tests/render/errorBoundaryServer.test.ms`).

## Hydration — a served page's nodes become the live tree

`hydrate` (`src/render/hydrate.ms`) runs the same mount as `render`, on a host that hands out the
nodes a parsed page already holds instead of creating them (`src/render/claim.ms`, the `claim`
capability of `Host`). Nothing else in the mount path knows: the element macro, templates and
the hand-written builders are unchanged.

**Why by position and not by key.** Solid finds a served element through a key: the server
writes `_hk` on every template root, the client sweeps `[_hk]` into a registry and
`getNextElement` looks the key up (`~/projects/solid-next` at `84dada77`,
`packages/web/src/client.ts` `getNextElement`, `gatherHydratable`). It needs the key because a
DOM-expressions template is created detached, with no parent to look in, and its `universal`
renderer has no hydration at all (`packages/universal/src/universal.ts` has no claim hook). A
Neon mount has an order instead, and the order is enough:

- a mount creates nodes in document order;
- an element is put into its parent only after its own children.

So the element being filled is always the last one created and not yet placed, and the node
asked for next is that element's next unread child. Keys were rejected for that reason: they
cost an attribute on every template root of every page and locate nothing position does not.
The owner ids (`Computation.id`, `src/core/runtime.ms`) stay, for `createUniqueId`.

**The one creation out of order** is a region's end anchor, made before the rows that sit in
front of it. A region therefore takes its anchor from `regionAnchor` and calls `sealRegion`
once its first rows are mounted; during hydrate the anchor is a fresh text that replaces the
page's placeholder at that moment. A new builder that creates a node ahead of what precedes
it in the document must do the same, or hydrate reads the wrong node; "regions the page sent
empty fill in after hydrate" (`tests/render/hydrate.test.ms`) fails when the seal is missing.
A subtree mounted where the page did not render it (a Portal's layer) goes through `unclaimed`.

**What the server writes so a parse keeps the node list** (`src/render/ssr.ms`): `<!---->`
where the tree holds an empty text, which an HTML parser would drop, and `<!--!-->` between two
adjacent texts, which it would merge. The DOM host's `claim` turns the first back into a text
node and removes the second. Solid's counterparts are
`<!--$-->`/`<!--/-->` around a dynamic child and `<!--!$-->` between text values
(`packages/web/src/server.ts`, `ssrTextTail`); Neon needs no pair because it does not scan for
a region's end.

A tree that differs from the page gets a message naming the missing node by tag, child index
and path. A debug build throws it. A release build logs it with `console.error` and rebuilds the
page: the mount goes on creating fresh nodes after the first difference, then `hydrate` disposes
it, empties the container and mounts the tree again, still reading the page's records
(`REFERENCE RD-12`). Limits, each one loud or measured:

- An element the tree leaves without children is not checked for extra ones, so a node that
  holds children Neon does not own (a canvas, a foreign editor's mount point) hydrates.
- `claim` refuses no tag the server writes. A wire tag whose DOM `createElement` does more than
  create an element (`scrollview`, `switch`, `activityindicator`, `multilinetextinput`, `image`,
  `svg`, `video`, `webview`, `camera`) is served as the element, classes and fixed attributes of
  `webHtmlTag`, `webControlClass` and `webFixedAttrs` in `src/render/web.ms`, the rules of
  `webRules` reach `renderToMarkup(...).css`, and `claim` leaves the host in the state
  `createElement` would have. A served switch carries `checked` and a served textarea its text,
  which `claim` turns back into the property. A served `video` or `webview` is not reloaded: the
  host skips a `src` or `srcdoc` the element already holds, as dom-expressions skips attribute
  writes while hydrating (`setAttribute`, `packages/dom-expressions/src/client.js:122`). A frame
  whose page loaded before `hydrate` counts that page as its first history entry and is not
  reported loaded; a served `camera` is kept and its stream starts in it, because a stream exists
  only in the browser. A `Modal` writes nothing into the page (its layer goes through a Portal
  into the overlay root, which `hydrate` mounts unclaimed); `Slider`, `Picker` and
  `DateTimePicker` are drawn from `view` and `pressable` and have no tag of their own.
  A `ScrollView` with `onRefresh` was not measured: the DOM host appends its refresh indicator
  itself, and the server writes none.
- Text content and attribute values are not compared; static attributes are written again.
- Markup the parser restructures (a block inside `<p>`, a `<tr>` without `<tbody>`) arrives
  as a different node list and fails as a mismatch.
- Events fired before hydrate are not replayed (Solid queues them in `_$HY.events`).

Measured 2026-10-13 on tree `e0c70ab823b7a09a5f995cf0eae0304d7e11921b`, msc v0.3.2 `ea7ae4d17`:
the Geass site (`~/metascript/geass/web/src`, copied beside a link to this tree) rendered on
the mock host and hydrated onto those nodes, `--target=js`: home 216 elements at width 1440 and
170 at 390, `/docs` 335 and 309, four more docs pages 110–272, the 404 page 8; the host created
0 elements in every case and the tree's serialisation was unchanged. On Chrome
(`tests/browser/hydrate.test.ms`): 0 elements created, every element still the parsed page's
own after a signal write, a press, a `Show` toggle and a `For` reorder.

## A served page — what a server render skips, the head, and links

**A server render calls no `ref`** (`asServer` in `src/render/environment.ms`, read by
`applyRef`). A ref handler expects the platform's node and on a server it would receive the
writer's record: Geass's `ref={startMech}` ran inside the Worker and its cast to
`HTMLCanvasElement` threw. Solid drops `ref` and event attributes when it compiles for the
server (`~/projects/solid-next` at `84dada77`, `packages/babel-plugin/src/ssr/element.ts`,
`key === "ref" || isEventName(key)`). Neon has one emission for every host, so the same
decision is taken at run time; the writer drops an event handler. `isServer()` holds only
inside the synchronous render, not for the whole program.

**`Head` is a portal, not a registry.** `@solidjs/meta` (`~/projects/solid-meta` at `391138e`,
`src/index.tsx`) keeps the head in a context: every `Title`/`Meta` calls `useHead` with a
`createUniqueId`, the provider sorts cascading tags and writes the DOM itself, and the server
collects strings. In Neon the tags are ordinary nodes mounted through the host into the root
it gives (`Host.headRoot`, the shape of `overlayRoot` for `Portal`), so a reactive title is one
`bindText` and a route that leaves takes its tags with it through `onCleanup`. The cascade
falls out of the order: a `Head` mounts in front of what is there, so the `Head` mounted last
(the innermost, unless a parent writes its own after the child) comes first, and a browser
reads the first `<title>`. A `title`, and a `meta` of one key, is in the document once, as
in solid-meta (`addTag`/`removeTag`, `src/index.tsx:94–170`): the DOM host holds the one a
later `Head` wins over out of `document.head`, behind a comment that keeps its place for the
tree that owns it, and puts it back when the winner leaves; `renderToMarkup` writes the first
of a key. The key is solid-meta's (`getTagKey`, `:42–58`): `name` or `property`,
`http-equiv`, `content`, `charset`, `media`. `content` is part of it, so two `og:image` metas
both stay, and so do a layout's description and a page's: a description belongs in one `Head`
per route. A `meta` with none of `name`/`property`/`http-equiv`/`charset` has no key and
always stays; solid-meta would keep one of two `itemprop` metas with equal content. Beside these stays
every other tag. Served tags carry `data-neon-head`; the DOM host removes them when the first
`Head` mounts (solid-meta removes `[data-sm]`). Limits: head tags are created again on the
client rather than taken over, so a stylesheet link belongs in the page shell, where it is
not reloaded; the shell itself (`<!doctype>`, `<html>`, `<body>`, the script tag) is written by
the server entry (`examples/site/server.ms`), not by Neon.

**Links are followed by one listener** (`followLinks`, `src/platform/browser/routingHistory.ms`),
the conditions of Solid Router's `handleAnchor` (`~/projects/solid-router` at `d0379e7`,
`src/data/events.ts`): primary button, no modifier, no `target`, no `download`, no
`rel="external"`, same origin. A link the routing session cannot match is left to the browser,
so the server answers it; a route tree with a catch-all route matches every link, so a missing
page renders on the client inside its layout, as Solid's catch-all does, and only a request
gets the 404 status (`examples/site`). After a followed link the page scrolls to the element
the fragment names, or to the top (`scrollToHash`, `src/routers/createRouter.ts:55`); the
browser fires no `hashchange` for it, so a consumer that wants the browser's own fragment
navigation answers `false` for that link.

**A route's state has to hold everything of the address it accepts.** A routing session writes
`registry.address()` back into the history entry as soon as it opens, and after a back or
forward whose entry lands on another address, so a codec that matches
`/docs/start?utm=1#notes` and encodes `/docs/start` rewrites the visitor's URL, and one that
matches only the bare path answers 404 to the tagged link (both measured on `examples/site`
and on Geass, 2026-10-13). The route tree shorthand (`src/navigation/router.ms` `Router`)
keeps the whole address as its state and derives the match from it.

**A path whose page is the same for every request is rendered to a file at build time.**
The route tree lists those paths (`RouteTree.staticPaths`): a route without params is one
path, a route with params lists its values through `paths`, and a catch-all is left out, because
a route codec only decodes and cannot be enumerated. The edge lane asks the built site Worker in
workerd for each and writes `out/static/<path>.html` plus `404.html` (`prerender`,
`tests/edge/run.mjs`). That is Astro's Cloudflare prerenderer (`~/projects/astro` at
`7492974`, `packages/integrations/cloudflare/src/prerenderer.ts`, `getStaticPaths` and
`render`): the bytes come from the same bundle and runtime that answer live requests, and a
render that fails fails the build. Astro requests a prerendered page with no query and no
headers (`packages/astro/src/core/request.ts`), so a page that reads either is not static;
the lane checks the query half by comparing each page with the same path plus `?utm=1`.
Geass reads the User-Agent for its layout width, so its docs stay on the Worker until the
width no longer decides the markup. Files use Astro's `'file'` layout (`/docs/start` →
`docs/start.html`): the `'directory'` layout's `docs/start/index.html` would be served at
`/docs/start/`, which the route tree shorthand redirects to `/docs/start` with 308. Serving the files ahead of the
Worker is the deployment's job (Workers Static Assets, or `run_worker_first` exclusions).
What a prerendered page saves is the Worker's render, measured 2026-10-15 on tree
`69c8920f26d68c66727a7886a05ae97300e7ff93` with the `-d:server` bundle in Node:
`respond("/docs/start")` 0.017–0.031 ms per request for its 1 433 bytes, three runs of 2 000
at load 17–27 on 14 cores. The rest is the platform serving a file instead of starting the
Worker, which a local run cannot measure.

Measured 2026-10-16 on tree `25f5f65aa491f01e7b4d6e80400a7c27a5b4caad`, msc v0.3.4 `15b93cbba`,
`sh tests/edge/run.sh` (workerd, then Chrome), with the site on the route tree shorthand:
`/` and `/docs/<slug>` answer 200 with their own title and description, `/docs/missing`,
`/nowhere` and `/docs/missing?utm=1` answer 404 with `noindex`, and `/docs/start/?utm=1` answers
308 to `/docs/start?utm=1`. Chrome attaches to `/docs/start` with no element of the 14 added or
removed; a link to another doc keeps the layout's `nav` element, replaces the page, and changes
the heading, title, description, `aria-current` and URL with one document request in total and
the scroll back at the top; back restores the page; a link to no page renders Not found in the
layout without a request. The debug bundles, not minified: `site.js` (server) 781 KB, 94 KB
gzipped; `siteClient.js` 1 270 KB, 155 KB gzipped. The site before the shorthand (`56102ef`),
built by the same msc: 655 KB, 79 KB gzipped, and 1 145 KB, 141 KB gzipped, so the shorthand,
its matcher and its outlet cost about 14 KB gzipped in each bundle.

### The request handler — `src/render/serve.ms`

`serve(app, url)` opens the router on the request address, renders `RouterProvider` through
`renderToStream`, and answers `{ status, location, body }`: the router's redirect is a status
and a location with no body, a route's own status serves its page, and an address no route takes
is 404 (400 for any other routing error) through `app.notFound`. `app.document` places the
markup's head, css, html and records; `htmlDocument(root, client)` is the default, with the
client module script last. On `--target=js`, `fetchPage(app, request)` maps a Fetch `Request` to
a `Response` (GET and HEAD; any other method is 405 with `allow`), the one call a Worker's
`fetch` makes for a page. Shape from SolidStart `server/handler.ts` (`createBaseHandler`: render,
then redirect by the response's `Location`) and Astro's Worker entry that maps `Request` to
`Response`. Not ported: SolidStart's `StartServer.tsx` document is a component that receives
`assets`, `scripts` and `children`; Neon's writer sends `Head` content to `SsrMarkup.head`
beside the body, so a document component cannot place it, and the document is a function over
the finished markup. A component form needs a head slot in the writer.

`serve(app, url, headers)` takes the request headers as a `Map` (optional); `fetchPage` passes the
Fetch request's. A component of the served tree reads them with `getRequestEvent()`:
`event.request.url` is the address `serve` received and `event.request.headers.get(name)`
matches the name in any case, names differing only in case joined with `, ` as Fetch joins them.
It is `null` outside a served render and on the client. The event is set on the render's root
owner with `setContext` and read through the caller's owner, Solid's `getRequestEvent` fallback
(`packages/web/src/server.ts:6448-6470`), never a module global, so two requests in flight in
one isolate each read their own. Neon has no `AsyncLocalStorage` on C, so a read with no current
owner is `null`; read the event in a component body or a reactive spot.

The window size of a served page follows the same path. In a `-d:server` build,
`publishWindow(width, height)` called under an owner sets the size on that render's owner with
`setContext`, and `useWindowDimensions()` under it reads that size; with no size published in its
render it reads the module's size, which a `publishWindow` outside any owner writes. A root
component that picks the size from its request (`getRequestEvent()`, say the user agent) calls
`publishWindow` first, and two requests in flight render with their own size. On the client, and
outside an owner on the server, `publishWindow` writes the module's size as before; a write under
an owner there is the owned-write error of any signal.

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
time, goes through `layerStyles` once, or, when a layer or a field is reactive (an
accessor is called), through one `bindStyleAll` over `layerStyles`, the lowering a
component's `style` array takes too; a reactive expression is `bindStyleAll`; anything
else is `applyStaticStyle`. A `ref` runs
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
A context tag (`<Ctx value=…>`) is the same shape with the call wrapped in the provider's scope.

**Fragments.** `<>…</>` owns no host node. In child position it is not emitted at all:
the macro splices its children into the parent's child list at COMPILE time
(`flattenFragments`, recursive, matching Solid's `normalizeIncomingArray`), and `<></>`
erases. At the ROOT it lowers through the flat tier with every root placed in front of
`before`, in order. Inside an expression a fragment is JSX like any other: an `&&` or `?:` arm
lowers to `Show` with the fragment as its children, and a prop value or a call argument
lowers through the converter to a multi-root NeonNode. There is no fragment-specific
rule left — where no NeonNode is expected (`a ?? <>…</>`) the compiler rejects a fragment
with the same error it gives an element there.

**Regions.** `For` / `Repeat` / `Show` / `Match` (`src/macros/ui/flow.ms`) each return
`regionNode(fn)` (`src/render/node.ms`): an anchor text node placed at the region's
position, plus one render effect that reconciles the region's rows in front of that anchor.
A `Row` (`src/render/reconcile.ms`) is a NeonNode plus the span of host nodes it
produced (`start`…`end`) and the owner it was created under.

A row is built where Solid builds it, in the compute that makes the row: a `Show` child inside
the `createMemo` compute (`packages/solid/src/client/flow.ts:226`), a `For` row by the mapper
under its own row owner inside the map's computed (`packages/signals/src/map.ts:362`). `builtRow`
mounts the row under the row's owner, untracked. The region effect's apply only places rows that
are already built, as dom-expressions `insert` does with nodes the compute made
(`packages/web/src/client.ts:1563`): `reconcileArrays` moves a built row by re-inserting its span,
keeps a live row where it is, and removes only a row absent from the next list — insertion targets
come from the NEW order (Svelte `each.js`), so a live row is never detached.

Where a row is built depends on the pass. The pass that creates the region builds in place, in
front of the region's anchor: the region's parent is still being built, so no one sees the rows
before the effect's first apply, and a hydration takes the page's nodes there. A later pass builds
into the region's holder (`RowHome`, a detached host node made on the first such build) and the
apply moves the rows out of it. A pending read in a row's build is therefore the rows memo's
pending status and reaches the nearest `Loading`, which holds its fallback; the nodes the failed
build had placed are freed (`buildInto`) and the region rebuilds the row when the value settles. A
pass that built some rows and then aborted leaves them where they were built, and the next apply
(or the region's disposal, for a holder) frees them. A `Loading` or `Errored` keeps its content in
that same holder while its fallback shows. A region with no owner never releases its holder, as
nothing owns the region either.

While a row mounts, `place` records the first and last host node it put into the row's parent, which
is how a row made of a fragment, a component or a nested region gets a span without anyone counting
nodes; an empty row gets one empty text node so it still has a position. A view that puts a node
into its parent without `place` leaves it behind in the holder of a later pass.

Every client reader builds its rows this way: the control-flow components, the navigator header's
`Slot`, the cells and grid items of `VirtualizedList` (a grid item's scope is created under the list
and its pending reads are re-pointed at the effect that builds it, as `mapArray` does,
`src/core/array.ms` `mapRows`), `ForList`'s ops, and a hot-reloaded instance, which Solid builds in the
memo that wraps it (`packages/solid/src/refresh/index.ts` `createProxy`) and Neon in the rows memo of
its region. A `Head` is not a region: its content mounts inside the mount that places it, in whatever
compute built the row around it. `reconcileArrays` does not mount. A row it is handed that no compute
built throws `[ROW_NOT_BUILT]` naming the region, so a reader that would build in the apply, and halt
reactivity on a pending read, fails where it was written. On the server a region writes its rows in
document order with `mountAt` from its own pass and describes them with `makeRow`.

**Show.** `<Show when={x}>` takes any value and tests its truthiness (MetaScript's: a `number`, `string`
or `boolean` by its zero value, a class by non-null; a nullable union `T | null` is a null check only,
which is a compiler card, not a Show rule). The element macro (`showCall`, `src/macros/ui/element.ms`)
picks the engine from `keyed` and the child, as `For` does from `keyed`: an element child is `Show`;
`keyed` is `ShowKeyed` and rebuilds when the value changes; a function child is `ShowWith`, which
receives an `Accessor<T>` of the value with `null` removed and throws when it is read while the
condition is false; `keyed` plus a function child is `ShowKeyedWith`, which receives the value itself.
`keyed` is written `true` or `false` in place — a computed value is a compile error, as on `For`. The
function and keyed forms evaluate `when` once per change in a memo created at mount (`showWhen`), so
the child's reads and the condition share one evaluation. Reference: solid-next
`packages/solid/src/client/flow.ts:164-250`; pins `tests/render/show.test.ms`.

**Server rendering.** There is one server renderer, and only a `-d:server` build has it:
`renderToString` and `renderToMarkup` (`src/render/ssr.ms`) are a compile error in any other
build, naming the flag at the call. Solid keeps its server renderer out of the browser bundle
by resolving `@solidjs/web` to a server entry under the `node` and `worker` export conditions
(`~/projects/solid-next` at `84dada77`, `packages/web/package.json` `exports["."]`); its
browser entry keeps a `renderToString` that logs and returns `undefined`
(`packages/web/src/server-mock.ts`, `throwInBrowser`), where a Neon build stops, because the
flag is known at compile time. `renderToMarkup` is the form for a process that answers many
requests: it collects the rules that one render mounted into the returned `css`, after the rules
registered outside any render (a theme's `:root`), and leaves the registry alone. A registry
shared by every request sends each page the rules of every page rendered before it, which is
why `renderToString` with `mountSheet()` stays the form for a process that prints one page
(`tests/render/ssrRequestServer.test.ms`). The Chrome lane hydrates pages a `-d:server` build wrote
(`tests/browser/serveApps.ms`), as Solid's hydration specs replay what its server specs
recorded (`packages/web/test/hydration/slot-hydration-3567.spec.tsx`, `loadArtifact`). A test
that renders to a string sits in `<name>Server.test.ms` beside the client file and runs only under
`-d:server`, as Solid keeps `packages/web/test/server/*.spec.tsx` apart from the client specs and
excludes them from the client run (`packages/web/vite.config.mjs`).

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

Sections dated before 2026-10-15 measure the engine as it was before the Solid 2.0 migration, and
they are kept as history of those numbers: the names in them (`mapArrayKeyed`, the `key` prop of `For` and `ForList`, now `keyed`) are the old engine's, and
the 2026-10-15 sections re-measure on the 2.0 engine.

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
slower** — and remove is unchanged. Fixed later the same day, below.

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
regression as Chrome, magnified by a host whose moves are linear. Fixed later the same day, below.

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

**The reorder regression, fixed.** The table above measured `reconcileArrays` as the merge landed it: it walked the
new order left to right and forced each slot, so a swap of two rows moved every row between them. It now leaves the
longest increasing run of surviving rows alone and moves the rest (Vue 3 / ivi), which is the minimum. Host calls
counted by a wrapping host, 1000 rows — exact counts, not timings:

| op | before | after |
|---|---|---|
| swap rows 1 and 998 | 997 `insertBefore` | **2** |
| reverse | 999 | 999 |
| remove half | 0 moves, 500 `removeChild` | 0 moves, 500 `removeChild` |

`reconcileArrays` alone, 5000 rows already in the host, ms per call, min of 3 interleaved page loads × 20 rounds,
lower is better. This isolates the reconciler from `mapArray` and from the row bodies:

| op | before | after |
|---|---|---|
| swap two rows | 1.8 | **0.4** |
| reverse | 9.0 | **0.4** |
| move one row to the front | **0.1** | 0.4 |
| remove half | 0.1 | 0.1 |

The one cell that got dearer is the small edit: the old walk stopped as soon as the rest matched, this one is five
passes over the list whatever the edit is. It costs 0.08 ms per 1000 rows and buys the two rows above.

End to end, 1000 rows of a dyn3 row in a `For` (`probe/m/opsDom.ms`, `opsNative.ms`), ms per operation, lower is
better; before = `9652fe9`, after = this arc, interleaved, min, load 3.5–3.9. "old direct" repeats the retired
emitter's column from the tables above, for scale:

| op | Chrome before | Chrome after | old direct | native before | native after |
|---|---|---|---|---|---|
| swap | 0.605 | **0.385** | 0.365 | 1.125 | **0.091** |
| reverse | 0.915 | **0.530** | 0.645 | 1.652 | **0.459** |
| remove half | 0.240 | **0.200** | 0.220 | 0.754 | **0.613** |
| mount | 1.900 | 1.900 | 2.300 | 2.795 | 2.553 |
| update | 0.700 | 0.700 | 0.805 | 0.386 | 0.390 |
| bytes per row (Chrome heap) | 1883 | 1893 | 1785 | — | — |

Verdict: reorder is no longer a regression — reverse and remove are now below the retired emitter too, swap is within
5% of it, and on a host whose moves are linear (mock, void, terminal) a swap is 12x cheaper. The 10 bytes per row are
the three marks the reconciler keeps on a `Row` instead of a per-update map.

Two things found while measuring this, both carded: std `Map` with a ref key costs 15–70x a number key per operation
(`~/metascript/.inbox/compiler/2026-09-20-map-ref-key-entry-copy-per-probe.md`), which is why the row marks live on the
row; and on `--target=js` an array index that is not a loop counter compiles to `BigInt(Math.trunc(i))`, 19x per read
(`…/2026-09-20-js-array-index-allocates-a-bigint.md`) — the kept-run search is written to index by arithmetic locals
only for that reason and should be simplified back when it is fixed.

Not measured, and why: reorder and memory on the void and terminal hosts (the terminal host has no bench; the void
host's own mount cost is the table above and still dominates a row); memory as live bytes on native (no runtime counter; the
footprint delta is an upper bound that includes allocator slack).

### 2026-09-20 — a key function takes an object list off the ref-keyed map

How it was measured. msc v0.2.55, binary `cdc62398`; `probe/m/keyedCost.ms` (gitignored), release
build, N = 5000 rows, 10 rounds, the three variants run alternately **inside one round of one
process**, every cell the MIN over the rounds, load 3.1 before the run. A cell is ms for one call of
the mapped accessor after the list is replaced — the whole `mapArray` step, no host: *build* is the
first call, the others replace the list and call again. **Lower is better.**

`number` is `mapArray` over a `number[]`; `object` is the same `mapArray` over an `Item[]`, which is
what a list of records costs today; `objectKeyed` is the same `Item[]` through `mapArrayKeyed` with
`(item) => item.id`.

| op, 5000 rows | `number` | `object` (before) | `objectKeyed` (after) | after ÷ before |
|---|---|---|---|---|
| build | 1.00 | 0.955 | 1.07 | 1.12 |
| swap | 0.256 | 2.84 | **0.279** | **0.098** |
| reverse | 0.266 | 2.59 | **0.267** | **0.103** |
| move 1 | 0.253 | 2.72 | **0.265** | **0.097** |
| remove half | 0.243 | 2.36 | **0.257** | **0.109** |
| add 1 | 0.050 | 0.071 | 0.154 | **2.17** |

Verdict: every reorder and removal on a list of objects drops ~10x and lands on the number list's
figure, which is what the key was for; the cause it removes is the ref-keyed `Map` carded at
`~/metascript/.inbox/compiler/2026-09-20-map-ref-key-entry-copy-per-probe.md`. **Two cells got worse
and both are the price of the key**: the keyed path extracts a key per row and builds its index over
the whole list, so the first build costs 12% more and appending one row costs 2.2x (0.071 → 0.154 ms
per 5000 rows) — the full-range index is what makes a duplicate key an error rather than a silent
wrong render.

Not measured, and why: Chrome (the JS backend's `Map` is not the one being routed around, and the
browser's timer coarsens at 0.1 ms to the size of the whole win on the cheap cells); a string key,
because it is not a surface Neon offers — measured on its own (`probe/m/keyKind.ms`, same machine)
a `Map<string, number>` cycle costs 9.85 ms against 4.54 for a ref key and 0.145 for a number key, so
a string key would be **worse than no key at all** on the C backend; and `<For>` itself, because the table times the
engine, not the tag — the `key` prop landed on the tag on 2026-09-21 and its cells are in
`tests/render/flow.test.ms`.

### 2026-09-21 — the macro tells mapArray when a row never reads its index

How it was measured. msc v0.2.55, binary `d74853ed`; `probe/m/indexFlagCost.ms` (gitignored), release
build, N = 5000 rows of `number`, 10 rounds, both variants run alternately **inside one round of one
process**, every cell the MIN over the rounds, load 2.6 before the run. A cell is ms for one call of
the mapped accessor — the whole `mapArray` step, no host. **Lower is better.**

`with index` is what every row paid before: an `IndexCell`, a lazily-signalled accessor, a closure
setter and three parallel setter arrays. `no index` is the same engine told the row never names its
index parameter, which the element macro now decides by reading the row arrow's body.

| op, 5000 rows | with index | no index | after ÷ before |
|---|---|---|---|
| build | 1.10 | **0.82** | 0.74 |
| swap | 0.286 | **0.219** | 0.77 |
| reverse | 0.262 | **0.205** | 0.78 |
| move 1 | 0.290 | **0.204** | 0.70 |
| add 1 | 0.060 | **0.040** | 0.67 |
| remove half | 0.273 | 0.440 | **1.61** |

Verdict: five cells of six get 22–33% cheaper and one gets 61% dearer. Remove-half is the only cell
that DISPOSES rows, and a root holding fewer closures costing more to dispose is backwards; three
hypotheses were tested and refuted (a shared accessor captured by every row, the zero-length setter
arrays, run order), so it was left open in BUGS.md §7 rather than explained here; the 2026-10-15 section below finds it gone on the 2.0 engine. The same inversion was
seen on 2026-09-20 by a hand-copied index-free `mapArray` in another arc, so it belongs to dropping
the machinery, not to this implementation.

What the macro decides, and what it cannot: a row written `(x) => …` or `(x, i) => …` whose body never
names `i` is emitted `usesIndex: false`; a named row function, or anything the macro cannot read, is
emitted `true`. A row that rebinds the index name reads as a use and keeps the machinery. The wrong
direction is caught loudly — a row emitted index-free gets an accessor that raises if it is ever read,
pinned by `tests/core/array.test.ms` — while the other direction only costs the win, and is covered by
this table rather than by a test.

Not measured, and why: Chrome (the win is allocation and closure count, and the browser's timer
coarsens at 0.1 ms to the size of four of these six cells); and whether the macro picks `false` on a
given tag, because the only runtime observable of the choice is the raise, so the table above is the
evidence that the false path is taken at all.

### 2026-10-15 — the same flag on the Solid 2.0 `mapArray` engine

`mapArray` / `mapArrayKeyedBy` take the flag again (`usesIndex`, solid-next `packages/signals/src/map.ts:75`
and `:97`, where the reference decides it from `map.length > 1`; Neon decides it in the element macro, so
`For` and `ForKeyedBy` pass what `rowUsesIndex` read). `/tmp/s2b/b1b/bench/indexFlagCost.ms`, release C
build, N = 5000, 10 rounds, the three variants alternating inside one round of one process, every cell
the MIN, load 28 on a shared machine (so read the ratios, not the milliseconds). `base` is the engine at
`b0125c8` with no flag; `with index` is the new engine told the row reads its index; `no index` is told it
does not.

| op, 5000 rows | identity base | with index | no index | no index ÷ base | keyed base | with index | no index | no index ÷ base |
|---|---|---|---|---|---|---|---|---|
| build | 1.055 | 1.055 | 0.907 | 0.86 | 2.195 | 2.142 | 1.278 | 0.58 |
| swap | 0.478 | 0.478 | 0.433 | 0.91 | 0.743 | 0.755 | 0.525 | 0.71 |
| reverse | 0.481 | 0.461 | 0.427 | 0.89 | 0.611 | 0.612 | 0.501 | 0.82 |
| move 1 | 0.465 | 0.465 | 0.430 | 0.92 | 0.681 | 0.673 | 0.510 | 0.75 |
| remove half | 0.770 | 0.749 | 0.668 | 0.87 | 1.135 | 1.042 | 0.925 | 0.82 |
| add 1 | 0.096 | 0.091 | 0.059 | 0.61 | 0.204 | 0.205 | 0.127 | 0.62 |

Verdict: every cell is cheaper without the index, and the flag costs the rows that read their index
nothing (`with index` ≈ `base`). The remove-half inversion of the 2026-09-21 table is gone on this engine.
A row emitted index-free raises if it reads its index (pinned by `tests/core/array.test.ms` and
`tests/render/flow.test.ms`), and the macro's decision is pinned per row shape by
`tests/render/forIndexElision.test.ms`. Not measured: Chrome and the JS backend.

### 2026-09-21 — one op per edit against a rebuilt array, and where the last O(n) actually lives

How it was measured. msc v0.2.55, binary `1fc3d947`; `probe/m/listOpsScale.ms` (gitignored), release
build, sizes N = 1000 / 5000 / 20000, 5 rounds per size with **all four roads run inside one round of
one process** and the round order flipped every other round; each cell the MIN over the rounds and then
over three runs of the whole binary; load 3.4–8.8 before each run, read from `vm.loadavg`. A cell is ms
for ONE user-level operation, taken as the mean of 20 consecutive ops (4 for `reverse`). **Lower is
better.** Both hosts are asserted correct in the same binary before the timing: after
`insert(1,9) · move(0,2) · remove(0) · replaceAll([4,5])` each prints `9213` then `45`.

The two roads. `For diff` is `<For each={xs}>` over a plain array signal — the caller builds the next
array and hands it over, the region diffs; **the cell includes building that array**, because the road
requires it. `ForList ops` is `<ForList each={list}>` over a `createList` handle — one op, no array
built, no list scanned.

The two hosts, which is the point of this table. `dll-host` keeps its children in a doubly linked list,
so `insertBefore` / `removeChild` / `nextSibling` are O(1), the way a DOM's are. `array-host` is
`mockHost`: children in an array, the reference node found by a linear `childIndex` and moved with a
`splice`, so the HOST alone is O(n) per call. Measuring only on `mockHost` would have credited the host's
cost to the region.

| ms per one op, `dll-host` (O(1) host) | 1000 diff | 1000 ops | 5000 diff | 5000 ops | 20000 diff | 20000 ops |
|---|---|---|---|---|---|---|
| mount the whole list | **0.373** | 0.727 | **2.646** | 4.864 | **14.04** | 21.37 |
| insert 1 row (middle) | 0.0356 | **0.0049** | 0.183 | **0.0216** | 4.104 | **0.0908** |
| move 1 row (neighbour swap) | 0.0524 | **0.0002** | 0.259 | **0.0002** | 4.464 | **0.00025** |
| remove 1 row (middle) | 0.0306 | **0.00465** | 0.159 | **0.0221** | 2.934 | **0.0854** |
| reverse the whole list | **0.1002** | 0.1052 | **0.497** | 0.530 | **7.491** | 10.29 |

| ms per one op, `array-host` (`mockHost`, O(n) per host call) | 1000 diff | 1000 ops | 5000 diff | 5000 ops | 20000 diff | 20000 ops |
|---|---|---|---|---|---|---|
| mount the whole list | **0.906** | 1.233 | **13.43** | 16.18 | **185.7** | 192.1 |
| insert 1 row (middle) | 0.0369 | **0.0057** | 0.197 | **0.0272** | 3.288 | **0.1875** |
| move 1 row (neighbour swap) | 0.0535 | **0.00095** | 0.267 | **0.00385** | 3.687 | **0.0149** |
| remove 1 row (middle) | 0.0313 | **0.00515** | 0.161 | **0.0250** | 1.912 | **0.0981** |
| reverse the whole list | **0.4335** | 0.4332 | **9.598** | 9.845 | **158.5** | 163.2 |

Verdict, on the O(1) host at 20000 rows: **move is 17 900x cheaper and FLAT in N** (0.0002 / 0.0002 /
0.00025 ms — the only cell the arc set out to make flat and the only one that is), insert is 45x cheaper
and remove 34x cheaper but both still **linear in N**; mount costs 1.52x and a whole-list reverse 1.37x
MORE than the diff road. On `mockHost` the same five cells still favour the op road by 17x to 250x, but
its mount and reverse figures are the host's linear `childIndex`, not the region's: the same mount is
185.7 ms there and 14.0 ms on the linked-list host.

Why insert and remove are still linear, and what would fix it: an op names its row by INDEX, so the
region keeps `rows` / `cells` / `disposers` index-addressable and an insert in the middle shifts three
pointer arrays — measured at a steady ~4.5 ns per row shifted (4.9 / 4.3 / 4.5 ns at the three sizes),
which is the whole remaining slope. No structure gives O(1) insert AND O(1) lookup by index; flat
insert/remove would need ops that name a row by KEY instead of by position, which is a surface change
and is not taken here. The diff road's own insert does NOT improve on the faster host (4.10 ms on
`dll-host` against 3.29 ms on `mockHost` at 20000): its cost is its own rebuilt array, `Map` and longest-
increasing-run, and no host can give that back.

Why mount is dearer: a `ForList` row carries `Accessor<T>`, so every row allocates a `Signal` and its
text binding subscribes to it; a `<For>` row carries bare `T` and its text is static. That per-row
subscription is exactly what makes `set(i, v)` a signal write instead of a rebuild — the mount pays for
the update.

Why reverse is dearer: `replaceAll` is the escape hatch, not the fast path. It matches each new item to
the row that carried it (by the optional number `key`, else by item identity) and hands the result to
`reconcileArrays`, so it pays for one extra pass over the old values on top of what `<For>` already
pays. On par at 1000 and 5000, 1.37x the diff road at 20000.

Not measured, and why: Chrome and a real DOM (the arc's claim is about the region's own work, and the
browser timer coarsens at 0.1 ms, which is 400x the flat move cell); object rows without a `key`, where
`replaceAll` falls back to a ref-keyed `Map` — its cost is the one already measured on
2026-09-20 (`Map` with a ref key, 15–70x a number key); memory; and the keyed `replaceAll` road, which
is pinned by tests but has no figure here.


### 2026-09-22 — where the mount and reverse premiums actually live, and the one fixable slice

How it was measured. msc v0.2.55, binary `d757c7e1`; `probe/m/forlistParts.ms` (gitignored), release,
N = 1000 / 5000 / 20000, 5 rounds x 3 runs with every variant run inside one round and the round order
flipped, each cell the MIN; load 5-9 before each run; `dll-host` only. Every hand variant is a copy of
the `listRegion` step shapes asserted to render the same string as the two real roads before any
timing. The fix was benched on the real road with `probe/m/listOpsScale.ms` + `runForlistAB.sh`:
two builds of one tree (stash), six interleaved runs, order flipped. **Lower is better.**

| ms at 20000 rows, dll-host | mount | | reverse | |
|---|---|---|---|---|
| `<For>` diff road (A0 / B0) | 13.24 | | 7.10 | |
| `ForList` op road (A1 / B1) | 19.33 | 1.46x | 10.88 | 1.53x |
| hand region, bare rows (A2) | 9.95 | | rows-only permutation, accessor rows (B5) | 9.16 |
| + per-row `Signal` cell (A3) | 9.42 | | same over static rows (B7) | 6.52 |
| + row reads the accessor (A4) | 18.72 | | prealloc bookkeeping (B2) | 11.12 |

Mount, attributed: the cell machinery itself is free (A2 -> A3); the subscription is the whole premium
— a row that reads its `Accessor` gets one computation each, +9.3 ms over 20000 rows — and the diff
road's own mount frame (fresh-row `reconcileArrays`, the `slice`, mapArray's bookkeeping) is 3.3 ms
dearer than the op road's. 9.3 - 3.3 = the 6 ms premium. Store preallocation buys nothing on mount
(A5). Not fixable without a surface change: the subscription is what makes `set(i, v)` a signal write
instead of a rebuild.

Reverse, attributed: a rows-only permutation over STATIC rows (B7) lands below the diff road — the
move machinery is not the problem. The same permutation over accessor rows costs +2.6 ms more (B5):
reordering rows that each carry a `Signal` and a computation pays it in cache locality with zero
signal work. The card's Map hypothesis is refuted: the diff road builds the same-shaped `Map`
(`mapArray`'s `newIndices`), and with number keys the whole `matchByIds` + `oldIds` block is 0.8 ms
of a 3.8 ms delta. What was left and fixable: `resetTo` grew seven bookkeeping arrays by push.

The fix (`4c49618`): `resetTo` preallocates `reuse` / `oldIds` / `newIds` / `nextRows` / `nextCells` /
`nextDisposers` / `kept` at exact size and index-assigns them, fresh rows through a `buildRowAt`
sibling of `buildRow` (mapArray's `makeRowInto` precedent: exact-size prealloc, every slot written
before any read — reading past what an array holds is a segfault on C). On the real road, interleaved:
`ForList` reverse 0.104 -> 0.099 / 0.562 -> 0.504 / 9.221 -> 8.870 ms at 1000 / 5000 / 20000
(-4.6 / -10.3 / -3.8%); every other cell inside the day's noise band, whose width the untouched
`<For>` road shows by swinging +-4% between runs. The flat move, 45x insert and 34x remove figures
are untouched: the op path is not on `resetTo`.

Not fixed, and why: the subscription (mount) and the reactive-row footprint (reverse) are the
`Accessor` row itself — dropping either means rows that carry bare `T`, which is the `<For>` surface,
not a change inside this one.

### 2026-10-04 — a provider's value on its owner, against typed slots on the context

The shape (`src/render/context.ms`): a provider's scope (`<Ctx value>`) carries one `context` entry on its own owner,
keyed by the context object and linked (`next`) to the entry that scope inherited. Every computation,
root and boundary scope inherits its owner's entry when it is created, so `useContext` walks the
providers above it, never the owners in between, to the first entry with its key. The value is held as
`unknown` and read back with `entry.value as Held<T>`, a cast the compiler tests on C and JS.

The inheritance is Solid 1.x's (read then, not re-read on 2.0): a new computation takes its owner's `context` object
(`packages/solid/src/reactive/signal.ts:1444` at `0af2c2b4`), a provider replaces it with a spread copy
holding its value (`:1762`), and `useContext` reads `Owner.context[id]` once (`:1216`). Neon links the
entries instead of copying them: providing costs one entry, not a copy of every context above, and a
read walks only the providers on its path. Before 2026-10-04 Neon walked `owner.owner`, the walk of
Nim Neon (`~/projects/neon/src/core/component.nim:45`, `ComponentContext.data: Table[string, pointer]`
walked through `parent`), whose `cast[pointer]` in and `cast[T]` out read memory unchecked.

Rejected: typed slots on `Context<T>` (`510b5cf`). Each provider pushed `{ owner, read }` into
`ctx.slots` and every `useContext` scanned the slots at each owner on its walk, so with N live
providers of one context a read costs O(N) and mounting N provider rows O(N²). It kept the value
typed without `unknown`; the cost below is why it went. Not taken either: a `Map` keyed by owner on
the context, offered as a stopgap while the compiler still refused `as Provided<T>`; the cast was
fixed in the compiler instead (recompiler `paper/NIM-REF.md` CK-127).

How it was measured. `bench/providerRows.ms`: N provider rows of one context, each mounting one
consumer, on the mock host; mount time in ms, lower is better. msc v0.3.0 (`0f1ecc060`), release C
and `--target=js` on node v24.1.0; slots = tree `16bd9048` (`510b5cf`), owner = tree `585c0f60`;
one full series each, then 3 alternating rounds at 8000 rows; load 16 on 14 cores.

| rows | slots C | owner C | slots JS | owner JS |
|---|---|---|---|---|
| 500 | 0.45 | 0.38 | 2.19 | 0.91 |
| 1 000 | 1.41 | 0.88 | 2.01 | 1.23 |
| 2 000 | 3.70 | 1.65 | 8.15 | 1.50 |
| 4 000 | 13.1 | 3.47 | 27.4 | 2.90 |
| 8 000 | 50.4 | 7.64 | 103 | 6.39 |

8000 rows over the 3 rounds: slots 38.3–39.4 ms C, 74.8–82.4 ms JS; owner 5.0–6.2 ms C, 3.3–3.8 ms JS.
Doubling the rows multiplies the slots mount by about 3.5 and the owner mount by about 2.

**Inherited entries against the owner walk.** `bench/contextDepth.ms`: one consumer reads a context
provided D levels above it, 200 000 reads, ns per read; "owners" puts D plain roots in between (the
effects, rows and roots of a real tree), "providers" puts D providers of another context in between.
msc v0.3.0 (`0f1ecc060`), release C and node v24.1.0; walk = tree `51567b14` (`349b3db`), inherited =
the tree of the commit that adds this table; 3 alternating rounds, the middle one shown, load 16–20 on
14 cores.

| between | D | walk C | inherited C | walk JS | inherited JS |
|---|---|---|---|---|---|
| owners | 0 | 9.3 | 9.5 | 19.6 | 21.0 |
| owners | 10 | 33.5 | 9.4 | 25.7 | 16.6 |
| owners | 50 | 151 | 9.4 | 79.5 | 9.6 |
| owners | 200 | 559 | 9.5 | 330 | 11.1 |
| providers | 10 | 53.9 | 27.4 | 20.9 | 26.3 |
| providers | 50 | 245 | 109 | 83.3 | 83.7 |
| providers | 200 | 945 | 432 | 358 | 340 |

A read no longer depends on how deep the consumer sits, only on how many providers sit between it and
its own. Creating owners did not get dearer: 20 000 roots of two effects each, mounted and disposed,
min of 7, three rounds: walk 57.9–84.2 ms C / 16.2–31.4 ms JS, inherited 52.2–82.2 ms C /
16.8–20.2 ms JS, with no provider above and under one (`out/probe/ownerChurn.ms`, not kept).

## Invariants — the contract every tier and every hand-built node must satisfy

1. **Evaluating JSX is pure** — it allocates the NeonNode and performs no host op
   and no signal read; everything happens when the node is called.
2. **A component body runs exactly once** — any second run is a serious bug
   (`bodyRuns`-counter test pattern).
3. **Every dynamic spot = one effect, created at mount, under the mounting
   owner**, a render effect — never at build time.
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
4a. **A row changes parents only through a FlatList grid's item pool**
   (`numColumns`, `src/components/virtualizedList.ms`). The pool is `mapArray`'s
   ownership lifted over every row container: one root per item while the item
   sits in any rendered row, disposed when it leaves the data or the window, its
   `index` a signal the list sets. A row container's region leaves a live item's
   row in place for the region that now lists it, which moves it in with
   `moveRow`; a container that leaves the window first parks its live items in
   the list content, because a host frees what it removes (native `removeChild`,
   the DOM host's listener release). Only an item that placed one host node moves
   between containers: a region placed directly in the item captured the old
   container as its parent, so an item that placed several nodes remounts on a
   row change, as React Native remounts every regrouped row. Pinned by
   `tests/render/flatList.test.ms` ("a grid keeps an item's state and host node
   when regrouping moves it to another row", prepend, removal, reorder, window,
   TextInput and multi-node cases, on a host that frees what it removes) and the
   Chrome case "a prepend moves a focused grid field to the next row as the same
   element, still focused".
5. **Dispose is total** — after unmount, signal writes reach zero effects
   (`tests/core/dispose.test.ms`).
6. **A Host adapter matches mock-host semantics op for op** — e.g.
   `insertBefore` detaches first (DOM move semantics). `mockHost()` is the
   reference implementation of the contract. The DOM host moves a node that is
   already in the document with `moveBefore` where the browser has it, so a
   moved element keeps its focus.

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
(optional: `x?: Accessor<T> | null`). `children` and every prop declared with another
type (handlers, `ref`, render callbacks) stay raw. At the call site the macro wraps every value prop — expressions
AND literals — as `accessor(() => expr)`, so the field type matches nominally and
a signal expression can never land as a snapshot. Inside the component a read of
`props.x`, or of `x` after `function C({ x }: Props)`, is an accessor read and
goes through `valueOf` where a value is needed (§Accessor). A value already typed
`Accessor<T>` (`label={props.label}`, `class={count}`) crosses raw, so a prop passed
down never nests as `Accessor<Accessor<T>>`. Negative probe: `probe/thunkProps3.ms` S1.

**Landed 2026-09-12 (phase 4.1); lowered by declared type since 2026-10-05.**
`componentCall` (macros/ui/element.ms) reads the called component's props type
through `bindSym` + `getType` and emits `accessor(() => v)` exactly when the field
is `Accessor<T>` (or `Accessor<T> | null`) and the value is not already an
`Accessor`; every other prop crosses as written, whatever its name or shape, so
`renderItem={row}` and `onEndReachedThreshold={1}` both land on their declared types.
An undeclared prop, a field mixing `Accessor` with a non-null type, or a tag that
names nothing in scope is a macro error (`tests/macros/run.sh`). `For` `each`,
`Repeat` `count`, `Show` `when` and `FlatList` `data` are `Accessor<…>` too, so a hand-written
call passes a signal (`each: items`) or `accessor(() => expr)`. `View`/`Text`/`Pressable`/`TextInput` declare `style?: Accessor<Style>
| null`, `class?: Accessor<string> | null`, `delayLongPress?: Accessor<number> |
null`, `value?: Accessor<string> | null`; `Context.provider` (the tag `<Ctx value=…>`) takes `value:
Accessor<T>` and reads it once when it mounts. An object-literal prop is
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
- `src/render/hydrate.ms` — `hydrate`: claims a served page, after the lazy modules it lists
- `src/render/lazy.ms` — `lazyModule` and the module registry `hydrate` preloads
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
