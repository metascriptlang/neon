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

**Entry fields.** Verdict · Solid / React / RN (file:line and symbol, at the commits above) · MS
(symbol and path) · Why · Don't (a wrong turn already taken) · Pin (tests that go red) · Checked
(date; read or measured).

**Verdicts.** `DIVERGE-INTENTIONAL`: Neon has its own mechanism or surface where Solid has one.
`FOLLOWS-RN`: Solid's surface is replaced by React Native's.

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
