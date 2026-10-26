# Navigation model anchor

The person approved this direction in the `rn-navigation-prod` discussion:
**Decompose-style navigation primitives and composition; Solid Router / TanStack
routing contracts; Solid reactivity underneath.** On 2026-10-15 the person approved
the layered design below ("chốt hướng này", "ghi vào document chính thức và implement
nó"), against the goal they set: an author-facing interface "dễ hiểu bằng hoặc hơn"
Next.js and Expo Router, with navigation, rendering and routing "độc lập, composable"
underneath, shorthands on top, and any odd pattern still composable from the
primitives. Reference-backed provisional choices are recorded here and in
`WORKAROUND.md`.

## Reference ownership

- **Decompose** (`~/projects/Decompose` `f48655a`): renderer-independent destination
  identity, child lifecycle, the navigation models (`router/children`, `stack`,
  `pages`, `slot`, `panels`), the re-entrant navigation queue (`Relay.kt`) and the
  browser history contract (`router/webhistory/WebNavigation.kt`, its per-model
  implementations `StackWebNavigation.kt`, `PagesWebNavigation.kt`,
  `PanelsWebNavigation.kt`, and the diff onto browser history in
  `webMain/.../WebHistoryNavigation.kt` `enableWebHistory`). Do not transplant Android
  lifecycle statuses into Solid owners without tracing their meaning.
- **Solid Router** (`~/projects/solid-router` `d0379e7`): location integration
  separated from matching and rendering; matching and ranking (`src/utils.ts`
  `createMatcher`, `scoreRoute`, `expandOptionals`), nested route creation
  (`src/routing.ts` `createRoutes`, `createBranches`), the outlet kept per route key
  (`src/routers/components.tsx` `Routes`), and the author-facing names (`A`,
  `useParams`, `useNavigate`, `useLocation`, `useMatch`, `useSearchParams`).
- **TanStack Router** (`~/projects/tanstack-router` `6777b8b`): typed params
  (`router-core/src/router.ts` `params.parse`/`stringify`), search validation
  (`route.ts` `validateSearch`), an entry guard that runs before a match commits
  (`route.ts` `beforeLoad`), pathless routes by `id`, route masks that keep the real
  location in history state (`router.ts` `routeMasks`, `unmaskOnReload`), and the
  history and request/SSR contracts (`packages/history/src/index.ts`).
- **Expo Router** 58.0.16 (`~/projects/expo` `cb88164`, `packages/expo-router`): an
  `href` resolved against the live navigator tree
  (`src/global-state/resolveNavigationDestination.ts`), navigators not yet mounted
  seeded from the route tree (`createSeededNavigationState.ts`), params local to a
  mounted screen (`useLocalSearchParams`), a layout choosing its navigator
  (`useScreens.tsx`).
- **Next.js** (`~/projects/next.js` `648110d4`, `packages/next/src`): declaration
  errors for ambiguous routes (`build/validate-app-paths.ts`), segment identity that
  includes the dynamic value and excludes search
  (`client/components/router-reducer/create-router-cache-key.ts`, `layout-router.tsx`),
  an explicit remount point (`template`).
- **React Navigation 7:** convenient navigator surface and mobile conventions,
  not the core model. Reference codecs: `getStateFromPath` and `getPathFromState`
  in [core 7.23.0](https://unpkg.com/@react-navigation/core@7.23.0/src/).
- **Unreal CommonUI:** supplementary reference for activation, focus and input
  in game UI; not a replacement navigation core.

## Fixed boundaries

Navigation must not require one universal stack or an application-wide screen
hierarchy. Built-in patterns and user compositions participate in one routing
world through a common contract. `src/navigation/routing.ms` `RoutingRegistry`
and `bindRoute` hold the provisional registration protocol; custom compositions
must not require a central switch on navigator kinds.

Routing identifies destinations and validates their arguments. Composition
chooses how they become active or visible. Routing must work before UI mount for
request URLs and SSR; route registration cannot depend solely on rendering
`Screen` children.

URL-addressable state, restorable navigation snapshots and navigation history
are distinct contracts. Encoding a URL does not promise to serialize every
retained screen, local UI value or resource. Multiple active regions require
explicit scope and address ownership, not silent query-key overwrites.

World/level loading, GPU resources and simulation lifecycle belong to Void or
the game runtime. UI activation does not implicitly pause or unload a world.

## Layers

Three layers and one binding. Each layer is usable without the others; only the
binding knows two of them. The import rule is checked by `tests/navigation/layers.sh`:
a routing file imports only `src/core` and routing files, a navigation model only
`src/core` and other models, a renderer no routing file.

**Routing (addresses)** owns patterns, matching and ranking, typed params and search,
entry guards, redirects and not-found decided before mount and on a server, `href`
building, static paths, histories and sessions. It never knows a navigation model, a
component or `src/render`.

- A route is a value with a relative pattern, an optional params codec, an optional
  guard and a status; patterns join down the tree (Solid `joinPaths`), and a route with
  no pattern groups its children without adding a segment (TanStack pathless `id`,
  Expo `(group)`). A typed route closes over its codec and exposes an untyped node to
  the tree, as `bindRoute` does, so one tree holds routes of different param types.
- Matching ports Solid `createMatcher`, `scoreRoute` and `expandOptionals`
  (`src/navigation/routeMatcher.ms`); `createRouteTree` in `src/navigation/route.ms`
  breaks a score tie by Next's segment order (static before param before splat, then
  shorter) and then by declaration. Param values are decoded, as Next does; Solid
  leaves them encoded.
- A codec that fails to decode makes its route not match, and ranking continues
  (Solid `matchFilters`), so `/users/:id` with an integer codec and `/users/:slug`
  coexist.
- Building a tree throws, naming both routes, for a route that can never match, param
  names that differ only by symbols or repeat down one chain, and a splat that is not
  last (Next `validate-app-paths.ts`). Next refuses two routes of one shape because
  they "cannot be distinguished from each other when matching URLs"; with codecs they
  can, so the error fires when every level of the earlier-ranked route accepts any
  value, and two splats at one level are that case. A Solid splat `*name` also matches
  no segment, so Next's required and optional splats are one kind here. These are
  author errors at the declaration, not runtime input.
- A guard runs before a match commits, on the server as on the client (TanStack
  `beforeLoad` timing). It returns a decision (continue, redirect, not found) instead
  of throwing, as the rest of Neon routing returns `Result`; a request history turns
  a redirect into 3xx and not-found into 404. Not found makes the route not match and
  ranking continues, as a codec failure does, so a catch-all route with status 404
  renders it (Next renders the nearest `not-found`).

**Navigation (presence)** owns which destinations are present and active, their order
and history, retention and lifecycle, generic over a configuration with a key. It
never knows a URL, a pattern or a component.

- Models over `createChildren`: `createChildStack`, `createChildPages`,
  `createChildSlot` (one optional child: dialog, sheet, modal) and
  `createChildPanels` (main, details, extra; single, dual or triple mode), as in
  Decompose.
- Identity is the configuration key. A routed destination's default key is its route
  and path params, not its search (Next segment key `name|value|type`; Decompose
  configuration equality): a new path param makes a new instance, so local state of
  one item never shows in another; an author keeps one instance across params with a
  `key` that omits them.
- Every model publishes its history as Decompose `WebNavigation` does: items of key,
  address part and nested child (the last is active), `navigate(keys)` to apply a
  traversal, and `onBeforeNavigate()` to refuse one. Defaults are Decompose's: every
  stack entry is a history entry; pages expose only the selected page and replace;
  panels follow `PanelsWebNavigation`. Pages take `visited`, the pages a back walks
  before the selected one, and map a path, parameters and child per page, where
  Decompose maps the whole `ChildPages`, because each visited page is its own item.
  The adapters are in
  `src/navigation/webNavigation.ms`; `webNavigationNode` erases a typed one to string
  keys, as `bindRoute` erases a codec, and decodes every key before applying any,
  where Decompose's binding can throw after applying a parent level.
- A navigation requested while one applies is queued (`Relay.kt`).

**Rendering (presentation)** draws a model: outlet, stack with motion, header and
gestures, pages with a tab bar, drawer, panels laid out by width, modal presentation.
A renderer takes a model and a `render(child)` function; input events call model
operations: edge swipe and hardware back today. A desktop app wires back itself, as
Decompose's Compose for Desktop recipe does (`docs/component/back-button.md:123-160`,
`f48655a`): a focusable root `View` takes `onKeyUp` and calls `dispatchHardwareBackPress()` on
`e.code === "Escape"`, and a focused `TextInput` that calls `e.stopPropagation()` on Escape keeps
the screen, because key events bubble from the focused node. The framework maps no key by default;
`examples/navigation/desktop.ms` is the recipe and `tests/platform/voidDesktopBack.test.ms` pins it.
The mouse back button is not wired. It never imports routing. `navigatorMotion.ms` stays the transition engine.
`renderPanels` lays panels out as Decompose's `HorizontalChildPanelsLayout`: one at a
time in single mode, main beside details or extra in dual, three columns in triple,
with weights and placeholders for an empty panel. The app picks the mode from its
width and calls `setMode`, as Decompose's `ChildPanelsModeChangedEffect` example does;
a mode change keeps every instance and writes no history, and choosing a detail
replaces the panels' one entry (`PanelsWebNavigation`).
`renderStack` takes an optional test for transparent children, as Expo's web
`NativeStackView` treats `transparentModal`: a transparent child fills the stack over
the ones below, which stay shown down to the first opaque child.

