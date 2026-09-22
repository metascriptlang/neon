# Solid parity — what Neon still owes the model it copies

Neon's reactivity is Solid's, by decision. The goal is parity of **concepts**, not of source: every
core idea Solid has, Neon has, localized to MetaScript — and where a compile step can replace a
runtime mechanism Solid needs only because JavaScript cannot see shapes, Neon takes the compiled
form instead. This file is the tracker. **The detail of each row lives in its card**, one per row,
under `~/metascript/.wt/`; keep the row here to one line.

Audited 2026-09-21 against `src/core/` (8 files, 553 lines) and `src/render/`.

## Already there

`createSignal` · `createEffect` · `createMemo` · `createRoot` · `onCleanup` · `untrack` · `batch` ·
`runWithOwner` · `getOwner` · owner tree with scoped cleanup · a two-lane queue that drains pure
computations before effects, so no downstream effect reads a stale memo · `createContext` /
`useContext` on the owner walk with a value thunk, so signals inside a context value track per
consumer · `createComponent` running the body untracked · `mapArray` / `indexArray` ·
`<Show>` / `<For>` / `<Index>` · `renderToString`.

## Missing

| # | concept | what it costs to be without it | card |
|---|---|---|---|
| 1 | **store** — `createStore`, `produce`, `reconcile`, `unwrap`, `createMutable` | no nested reactivity: a write anywhere in an object invalidates every reader of it. The compiler replaces Solid's `Proxy` with one signal per field, and makes a wrong path a type error | `solid-store.md` |
| 2 | **async** — `createResource`, `<Suspense>`, `startTransition` / `useTransition`, `lazy` | no async story at all. Needs a pending state on `Computation`, so the shape is decided early even if it ships late | `solid-async.md` |
| 3 | ~~error channel — `catchError`, `<ErrorBoundary>`~~ | done `12a9456` (2026-09-22): the handler carries the message, not the `Error` — parked on a compiler bug, see the card | ~~`solid-error-boundary.md`~~ |
| 4 | **the third effect tier** — a deferred `createEffect`, and `onMount` | today's `createEffect` runs immediately, so it *is* Solid's `createRenderEffect`; nothing has a correct place to read a host node back | `solid-effect-tiers.md` |
| 5 | `createSelector` | selecting one row of a list re-runs every row's effect | `solid-selector.md` |
| 6 | `equals` on `createSignal` | equality is hardcoded to identity, so a value mutated in place can never announce itself and there is no always-notify signal | `solid-signal-equals.md` |
| 7 | `<Switch>` / `<Match>`, `<Dynamic>`, `<Portal>` | no n-way choice, no component-as-a-value, no mounting outside the subtree | `solid-control-flow.md` |
| 8 | `hydrate`, `createUniqueId`, resource serialization | SSR produces markup but nothing can attach to it | `solid-hydrate.md` |

## Deliberately not taken

- `children()` / `Children.map` / `cloneElement` — the one-NeonNode arc (2026-09-19) settled that
  `children` is one `NeonNode`; inspecting or rewriting a child list is not a thing Neon does.
- `mergeProps` / `splitProps` — replaced by the compile-time spread-props contract: props are
  pure-JS objects and `{...props}` is resolved by type, not merged at runtime.

## Using this file

A row moves out of the table when its card's "Done when" holds on `main`; record the commit sha in
the card and delete the card. A row is never expanded here — if it needs a paragraph, it belongs in
the card.
