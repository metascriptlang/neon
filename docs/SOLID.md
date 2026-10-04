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
`useContext` on context entries every owner inherits, with a value thunk, so signals inside a
context value track per consumer · `createComponent` running the body untracked · `mapArray` / `indexArray` ·
`<Show>` / `<For>` / `<Index>` · `renderToString`.

## Missing

| # | concept | what it costs to be without it | card |
|---|---|---|---|
| 1 | **store** — `createStore`, `produce`, `reconcile`, `unwrap`, `createMutable` | no nested reactivity: a write anywhere in an object invalidates every reader of it. The compiler replaces Solid's `Proxy` with one signal per field, and makes a wrong path a type error | `solid-store.md` |
| 2 | **async** — `createResource`, `<Suspense>`, `startTransition` / `useTransition`, `lazy` | no async story at all. Needs a pending state on `Computation`, so the shape is decided early even if it ships late | `solid-async.md` |
| 3 | ~~error channel — `catchError`, `<ErrorBoundary>`~~ | done `12a9456` (2026-09-22); since `00de615` (2026-09-25) the handler and the fallback receive the thrown `Error` itself, the same object on C and `--target=js` (`tests/render/errorBoundary.test.ms`). A thrown string arrives as an `Error` carrying it, and a thrown non-`Error` value is a compile error (recompiler `1debbcc8`) | ~~`solid-error-boundary.md`~~ |
| 4 | **the third effect tier** — a deferred `createEffect`, and `onMount` | today's `createEffect` runs immediately, so it *is* Solid's `createRenderEffect`; nothing has a correct place to read a host node back | `solid-effect-tiers.md` |
| 5 | `createSelector` — implemented on `wt/solid-selector`; land pending | keyed subscriptions in `src/core/selector.ms`; native nullable-source acceptance is compiler-blocked (below) | `solid-selector.md` |
| 6 | `equals` on `createSignal` | equality is hardcoded to identity, so a value mutated in place can never announce itself and there is no always-notify signal | `solid-signal-equals.md` |
| 7 | `<Switch>` / `<Match>`, `<Dynamic>`, `<Portal>` | no n-way choice, no component-as-a-value, no mounting outside the subtree | `solid-control-flow.md` |
| 8 | `hydrate`, `createUniqueId`, resource serialization | SSR produces markup but nothing can attach to it | `solid-hydrate.md` |

## Selector acceptance, not yet landed

Reference: Solid `packages/solid/src/reactive/signal.ts` `createSelector` (834–875).
The keyed-subscription mechanism stays; using Neon's existing `Source` graph keeps
subscription teardown in the same lifecycle instead of adding a second teardown system.
Only changed matches notify their readers; all registered keys are still scanned.

Measured 2026-10-04 on source/test tree `86b7d472389eeac078219aa031a78bfd6466ede7`,
installed binary/support `7a4af78c9`, macOS on a shared machine:
- `msc test --target=js tests/core/selector.test.ms`: all 11 cases pass. The native command
  stops before runtime because std cannot hash `int32 | null`; no nullable case is skipped.
  Earlier, before the identity and nullable boundaries were added, the initial 9 cases passed
  C and JS on the same selector implementation. That is not a current full-native verdict.
- `msc run out/selectorConsumer.ms` and its `--target=js` run mounted 1000 actual JSX rows:
  first selection wrote one row class, moving 0 → 999 wrote two, disposal stopped writes.
- `msc run out/selectorIdentity.ms` and its `--target=js` run kept three equal-field objects
  distinct: moving to an unsubscribed object changed only the previously selected reader.
- `msc build --target=js out/selectorBrowser.ms` plus real Chromium showed 1000 DOM rows,
  row 0 then row 999 highlighted. Observed class mutations were only the leaving and entering
  rows on both moves, with no page errors. These throwaway consumers were removed afterwards.

Native acceptance is parked on
`~/metascript/.inbox/compiler/2026-10-04-nullable-primitive-map-key-has-no-native-hash.md`.
No full gate or land verdict; row 5 remains open until the original C/JS suite and land pass.

## Deliberately not taken

- `children()` / `Children.map` / `cloneElement` — the one-NeonNode arc (2026-09-19) settled that
  `children` is one `NeonNode`; inspecting or rewriting a child list is not a thing Neon does.
- `mergeProps` / `splitProps` — replaced by the compile-time spread-props contract: props are
  pure-JS objects and `{...props}` is resolved by type, not merged at runtime.

## Using this file

A row moves out of the table when its card's "Done when" holds on `main`; record the commit sha in
the card and delete the card. A row is never expanded here — if it needs a paragraph, it belongs in
the card.