**Binding** is the only module that imports two layers.

- Cold resolution: an address without a snapshot is matched and every level's model
  is seeded from the match (Expo `createSeededNavigationState`). A stack may name an
  `initial` route placed below a cold-opened destination; it applies to cold
  resolution only, because in-app navigation already has a real history.
- In-app `navigate(href)` and `<A>`: match the href, walk the live models from the
  root while each level's active destination equals the matched one, and apply the
  first differing level's operation: select a page, activate a slot, and on a stack
  what Expo's default `NAVIGATE` does (Expo `resolveNavigationDestination`; its
  `StackRouter.tsx` `NAVIGATE` branch): update the top in place when it is the same
  route, otherwise push. Popping back to an earlier entry is `dismissTo`, an explicit
  call, so a link to a tab's root from deep in its stack pushes that root again.
- History: the binding diffs the models' published items onto the routing session as
  Decompose `enableWebHistory` does, so browser back walks what the models' own back
  walks. A change rewrites from the first item whose key differs: same keys replace the
  URL, more keys push, fewer keys go back by the count (and replace when the browser has
  fewer entries), and otherwise the browser goes back to the first changed entry,
  replaces it and pushes the rest. The URL joins the active branch's parts top to bottom, each
  part encoded by that level's route. The entry state carries the tree of keys in the
  `__neonRouting` slot that `src/platform/browser/routingHistory.ms` already writes.
- Traversal asks `onBeforeNavigate` down the active branch, returns the browser to
  where it was on a refusal, and otherwise applies the stored keys level by level
  with mirroring suppressed. An entry without usable state resolves from its address.
