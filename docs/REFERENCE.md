# REFERENCE — where Neon departs from Solid and React on purpose

Neon's base is Solid 2.0 (`~/projects/solid-next` at `84dada77`): reactivity, control flow, async,
stores and rendering take Solid's mechanism as it is. The component and event surface is React
Native's (`~/projects/react-native` at `693e9628e8c`; React `~/projects/react` at `71f7255`). This
file answers "does Neon do what Solid does here, and if not, why?", one entry per departure. The
mechanism itself is read in the reference and in our source at the pointers.

**When an entry is written.** Neon departs only where its way is better or fits MetaScript better
(C has no GC and no `Proxy`; the checker can refuse at compile time what Solid warns about at run
time), and the entry is written after the person approves the departure, because every later
session reads an entry as permission. Emitted code that differs while every program keeps its
result is not a departure and gets no entry. A difference nobody chose is a bug, for `BUGS.md` or
a compiler card.

**How to look up.** `grep -n '^### ' docs/REFERENCE.md` lists the entries; a source comment cites
one by ID (`REFERENCE RD-2`). IDs are permanent: a new entry takes the next free number of its
section, an entry whose verdict changes keeps its ID, a removed entry leaves its number unused.

**Entry fields.** Verdict · Solid / React / RN / R3F (file:line and symbol, at the commits above) · MS
(symbol and path) · Why · Don't (a wrong turn already taken) · Pin (tests that go red) · Checked
(date; read or measured).

**Verdicts.** `DIVERGE-INTENTIONAL`: Neon has its own mechanism or surface where Solid has one.
`FOLLOWS-RN`: Solid's surface is replaced by React Native's. `FOLLOWS-R3F`: inside a Void area, where Solid
and React Native have no 3D surface, Neon takes React Three Fiber's (`~/projects/react-three-fiber`
at `d604b18`); an entry there names it in an **R3F** field.

| Section | IDs | Scope |
|---|---|---|
| Surface | SF-* | tags, events, refs: what React Native decides |
| Props | PR-* | the props object, spread, children |
| Reactivity | SR-* | signals, reads, errors |
| Render | RD-* | JSX lowering, refs, hosts, hydration |

## Surface

### SF-1 · The component and event vocabulary is React Native's

- **Verdict:** FOLLOWS-RN
- **Solid:** lowercase HTML tags and `onClick` (`packages/solid/CHEATSHEET.md:463`)
- **RN:** `TextInput` `onChangeText?: (text: string)` (`packages/react-native/Libraries/Components/TextInput/TextInput.flow.js:823`); `Pressable` `onPress`
- **MS:** `View`, `Text`, `TextInput`, `Pressable` in `src/components/primitives.ms`; each host maps the universal tag in its own `createElement` (the DOM through `htmlTagFor`, `src/render/node.ms`)
- **Why:** Neon is mobile-first and renders to hosts that have no HTML, so one vocabulary has to mean the same thing on every host (the person, 2026-09-03).
- **Checked:** 2026-10-16, read.

### SF-2 · Refs run innermost first, as in React

- **Verdict:** FOLLOWS-RN
- **Solid:** a ref runs after the element's attributes and before its children (dom-expressions `dom-next`, `packages/babel-plugin-jsx/src/dom/element.ts`, the `ref` branch of the attribute loop)
- **React:** `commitAttachRef` (`packages/react-reconciler/src/ReactFiberCommitEffects.js:756`), in the commit's layout pass, a child's ref before its parent's
- **MS:** `setupRefCall` in `src/macros/ui/element.ms`
- **Why:** `ref` belongs to the component and event surface.
- **Checked:** 2026-10-16: `commitAttachRef` located; the Solid order and React's traversal order are carried over from `docs/SOLID.md`, not re-read.

### SF-3 · `fontFamily` is a CSS family list, not one family name

