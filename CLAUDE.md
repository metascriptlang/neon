# Neon - Cross-Platform UI Framework in MetaScript

**TypeScript Syntax + Compile-Time Macros + Fine-Grained Reactivity + Native Performance**

---

## Project Identity

**What**: Neon is a cross-platform reactive UI framework reimplemented in MetaScript (originally written in Nim)

**Target Platforms**:
- C backend → Desktop, iOS, Android, Terminal, IoT
- JavaScript backend → Browser (websites, web apps)

**Dual Purpose**:
1. **Production UI Framework**: React-like API + Solid.js reactivity for cross-platform development
2. **MetaScript Dogfooding**: Stress-test compiler, find edge cases, drive language evolution

**Why MetaScript over Nim**:
- **Co-Evolution**: Neon findings improve MetaScript, MetaScript improvements benefit Neon
- **TypeScript Syntax**: More approachable than Nim for web developers
- **Three Backends**: C (native), JS (browser), Erlang (distributed) - vs Nim's two

**Reference Architecture**: Original Neon (Nim) at `/Users/le/projects/neon`
- What we build next, in order: docs/ROADMAP.md
- Port status & MetaScript power map: docs/PORT-STATUS.md
- Original Nim reference: docs/nim.md
- MetaScript compiler docs (source of truth): /Users/le/metascript/recompiler/docs/
  - `LANG.md` — language reference
  - `LANG-METAPROGRAMMING.md` — macro model
  - `LANG-JSX.md` + `JSX-ROADMAP.md` — JSX
  - `PROTOCOLS.md` — convention-based dispatch

**Compiler**: `/Users/le/metascript/recompiler` (self-hosted, invoked via the `msc` CLI in `$PATH` — see Quick Reference)

---

## ⚠️ CRITICAL: Development Philosophy

**MetaScript is NOT stable** - This project requires disciplined, incremental development to succeed.

### The Golden Rule: TDD Development Cycle

**Test-Driven Development is MANDATORY**. Tests protect what we've built, keep it bulletproof, stable, and solid.

### The Three-Step Workflow

**ALWAYS follow this exact order:**

1. **Make it work/visible** - Get something running and see-able first
   - Focus on making the behavior reproducible and visible
   - Don't solve problems you can't see yet
   - Output/logging is your friend - make everything observable

2. **Make it right** - Ensure it does what we expect
   - Verify correctness through tests
   - Match the intended behavior from requirements
   - Fix bugs and edge cases

3. **Make it solid** - Production-level quality
   - Refine to world-class standards
   - Optimize performance
   - Polish developer experience

**DO NOT skip steps or work out of order.**

### Prioritize Small, Solid Progress

- **Small wins over massive incomplete work**: Ship incremental features that actually work
- **Visible progress over invisible effort**: If you can't see it, it doesn't count yet
- **Connected to real output**: Everything should tie to something runnable/testable

### A MetaScript limitation is a compiler card, not a workaround

It follows the workspace compiler boundary (`~/metascript/CLAUDE.md`): repro, card, park, move on.

### Practical Implications

**Before writing ANY code:**
- [ ] Do I have a test that will verify this works?
- [ ] Can I see/observe the output of this change?
- [ ] Is this the smallest increment that produces visible progress?

**When stuck:**
- [ ] Is the problem visible and reproducible?
- [ ] Have I written a failing test that demonstrates it?

**Remember**: Slow and solid beats fast and broken. Every line of code should be tested, visible, and built on a stable foundation.

---

## Git — one worktree per arc, `/split-commit`, fast-forward land

Neon holds the workspace rules with plain git. It has no `wt.sh`, no `gate.sh` and no land script, and does not need one.

- **One worktree per feature or named arc**, reused by every session of that arc. It sits BESIDE this checkout, because Neon imports `../void` and `../yoga` by relative path:
  `git worktree add -b wt/<name> ../neon-wt-<name> main`, then inside it `mkdir deps && ln -s ../../yoga/deps/yoga deps/yoga`.
  Sequential steps of one arc are commits in that worktree, never new worktrees.