- History and traversal are `src/navigation/webHistory.ms` `createWebHistory`, a
  participant like any other: register it, open the session, then `enable(session)`.
  Where it leaves `WebHistoryNavigation.kt`, and why:
  - The routing history stores the entry's index beside its state (`__neonIndex`,
    TanStack's shape), because one session entry carries every region; a refusal goes
    back by the session's tracked position, not by `baseIndexOffset`.
  - A traversal applies each level inside its own `flush`, so the next level reads its
    committed children. The mirror skips while a commit applies (Decompose's `isEnabled`)
    and also reads an epoch the commit bumps, because the registry's own drain runs after
    the flag is reset. A participant that adds work to a restore, as the router settles
    a redirected leaf, runs it inside the same suppressed commit (`suppressed`), since
    each level's flush has already drained before that work starts.
  - One render effect walks the active branch from the root, and a pop records its
    count when the level changes: a disposed child publishes `[]` and queued effects
    run last in first out, so a per-level effect would read disposed models.
  - A change rewrites from the first item whose key differs, and a nested change stays
    inside its active item's entries. Decompose rewrites from the browser's first
    entry, and a nested rewrite passes up only the child's entries (`subscribe`,
    `onRewrite`), so the entries of the items before the active one were lost: a tab
    switch at `/feed/1` under `/` dropped `/`, and `setParams` two entries deep dropped
    both below it. Pushes, pops and same-key changes write what Decompose writes. An
    entry before the change keeps the keys it was written with, as Expo's snapshots do.
  - Nested entries are built as push and rewrite build them. Decompose's `history()`
    adds every node of an item's history, which by reading lists an item twice at
    depth three; not run in Kotlin.
  - An entry without state resolves from its address, as this design says, and asks no
    `onBeforeNavigate`; Decompose ignores such an entry. `onBeforeNavigate` is asked on
    every restore, also one that changes only another region.
  - The key tree is stored as Decompose's `SerializableNode` list. There is no `schemaVersion` or
    `onRecreate`, where Decompose recreates on a version mismatch: state that cannot be
    used resolves from the entry's address, which the registry passes to each region's
    `restore`. A malformed tree resolves before anything applies; a nested key that
    does not decode is found only after its parent level applied, since its decoder
    belongs to the child those keys create, so the binding puts the previous keys back
    and resolves, inside the same suppressed commit. An entry whose whole snapshot, or whose router state,
    does not parse resolves from its address the same way. With no address for the
    region, a malformed tree reports `IncompleteSnapshot`. `onBeforeNavigate` is asked before the fallback.
- Reload restores the entry's structure (a TanStack mask with `unmaskOnReload:
  false`); a leaf route with `resolveOnReload: true` resolves from the address on a
  reload instead, which is Next's hard navigation and TanStack's `unmaskOnReload`.
  A reload is told apart as TanStack does (`tempLocationKey`): each router draws a
  random document key and writes it into its entries, so an entry with another key
  was written before the page loaded, while back and forward in the same page restore.
  A back from a reload that resolved from the address does not know the stack under it: the
  entries before the reload carry no structure Neon trusts, so a back onto a
  `resolveOnReload` entry resolves its address as a link does and pushes it over the
  reloaded page (`[post 2]` then back gives `[post 2, post 1]` at `/feed/1`). TanStack has
  no stack to rebuild (`router.ts:1519`, a location is rendered whole) and Expo
  navigates to the entry's path (`browserHistory.ts` `navigateToBrowserPath`), so neither
  settles whether such a back pops; this stays as is until the person decides.
- A stack retains every pushed page, so links that ping-pong grow it without bound
  (40 pushes keep 41 mounted). Expo Router and React Navigation do the same on the web:
  `NativeStackView.tsx:143` only sets `display: none` on a page that is not focused, and
  `StackRouter.tsx` `NAVIGATE` pushes a route without a `getId` match; it moves an
  existing route to the top only when `getId` (Expo `dangerouslySingular`) names the same
  id, and pops to it only for `pop: true`, which Expo's `navigate` does not send
  (`dismissTo` is the explicit pop). Neon matches this, with one difference: `NAVIGATE` to
  the same route name with other params updates the top in place there
  (`StackRouter.tsx` `route = currentRoute`), where Neon's key holds the params and pushes.
- A tab root linked while its stack is retained pushes that root as its own entry:
  the mirror compares the entries each item publishes, since an item that keeps its key
  but whose nested stack shrank to its root still changes the entries.
- Each rendered destination provides its own params to `useParams` (Expo local
  params); the whole address is `useLocation`. Multi-region apps keep
  `RoutingRegistry` scopes; a route tree is one participant.

## Shorthands

A route tree for the common case, compiled into the layers above:

```tsx
const thread = route(":id", { params: { parse: …, stringify: … } });

