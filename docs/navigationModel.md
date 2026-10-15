# Navigation model anchor

The person approved this direction in the `rn-navigation-prod` discussion:
**Decompose-style navigation primitives and composition; Solid Router / TanStack
routing contracts; Solid reactivity underneath.** Subsequent authorization covers
continuous implementation with reference-backed provisional choices, recorded
here and in `WORKAROUND.md`; it does not claim final API review.

## Reference ownership

- **Decompose:** renderer-independent destination identity, child lifecycle and
  composable navigation models. Start with its [Generic Navigation](https://arkivanov.github.io/Decompose/navigation/children/overview/)
  and `ComponentContext.children`; do not transplant Android lifecycle statuses
  into Solid owners without tracing their meaning.
- **Solid Router:** location integration separated from matching and rendering;
  browser, memory and request/static sources. Trace `src/routers/createRouter.ts`,
  `Router.ts`, `StaticRouter.ts` and `src/routing.ts` in
  [solidjs/solid-router](https://github.com/solidjs/solid-router).
- **TanStack Router:** typed and validated params/search, history and request/SSR
  contracts. Trace `packages/history/src/index.ts` in
  [TanStack/router](https://github.com/TanStack/router), plus its
  [search params](https://tanstack.com/router/latest/docs/framework/react/guide/search-params)
  and [SSR](https://tanstack.com/router/latest/docs/framework/react/guide/ssr) references.
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
- The models diverge from Decompose where it fails loud or lacks a mechanism:
  identity is a `key` function, not configuration equality; `pop` on one item and
  `popTo` past the end throw instead of doing nothing or taking the whole stack;
  navigation is synchronous, without `onComplete`, and a change made while one
  applies throws instead of queueing (`Relay.kt`); every page stays created, with
  no `pageStatus`; there is no back handler or saved-state serializer. `selectNext`
  and `selectPrev` take `circular` as a required argument until the compiler card
  on default parameters of generic class methods lands.
- A stack holds the routes up to its focused one, so a reset or restored state
  whose `index` is below its last route drops the routes above it, as
  `@react-navigation/stack` `StackView` renders such a state.
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
  the routing session, then mounts or hydrates. A navigation made in the app changes
  the model first and the app records it with `session.sync`, as a custom
  composition does; mirroring a navigator's pushes and pops into browser history
  (Decompose `enableWebHistory`) is not ported.
- Typed route bindings close over their decoder and typed model setter rather
  than exposing an untyped global params getter. Legacy navigators retain one
  `P`; heterogeneous ParamList compatibility is not claimed.
- Secondary addresses reserve the `__nav.` query namespace. This makes region
  ownership explicit without imposing an editor/game hierarchy. Unknown scopes
  are errors rather than ignored links.
- Navigation snapshots are participant codecs, not serialization of arbitrary
  reactive graphs. URL traversal can therefore restore a retained document stack
  without promising persistence of every local edit or GPU resource.
- Request routing initializes before mounting, on a server as on a client. What a
  server render writes and how `hydrate` takes it over is `docs/RENDER-MODEL.md`.