- **The arc's goal lives in its card, `~/metascript/.wt/<name>.md`** — one card folder for the whole workspace, outside every checkout. It holds the Goal, a "Done when" a session can run, and a State of a few lines naming the step in flight. Memory points at the card and never copies its state; the card is deleted once "Done when" holds on `main`.
- **Commit in the worktree through `/split-commit`**, without asking. A session ends with its work committed and the card's State current.
- **The gate is `bash tests/run.sh`, read by its exit code.** A commit runs the test files of the module it touches plus their importers; the full gate runs before a land that changes `src/` or a shared contract. One `msc` per directory at a time.
- **Land a slice as soon as it stands alone**: `git rebase main` in the worktree, gate, then `git -C ~/metascript/neon merge --ff-only wt/<name>`. Git refuses the merge when it touches a path the main checkout holds uncommitted work on — leave that refusal alone and report it.
- **The main checkout only receives lands.** Never push without asking.
- **A worktree is removed from outside its own session**: check it holds no dirty file and no commit missing from `main`, `unlink deps/yoga`, `git worktree remove <path>`, `git branch -d wt/<name>`.

---

## Quick Reference

### Development Commands

Neon builds and tests run through the installed `msc` (workspace `CLAUDE.md`, Toolchain); it typechecks and does real C/JS codegen.

```bash
msc test tests/core/signal.test.ms           # single test file
msc test tests/render/reconcile.test.ms

# Run Neon examples / smoke runs
msc run examples/counter.ms                  # build native + run
msc build examples/counter.ms                # build native binary (no run)

# Do NOT `rm -rf out` by default: the object cache is fingerprint-keyed and correct;
# wiping it makes every suite cold for minutes.
```

### File Structure

```
neon/
├── CLAUDE.md              # This file - AI assistant guide
├── docs/
│   ├── nim.md             # Original Neon (Nim) reference
│   ├── metascript.md      # Pointer to MetaScript compiler docs
│   ├── PORT-STATUS.md     # Port status + MetaScript power map (LIVE)
│   ├── RENDER-LAYERS.md   # 3-layer render model (A reconcile / B paint / C GPU) — Neon × Void × platform
│   └── COLLAB.md          # Collaboration model (CRDT + AST + Git)
│
├── src/
│   ├── index.ms           # Framework entry point
│   │
│   ├── core/              # Reactive runtime (✓ ported)
│   │   ├── signal.ms      # Signal[T] - reactive state
│   │   ├── effect.ms      # createEffect - side effects
│   │   ├── memo.ms        # createMemo - cached computation
│   │   ├── owner.ms       # Owner hierarchy for cleanup
│   │   ├── runtime.ms     # Reactive runtime (batching, scheduling)
│   │   ├── cleanup.ms     # onCleanup - disposal
│   │   ├── array.ms       # Keyed list helpers
│   │   └── types.ms       # Core reactive types
│   │
│   ├── render/            # Renderer-agnostic layer (✓ ported, NOT in Nim original)
│   │   ├── node.ms        # VNode / element construction
│   │   ├── host.ms        # Host operations contract
│   │   ├── hostTypes.ms   # Host-facing type surface
│   │   ├── reconcile.ms   # Reconciler
│   │   ├── component.ms   # createComponent seam
│   │   ├── context.ms     # createContext / useContext
│   │   ├── event.ms       # NeonEvent construction
│   │   ├── template.ms    # Template cloning
│   │   ├── style.ms       # Style merge + resolution
│   │   ├── css.ms         # CSS text generation
│   │   └── sheet.ms       # Stylesheet registry
│   │
│   ├── macros/            # Compile-time transformations
│   │   └── ui/
│   │       ├── element.ms  # element macro - JSX → VNode tree (sacred)
│   │       ├── direct.ms   # direct-emission macro
│   │       ├── flow.ms     # Show / For control flow
│   │       ├── reactive.ms # reactive-expression detection
│   │       ├── style.ms    # createStyles macro
│   │       └── theme.ms    # createTheme / setTheme macros
│   │
│   ├── components/        # The vocabulary users write
│   │   └── primitives.ms  # View / Text / TextInput / Pressable
│   │
│   └── platform/          # Platform-specific renderers
│       ├── types.ms       # Cross-platform Element interface
│       ├── browser/
│       │   └── dom.ms     # DOM rendering (JS backend)
│       ├── terminal/      # host.ms · paint.ms · types.ms
│       └── void/
│           └── host.ms    # Void scene graph + yoga flexbox
│       # TODO: ios/, android/ — gate with `when (ios)`, NOT blocked
│
├── examples/              # Usage examples
│   ├── components/        # Demo components (counter.ms, todoList.ms)
│   ├── counter.ms         # Basic reactivity
│   ├── counterDom.ms      # Counter via DOM
│   ├── signalApi.ms       # Signal API demo
│   ├── reactivityTest.ms
│   ├── showcaseDom.ms
│   └── closureReassign.ms
│
├── tests/                 # Test suite — mirrors src/
│   ├── core/              # Reactive system tests (4 files)
│   ├── render/            # Render / reconcile / macro tests (18 files)
│   ├── style/             # Style, variants and theme tests (10 files)
│   ├── platform/          # terminal.test.ms · void.test.ms
│   └── run.sh             # Full gate: every test native, then --target=js
│
└── build/                 # Generated artifacts
```