const routes = createRoutes([
  { path: "/", component: Home },
  { path: "/blog/:slug", component: Post },
  { layout: AppShell, navigator: Tabs, children: [
    { path: "/feed", component: Feed },
    { path: "/inbox", navigator: Stack, children: [
      { path: "", component: Inbox },
      { route: thread, component: Thread },
    ] },
  ] },
  { path: "*", status: 404, component: NotFound },
]);
```

`path` gives untyped routes whose params are strings; `route` gives typed ones.
Solid Router's names are kept where the meaning is the same. A component reads a typed
route's params with `useParams({ from: thread })`, TanStack's `from`, with the route value
standing where TanStack checks a registered id: the params come through that route's
codec, from the component's own route or an ancestor, and a route off the component's
path throws, as TanStack's strict `from` does. `router.navigate({ to: thread, params })`,
TanStack's `navigate({ to, params })`, writes them through the same codec, with `search`
and `replace` beside them; a route outside the router's tree throws. `useNavigate()`
keeps Solid's string form: the value it returns would need a generic function type
(`<P>(to: ToOptions<P>) => boolean`), which MetaScript does not parse.

A route entry takes `preload`, Solid Router's `RoutePreloadFunc`
(`~/projects/solid-router` `types.ts:77-84`, `routing.ts:696-705`): it is called with
`{ params, location, intent }` before the route's component is created, once per mounted
route and parent before child, so a search-only change does not run it again. A `route<P>`
entry's `preload` takes `P` through the codec, as `useParams({ from })` does, and a `path`
entry takes the string map. `intent` is `"initial"` for a route mounted at open or by a
server render, `"navigate"` for one a link, `useNavigate` or `router.navigate` opened,
`"native"` for one browser back, forward or `go` opened (`routing.ts:447-507`), and
`"preload"` for `router.preload(href)`, which runs the preloads along an address and mounts
nothing (`routing.ts:650-680`). A page a history move mounts again is preloaded again, as
Solid's remounted route is. A route's component receives `{ params, location, data }`, Solid's
`RouteSectionProps` (`types.ts:84-101`): `data` is what the same preload call returned, once per
mount (`routing.ts:690-720`, `createRouteContext`). `route<P>` takes a void preload; `route<P, D>`
takes one that returns `D`, and `componentOf(entry, (props: RouteSectionProps<P, D>) => ...)` gives
the component `params` as the typed `P` through the codec and `data` as `D`, so a preload that
returns a `query` promise hands it to `createAsync(() => props.data)` with no second fetch. A
`path` entry's component gets `params` as the string map and no readable `data`, because its
`preload` returns nothing. `children` stays on `LayoutProps`: Neon keeps a layout and a page
apart, where Solid's one component renders an outlet through `props.children`. `location` is the
address the route mounted with, not live; `useLocation()` is the live one. A generic instantiated
as `void` does not build on C (a class field of type `D`), so `route` has a void and a data
overload and a void preload keeps its place. `hrefOf` and `paramsOf` name `D` beside `P`.
`followPreloads(router.preload)`
in `src/platform/browser/routingHistory.ms` is `data/events.ts:83-146`: hover waits 20 ms and
does not repeat on the same link, focus and touch preload at once, and `preload="false"` on the
anchor skips it; `<A>` takes no `preload` prop, so that attribute is written on a plain `<a>`.

`src/navigation/router.ms` compiles the tree into one `RouteTree`, and `createRouter`
makes it one participant of scope `main`. A layout keeps its instance while the routes
under it change; a page is replaced when its matched path changes and kept when only
the search does, through an outlet keyed by route and path as Solid's `routeStates`
is. A leaf takes a component and a level with children a layout or nothing; anything
else throws at the declaration, as the tree's own errors do. Redirects are followed
before mount, at most 20, and the history entry ends on the last address, on a back or
forward as on a link (TanStack `followRedirect`, `load-client.ts`, replaces on any load). A path ending in `/` is redirected for good
(308) to the one without it, as Next's default `trailingSlash: false` does
(`load-custom-routes.ts`, the `/:path+/` redirect), so a page has one address on a
server, in static output and in the browser. A route in a Stack may name
`presentation: "transparentModal"` to show over the screen below it (Expo's
`presentation`); anywhere else the declaration throws. `Router.response()` gives a server the
first redirect's status and final location, or the route's status. The query of an address is decoded as
`URLSearchParams` does (Solid `extractSearchParams`, `utils.ts:50`): a malformed escape stays literal and an
invalid byte becomes U+FFFD, while a malformed escape in the path is `InvalidAddress` and a 400 (Next
`DecodeError`, `base-server.ts:1545`). A double slash inside a path matches no route (Solid `createMatcher`,
`utils.ts:73-76`, #567). A relative `navigate` target resolves as Solid's `resolvePath` does (`utils.ts:22`,
`routing.ts:572-605`): `?q` keeps the current path, and `useNavigate` joins the target onto the calling route's
path, while `router.navigate`, which has no route, joins it onto the root like Solid's base route; dot segments are
removed as the URL parser does for Solid. A redirect whose target has a scheme or starts with `//` leaves the app:
a server answers with that `Location` (Solid `data/response.ts:1-20`) and a client hands it to `router.leaveWith`,
which `followExternalRedirects(router)` (`src/platform/browser/routingHistory.ms`) points at `window.location.href`
(Solid `data/action.ts:195-200`); with no handler it throws. The React Navigation
surface (`createStackNavigator`, `NavigationContainer` with `linking`) is a second
shorthand over the same models. An author whose URL shape differs from the navigation
shape skips the tree and composes the models and the binding directly.

Later and separable: typed params derived from the pattern by a macro reading the
pattern literal and the type argument (MetaScript has no template-literal types;
macros read literals through `stringValue`, `recompiler/docs/LANG-METAPROGRAMMING.md`),
and file-based routes generating the same tree.

## Odd patterns the layers must compose

Each is an acceptance test. A pattern that needs a special case means a layer is wrong,
and the work stops for a decision.

1. A photo opened from a grid shows as a modal over the grid with its own URL; back
   closes it; reload keeps the modal or, opted in, shows the photo page (Next
   intercepting routes, TanStack masks).
2. Master/detail: two columns when wide, a stack when narrow, one set of addresses;
   resizing keeps the selection (Decompose panels).
3. Tabs each holding a stack: a cold `/inbox/42` opens the inbox tab on `[Inbox, 42]`;
   each tab keeps its stack; browser back walks the visits.
4. A guarded route answers a signed-out request with a redirect on the server and
   redirects before mount on the client.
5. An editor with two independently addressable regions (`__nav.` scopes).
6. A content site: flat routes, a shared layout, 404 and static paths.

## Rejected, and why

- A web-only route table beside the React Navigation navigators: two surfaces with
  one meaning, which the person's goal rules out.
- Diffing the container's state after each change (React Navigation `useLinking`) to
  follow in-app navigation: every model already knows whether it pushed, popped or
  replaced, and Expo SDK 58 left that diff for a per-router declaration
  (`src/react-navigation/routers/types.tsx` `RouterBrowserHistoryAction`). Decompose's
  `WebNavigation` publishes the same fact from the navigation layer, which is this
  model's reference.
- One tree serving as match result, navigation state and render input (Next.js
  `FlightRouterState`, described in its own source as "overloaded with concerns"),
  and a file tree doubling as each navigator's screen list with one anchor driving
  ranking, deep links and the initial route (Expo): both make a URL shape dictate a
  navigation shape.
- Guards that render a redirect after mount, client only (Expo `Protected`): a server
  cannot answer with the right status.
- Keeping one instance when a path param changes (Solid Router): local state of the
  previous item stays on screen for the next one.

## Design gate

Trace the owning reference before proposing each primitive. A capability not
supported by that mechanism is raised as **NEW MECHANISM**, with its need and
regression surface, before implementation. Do not combine every reference API
into a new general-purpose framework.

