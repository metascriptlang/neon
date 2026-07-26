# MetaScript — Reference Pointer

**Last Updated**: 2026-07-06

MetaScript is a systems programming language with TypeScript syntax that compiles to C, JavaScript, and Erlang. Neon is built on it and dogfoods the compiler.

**The canonical, up-to-date MetaScript documentation lives in the compiler repo**, not here. Anything below this section is a navigation aid, not a copy.

---

## Source of Truth

`/Users/le/metascript/recompiler/docs/` — open these directly. They are kept in sync with the actual compiler.

### Core

| Doc | What it covers |
|---|---|
| `LANG.md` | Full language reference: types, operators, declarations, control flow, type system, strings, collections, memory, async, actors, decorators, testing |
| `LANG-STRUCT.md` | `struct` value types, parameter passing ABI |
| `LANG-PRIMITIVE.md` | Primitive types & sizing |
| `LANG-MOVE.md` | Move semantics, ownership transfer |
| `LANG-ASYNC.md` | `Promise<T>`, `Promise<Result<T,E>>`, spawn, AbortController |
| `LANG-RUNTIME.md` | Runtime primitives |
| `LANG-PRELUDE.md` | Built-in prelude |
| `LANG-BUILD.md` | Build system |
| `LANG-INTERLOP.md` | C/JS interop |
| `LANG-RAW.md` | Raw escape hatches |
| `LANG-TEST.md` | `test` / `assert` / power assert |
| `LANG-MORPH.md` | Codegen transforms |

### Metaprogramming (critical for Neon)

| Doc | Why Neon cares |
|---|---|
| `LANG-METAPROGRAMMING.md` | Macro model — `Node` is compile-time only; macros consume JSX / `quote` / `createNode` and return runtime AST. Phase A/B/C/D/E done, Phase F (`@target` expansion) TODO. |
| `LANG-JSX.md` + `JSX-ROADMAP.md` | JSX spec + per-phase status. Neon's `element` macro consumes JSX. |
| `PROTOCOLS.md` | Convention-based dispatch (`getDynamicField`, `asString`, `toItems`) — for dynamic props, style serialization. |

### Other

| Doc | Notes |
|---|---|
| `FEATURES.md` | Feature matrix overview |
| `NIM-REF.md` | Nim → MetaScript mapping (useful when porting) |
| `DIAGNOSTICS.md` | Error reporting |
| `LSP.md` | Language server |
| `FMT.md` | Code formatter |
| `JSON.md` | Typed JSON parsing |
| `SERIALIZE.md` | Serialization layer |
| `ORC.md` | Memory management (DRC) |
| `PARALOCK.md` | Spawn / actor safety rules |
| `PIPELINE.md` | Compiler pipeline |
| `TRANSFORM.md` | Transform passes |
| `PACKAGE.md` | Package manager |
| `BUILD-CACHE.md`, `BUILD-PERF.md` | Build performance |

---

## Neon-specific MetaScript usage

See **`docs/PORT-STATUS.md`** for:

- Which MetaScript features the port currently uses (JSX, macros, extension methods)
- Which features are queued for adoption (struct, discriminated union, `Promise<Result>`, actor, `@derive(Hash)`)
- Compiler caveats affecting Neon (macro expansion v1 limits, `@target` not yet expanded)