- **Verdict:** DIVERGE-INTENTIONAL
- **RN:** one family name, looked up whole (`packages/react-native/React/Views/RCTFont.mm:166` `fontNamesForFamilyName`); fallback is left to the platform text stack
- **MS:** `familyFont` in `src/platform/void/host.ms` splits the list into void2d `Font.family` and `Font.fallbacks`; the DOM host passes the string to CSS unchanged; the native hosts refuse a list by name
- **Why:** the Void host owns its text stack, so the author needs a way to name fallback families, as CSS `font-family`, Flutter `fontFamilyFallback` (`packages/flutter/lib/src/painting/text_style.dart:396`) and GPUI `font_fallbacks` do. The CSS spelling gives the same string the same meaning on the DOM host. The person approved it on 2026-10-18.
- **Don't:** add a second prop for the fallbacks, or resolve system fonts in Neon. Discovery belongs to void2d's platform layer (`~/metascript/.inbox/void/2026-10-18-system-font-fallback.md`).
- **Pin:** `tests/platform/voidFont.test.ms`
- **Checked:** 2026-10-18, read.

### SF-4 · Solid's `Switch`/`Match` is `<Match fallback>` with `<Case when>` branches

- **Verdict:** DIVERGE-INTENTIONAL
- **Solid:** `<Switch fallback>` holds `<Match when>` branches and reads them back from `props.children` as an array (`packages/solid/src/client/flow.ts:273-341`; server `packages/solid/src/server/flow.ts:172-266`)
- **RN:** `Switch` is the toggle control (`packages/react-native/Libraries/Components/Switch/Switch.js`)
- **MS:** `matchCall` in `src/macros/ui/element.ms` lowers `<Match>` to one `Match({ cases, fallback })` call; `Match`, `Case`, `CaseKeyed`, `CaseWith`, `CaseKeyedWith` in `src/macros/ui/flow.ms`
- **Why:** React Native's `Switch` keeps its name (SF-1), so Solid's pair moves down one name (the person, 2026-10-16). `children` is one `NeonNode` (PR-1) and cannot be read back as a list, so the element macro collects the branches at compile time, refuses a `<Case>` outside `<Match>` and a `<Match when>`, and the selection keeps Solid's chain: a later `when` is not read once an earlier one wins, and a branch mounts again only when the selected index changes, or with `keyed` when the value does.
- **Don't:** collect the branches at run time; a stray `<Case>` would then fail only when it renders.
- **Pin:** `tests/render/match.test.ms`, `tests/render/matchServer.test.ms`, `tests/browser/match.test.ms`, the `Match`/`Case` programs in `tests/macros/`
- **Checked:** 2026-10-16, read and measured on C, JS, the server build and Chrome.

## Props

### PR-1 · `children` is one `NeonNode`; no `children()` helper

- **Verdict:** DIVERGE-INTENTIONAL
- **Solid:** `children()` resolves the children into a node list a component can inspect (`packages/solid/src/client/core.ts:181`)
- **MS:** `NeonNode` in `src/render/hostTypes.ms`
- **Why:** JSX lowers to one mount function `(host, parent, before)`, so a child list is never materialized and there is nothing to inspect or rewrite (one-NeonNode arc, 2026-09-19).
- **Don't:** bring back `children()`, React's `Children.map` or `cloneElement`; they are the only things that arc gave up, and it gave them up on purpose.
- **Checked:** 2026-10-16, read.

### PR-2 · No `merge` / `omit`: `{...props}` is expanded at compile time by type

- **Verdict:** DIVERGE-INTENTIONAL
- **Solid:** `merge` and `omit` (`packages/signals/src/store/utils.ts:976`, `:1119`), the 2.0 names of 1.x `mergeProps` / `splitProps`
- **MS:** the spread branch of `src/macros/ui/element.ms`. Fields apply left to right and the later one wins; `null` removes the attribute; `style` in a spread replaces the style; explicit JSX children win over a `children` field; an `Accessor` field stays reactive.
- **Why:** Solid needs `merge` and `omit` because props are getter objects whose getters must survive a copy. Neon's props are plain objects whose reactive fields are `Accessor<T>` values, so a copy keeps them reactive, and the compiler knows every field statically.
- **Pin:** `tests/render/spread.test.ms`, `tests/render/spreadServer.test.ms`
- **Checked:** 2026-10-16, read.