The three consumer axes are exercised by `examples/components/routing.ms`
`RoutingDemo` and `tests/navigation/routingConsumers.test.ms`, with actual Chrome
history traversal in `tests/browser/routing.test.ms`. Inventory proves UI overlay
routing, not a running Void world's resource policy. Transitions are a render-layer
choice, outside the navigation model; `createNativeStackNavigator` renders with the
same JS-driven frames.

## Route data

`query(fn, name)`, `revalidate(key?)` and `createAsync(fn)` (`src/navigation/data.ms`) are
the read side of Solid Router's route data (`~/projects/solid-router` `d0379e7`,
`src/data/query.ts`, `src/data/createAsync.ts`); `createAsync` is the async memo of
`hydrateMemo.ms` under that name, as Solid 2.0 has it. A query keys its calls by
`name + hashKey(args)` (`query.ts:83`), shares one in-flight promise per key, serves a
settled answer for 5 s or while a reader tracks it (`query.ts:105-111`), and
`revalidate` zeroes the matching entries and bumps their readers (`query.ts:41-56`).
On the server a query registers a slot under its key, so the writer emits it as a record
beside the memo's; on the client a query whose key has a record adopts it once and drops
it (`query.ts:132-135`, `:173`). A key always carries the JSON brackets of its arguments,
so it never equals an owner id. A read takes the router's `intent` as Solid's `getIntent()`
does (`query.ts:78`, `:104-142`): `"native"` reuses an entry whatever its age, any other
intent reuses it while a reader holds it or within `PRELOAD_TIMEOUT`, an entry a preload
made is refreshed when read and dropped after the timeout otherwise, and a `"navigate"`
read of a refreshed entry bumps its readers. The intent is `Router.intent`, set around a
route's `preload` and its component's mount (`mountLater`) from the stop's intent and
around `Router.preload` as `"preload"`; `Router.preload` runs under the owner its `RouterProvider` mounts under (`routing.ts:663`, `runWithOwner`), so a DOM event sees the intent, and a query called in a preload function does not surface its rejection (`query.ts` `inPreloadFn`); a read outside a router has none. A query that
throws a redirect while read navigates the router in place (`query.ts:177-195`, `replace`)
and its promise never settles, where Solid resolves `undefined` into a typed slot; a
preload read does not follow it; on a request history the router's `response()` carries it
and the promise rejects with it. Diverges from Solid where Neon has no counterpart: intent
is not a module global (a read after an `await` has no owner and so no intent), a returned
`Reply` and `json` are parked (below), no `query.get` or `query.set`, an arity-0/1/2
overload set in place of a rest tuple, `queryKey(name, …)` in place of `fn.keyFor` and
`fn.key`, and the cache is swept on insert in place of an interval. A record adopts only
for a struct or interface result (`hydrateMemo.ms`).

A query that throws `notFound()` while read is the same path with the next route in place of a
location. TanStack renders the nearest `notFoundComponent` and answers 404 for a loader's
`notFound()` (`~/projects/tanstack-router` `6777b8b`, `router-core/src/load-server.ts:90`,
`:547-585`); Neon's not-found unit is the route, as for a guard (above), so the router resolves
the same address again with the failed leaf left out (`Router.missing`) and the catch-all route
renders in its place, and `Router.response()` carries that route's own `status` (Next
`not-found`, nearest boundary). `serve` renders again once when the answer changed the status,
because a first pass has already mounted the failed route. Nothing matches once the failed leaf
is out: the render throws, naming the address. Where the status can still change follows
SolidStart (`~/projects/solid-start` `9b943dc`, `start/src/server/handler.ts:98-105`,
`:199-220`): a status is written at `onCompleteShell`, and anything settling after the shell
has flushed cannot change it (SolidStart's redirect becomes a client-side one,
`:214`). A read outside `<Loading>` holds the shell, so its answer is the status at the first
byte; a read under `<Loading>` answers after it. `serve` buffers the whole body, so the
response it builds always carries the final status; a caller that pipes `renderToStream`
sees the status of the first byte only for reads that hold the shell
(`tests/render/routeStatusServer.test.ms`). A site that needs 404 for a deferred read puts
the read outside `<Loading>`. Solid Router has no status API of its own; SolidStart's
`<HttpStatusCode>` is not taken, since a thrown `notFound()` also picks the UI.

`action(fn, name)`, `useAction`, `useSubmission` and `useSubmissions` (`src/navigation/action.ms`)
are the mutation side (`src/data/action.ts`): a call records a `Submission` on the router
(`router.submissions`, `routing.ts:519`; the hooks read `useRouter()` and fail loud outside a
`RouterProvider`) under the action's url `https://action/<name>` (`action.ts:111-135`), settles
it, then handles the response (`handleResponse`, `:179-215`): a `Location` navigates the
router, `revalidate` keys invalidate and revalidate only the matching queries and no keys all
of them, an error that is not a response returns before it. `onComplete` (`:75-79`, `:95-106`)
takes `{ name, onComplete }` in place of `string | { name?, onComplete? }`; Neon requires the
name. It receives a settled copy before the live submission settles, and a `retry()` called
from it supplies the call's answer. A null answer or a redirect clears the submission and
the call resolves null (Solid resolves `undefined`). `retry()` re-runs `fn` (`:128-133`) and
an error also rejects the call (`:107`). Diverges: an action takes one input value in place
of a rest tuple; the call is `useAction(a)(input)` because a function value cannot carry
`url` or be an `unknown` key; `result`, `error` and `pending` are methods; `useSubmission` is
an accessor of the latest submission or null in place of a stub proxy.

A `<form action={a.url}>` submits through its action on the client: `followSubmits(submit)`
(`src/platform/browser/routingHistory.ms`) is the submit half of `setupNativeEvents`
(`data/events.ts:104-130`, listener `:140`): a handled submit is prevented, one already
prevented or with no action is left alone, a submitter's `formaction` wins over the form's
`action`, and a form of an `https://action/` url that is not `POST` throws. `formAction(fn, name)`
makes the action whose input is `FormData` and registers it by url (`actions`, `action.ts:25`,
`:27-33`, released with the owner it was made under); `submitForm(router, url, data)` runs the
registered one, as `useAction` would, and answers whether there was one. A failure stays in the
submission and rejects no one, since a form has no caller (`if (result.error && !form)`, `:107`).
Diverges: `FormData` is Neon's own class of text fields (a file field throws), always the input
where Solid hands `URLSearchParams` unless `multipart/form-data`; no `actionBase` branch, since a
Neon action has only the `https://action/` url (no `.with`, no server url yet); `formAction` stands
in for an `action` overload on `(input: FormData)`, parked on a compiler card.

