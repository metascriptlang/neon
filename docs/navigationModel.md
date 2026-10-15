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

- The built-in navigators hold their routes as `createChildren` children: a route's
  key, its seed (name and initial params) and its active flag are the child state,
  and its `Navigation<P>` is the child instance (`core.ms` `place`). Decompose's
  `childStack` is `children` plus a transformer (`ChildStackFactory.kt`); Neon's
  stack, tabs and drawer still share one `NavigatorCore` whose operations branch on
  the navigator kind.
- Transitions belong to the render layer, as Decompose's
  `Children(animation = stackAnimation())`: `navigatorMotion.ms` diffs the route
  children, keeps a leaving screen rendered until its exit ends
  (`AbstractStackAnimation.kt`), and snaps when the screen set changes. A host that
  wants platform transitions renders the same children its own way.
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
