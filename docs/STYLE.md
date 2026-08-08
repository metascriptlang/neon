# Neon — Style System Design

**Status**: design settled 2026-07-27. **S1 landed 2026-07-27 (night)**; **S1b landed 2026-07-27
(late night)** — `createStyles` is a real macro (`src/macros/ui/style.ms`): it rewrites each sheet
entry into `styleOf(entry)` so the checker itself does jobs 1-2 of §4 — entry literals get the
excess-property check against `Style` (typo = checker error at the key) and sheet fields carry the
named `Style` type. **The hand-written `Sheet` interface is GONE** (`tests/render/style.test.ms` has
no annotation). Static-sheet guards: an entry that is not an object literal, or any style field whose
value is a call (sheet OR inline `style={{...}}`), is a compile error until S4. Needed one compiler
root fix (recompiler bug051): the macro round-trip dropped ObjectLiteral `keyLocations` and the
excess/duplicate-key diagnostics were location-gated → silently swallowed, dying later in C.
Value normalization (§4 job 3) waits for S2 paint; `@comptime` fold (§4 job 6) is deliberately NOT
done — see the §4 note. Projection caching (§5) not yet.

**Rule for this file** (same as `BUGS.md`): every compiler capability claimed in §7 is a MEASUREMENT
with the command that produced it. If you can't reproduce it, re-measure and rewrite the row — do
not layer a correction on top of a stale claim.

---

## 0. The bet

> **The author writes CSS-friendly text; the compiler emits native values; the runtime parses nothing.**

Today a style is a string (`"width:200;flexDirection:column"`) that every host re-parses at runtime —
`parseFlexStyle` splits on `;`/`:` and `styleEnum` does string comparisons **per element**. A typo is
silent. The target replaces that with a compile-time-normalized, statically-analyzable IR: colors
become `Color{r,g,b,a}`, enums become ordinals, and typos become compile errors — at **zero** runtime
cost.

---

## 1. The deciding constraint — Neon Studio

Style is not only a developer API. Per `docs/EDITOR.md`, the canvas edits **real source**: the editor
reads the AST and writes back the exact tag. That requirement, not the host, decides the design.

| Constraint from Studio | Rejected | Kept |
|---|---|---|
| Editor reads the **AST**, not runtime values | `style={computeStyle(x)}` as the normal form | static literals are the default form; a function is an explicit escape hatch |
| Editor must know **where a property came from** (shared sheet vs. local override) | `{...base, x}` spread — flattening **destroys provenance** (this reason is independent of the spread codegen bug, §7) | **array layering** `[s.box, {…}]` — layers stay distinguishable |
| Edit mode runs **Raiser**, ship runs **C/JS** — semantics must match | "macro emits host calls directly, no Style value at runtime" (cheapest, but unintrospectable) | **Style is a real runtime value** — introspectable, identical under both backends |

The third row is the important trade: we deliberately give up the theoretical minimum (no style object
at all) to keep the editor able to see what it is editing.

---

## 2. Authoring surface

```ts
const s = createStyles({
  btn: {
    padding: 8,
    backgroundColor: "#334",
    color: "#fff",
    variants: {
      size:  { sm: { padding: 6 }, lg: { padding: 12 } },
      state: { on: { backgroundColor: "#445" } },
    },
  },
  title: { fontSize: 18, color: "#fff" },
});

<button style={s.btn({ size: "lg", state: pressed() && "on" })}>+</button>
<div style={[s.btn, { width: w() }]}>…</div>
//            ↑ sheet entry   ↑ local override (Studio writes here on drag)
```

Two composition forms, both preserving provenance:

- **variants** — named groups selected by name. Borrowed from Unistyles 3.0 (§8); replaces the
  ad-hoc `hover:`/`ios:` nested blocks of an earlier draft.
- **array layering** — `[sheetEntry, override]`, later layer wins. This is the Figma model (shared
  style + instance override) and is what Neon Studio manipulates.

---

## 3. The Style IR

`Style` lives in the **render layer** and must **not** import Yoga, void, or any host type.

- **Flat**, one vocabulary: layout + paint + text + transform. No `ViewStyle`/`TextStyle` split.
  The Nim original (`src/core/style.nim`) and React Native both split; it is a known annoyance, and
  it is unnecessary here because each host projects the subset it understands anyway (§5).
- **`T | null` means unset.** Matches `yoga/src/style.ms:FlexStyle`. Do **not** wait for `Partial<T>`
  — it is not shipped (§7).
- **Dimensions are `number | string`** — bare number = points, `"50%"` = percent, `"auto"`. Same
  convention as `FlexStyle`, so the layout subset maps 1:1.
- **Colors are authored as strings** (`"#334"`) and normalized to a native color value by the macro.

---

## 4. What the macro does at compile time

`createStyles` is a **macro, not a function**. The reason is not aesthetics: `Partial<T>`, `Record<K,V>`
and mapped types are all marked *(planned)* in `recompiler/docs/LANG.md` — **the type-level route is
closed**, while metaprogramming is shipped. MetaScript substitutes macros for type-level programming.