`redirect(address, status | init)`, `reload(init)` and `notFound()` build one `Reply`
(`route.ms`, `response.ts:3-36`) that is also the guard decision, so a guard and an action
return the same `redirect`. `Reply` extends `Error` because only an `Error` or a string
can be thrown, and `catch` reads it with `instanceof` (a class has runtime identity, an
interface has none). `redirect` keeps the guard's status 307 (TanStack `redirect.ts`) in
place of Solid's 302. `revalidate` takes `string[]`, not `string | string[]`. What a
`Reply` does is read where a failure is caught, so a redirect or reload is thrown
(`throw redirect("/login")`) from an action or a query; one a function returns, `json(data)`
with its typed body and `NarrowResponse<T>` (a conditional type with `infer` checks and runs
on both backends in isolation) are parked on
`2026-10-24-instanceof-of-a-generic-answer-union-fails-on-c.md`: on C `instanceof` of a
union holding a generic subclass is false, of a type parameter instantiated with a type that
has no object member emits invalid C, and a generic `Json<never>` emits a `void` field.
An absolute `Location` is an error naming the case, because a router opens only the
addresses of its own routes.

A route's `component` is `(props: RouteSectionProps<Map<string, string>, unknown>) => NeonNode`, so
`lazy<{}>(load)` and a component with no parameter fill it directly (Solid's
`RouteSectionComponent`, whose `Component<{}>` member is the same case), under a layout that
holds the `<Loading>` (the router adds none). Solid Router calls `component.preload` at
`routing.ts:650-681` and `:690-704`, which Neon lacks until the `.preload()` card lands.
`tests/render/lazyRoute.test.ms` pins it on the mock host and `tests/browser/lazy.test.ms`
in Chrome: the module is not fetched until the first navigation to the route. Hydration
claims the served node only when the module is already loaded
(`tests/render/lazyHydrate.test.ms`); Solid hands the client a preloaded module per
hydration id (`client/hydration.ts:1326-1346`) and Neon has no such registry, so a lazy
component still pending at `hydrate` fails to claim. `<A preload={false}>` renders
`preload="false"` on the anchor, where `followPreloads` reads it (`data/events.ts`).

## Linking

`src/navigation/linking.ms` follows React Navigation 7 (`@react-navigation/native@7.5.1`
`extractPathFromURL.tsx`; `@react-navigation/core@7.24.0` `getStateFromPath.tsx` and
`queryString.ts`). The first prefix that matches wins, not the longest. A prefix ends at a host
boundary (`$`, `/`, `?`, `#`), so `https://x.com` never matches `https://x.com.evil.com`, and a
`*` label matches one or more host characters (`https://*.example.com`). In the query, `+` is a
space and a malformed escape keeps its raw text; in a path param, a malformed escape rejects
that route and the next candidate is tried. Two things are left for the person: a repeated query
key is an array in React Navigation and `?flag` is `null`, while `NavTarget.values` is
`Map<string, string>` and keeps the last value and `""`.
## Base path

`createRoutes(configs, base)` mounts the whole tree under `base` (Solid `createBranches(routeDefs,
base)`, `components.tsx:48`; `routing.ts:297-310` joins it into every pattern, and `:474` rejects an
absolute base). Matching therefore sees only addresses under it: `createRouter` on `/docs/a`
with base `/app` is `RoutingError.NoMatch`, which `serve` answers as 404. Addresses inside the
router (`location().pathname`, history entries, `response().location`, typed `href`) carry the
base, as Solid's `location` does. `router.navigate`, `useNavigate` and a guard's `redirect` take
the address without it and add it once (`resolvePath(base, to, from)`, `routing.ts:547` and
`utils.ts:22-35`); the typed `navigate({ to })` and a tab press already hold the full address and
skip that step. `<A href="/x">` renders `href="/app/x"`; a relative or external href is left as
written. `followLinks(navigate, router.base)` leaves a link outside the base to the browser and
strips the base before `navigate` (`data/events.ts:56-62`). `followPreloads` passes the browser
address through, which the base-carrying tree matches as it is; `followSubmits` keys on action
URLs, which are registry keys and not addresses. References: Solid
Router `d0379e7`. `tests/navigation/routerBase.test.ms`, `tests/render/routerBaseServer.test.ms`
and `tests/browser/routerBase.test.ms` pin it.

## Scroll

`followScroll(router)` (`src/platform/browser/scroll.ms`) gives a web router its scroll
behaviour; routing stays host-free and sees only `Scroller.arrived(address, replace, scroll)`
(`src/navigation/scroll.ms`), which the router calls from each history write
(`RoutingSession.observeWrites`). References: Solid Router `d0379e7`
(`routers/createRouter.ts:55`, `routers/Router.ts:39-45`, `routers/scrollRestoration.ts`),
TanStack Router `6777b8b` (`router-core/src/scroll-restoration.ts`), Next.js `648110d4`
(`layout-router.tsx:145-270`).

- A push or a replace scrolls to the `#hash` element, else to the top (`scrollToHash`,
  `createRouter.ts:55-61`; TanStack `scroll-restoration.ts` `onRendered`, replace included).
  A search-only change is an ordinary navigation, so it scrolls too; Solid's `useSearchParams`
  defaults `scroll: false` (`routing.ts:246`), and Neon has no such setter yet.
