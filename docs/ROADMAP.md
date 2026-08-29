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

**1. A token cannot be unitless — the unit belongs to the PROPERTY, not to the token.** A bare number
always gets `px`, so `opacity: theme.o5` spells `0.5px`, which is invalid CSS: the browser drops the
declaration silently and the element renders fully opaque. Design settled 2026-08-30 by measurement:
`:root` holds the RAW value and `createStyles` applies the unit at the use site, because the use site
is the only place that knows the property. To choose between `calc(var(--x) * 1px)` and a bare
`var(--x)` the macro must know whether the token is a number or a string, which it can read from the
type — but only when `theme` is a real const, so the arrow marker goes away and recognition moves to
a type brand (`themeOf` returns `Theme<T>`, `type Theme<T> = T`).

```
today         theme.sp2 → var(--sp2)         :root{--sp2:8px}      ← unit baked at DECL
              theme.o5  → var(--o5)          :root{--o5:0.5px}     ← invalid for opacity

target        createStyles({ card: { padding: theme.sp2, opacity: theme.o5, width: theme.w } })
              :root{ --sp2:8; --o5:0.5; --w:50% }                  ← raw, one form per token
              padding: calc(var(--sp2) * 1px)   number + sized property
              opacity: var(--o5)                unitless property
              width:   var(--w)                 string token, never calc-wrapped
```

Every branch is decided at expansion — no runtime `typeof`, nothing extra baked into the theme.
`deg`/`ms` later cost one more unit string. Three alternatives were measured and rejected, do not
re-open them: **token categories** (Panda's answer — forces a nested theme and still breaks when one
token feeds both `padding` and `opacity`); **two baked forms** (`--x` plus a raw `--x-n` — duplicates
in the theme what the use site already knows); **runtime `typeof` at sheet init** (works, but defers a
compile-time fact to run time, against this repo's first principle).

Compiler dependency, partly paid: a generic alias instantiation used to carry no identity and never
peel — recompiler `b3907f8`+`d936a21`+`0898b5b` closed 5 of 7 measured cells (Nim parity:
`typeof(v)` on `type Brand[T] = T` prints `Brand[t.Pt]`, so an alias keeps its name for inspection
while staying structurally transparent). Still open: the call-site instantiation names the instance
after the alias BODY, so a macro reads `T` where it needs `Theme`. Two red facets and the
truncated-battery caveat are rows in `BUGS.md` §2.

**2. Runtime theme switching.** The static half landed: `createTheme` bakes one `:root` rule and
`createStyles` spells `var(--token)`. Switching is the half that makes it a feature.

```
setTheme(dark)  →  web:    replace the one :root rule by key, no re-render
                →  native: one signal per token; S4a already emits exactly one
                           effect per dynamic style field
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
