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
  panels follow `PanelsWebNavigation`. The adapters are in
  `src/navigation/webNavigation.ms`; `webNavigationNode` erases a typed one to string
  keys, as `bindRoute` erases a codec, and decodes every key before applying any,
  where Decompose's binding can throw after applying a parent level.
- A navigation requested while one applies is queued (`Relay.kt`).

**Rendering (presentation)** draws a model: outlet, stack with motion, header and
gestures, pages with a tab bar, drawer, panels laid out by width, modal presentation.
A renderer takes a model and a `render(child)` function; input events (edge swipe,
hardware back, mouse back button, shortcuts) call model operations. It never imports
routing. `navigatorMotion.ms` stays the transition engine.

**Binding** is the only module that imports two layers.

- Cold resolution: an address without a snapshot is matched and every level's model
  is seeded from the match (Expo `createSeededNavigationState`). A stack may name an
  `initial` route placed below a cold-opened destination; it applies to cold
  resolution only, because in-app navigation already has a real history.
- In-app `navigate(href)` and `<A>`: match the href, walk the live models from the
  root while each level's active destination equals the matched one, and apply the
  first differing level's operation: push or pop back on a stack, select a page,
  activate a slot (Expo `resolveNavigationDestination`).
- History: the binding diffs the models' published items onto the routing session as
  Decompose `enableWebHistory` does. Same keys replace the URL, more keys push, fewer
  keys go back by the count (and replace when the browser has fewer entries), and
  anything else rewrites. The URL joins the active branch's parts top to bottom, each
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
    the flag is reset.
  - One render effect walks the active branch from the root, and a pop records its
    count when the level changes: a disposed child publishes `[]` and queued effects
    run last in first out, so a per-level effect would read disposed models.
  - Nested entries are built as push and rewrite build them. Decompose's `history()`
    adds every node of an item's history, which by reading lists an item twice at
    depth three; not run in Kotlin.
  - An entry without state resolves from its address, as this design says, and asks no
    `onBeforeNavigate`; Decompose ignores such an entry. `onBeforeNavigate` is asked on
    every restore, also one that changes only another region.
  - The key tree is a preorder list until the compiler card on JSON of a type holding
    an array of itself lands (parked in `BUGS.md`). There is no `schemaVersion` or
    `onRecreate`; undecodable state takes the session's `IncompleteSnapshot` path.
- Reload restores the entry's structure (a TanStack mask with `unmaskOnReload:
  false`); a presentation can resolve from the address on reload instead, which is
  Next's hard navigation.
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
  { layout: Tabs, children: [
    { path: "/feed", component: Feed },
    { path: "/inbox", layout: Stack, children: [
      { path: "", component: Inbox },
      { route: thread, component: Thread },
    ] },
  ] },
  { path: "*", status: 404, component: NotFound },
]);
```

`path` gives untyped routes whose params are strings; `route` gives typed ones.
Solid Router's names are kept where the meaning is the same.

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
server, in static output and in the browser. `Router.response()` gives a server the
first redirect's status and final location, or the route's status. The React Navigation
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

## Provisional choices and remaining limits

- The built-in navigators are compositions of two public models over
  `createChildren`: `createChildStack` (`childStack.ms`, Decompose `childStack`)
  under the stack, `createChildPages` (`childPages.ms`, Decompose `childPages`)
  under tabs and drawer. A route's key, seed (name and initial params) and active
  flag are the child state; its `Navigation<P>` is the child instance
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
- `NavigationContainer` joins a registry through `routing={{ registry, scope }}`:
  its `linking.config` is the participant's codec (`targetFromPath` opens an
  address, `pathFromState` reports one), and its snapshot holds the root state's
  route names and string params. It registers when its node is built and, until it
  mounts, reports the address it was asked to open, so an app builds its tree, opens
  the routing session, then mounts or hydrates. Until the container's navigators
  publish `WebNavigation` to `createWebHistory`, a navigation made in the app changes
  the model first and the app records it with `session.sync`, as a custom composition
  does.
- Typed route bindings close over their decoder and typed model setter rather
  than exposing an untyped global params getter. Legacy navigators retain one
  `P`; heterogeneous ParamList compatibility is not claimed.
- Secondary addresses reserve the `__nav.` query namespace. This makes region
  ownership explicit without imposing an editor/game hierarchy. Unknown scopes
  are errors rather than ignored links.
- Navigation snapshots are participant codecs, not serialization of arbitrary
  reactive graphs. URL traversal can therefore restore a retained document stack
  without promising persistence of every local edit or GPU resource.
- The route tree shorthand has layout levels only; Stack and Tabs as levels come with
  the binding's cold resolution and href walk, which are not written yet. It takes `path` strings only, and the web navigation adapters take a
  required options object, until two compiler cards land (both parked in `BUGS.md`).
  Its `<A>` renders a web `<a>`; on a native host that is a plain view until `<A>`
  and React Navigation's `Link` become one through the binding.
- Request routing initializes before mounting, on a server as on a client. What a
  server render writes and how `hydrate` takes it over is `docs/RENDER-MODEL.md`.
- Not in the first version of the layers: data loading per route (Solid `preload`,
  TanStack `loader`), scroll restoration on client navigation, focus and
  announcement after a navigation, and guards that re-run by themselves when sign-in
  state changes (the first version offers an explicit revalidation, as TanStack
  `router.invalidate`).