- `navigate(href, { scroll: false })` skips the scroll to the top and still scrolls to a hash
  target that exists, as Solid (`createRouter.ts:55-61`) and TanStack's `resetScroll: false`
  with a hash do. Next's `scroll={false}` leaves everything alone; Neon follows the two owners.
  `<A noScroll>` renders the attribute and `followLinks` passes `{ scroll: false }` to its
  callback, as Solid reads `noscroll` off the anchor (`data/events.ts` handleAnchorClick).
- `followScroll` sets `history.scrollRestoration = "manual"` and puts it back on dispose
  (`scrollRestoration.ts:33`). It records `scrollY` on every scroll event under the entry's
  `__neonIndex` (Solid keys by `_depth`, `:48-50`), drops the offsets from a new entry on
  (`onPush`, `:77-80`), saves them in `sessionStorage` on `pagehide` (`:51-57`) and restores
  on `popstate`, after the router's own listener has rendered. An entry with no record goes to
  its hash, else the top.
- A document that loads as a reload or back_forward restores its entry's offset
  (`:92-98`); `followScroll(router, type)` takes the navigation type for a test.
- Late content: Solid restores once, after routing settles, and says a document still
  growing is not chased (`scrollRestoration.ts:21-27`); TanStack restores after `onRendered`,
  once its loaders resolved. Neon mounts a page under a `Loading` at once and has no routing
  settle, so a restore whose offset the document cannot yet hold waits on a `ResizeObserver`
  and scrolls only when the offset is reachable (never to a clamped value). A wheel, touch or
  key event, the next navigation, or dispose cancels the wait. This hold has no reference;
  it is a separate commit so it can be dropped.
- Not built: nested scroll containers (TanStack `data-scroll-restoration-id`, needs an id on
  `ScrollView`); smooth `scrollRestorationBehavior`.

## Announcement

`followAnnouncements(router)` (`src/platform/browser/announce.ms`) ports Next.js
`app-router-announcer.tsx` (`648110d4`): a visually hidden `role="alert"` `aria-live="assertive"`
region (`:10-30`) is set to `document.title`, else the first `h1`, after a route change, and
not on the first load, where screen readers read the page themselves; an unchanged title is
not repeated (`:55-69`). It follows the router's pathname, so push, replace and back and forward
all announce. Solid Router `d0379e7`, TanStack Router `6777b8b` and Expo Router have no
announcement and no focus move. Next's `layout-router.tsx:224-225` states that it leaves focus
untouched and defers resetting it, so Neon moves no focus. Neon uses a plain element where Next
uses a shadow root.

## Provisional choices and remaining limits

- The built-in navigators are compositions of two public models over
  `createChildren`: `createChildStack` (`childStack.ms`, Decompose `childStack`)
  under the stack, `createChildPages` (`childPages.ms`, Decompose `childPages`)
  under tabs and drawer. A route's key, seed (name and initial params) and active
  flag are the child state; its `Navigation<PL>` is the child instance
  (`NavigatorCore.child`). `NavigatorCore` keeps what every navigator shares
  (screens, route keys, `beforeRemove` guards, nested links, state and restore) and
  hands each operation to the `NavigatorModel` its navigator builds: `stackModel`,
  `pagesModel` with `backBehavior` history, and `drawerModel`, which keeps the open
  flag beside the pages. No operation compares `NavigatorKind`; the header back
  button, the motion kind and the drawer swipe read what the renderer passes
  (`createNavigatorMotion(core, stacked)`, `screenView(…, menu)`) or the
  `NavigatorLink.canPop` capability.
- The models diverge from Decompose where Neon lacks a mechanism: identity is a
  `key` function, not configuration equality; `pop` and `popTo` return whether they
  popped, where Decompose passes it to `onComplete`; navigation is synchronous,
  without `onComplete`, and a change made while one applies throws instead of
  queueing (`Relay.kt`) until the binding's queue lands; every page stays created,
  with no `pageStatus`; there is no back handler or saved-state serializer.
  `selectNext` and `selectPrev` take `circular` as a required argument until the
  compiler card on default parameters of generic class methods lands.
- A stack's focused route is its last: a reset or restored state keeps every route
  and focuses the last whatever its `index`, as React Navigation's
  `StackRouter.getRehydratedState` does for a state that is not `stale: false`.
- Transitions belong to the render layer, as Decompose's
  `Children(animation = stackAnimation())`: `navigatorMotion.ms` diffs the route
  children, keeps a leaving screen rendered until its exit ends
  (`AbstractStackAnimation.kt`), and snaps when the screen set changes. A host that
  wants platform transitions renders the same children its own way.