---

## Table of Contents

**Essential Reading**:
- [CRITICAL: Development Philosophy](#️-critical-development-philosophy) - Must-read methodology
- [Git](#git--one-worktree-per-arc-split-commit-fast-forward-land) - Worktree, card, commit, land
- [Sacred Files](#sacred-files-do-not-modify-api) - API protection policy
- [Quick Reference](#quick-reference) - Commands and structure

**Development Guides**:
- [Reference Architecture](#reference-architecture-nim--metascript) - Nim vs MetaScript comparison
- [Development Workflow](#development-workflow) - Phase 1-4 implementation plan
- [Compiler Co-Evolution](#compiler-co-evolution-strategy) - MetaScript integration
- [Testing Strategy](#testing-strategy) - Test pyramid and coverage
- [Key Principles](#key-principles) - Framework design philosophy

**Practical Guides**:
- [Common Tasks](#common-tasks) - How-to recipes
- [Troubleshooting](#troubleshooting) - Problem diagnosis
- [Success Metrics](#success-metrics) - Phase completion criteria
- [Resources](#resources) - External references

---

## Sacred Files (DO NOT MODIFY API)

| File | Reason | Breaking Change Impact |
|------|--------|------------------------|
| `src/core/signal.ms` | Reactive core API | Affects all reactivity |
| `src/macros/ui/element.ms` | UI DSL macro (JSX → VNode) | Changes framework API |
| `src/render/node.ms` | VNode construction contract | Affects every renderer |

**Decision Tree**:
```
Making changes?
├── Core (signal.ms, effect.ms) → ASK FIRST, test ALL platforms
├── Macros (element.ms) → Verify tests/render/element.test.ms still works
├── Platform-specific → Test on actual devices
└── Examples/Docs → Safe to modify
```

---

## Reference Architecture (Nim → MetaScript)

### Original Neon (Nim)

```nim
# Nim syntax with templates/macros
let (count, setCount) = createSignal(0)

element:
  View(style = styles.container):
    Text: proc(): string = $count()
    Button(onPress = proc() = setCount(count() + 1)):
      Text: "+"
```

### Neon-MetaScript (This Project)

```typescript
// MetaScript syntax with @macros
const [count, setCount] = createSignal(0);

element:
  View(style = styles.container):
    Text: () => count.toString()
    Button(onPress = () => setCount(count() + 1)):
      Text: "+"
```

**Mapping**:

| Concept | Nim (Original) | MetaScript (This) |
|---------|----------------|-------------------|
| **Signals** | `proc createSignal[T](val: T)` | `createSignal<T>(value): [Accessor<T>, (v: T) => void]` |
| **Effects** | `proc createEffect(f: proc())` | `function createEffect(f: () => void)` |
| **UI DSL** | `macro element(body: untyped)` | `macro element(body: ASTNode)` |
| **C FFI** | `proc {.importc.}` | `extern function` |
| **Compilation** | Nim → C → Binary | MetaScript → C → Binary |

---

## Development Workflow

See `docs/PORT-STATUS.md` for the live, detailed port status + module mapping. Summary below.

### Phase 1: Reactive Core ✅ DONE

**Goal**: Solid.js-style reactivity in MetaScript — signal/effect/memo/owner/cleanup/runtime.

**Delivered**: `src/core/{signal,effect,memo,owner,cleanup,runtime,array,types}.ms` + 4 test files in `tests/core/`. Render layer (`src/render/{host,node,reconcile}.ms`) was added beyond the Nim original — cleaner architecture.

### Phase 2: UI Macro System ✅ PARTIAL

**Goal**: Compile-time DSL transformation via JSX + macros.

**Delivered**: `src/macros/ui/element.ms` (JSX → VNode tree) + `flow.ms` (Show/For). `style.ms` is a stub.

**Remaining**: component macro (function components), createStyles macro, full attribute classification (animatable/events/static).

### Phase 3: Platform Backends — IN PROGRESS

**Goal**: Renderers for each platform.

**Delivered**: `src/platform/browser/dom.ms` (partial DOM, JS backend), `src/platform/terminal/`
(host + paint, green), `src/platform/void/host.ms` (Node2D scene graph + yoga flexbox + hit-testing,
green). Yoga is DONE — the binding lives in its own repo (`~/metascript/yoga`) and `deps/yoga`
symlinks a real checkout; Neon carries no `src/yoga/` of its own.

**NOT blocked.** Both the OS axis and the backend axis are `when` blocks (msc >= 0.2.42;
`@platform`/`@target` were retired 2026-08-09 and now raise an error):

```typescript
when (macos) { @passL("-framework Metal"); @compile("./bridgeEmbed.m"); }
when (js)    { /* browser-only code — never type-checked on a C build */ }
```

void ships macos/ios/android that way (`void/src/sokol/gpu.ms`) by gating
`@compile`/`@passC`/`@passL`/`@link` around ONE backend-agnostic extern surface — copy that shape.
Unlike the old `@platform`, `when` gates arbitrary code, not just directives: a dropped branch is
never type-checked, so it may call APIs that do not exist on the other target. Flags come from the
define table (`msc --help-defines`): backend `c`/`js`, OS `macos`/`ios`/`android`/…, `debug`/
`release`/`danger`, plus anything passed as `-d:name[=value]`.

**Remaining**: iOS host, Android host.

---

## What Neon Tests About MetaScript

| Neon Feature | MetaScript Stress Test |
|--------------|------------------------|
| **Reactive signals** | Generic classes, closures, effect tracking |
| **UI macros** | Complex AST transformations, multi-pass expansion |
| **Cross-platform** | C FFI, conditional compilation, multi-backend |
| **Performance** | Zero-cost abstractions, inline expansion |
| **Type safety** | Generics, type inference, ownership tracking |

---

## Testing Strategy

### Test Pyramid

```
         ┌──────────────────┐
         │  Integration     │  20% - Full platform tests
         │  (iOS/Android)   │
         ├──────────────────┤
         │   Macro Tests    │  30% - DSL transformation correctness
         ├──────────────────┤
         │   Unit Tests     │  50% - Reactive core, individual functions
         └──────────────────┘
```

### Unit Tests (Core Reactivity)

```bash
# Test signals, effects, memos
msc test tests/core/signal.test.ms
msc test tests/core/memo.test.ms
msc test tests/core/dispose.test.ms
msc test tests/core/array.test.ms
```

**Coverage**: 90%+ for core reactive system

### Macro & Render Tests

```bash
# Test JSX → VNode macro expansion + reconciler
msc test tests/render/element.test.ms
msc test tests/render/reconcile.test.ms
msc test tests/render/reconcileHard.test.ms
msc test tests/render/flow.test.ms
msc test tests/render/counter.test.ms
msc test tests/render/renderToString.test.ms
```

**Coverage**: 85%+ for macro correctness

### Integration Tests (Platform)

```bash
# Browser (JS backend)
msc build examples/counterDom.ms

# Terminal + Void hosts ship today — see tests/platform/terminal + tests/platform/void
# iOS / Android — TODO, and NOT compiler-blocked: use `when (ios)`, as void/src/sokol/gpu.ms does
```

**Coverage**: Smoke tests for each platform

### Pre-Commit Checklist

- [ ] All core tests pass: `msc test tests/core/*.test.ms`
- [ ] All render tests pass: `msc test tests/render/*.test.ms`
- [ ] No regressions: `msc run examples/counter.ms` runs clean
- [ ] Documentation updated if API changed
- [ ] No MetaScript compiler crashes

---

## Key Principles

### 1. Compile-Time First

**Prefer compile-time** over runtime for everything possible:
- UI structure: Macro expansion, not runtime VDOM
- Style composition: Compile-time merging
- Type validation: Static type checking
- Optimization: Macro-driven inlining

### 2. Platform Neutral Core

**Keep platform-specific code isolated**:
```
src/core/        ← Platform-agnostic (signals, effects)
src/macros/      ← Platform-agnostic (DSL transformation)
src/platform/    ← Platform-specific (UIKit, DOM, etc.)
```

### 3. Type Safety Everywhere

**Leverage MetaScript's type system**:
- No `any` types (use `unknown` with narrowing)
- Generic components: `Component<Props>`
- Ownership tracking: `Owned<T>` / `Borrowed<T>`

### 4. Reactivity as First Class

**Everything is reactive by default**:
- Props are signals
- State is signals
- Derived values are memos
- Side effects are effects

### 5. Zero-Cost Abstractions

**No runtime overhead**:
- Macros expand to direct calls
- Signals compile to plain values when static
- Effects inline when possible

---

## Common Tasks

### Add a New Component

```bash
# 1. Create component file under src/components/
touch src/components/MyComponent.ms

# 2. Implement with JSX + element macro (see src/macros/ui/element.ms for the contract)
#    Reference: examples/counter.ms and tests/render/counter.test.ms

# 3. Test it
msc run examples/use-component.ms
```

### Add Platform Support

```bash
# 1. Create platform directory under src/platform/
mkdir -p src/platform/myplatform

# 2. Implement Element interface (see src/platform/types.ms)
touch src/platform/myplatform/renderer.ms

# 3. Add extern bindings for platform APIs (see src/platform/browser/dom.ms as reference)

# 4. Test on actual platform
msc build examples/counter-myplatform.ms
```

### Debug Macro Expansion

MetaScript does not currently have a `msc expand` CLI. To inspect macro output:

1. Write a minimal test in `tests/render/` that exercises the macro.
2. Add `console.log`/`assert` on the produced VNode tree (see `tests/render/element.test.ms`).
3. Run: `msc test tests/render/element.test.ms`.

### Profile Performance

```bash
# Compile to C with profiling flags (add via @passC in source)
msc build examples/counter.ms

# Run the produced binary
./build/c/counter
```

---

## Troubleshooting

### Macro Expansion Doesn't Work as Expected

**Symptom**: Generated code is wrong

**Steps**:
1. Add `console.log`/`assert` on the produced VNode tree (no `msc expand` CLI yet)
2. Check macro implementation in `src/macros/ui/element.ms`
3. Add test case in `tests/render/element.test.ms`
4. Fix macro logic
5. Verify all existing tests still pass

### Platform-Specific Rendering Issue

**Symptom**: Works in browser but not iOS

**Steps**:
1. Check platform implementation: `src/platform/ios/uikit.ms` (TODO — not yet ported)
2. Verify extern bindings are correct
3. Test C FFI separately (simple test program)
4. Add platform-specific test in `tests/platform/ios.test.ms`

### Reactivity Not Updating

**Symptom**: UI doesn't update when signal changes

**Steps**:
1. Verify signal is actually changing: Add `console.log(count())`
2. Check effect is created: Search for `createEffect` in generated code
3. Test reactive core in isolation: `tests/core/signal.test.ms`
4. Ensure macro wrapped reactive expression in effect

---

## Success Metrics

### Phase 1 Complete ✅:
- [x] Signals work: get/set with dependency tracking
- [x] Effects work: auto-run on dependency changes
- [x] Memos work: cached computations, lazy re-evaluation
- [x] Tests pass: 90%+ coverage of core reactivity

### Phase 2 Partial ✅:
- [x] `element` macro transforms JSX to VNode tree
- [x] `flow.ms` (Show/For) works
- [ ] `createStyles` macro generates style objects (style.ms is a stub)
- [ ] Component macro (function components)
- [ ] Full attribute classification (animatable/events/static)

### Phase 3 Complete When:
- [ ] iOS backend renders native UIKit views
- [ ] Android backend renders native Android Views
- [ ] Browser backend renders HTML/DOM
- [ ] Terminal backend renders TUI
- [ ] Yoga layout works on all platforms

### Project Success When:
- [ ] Same codebase compiles to all platforms
- [ ] Performance: 90%+ of hand-written native code
- [ ] Developer experience: TypeScript familiarity
- [ ] MetaScript compiler improved from Neon feedback
- [ ] Production apps shipped using Neon-MetaScript

---

## Resources

**Reference Projects**:
- Original Neon (Nim): `/Users/le/projects/neon`
- MetaScript Compiler: `/Users/le/metascript/recompiler`
- Solid.js (reactivity inspiration): https://solidjs.com
- Yoga (layout engine): https://yogalayout.com

**Documentation**:
- Roadmap (what's next, in order): docs/ROADMAP.md
- Port status + MetaScript power map: docs/PORT-STATUS.md
- Original Neon (Nim) reference: docs/nim.md
- Collaboration model: docs/COLLAB.md
- MetaScript compiler docs: `/Users/le/metascript/recompiler/docs/`

**MetaScript Compiler**:
- Source: `/Users/le/metascript/recompiler/src`
- Tests: integrated in `src/index.ms` (`msc test src/index.ms`)
- Build: `msc build src/index.ms --gc=drc --danger --cc=clang --output=msc` (no `rm -rf out`)

---

**North Star**: Cross-platform UI framework with TypeScript syntax, compile-time metaprogramming, and native performance - while dogfooding MetaScript to make both projects production-ready.
