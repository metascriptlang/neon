# Neon — Roadmap

What we build next, in order, and why that order. **Forward-looking only.**

| doc | owns |
|---|---|
| this file | the order of work across the whole framework |
| `docs/STYLE.md` §9 | the style/theme stages (S1-S4) in detail |
| `docs/RENDER-MODEL.md` | the two emission tiers and the lifecycle |
| `docs/PORT-STATUS.md` | the Nim → MetaScript module map, and history |
| `BUGS.md` | every open bug, compiler or framework |

**Rule for this file** (same as `BUGS.md` and `STYLE.md`): a row moves to *done* only with the
command that proved it. Never layer a correction on a stale row — rewrite the row.

---

## Now

**1. Token categories — a token cannot be unitless.** A bare number always gets `px`, so
`opacity: theme.o5` spells `0.5px` and `flex: theme.f1` spells `1px`. This is a hole inside the code
that landed on 2026-08-29, it is cheap, and it has a red test in one line. Do it before anything
builds on tokens.

**2. Runtime theme switching.** The static half landed: `createTheme` bakes one `:root` rule and
`createStyles(theme => …)` spells `var(--token)`. Switching is the half that makes it a feature.

```
landed        theme.sp2  →  var(--sp2)        :root{--sp2:8px}
  1.          opacity: theme.o5  →  0.5px     ← wrong, fix first
  2.          setTheme(dark)     →  rewrite :root, web repaints with no re-render
                                 →  native: one signal per token, the S4a dynamic-field
                                    path already carries it
```

Web is nearly free (one rule replaced by key — `registerCss` already replaces by key). Native is the
real design question: a token becomes a signal, and every style field reading it becomes a dynamic
field. S4a already emits exactly one effect per dynamic field, so the mechanism exists.

---

## Next

| # | work | state | size |
|---|---|---|---|
| 3 | `variants` — the caller picks at the use site (`when` is for what the environment picks) | designed in `STYLE.md` §2, not implemented | medium |
| 4 | sheet lifecycle: `mountSheet` for SSR, and `flushSheet` rewriting the whole `<style>` on every flush | `src/render/sheet.ms` | small |
| 5 | direct emission D5 — the per-target switch in `build.ms` plus a benchmark against the tree tier | D1-D4 landed; `build.ms` has no switch yet | medium |
| 6 | iOS host | `src/platform/ios/` empty | large |
| 7 | Android host | `src/platform/android/` empty | large |

**Not blocked on the compiler.** iOS/Android gate with `when (ios) { … }` around
`@compile`/`@passC`/`@passL`/`@link` over one backend-agnostic extern surface — the shape
`void/src/sokol/gpu.ms` already ships. An untaken `when` branch is never type-checked, so it may call
APIs that do not exist on the other target.

---

## Later

In rough priority order, once the above is standing:

- breakpoints / media queries, and the runtime object (`rt`: insets, dimensions, orientation)
- pseudo-states beyond variants — hover/focus join `when`, not a separate `states:` block
- animation — the largest single module in the Nim original (~2055 LOC), deliberately last
- from the Nim original and not yet ported: `resource` / `http` / `async` (the MS idiom is
  `Promise<Result<T,E>>` + `try await`, not a port of the Nim shape), `error_boundary`, `config`
- `tests/macros/` and `tests/integration/` are empty directories

---

## Not our queue

Red results on the **JS lane are pre-existing** and belong to the compiler, not to Neon: value-copy
treats `fn | null` as a struct, so a copied callback becomes a non-function. A parallel session has
the fix staged. Measure the lane against the per-file baseline in `BUGS.md` before attributing a red
to new Neon work.