Six jobs, all at expansion time:

1. **Validate property names** against `Style` → `widht: 200` is a compile error.
2. **Synthesize a named sheet type** so `s.titel` is a compile error with suggestions (§7 proves the
   diagnostic quality: *"Property 'titel' does not exist on type 'Sheet'. Available: box, title"*).
3. **Normalize values** — `"#334"` → color literal, `"column"` → enum ordinal. Runtime parses nothing.
4. **Split static from dynamic** — literal fields fold into a constant; fields whose value reads a
   signal become fine-grained effects (§6).
5. **Strip non-target platform blocks** — dead style data never reaches the binary.
6. **Fold the result with `@comptime`** so the sheet is a constant, not runtime construction.

> **S1b note on job 6 (measured decision):** the fold is deliberately NOT done. `@comptime` replaces
> the block with plain literals, and a plain object literal is ANON-typed — exactly the shape the
> repr gate rejects against `Style` (probe A's failure mode). Folding would therefore destroy the
> typing the styleOf rewrite exists to create. The sheet is a module-scope const: it is constructed
> once per program already, so the fold buys one-time init at the cost of the type system. Revisit
> only when `@comptime` propagates result types (planned compiler enhancement).

---

## 5. The host seam — `asX` protocol, not a Host method

Core defines `Style`. Each host declares the projection **in its own module**:

```
                     Style  (portable IR, knows no platform)
                       │
   ══════ asX convention-based dispatch — checker inserts the call ══════
        │                        │                         │
  void host module        terminal host module       browser host module
  asFlexStyle(this Style) asTerminalStyle(this …)     asCss(this Style)
        │                        │                         │
  layout → yoga applyStyle   color/bold only          real CSS classes
  color  → Node2D.color      (no flex at all)
  bg     → rect fill
```

Why this rather than adding `applyStyle(node, Style)` to the `Host` interface: the interface version
forces **every** host to implement it and forces core to anticipate the projection. The protocol
version is opt-in per host, keeps core blind to platforms, and gives N vocabularies × M hosts = **N+M**
— the same ladder `recompiler/docs/PROTOCOLS.md` already shipped for serialization.

> **CORRECTION (2026-07-28, S2).** The either/or above is wrong, and shipping it that way cost a
> segfault. `renderNode` is generic over `Host` — at that call site there is no static host type, so
> `asX` **cannot** dispatch. The two mechanisms are layers, not rivals:
> **`Host.setStyle` is the seam** (dynamic, one entry point the renderer can call) and
> **`asX` is the projection inside each host's `setStyle`** (`asFlexStyle` for void, `asTerminalStyle`
> for terminal, `applyCss` for browser). The §5 objection — "the interface version forces every host
> to implement it" — turned out to be the *feature*: S1 added `setStyle` to `Host`, terminal and
> browser silently didn't implement it, and MS had no conformance check, so the omission became a
> NULL function pointer (BUGS.md §5, 2026-07-28). The compiler now rejects a missing function-typed
> field, which is what makes this layering safe to rely on.

**Projection is cached per sheet entry.** A sheet entry is a constant, so each host projects it once
and reuses it across every element that references it.

---

## 6. Reactivity — static on the node, dynamic through effects

This mirrors a pattern `src/render/node.ms` already established: `text` (static) vs `dyn` (reactive
thunk). Style follows the same shape rather than introducing a new concept:

- static, merged, normalized sheet data → `VNode.style` constant
- a field reading a signal → one effect updating **exactly that property** on the host node

No re-render, no whole-style re-apply, no diffing.

### Design commitment: dependency detection must be semantic

The macro decides "is this field dynamic?" by asking the **checker** whether the expression reads a
signal — never by pattern-matching syntax. This is not a stylistic preference: it is the specific
failure mode Unistyles 3.0 ships with (§8), documented on their own *"Why my view doesn't update?"*
page — a Babel plugin outside the compiler must guess, and it guesses wrong on "custom syntax not
covered by the plugin". A macro inside the compiler knows.

---

## 7. Measured compiler facts (2026-07-27)

Each probe was built in its **own directory** — running them in parallel against a shared `/tmp/out`
produced a spurious `undefined symbol` from another probe's module. Same cache-collision trap
recorded in `BUGS.md` §1: isolate, or `rm -rf out` between runs.

