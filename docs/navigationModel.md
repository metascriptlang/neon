# Navigation model anchor

The person approved this direction in the `rn-navigation-prod` discussion:
**Decompose-style navigation primitives and composition; Solid Router / TanStack
routing contracts; Solid reactivity underneath.** This is a model decision, not
approval of a concrete protocol or implementation.

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
world through a common contract. The concrete registration protocol remains to
be designed and approved; custom compositions must not require a central switch
on navigator kinds.

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

Next, propose the smallest shared routing contract against three consumers:
a stack app, an editor with simultaneous panes, and a game world with overlays.
The proposal must explain URL round-trips, history traversal, request-local SSR
initialization, identity/lifecycle ownership and params validation. Validate with
those consumers before treating the protocol as settled. API names, per-route
MetaScript typing and native transition policy are not decided by this anchor.