### PR-3 · Destructured props stay reactive; a destructuring default fires on `null`

- **Verdict:** DIVERGE-INTENTIONAL
- **Solid:** props are getter objects, so destructuring reads each getter once and the binding stops tracking
- **MS:** reactive fields are `Accessor<T>` values, so destructuring copies the accessor. MetaScript has one absent value, `null`, so a default in a destructuring pattern fires on `null` and on a missing field, and not on `""`, `0` or `false` (recompiler `docs/LANG.md`).
- **Why:** destructuring is plain TS; keeping it working is what the TS surface promises (the person, 2026-09-05 and 2026-09-10).
- **Pin:** `tests/render/component.test.ms` "a destructured props parameter reads bare and stays reactive"
- **Checked:** 2026-10-16, read.

## Reactivity

### SR-1 · An accessor is read without a call where its value is asked for

- **Verdict:** DIVERGE-INTENTIONAL
- **Solid:** a signal is always read by calling it, `count()`
- **MS:** `valueOf` on `Accessor<T>` in `src/core/signal.ms`; the checker applies the `valueOf` protocol where a bare read would not type, so `const [x] = createSignal(2); x * 2` is `4` (`docs/ROADMAP.md` row 3; recompiler `docs/PROTOCOLS.md`)
- **Why:** the compiler sees the type, so it inserts the call Solid has to teach.
- **Pin:** none found by grep under `tests/core/`.
- **Checked:** 2026-10-16, read.

### SR-2 · A boundary always receives an `Error`

- **Verdict:** DIVERGE-INTENTIONAL
- **Solid:** `ErrorAccessor = Accessor<unknown>` (`packages/solid/src/client/flow.ts:19`)
- **MS:** a thrown string arrives as an `Error` carrying it; throwing any other non-`Error` value is a compile error (recompiler `1debbcc8`)
- **Why:** the boundary sees the same object on C and on `--target=js`, and a fallback does not have to narrow `unknown`.
- **Pin:** `tests/render/errorBoundary.test.ms`
- **Checked:** 2026-10-16, read.

### SR-3 · `onCleanup` without an owner throws

