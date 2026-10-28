# Solid parity — what Neon still owes the model it copies

Neon's reactivity is Solid 2.0's (`~/projects/solid-next` at `84dada77`), by decision. The goal is
parity of **concepts**, not of source: every core idea Solid has, Neon has, localized to
MetaScript — and where a compile step can replace a runtime mechanism Solid needs only because
JavaScript cannot see shapes, Neon takes the compiled form instead. This file is the tracker.
**The detail of each open row lives in its card**, one per row, under `~/metascript/.wt/`; keep the
row here to one line.

## Already there

What `src/index.ms` exports from `src/core/` and from `src/macros/ui/flow.ms`, less the rows below.
The core is Solid 2.0's graph, scheduler and effect split, read from `packages/signals`; the places
Neon departs from it are in `docs/REFERENCE.md`.

## Missing

| # | concept | what it costs to be without it | card |
|---|---|---|---|
| 1 | **store** — `createStore` done in the Solid 2.0 arc as a `Proxy` store with a draft-first setter: `setStore((s) => { s.user.name = "Ann"; })` applies at the next flush, a write re-runs only the readers of that field or array index, a nested record is one store wherever it sits, the seed and every object written in are copied at the first write and never mutated, and a write outside the setter is a compile error. `snapshot`, `reconcile` (by key or by position), `createStore(fn, seed)` and `createProjection(fn, seed)`, which replaces the deleted `createSelector`, are done (`tests/core/store.test.ms`). Still missing: the setter's or the derive's returned value (compiled and dropped today), an async derive, `refresh` of a derived store, `storePath`, `deep`, `createOptimisticStore`, and the `shallow` and `key` options. A callback array method on a store of records, `snapshot(state.user)` with `T` inferred, a function-valued field, a shared nested array and the store's memory bound are parked (`BUGS.md`) | a derive that returns server data instead of writing it field by field, and async derived stores | `neon-solid2.md` |
| 2 | **async** — transitions (`startTransition` / `useTransition`), optimistic updates, `action` | `lazy` is done (`lazy(load)` over the async memo as `packages/solid/src/client/component.ts:127` does: one shared load, a memo per instance behind the surrounding `<Loading>`, and the server render waits for the module; `tests/render/lazy.test.ms`, `lazyServer.test.ms`); it takes a loader returning the component, keyed by the module its `import("…")` names (the `lazy` macro reads it, `lazyModule(key, load)` takes it written), and has no `preload` on the component yet, because a `(props) => NeonNode` carries no properties; it mounts through an effect and `Show`, so it settles inside a `For` row and after a navigation (`tests/render/lazyRoute.test.ms`, `tests/browser/lazy.test.ms`); on the client its body reads the module's readiness, as Solid's lazy reads its memo in the render, so a region whose new row waits on a module keeps its old rows and a navigation to a lazy route keeps the old page until the new one can render (`tests/navigation/routeLazyHold.test.ms`), and hydrates a served node once the module is loaded (`tests/render/lazyHydrate.test.ms`); the server records hydration id to module key in `ServerContext.modules` and writes it into the page's `_$HY.m` table, and `hydrate` claims the served page only after the modules that table lists have loaded, as `packages/web/src/client.ts:2425` does behind `loadModuleAssets` (`tests/render/lazyPreload.test.ms`, `lazyModuleServer.test.ms`, the cold case in `lazyHydrate.test.ms`, `tests/browser/lazyHydrate.test.ms`). The rest of async is done in the Solid 2.0 arc: an async `createMemo` with `NotReadyError`, `isPending`, `latest`, `refresh`, and `createLoadingBoundary` / `<Loading>` (`tests/core/memoAsync.test.ms`, `memoError.test.ms`, `memoRefresh.test.ms`, `pendingLatest.test.ms`, `loadingBoundary.test.ms`, `tests/render/loading.test.ms`). The async entry ships as `createAsyncMemo` and is not exported from `src/index.ms`: Solid 2.0 has one `createMemo` for sync and async computes, and the overload waits on the compiler cards of 2026-10-16 named at `src/core/memo.ms`. `createResource` and `<Suspense>` are deleted, not ported. What is left has no consumer yet | `solid-async.md` |
| 3 | ~~error channel — `createErrorBoundary`, `<Errored>`~~ | done in the Solid 2.0 arc, which deleted `catchError` and `<ErrorBoundary>`: the fallback receives the thrown `Error` itself, the same object on C and `--target=js` (`tests/render/errorBoundary.test.ms`; `docs/REFERENCE.md` SR-2). A render on the server sends a generic error outside a dev build (`tests/render/errorBoundaryServer.test.ms`). The content stays behind the fallback and comes back on reset (`tests/render/erroredKeep.test.ms`; `docs/REFERENCE.md` RD-5) | ~~`solid-error-boundary.md`~~ |
| 4 | ~~the effect split — `createEffect(compute, effect)`, `createRenderEffect`, `onSettled`~~ | done in the Solid 2.0 arc, which deleted `onMount`, `createBindingEffect` and the one-function effects: `createRenderEffect` is the tier the framework binds with, `createEffect` and `onSettled` run after it, and neither runs on the server (`tests/core/effect.test.ms`, `onSettled.test.ms`, `effectServer.test.ms`) | ~~`solid-effect-tiers.md`~~ |
| 6 | ~~`equals` on `createSignal`~~ | done in the Solid 2.0 arc: `createSignal(v, { equals, ownedWrite })`, where `equals: false` always notifies (`tests/core/signal.test.ms`) | ~~`solid-signal-equals.md`~~ |
| 7 | ~~`<Switch>` / `<Match>`~~, `<Dynamic>` | `<Switch>` / `<Match>` done in the Solid 2.0 arc as `<Match fallback>` / `<Case when>`, because React Native's `Switch` (`src/components/switch.ms`) keeps its name: the first truthy `when` wins, the branch mounts again only when the selected index changes (or, with `keyed`, when the value's identity does), and `keyed` and a function child take `Show`'s forms. `<Case>` outside `<Match>` and `<Match when>` are compile errors (`tests/render/match.test.ms`, `matchServer.test.ms`, `tests/browser/match.test.ms`, `tests/macros/matchWhenRejected.ms`, `caseOutsideMatchRejected.ms`). Still missing: no component-as-a-value (`<Dynamic>`). `<Portal>` exists (`src/render/portal.ms`, used by `Modal`) | `solid-control-flow.md` |
| 8 | ~~`hydrate`, `createUniqueId`~~; async values across the wire | `hydrate` and `createUniqueId` done `3309f37` (2026-10-13): a served page's nodes become the live tree by position, without Solid's `_hk` keys (`docs/RENDER-MODEL.md` "Hydration"; `tests/render/hydrate.test.ms`, `tests/browser/hydrate.test.ms`, `tests/edge/run.sh`). An async memo's value travels from the server to the client: `examples/site` route `/notes/:slug` reads request-time data under `<Loading>`, the worker renders it with the awaited `renderToStream`, and Chrome adopts the record with no data request (`tests/edge/run.mjs`) | `solid-hydrate.md` |

