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
- **Compiler Control**: We own MetaScript - can fix compiler bugs immediately
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

### MetaScript is Your Best Friend, NOT Enemy

**CRITICAL POLICY: NEVER WORKAROUND COMPILER LIMITATIONS**

When you hit a MetaScript limitation:

1. **IMMEDIATELY STOP** current work
2. **Switch to MetaScript project** at /Users/le/metascript/recompiler
3. **Fix the compiler** to support what Neon needs
4. **Return to Neon** with solid compiler support
5. **Continue with confidence** - no hacks, no workarounds

**Why?**
- We own MetaScript - we can fix it immediately
- Workarounds create technical debt and hide real issues
- Compiler improvements benefit all future MetaScript projects
- Clean code > clever hacks

**MetaScript wants to help** - ask it for whatever capabilities you need. If it can't do something, that's a feature request, not a limitation to work around.

### Practical Implications

**Before writing ANY code:**
- [ ] Do I have a test that will verify this works?
- [ ] Can I see/observe the output of this change?
- [ ] Is this the smallest increment that produces visible progress?
- [ ] Am I tempted to workaround a compiler issue? (If yes → fix compiler first)

**When stuck:**
- [ ] Is the problem visible and reproducible?
- [ ] Have I written a failing test that demonstrates it?
- [ ] Is this a MetaScript limitation? (If yes → fix compiler, don't workaround)

**Remember**: Slow and solid beats fast and broken. Every line of code should be tested, visible, and built on a stable foundation.

---

## Quick Reference

### Development Commands

Neon builds and tests run directly via the self-hosted `msc` CLI (installed in `$PATH` at `~/.metascript/bin/msc`). No Bun, no `bun run` — `msc` is the ground truth: it typechecks AND does real C/JS codegen, so it catches bugs the old transpile-only Bun path hid.

```bash
# Build the MetaScript compiler (only when compiler source changed)
cd /Users/le/metascript/recompiler
rm -rf out && msc test src/index.ms          # full compiler test suite

# Run Neon tests (self-hosted msc — real codegen, no false-green)
cd /Users/le/metascript/neon
msc test tests/core/signal.test.ms           # single test file
msc test tests/render/reconcile.test.ms

# Run Neon examples / smoke runs
msc run examples/counter.ms                  # build native + run
msc build examples/counter.ms                # build native binary (no run)

# Tip: always `rm -rf out` before a fresh compiler build — stale artifacts cause false passes.
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
│   │   └── reconcile.ms   # Reconciler
│   │
│   ├── macros/            # Compile-time transformations (partial)
│   │   └── ui/
│   │       ├── element.ms # element macro - JSX → VNode tree (sacred)
│   │       ├── flow.ms    # Show / For control flow
│   │       └── style.ms   # createStyles macro (stub)
│   │
│   ├── platform/          # Platform-specific renderers
│   │   ├── types.ms       # Cross-platform Element interface
│   │   └── browser/
│   │       └── dom.ms     # DOM rendering (JS backend, partial)
│   │   # TODO: ios/, android/, terminal/
│   │
│   └── yoga/              # Flexbox layout (empty — TODO)
│   └── starter/           # Example components (empty — TODO)
│
├── examples/              # Usage examples
│   ├── counter.ms         # Basic reactivity
│   ├── counterDom.ms      # Counter via DOM
│   ├── signalApi.ms       # Signal API demo
│   ├── reactivityTest.ms
│   ├── showcaseDom.ms
│   └── closureReassign.ms
│
├── tests/                 # Test suite
│   ├── core/              # Reactive system tests
│   │   ├── signal.test.ms
│   │   ├── memo.test.ms
│   │   ├── dispose.test.ms
│   │   └── array.test.ms
│   └── render/            # Render/reconcile/macro tests
│       ├── reconcile.test.ms
│       ├── reconcileHard.test.ms
│       ├── host.test.ms
│       ├── hostOps.test.ms
│       ├── flow.test.ms
│       ├── element.test.ms
│       ├── region.test.ms
│       ├── counter.test.ms
│       └── renderToString.test.ms
│
└── build/                 # Generated artifacts
```

---

## Table of Contents

**Essential Reading**:
- [CRITICAL: Development Philosophy](#️-critical-development-philosophy) - Must-read methodology
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
signal count = 0;

element:
  View(style = styles.container):
    Text: () => count.toString()
    Button(onPress = () => count.set(count() + 1)):
      Text: "+"
```

**Mapping**:

| Concept | Nim (Original) | MetaScript (This) |
|---------|----------------|-------------------|
| **Signals** | `proc createSignal[T](val: T)` | `macro signal<T>(name, value)` |
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
symlinks a real checkout; `src/yoga/` here is a vestigial empty dir, not a TODO.

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

### Phase 4: Compiler Co-Evolution (Ongoing)

**Goal**: Find and fix MetaScript compiler issues.

```bash
# When you hit a compiler bug:
cd /Users/le/metascript/recompiler
# Fix the compiler (TDD: write failing test first)
rm -rf out && msc test src/index.ms

# Verify fix in Neon
cd /Users/le/metascript/neon
msc test tests/core/signal.test.ms
```

**Feedback Loop**:
1. Neon implementation hits compiler edge case
2. **STOP Neon work immediately**
3. Switch to MetaScript project
4. Write failing compiler test demonstrating the issue
5. Fix MetaScript compiler with proper solution
6. Verify fix with test suite
7. Return to Neon and continue with solid compiler support
8. Both projects improve - no technical debt created

---

## Compiler Co-Evolution Strategy

### What Neon Tests About MetaScript

| Neon Feature | MetaScript Stress Test |
|--------------|------------------------|
| **Reactive signals** | Generic classes, closures, effect tracking |
| **UI macros** | Complex AST transformations, multi-pass expansion |
| **Cross-platform** | C FFI, conditional compilation, multi-backend |
| **Performance** | Zero-cost abstractions, inline expansion |
| **Type safety** | Generics, type inference, ownership tracking |

### When to Fix Compiler vs Workaround

**ALWAYS Fix in MetaScript** - No exceptions:
- Type inference limitation → Fix type checker
- Macro expansion bug → Fix macro expander
- C codegen issue → Fix C backend
- Missing FFI capability → Add FFI feature
- Syntax limitation → Extend parser
- Any other compiler issue → Fix the root cause

**NEVER Workaround in Neon**:
- ❌ Don't accept "cosmetic syntax issues"
- ❌ Don't settle for "good enough" hacks
- ✅ Always fix MetaScript to support what Neon needs

**We own the compiler** - there's no reason to compromise.

### Bug Tracking Template

```markdown
## MetaScript Compiler Issue: [Title]

**Found in**: Neon [component] (e.g., signal.ms, element.ms)
**Current Behavior**: [What happens now]
**Expected Behavior**: [What MetaScript should support]

**Minimal Reproduction**:
```typescript
// MetaScript code that demonstrates the issue
```

**Error Output**:
```
<!-- Compiler error message -->
```

**Impact**: [How this blocks Neon development]
**Priority**: [High/Medium/Low]
**Status**: [Investigating/In Progress/Fixed]
```

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

# Terminal + Void hosts ship today — see tests/platform/terminal + tests/render/voidHost
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
# 1. Create component file under src/starter/
touch src/starter/MyComponent.ms

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

### MetaScript Compiler Crashes

**Symptom**: `msc test` or `msc build` segfaults or panics

**Steps**:
1. **STOP Neon work** - don't try to work around this
2. Simplify code to minimal reproduction case
3. Switch to `/Users/le/metascript/recompiler`
4. Write failing compiler test demonstrating the crash
5. Fix the compiler (TDD)
6. Verify fix: `rm -rf out && msc test src/index.ms`
7. Return to Neon - issue is now permanently resolved

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
- Build: `rm -rf out && msc test src/index.ms`

---

**North Star**: Cross-platform UI framework with TypeScript syntax, compile-time metaprogramming, and native performance - while dogfooding MetaScript to make both projects production-ready.