- **Verdict:** DIVERGE-INTENTIONAL
- **Solid:** `onCleanup` with no owner emits the dev-only `NO_OWNER_CLEANUP` warning and returns; production is a silent no-op (`packages/signals/src/signals.ts:90-100`; `core/owner.ts:305-311` `cleanup` returns when there is no context; `documentation/solid-2.0/08-dev-diagnostics.md:949`)
- **MS:** `onCleanup` in `src/core/cleanup.ms` throws "onCleanup called outside a reactive context will never be run" in every build. Host code that may run without an owner checks `getOwner()` before it registers, because there the work has no lifetime to end (`keep` in `src/platform/browser/dom.jms`, as Solid's `addEventListener` registers nothing, `packages/web/src/client.ts:950-980`).
- **Why:** a cleanup that never runs is a resource leak no build reports; Neon fails loud at the call (the person, 2026-10-16: keep the throw unless the call is not really an error).
- **Pin:** `tests/core/owner.test.ms` (the two "outside a reactive context" cells), `tests/browser/dom.test.ms` "listeners added with no owner attach and are released by the host"
- **Checked:** 2026-10-16, read.

### SR-4 · A plain value read directly in a component body throws in a debug build

- **Verdict:** DIVERGE-INTENTIONAL
- **Solid:** a component body runs under `untrack(fn, "<Name>")` (`packages/solid/src/client/core.ts:241-290`). A read there of a pending async value throws `[PENDING_ASYNC_UNTRACKED_READ]` (`packages/signals/src/core/dev.ts:857-872`), and a read of any other reactive value only warns `[STRICT_READ_UNTRACKED]` (`core.ts:1809`, `dev.ts:874-896`). Both are dev-only.
- **MS:** `assertTrackedRead` in `src/core/runtime.ms` throws both, inside `when (debug)`; `untrack(fn, label)` in `src/core/signal.ms` sets the label and `createComponent` (`src/render/component.ms`) runs the body under "a component body". A release build carries neither check.
- **Why:** a read that never updates is a bug the page shows only later, so a debug build fails at the read (the person, 2026-10-16, on SR-3's rule: keep the throw unless the call is not really an error; and on these checks: "nếu nó hữu ích thì giữ trong debug, xóa ở prod"). A one-time read is written `untrack(() => …)`.
- **Pin:** `tests/core/strictRead.test.ms` (debug and `--release`, C and JS)
- **Checked:** 2026-10-17, read; measured on C and JS.

## Render

### RD-1 · A ref array is composed at compile time, and only a literal one

- **Verdict:** DIVERGE-INTENTIONAL
- **Solid:** `applyRef` flattens an array at run time (`packages/universal/src/universal.ts:563-564`)
- **MS:** `composeRefs` (`src/render/bind.ms`), emitted by `src/macros/ui/element.ms`. Nested arrays and `null` entries flatten away; an empty array is an error; an array held in a variable is a type error.
- **Why:** the compiler sees the literal, so a component receives one function.
- **Pin:** `tests/render/ref.test.ms`
- **Checked:** 2026-10-16, read.

### RD-2 · A ref's apply phase runs under the mounting owner

- **Verdict:** DIVERGE-INTENTIONAL
- **Solid:** `runWithOwner(null, () => applyRef(resolved, element))` (`packages/universal/src/universal.ts:569`)
- **MS:** `setupRef` and `applyRef` in `src/render/bind.ms`
- **Why:** the in-tree `StatusBar` and `WebView` refs register work under that owner, so it is cleaned up with the component.
- **Pin:** `tests/render/ref.test.ms`
- **Checked:** 2026-10-16, read.

### RD-3 · `<Void ref>` receives a `VoidAreaHandle`, not a node

- **Verdict:** DIVERGE-INTENTIONAL
- **Solid:** a ref receives the element
- **MS:** `src/render/voidAreaHandle.ms`; `docs/VISION.md`
- **Why:** a Void area is a GPU scene, not a host node; the handle is what an author can act on.
- **Checked:** 2026-10-16, read.

### RD-4 · Hydration finds served nodes by position, not by `_hk` keys

- **Verdict:** DIVERGE-INTENTIONAL
- **Solid:** `getNextElement` and `gatherHydratable` (`packages/web/src/client.ts`)
- **MS:** `src/render/claim.ms`, the `claim` capability of `Host`
- **Why:** `docs/RENDER-MODEL.md` "Hydration". A Neon mount creates nodes in document order, so position finds every node a key would, without an attribute on every template root.
- **Pin:** `tests/render/hydrate.test.ms`, `tests/browser/hydrate.test.ms`
- **Checked:** 2026-10-16, read.

### RD-5 · A boundary parks its content in a holder it owns, and `Host.release` frees it

- **Verdict:** DIVERGE-INTENTIONAL
- **Solid:** the boundary's tree is a computed that holds the content as a heap value (`packages/signals/src/boundaries.ts:544`, `:550`); the output pass swaps between that value and the fallback (`:625`, `:657`) and the garbage collector frees what nothing holds.
- **MS:** `errorRows` and `loadingRows` in `src/macros/ui/flow.ms` mount the content once in a `Row` whose `keep` is a holder node the boundary creates and never attaches; `removeRow` moves a kept row's span into it and `Host.release(holder)` frees what is parked when the boundary is disposed, after the content's owner (`src/render/reconcile.ms`, `src/render/hostTypes.ms`).
- **Why:** C has no GC, so host nodes that nothing shows still need an owner and a free. The holder is that owner, and the content keeps its nodes and state through a fallback as it does in Solid. A tree that never finished mounting is freed, as Solid recomputes a tree that failed.
- **Pin:** `tests/render/erroredKeep.test.ms`, `tests/render/loading.test.ms`, `tests/render/keepRows.test.ms`, `tests/platform/voidPark.test.ms`
- **Checked:** 2026-10-16, read and measured on mock and void hosts.

### RD-6 · A region resolves its parent through its anchor

- **Verdict:** DIVERGE-INTENTIONAL
- **Solid:** the top level is a value with no parent: `render` inserts it into the container it was given (`packages/universal/src/universal.ts:591`) and `insert` closes over a fixed `parent` (`:134`).
- **MS:** `regionParent` in `src/render/claim.ms` asks `Host.parentOf(anchor)` at every update after the first, and `regionNode` (`src/render/node.ms`) and `listRegion` (`src/render/listRegion.ms`) reconcile into the answer.
- **Why:** a `NeonNode` pushes its nodes into a parent (PR-1), so a region that sits at the top of a parked row has the holder, not the page, as its parent when it next updates. The anchor is the one node that always sits where the rows go.
- **Pin:** `tests/render/keepRows.test.ms`
- **Checked:** 2026-10-16, read and measured on the mock host.

### RD-7 · A server async value travels as a typed JSON string, not as seroval

- **Verdict:** DIVERGE-INTENTIONAL
- **Solid:** the server serializes each async value with seroval into the `_$HY.r` global, keyed by owner id (`packages/web/serialization/src/serializer.ts:144, 182-209`), and the client evaluates the JS that seroval wrote.
- **MS:** `renderToStream` (`src/render/ssr.ms`) writes `<script>(self._$HY||(self._$HY={r:{},e:{},m:{}})).r["<id>"]="<json>"</script>`, where `<json>` is `JSON.stringify<T>` derived from the memo's `T` at compile time and escaped by `scriptLiteral` (`src/render/hydrationRecords.ms`). A rejected memo writes its sanitized message into `.e["<id>"]`. The client decodes with `JSON.parse<T>` (`src/render/hydrateMemo.ms`), and a decode failure names the id and the decoder's error.
- **Why:** seroval walks a value by reflection, which C does not have. A typed JSON codec gives the same bytes on C and JS. A `T` that JSON cannot encode is refused at compile time, not when the page is served. Rejections get their own `.e` map because the JSON codec refuses a generic value-or-error wrapper.
- **Pin:** `tests/render/renderToStreamServer.test.ms` (record bytes and escaping), `tests/browser/hydrateAsync.test.ms` (hydrate reads the record, zero requests)
- **Checked:** 2026-10-16, read and measured on C, JS and Chrome.

### RD-8 · The tracking run of an adopted value is a real run on C

- **Verdict:** DIVERGE-INTENTIONAL
- **Solid:** a hydrating compute that adopts a serialized value runs once to record its dependencies, with the global `fetch` and `Promise` swapped for fakes that never settle, and its result is discarded (`packages/solid/src/client/hydration.ts:491-525` `subFetch`; RFC `documentation/solid-2.0/05-async-data.md` "The tracking run").
- **MS:** `traceRun` (`src/render/traceRun.ms`) swaps `fetch` and `Promise` on JS, as Solid does. On C it runs the compute and discards the result.
- **Why:** C has no global `fetch` to swap. Solid's run already leaks a request after a non-fake `await` (the RFC's documented limit), and on C every adopted compute behaves like that case. What the page shows is the same on both backends; only the discarded request differs.
- **Pin:** `tests/render/hydrateAsync.test.ms` (zero requests on JS, one discarded run on C)
- **Checked:** 2026-10-16, measured on C and JS.

### RD-9 · A 3D pointer event reaches the nearest hit, not every intersection

- **Verdict:** FOLLOWS-RN
- **R3F:** `intersect` lists every object the ray hits, nearest first, with each hit's handler-bearing ancestors as entries of their own (`packages/fiber/src/core/events.ts:205-277`), and `handleIntersects` calls the handler of every entry until `stopPropagation` (`:281-393`); `stopPropagation` also stops delivery to farther objects (`:355-375`). The docs state it: "The `intersections` array in the event includes all objects intersecting the ray, not just the nearest" (`docs/API/events.mdx:61-64`).
- **RN:** one topmost target, found by walking children from the top of the z-order: Android `findTouchTargetView` (`packages/react-native/ReactAndroid/src/main/java/com/facebook/react/uimanager/TouchTargetHelper.kt:219`), iOS `hitTest:withEvent:` over `reverseObjectEnumerator` (`packages/react-native/React/Views/RCTView.m:200`). Babylon's `scene.pick` agrees: it keeps the closest hit (`~/projects/_babylon/Babylon.js` `449e8a7`, `packages/dev/core/src/Culling/ray.core.ts:851`).
- **MS:** the 2D half is built: the Void host presses only the topmost pressable under the pointer and bubbles through its ancestors until `stopPropagation` (`src/render/event.ms` `stopPropagation`, `src/platform/void/host.ms`), and gives what no 2D handler takes to the area's layers, top paint order first, through `AreaLayer.hit` (`src/render/voidAreaHandle.ms`). The 3D half follows the same rule on that hook (`src/components/scene3d/pointer.ms`): Void's `rayFromScreen` and `pickNearestOn` find the nearest hit, `pointerdown` walks its 3D ancestors until `stopPropagation`, only the innermost node with a press handler presses, the pressed node captures the pointer until release, and `Scene3D onPressMissed` hears a still click that hits nothing. A scene with no pointer handler never picks.
- **Why:** one target per press is what a View inside the same area already gets, so 2D and 3D handlers see one rule; what lies behind the nearest hit is occluded on screen, and an author who wants it asks Void for the ray's hits.
- **Don't:** deliver to farther objects and expect `stopPropagation` to undo it, as R3F does; a handler behind the hit would then run before the nearer one can stop it.
- **Pin:** 2D: `tests/platform/voidPointer.test.ms` ("a pressable drawn over another takes the press alone", "stopPropagation stops a pointer event at the node that calls it", "a layer hears what no 2D handler takes, top layer first"), `tests/render/scene2dEvents.test.ms`. 3D: `tests/render/scene3dPointer.test.ms` (nesting cases mirror `scene2dEvents.test.ms` "a gesture around a plain press"), `tests/device/scene3dPointer.ms` (mesh, HUD View on top, miss, through the real window host).
- **Checked:** 2026-10-22, read; decided under the person's delegation for the void-endgame arc (decision D2).

### RD-10 · `<Node id>` attaches a node it does not own

- **Verdict:** FOLLOWS-R3F
- **R3F:** `<primitive object>` places an existing object and never disposes it: "Primitives will not dispose of the object they carry on unmount" (`docs/API/objects.mdx:166`); `removeChild` skips dispose for `type === 'primitive'` (`packages/fiber/src/core/reconciler.tsx:347`, `:417`).
- **MS:** `Node` in `src/components/scene3d/node.ms`, exported beside `useScene3D()` and `useSceneNode()`: it places an existing `NodeId3D` under the current scene parent, binds `NodeProps` onto it and refuses a changed `id`. On unmount it frees only what Neon mounted under it and gives the node back under its former parent before its former next sibling; when that parent is gone it parks the node in a hidden, detached group of the scene, because Void exports no detach (`.inbox/void/2026-10-22-export-detach-for-3d-nodes.md`). It never calls `remove`.
- **Why:** a node made outside Neon belongs to whoever made it; disposing it on unmount would free what the caller still holds. This is R3F's rule, not a departure from it; the entry exists because every other Scene3D component owns and removes its node (`src/components/scene3d/core.ms` `ownNode`).
- **Don't:** expect an unmounted `<Node>` to free its node; the caller closes it.
- **Pin:** `tests/render/scene3dHost.test.ms` ("Node places an app-made node, mounts its children under it, and gives it back without freeing it")
- **Checked:** 2026-10-22, read; decided under the person's delegation for the void-endgame arc (decision D5).

### RD-11 · Scene3D's default tone curve is Linear without `hdr`, Filmic with it

- **Verdict:** DIVERGE-INTENTIONAL
- **R3F:** `gl.toneMapping` is `ACESFilmicToneMapping` unless the Canvas is `flat` (`packages/fiber/src/core/configuration.ts:308`), with or without an HDR target.
- **MS:** `Scene3D` in `src/components/scene3d/scene.ms` leaves Void's default `ToneMode.Linear` (`void/src/void3d/renderer.ms` `Renderer`, after Heaps `h3d.scene.pbr.Renderer`) on an LDR scene and sets `ToneMode.Filmic`, Void's ACES fit (`void/src/void3d/toneMap.ms` `filmic`), when `hdr` is on. `toneMapping` overrides either default; LDR scene programs apply the chosen curve too (`void/src/void3d/shader3d.ms` `toneMapped`).
- **Why:** an LDR scene holds colours in [0,1], and Linear shows them as authored at exposure 1; the ACES fit maps 1.0 to about 0.80, so every authored white would dim. With `hdr` the scene holds values above 1 that need a curve, and there Neon takes R3F's ACES default.
- **Don't:** expect R3F's look from an LDR Scene3D without setting `toneMapping={ToneMode.Filmic}`.
- **Pin:** `tests/render/scene3dLook.test.ms` ("an LDR Scene3D keeps Void's linear curve at exposure 1 and reserves no tone map", "hdr reserves the tone map at mount, defaults to the ACES curve and refuses a change")
- **Checked:** 2026-10-22, read; decided under the person's delegation for the void-endgame arc (decision D8).

### RD-12 · A page that differs from the tree throws in a debug build and is rebuilt in a release build

- **Verdict:** DIVERGE-INTENTIONAL
- **Solid:** dom-expressions throws `Hydration Mismatch` in development only; in production `getNextElement` creates the one node whose `_hk` key it did not find and hydration goes on (`~/projects/dom-expressions` at `27a88be`, `packages/dom-expressions/src/client.js:277-283`).
- **React:** the cursor is positional, as Neon's; a mismatch throws `HydrationMismatchException` and queues an error saying "this tree will be regenerated on the client" (`packages/react-reconciler/src/ReactFiberHydrationContext.js:388-415`), reported through `onRecoverableError` (default `reportGlobalError`, `ReactFiberErrorLogger.js:123`). Svelte does the same for a whole root: `hydrate` catches, clears the target and mounts (`~/projects/svelte` at `6eb720a`, `packages/svelte/src/internal/client/render.js:131-146`).
- **MS:** `refuse` in `src/render/claim.ms` throws the message in a debug build. In a release build it records the first message on the claim and turns every later host op into a plain create or insert; `hydrate` (`src/render/hydrate.ms`) then disposes that tree, removes the container's children, mounts the tree again with `render` while the claim still serves the page's records, and logs the message with `console.error`. A page that matches pays one `null` check.
- **Why:** a claim finds a node by position, not by key, so after the first difference nothing says which served node belongs to which later tree node; only the whole root can be rebuilt, as React rebuilds. The claim never throws in a release build, because a throw from inside a region happens during a flush and halts reactivity, which a release build never revives.
- **Pin:** `tests/render/hydrateRefusal.test.ms` (debug and `--release`, C and JS: a missing node at the top level and in a region, extra children in an element, in a region's element and in the container, a record kept through the rebuild)
- **Checked:** 2026-10-24, read; measured on C and JS.

### RD-13 · `getRequestEvent` reads only the render's owner, and the event is `{ request: { url, headers } }`

- **Verdict:** DIVERGE-INTENTIONAL
- **Solid:** `getRequestEvent` reads the AsyncLocalStorage store that `provideRequestEvent` fills, and only when that store is empty falls back to the caller's render context found through its owner (`~/projects/solid-next` at `84dada77`, `packages/web/src/server.ts:6448-6470`, `renderContextOf` :6662). The event is `{ request: Request; locals }` (`client.ts:120`), `undefined` outside a request.
- **MS:** `serve` (`src/render/serve.ms`) sets the event on the served render's root owner with `setContext`; `getRequestEvent()` reads it through the owner and is `null` outside a request and on the client. `RequestEvent { request: { url, headers } }`, `headers.get(name)` by any case of the name.
- **Why:** C has no AsyncLocalStorage, so the owner path is the only one both targets have; one record type works on both targets, and C has no Fetch `Request`.
- **Don't:** keep a module-global current request: two requests in one workerd isolate would read each other's.
- **Pin:** `tests/render/serveServer.test.ms`
- **Checked:** 2026-10-24, measured on C and JS; decided under the person's delegation ("tự trả lời").