- `NavigationContainer` joins a registry through `routing={{ registry, scope }}` with
  the participant of `createWebHistory` (`containerHistory.ms`). It registers when its
  node is built and, until it mounts, reports the address it was asked to open, so an
  app builds its tree, opens the routing session, then mounts or hydrates. After
  mount, `ref.enableHistory(session)` turns the mirror on, as a Decompose app calls
  `enableWebHistory`; turning it on by itself would need the session to announce that
  it opened, a new mechanism. Each navigator publishes its routes as `WebNavigation`,
  keyed by route key, name and string params, with path parts from the screens'
  `linking` paths; a cold open or an entry without state resolves through
  `targetFromPath`. Where it leaves Decompose and Expo, and why:
  - A traversal into a navigator that has not mounted yet holds the stored keys and
    seeds it with them when it mounts, as React Navigation restores a saved state;
    Decompose has no mount gap. A navigator inside a closing screen is skipped, since
    the exit animation keeps it registered.
  - Neon reuses a route by key, so a traversal writes params into a live route that
    keeps its key; Decompose configurations are immutable.
  - `setParams` changes the key and so replaces the entry it changes, as Expo's
    `SET_PARAMS` does (`BaseRouter.tsx` declares nothing).
  - Tabs and drawer publish the pages their `backBehavior` walks back (`pagesModel`
    `backPath`), so browser back, Android back and `goBack` walk one path: `firstRoute`
    (the default, as Expo's) adds the first page before another selected one,
    `initialRoute` the initial one, `none` nothing, and `history` the visits without
    repeats, as React Navigation's `history` (`TabRouter.tsx` `changeIndex`). Expo keeps
    the browser log apart from the tab history, so its browser walks every visit
    (`getBrowserHistoryForAction`) while its back walks the tab history; here both walk
    the tab history, and revisiting a tab rewrites the entries after the first visit it
    moves. A log of every visit is React Navigation's `fullHistory`, which Neon does not
    offer until an app asks for it; it would be one more visit list both backs walk. A
    drawer defaults to `firstRoute`, as `DrawerRouter` does: a switch away from the first
    page adds an entry and a switch between later pages replaces it.
  - Opening the drawer adds an entry at the same address and closing it goes back one,
    as Expo's `DrawerRouter` adds a drawer history item. The open item carries the
    selected page's address and no child, since the URL comes from the last item. A
    traversal restores the stored open state; a reload, or a traversal into a drawer
    not mounted yet, lands closed. Pushing in a parent stack while the drawer is open
    keeps the open entry, where Expo replaces it.
  - Browser back asks `beforeRemove` of each stack's top screen down the active branch
    and returns the browser on a refusal, as Expo refuses a prevented restore
    (`global-state/browserHistory.ts`). `onBeforeNavigate` carries no target
    (Decompose's contract), so a forward traversal asks too, and the action handed
    over is `GO_BACK`.
  - With routing on, a nested screen whose linking path is `exact` is refused: each
    level's part joins its parent's.
- Typed route bindings close over their decoder and typed model setter rather
  than exposing an untyped global params getter. The built-in navigators take
  React Navigation's per-screen ParamList: `createStackNavigator<PL>()`,
  `navigation.navigate(name, params?)` typed per screen (`params` required unless
  `null` is in the screen's entry), `useRoute<PL, "Name">()` for `route.params`
  and `route.setParams`, `getParent<PL, Q>()` for the parent's list. Each route
  keeps its params as a `ParamBox<PL[K]>` in one slot (`core.ms`), whose type
  argument is the identity a read checks, so reading a route as another screen's
  type stops with `invalid object conversion` instead of reinterpreting memory.
  A screen's codec (`initial`, `parse`, `stringify`) is built with
  `Navigator.params.of("Name", {...})` and passed as `params`, because `<Screen>`
  cannot yet infer its name's type (`name` is `keyof PL`, the rest is not tied to
  it; `~/metascript/.inbox/compiler/2026-10-24-a-keyof-constrained-type-parameter-inferred-from-an-object-literal-property-widens-to-string.md`). A navigate to a name of another navigator bubbles without params; naming it
  in this navigator's list is what lets it be written (React Navigation's
  composite navigation prop does that through its parent's list).
  Tabs and drawer take the same lists as the stack, `reset` takes routes from
  `navigation.routeOf(name, params?)` typed per screen on all three, and a screen
  inside a nested navigator reaches its parent's screens with
  `getParent<PL, Q>().navigate(name, params)` typed by `Q` (React Navigation's
  `CompositeNavigationProp`, written by naming the parent's list). The container
  ref's `navigate(name)` is not typed yet (`WORKAROUND.md` V3).
- Secondary addresses reserve the `__nav.` query namespace. This makes region
  ownership explicit without imposing an editor/game hierarchy. Unknown scopes
  are errors rather than ignored links.
- Navigation snapshots are participant codecs, not serialization of arbitrary
  reactive graphs. URL traversal can therefore restore a retained document stack
  without promising persistence of every local edit or GPU resource.
- Stack and Tabs are levels of the route tree shorthand (`src/navigation/router.ms`),
  each backed by `createChildStack` or `createChildPages` and mirrored through
  `createWebHistory`. A `navigate` that changes only the search or the hash pushes an
  entry unless `replace`, as Solid's `navigate` does (`routing.ts:615`), and the first
  call of a batch decides, as its `navigateEnd`; a navigator action that keeps its keys,
  such as `setParams`, updates the current entry, as Expo's `getBrowserHistoryForAction`
  returning nothing does.
  Their renderers (`childView.ms`) keep every stack entry mounted and show only the
  top, and keep a tab mounted from its first selection, hiding the inactive ones (React
  Navigation `CardStack` with `detachInactiveScreens`, the lazy tabs of
  `BottomTabView`). Neither animates, and no option unmounts or pops a tab on blur. A
  tab level publishes the tabs its `backBehavior` walks back, as the container's tabs
  do: `firstRoute` by default, so browser back from the inbox returns to the feed tab as
  it was, or `history` or `none`; `initialRoute` throws, since Tabs take no initial
  route. A traversal restores the visits from the entry's keys. A Tabs level without a
  layout draws React Navigation's bottom tab bar under its pages; a layout places
  `<TabBar />` itself or draws its own from `useTabs()`, the triggers of Expo Router's
  `TabTrigger` (label, options, focused, the tab's live address, press). Each route of
  the level labels its tab through `options`, React Navigation's `ScreenOptions`, as an
  object or a function read reactively; `options` under any other level throws. Pressing
  another tab navigates to the address that tab was left on, so its stack, its guard and
  a history entry come with it; pressing the shown tab pops its stack to the root when
  the stack holds more than one screen (native stack's `tabPress` → `popToTop`). Not yet:
  a web `<a href>` around a trigger, a preventable `tabPress`, and a hidden tab (Expo's
  `href: null`). Tabs are declared as a
  `navigator` beside the `layout`: the layout is the frame the author draws, the
  navigator the model it drives, so any frame drives any model. A typed `route` takes its
  path, status, guard and paths from its definition, so a config naming them beside it throws.
  Its `<A>` renders a web `<a>`; on a native host that is a plain view until `<A>`
  and React Navigation's `Link` become one through the binding.
- Request routing initializes before mounting, on a server as on a client. What a
  server render writes and how `hydrate` takes it over is `docs/RENDER-MODEL.md`.
- Not in the first version of the layers: data loading per route (TanStack `loader`;
  Solid's `preload` is in, without its `data` result), focus after a navigation, and guards that re-run by themselves when sign-in
  state changes (the first version offers an explicit revalidation, as TanStack
  `router.invalidate`).