| Capability | Result | Probe |
|---|---|---|
| **`asX` protocol dispatch** | ✅ printed `PROTO-DISPATCHED` | `useFlex(s)` where `s: Style`, `Flex` expected, with `function asFlex(this s: Style): Flex` in scope |
| **`@comptime` fold** | ✅ printed `COMPTIME-FOLDED` | `const SIZE = @comptime { return 4 * 1024; };` then `SIZE === 4096` |
| **Named-field sheet + suggestions** | ✅ `Property 'titel' does not exist on type 'Sheet'. Available: box, title` | `interface Sheet { box: Style; title: Style }`, then `styles.titel` |
| **Excess-property check on object literals** | ✅ `'widht' does not exist in type 'S'` | `const bad: S = { widht: 5.0 as float32 };` |
| **Missing field on `T \| null` interface** | ✅ accepted — absent field = unset | `const ok: S = { width: 5.0 as float32 };` with `height` omitted |
| **Object spread `{...base, x}`** | ❌ **C codegen bug** — checker passes, C fails: `no member named 'dotdotdot_' in 'struct Style'` | `const merged: Style = { ...base, height: 20.0 as float32 };` |
| `Partial<T>` / `Record<K,V>` / mapped types | ❌ not shipped — `LANG.md` marks them *(planned)* | — |
| JSX attribute carries an expression Node | ✅ per `LANG-JSX.md` — `jsxAttrValue` is a `Node`; `style={s.box}` already parses | `src/macros/ui/element.ms` classifies attrs since D2: string literal → `attr`, `on*` → `evt`, any other expr → `dynAttr` thunk |
| **Excess-property check through a macro-emitted call** (2026-07-27 late night) | ✅ since recompiler bug051 — `keyLocations` survive the macro round-trip, and the excess/duplicate diagnostics fall back to the literal's location instead of being swallowed. Pre-fix this died at the C layer (`no member named 'widht'`) | `probe/style_neg.ms` (deliberate-red), recompiler `src/test/fixedbugs/bug051.ms` |
| **Macro `error(msg, node)` diagnostics** | ✅ fires once, exact location, `Macro 'name':` prefix | `createStyles`/`element` static-style guards, `probe/style_neg.ms` |

The spread row is a genuine compiler bug and belongs in `BUGS.md` §2. It does **not** block S1; it
blocks the composition work in S3. Note that array layering was chosen over spread for provenance
(§1), so this bug is not the reason for that choice.

---

## 8. Prior art

| Source | What we take | What we reject |
|---|---|---|
| **Nim Neon** (`~/projects/neon/src/core/style.nim`) | the named-sheet idea; platform override blocks | `Table[string, NeonStyle]` built at **runtime**; `ViewStyle`/`TextStyle` split; `Option`/`some()` wrapping (MS uses `T \| null`) |
| **Unistyles 3.0** | **variants + compound variants**; breakpoints/media queries; a runtime object (`rt`: insets, dimensions, orientation, fontScale); web host emitting real CSS classes | its machinery — see below |
| React Native | array layering; `number \| string` dimensions | runtime array flattening; the style-type split |
| Solid.js | fine-grained per-property updates | whole-object recreation inside an effect |

**On Unistyles specifically** — it is the same architecture (compile-time analysis + fine-grained
native updates, no re-render), reached independently. The difference is substrate: it needs a **Babel
plugin** (JS has no macros), a **C++ core + Nitro + JSI on Fabric** (JS cannot touch the shadow tree
cheaply), and a **closed 16-entry dependency enum** (React has no signals). Neon gets all three from
the language and the existing reactive runtime, and additionally normalizes values at compile time —
Unistyles still parses colors and enums in C++ at runtime (its own claim is "<0.1 ms per StyleSheet",
i.e. > 0). "No re-render", their headline, is Neon's default.

---

## 9. Roadmap

Each stage ends green. TDD: red test first.

| Stage | Scope | Blocked by |
|---|---|---|
| **S1** | flat `Style`; minimal `createStyles` macro (validate names, synthesize sheet type, fold constant); `VNode.style`; void host `asFlexStyle` reusing `yoga applyStyle`. Keep the legacy string path working. | — |
| **S2** | paint + text: `backgroundColor` (void rect fill, terminal bg), text color/size. Cross-host test. | S1 |
| **S3** | array layering + variants; compile-time merge when all layers are static. | spread codegen bug (§7) once runtime merge is needed |
| **S4** | reactive style fields via the element macro's attribute classification (the Phase 2 debt — same feature); platform blocks; theme tokens. | S3 |

Deferred, in rough priority order: breakpoints/media queries, runtime object (`rt`), pseudo-states
beyond variants, animation (Nim had `AnimationDemo`), browser host emitting CSS classes.

---

## 10. Files this touches

| File | Change | Note |
|---|---|---|
| `src/macros/ui/style.ms` | the macro — real since S1b (styleOf rewrite + static-sheet guards) | |
| `src/render/style.ms` | **new** — the `Style` IR | must not import Yoga or any host |
| `src/render/node.ms` | add `style` field to `VNode` | ⚠ **sacred file** — API change, needs sign-off |
| `src/platform/void/host.ms` | add `asFlexStyle`; keep `parseFlexStyle` for the legacy string path | |
| `src/platform/terminal/host.ms` | add `asTerminalStyle` | S2 |
| `src/macros/ui/element.ms` | route `style={…}` to the typed channel | ⚠ sacred |