## Taken from Solid 2.0: ref directive factories

Reference: Solid `2.0.0-rc.15`, `packages/solid/CHEATSHEET.md` "Refs and directives",
`documentation/solid-2.0/MIGRATION.md` (`use:` removed, ref factories, array refs);
dom-expressions `dom-next`, `packages/runtime/src/client.js` `ref` and `applyRef`, and
`packages/babel-plugin-jsx/src/dom/element.ts` (the `ref` branch of the attribute loop).

- `ref={fn}`, `ref={[a, b]}` and `ref={tooltip(opts)}` on elements and on components that forward
  `ref`. The array is composed at compile time (`composeRefs`), so a component still sees one
  function; nested arrays and `null` entries flatten away, an empty array is an error, and only a
  literal array is taken: an array held in a variable is a type error (`docs/REFERENCE.md` RD-1).
- Two phases, as in Solid: the factory call is the setup phase, in the mounting owner and
  untracked (`setupRef`), so its effects and `onCleanup` belong to the component; the function it
  returns is the apply phase, untracked (`applyRef`), under the mounting owner (`docs/REFERENCE.md`
  RD-2). `docs/RENDER-MODEL.md` "Refs" gives the details.
- Ref order is React's, innermost first (`docs/REFERENCE.md` SF-2).
- `use:` is not adopted: Solid 2.0 removed it too.
- `<Void ref>` receives a `VoidAreaHandle` (`docs/REFERENCE.md` RD-3).

## Deliberately not taken

`children()`, `mergeProps` / `splitProps` and the rest of Neon's departures from Solid are recorded
in `docs/REFERENCE.md`.

## Using this file

A row moves out of the table when its card's "Done when" holds on `main`; record the commit sha in
the card and delete the card. A row is never expanded here — if it needs a paragraph, it belongs in
the card.
