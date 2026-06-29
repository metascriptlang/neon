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

**Reference Architecture**: Original Neon (Nim) at ~/projects/neon
- Documentation: docs/nim.md
- MetaScript capabilities: docs/metascript.md

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
2. **Switch to MetaScript project** at /Users/le/projects/metascript
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

```bash
# Development (MetaScript compiler)
cd /Users/le/projects/metascript
zig build
export PATH=$PWD/zig-out/bin:$PATH

# Build Neon framework
cd /Users/le/metascript/neon
msc compile --target=c src/neon.ms          # Native library
msc compile --target=js src/neon.ms         # Browser bundle

# Run examples
msc run --target=raiser examples/counter.ms  # VM (fastest iteration)
msc run --target=js examples/counter.ms      # Browser preview

# Testing
msc test tests/core/signal.test.ms           # Unit tests
msc test tests/macros/element.test.ms        # Macro tests
msc test tests/integration/*.test.ms         # Integration tests

# Macro expansion preview
msc expand examples/counter.ms               # See generated code
```

### File Structure

```
neon/
├── CLAUDE.md              # This file - AI assistant guide
├── docs/
│   ├── nim.md             # Original Neon (Nim) reference
│   ├── metascript.md      # MetaScript capabilities
│   ├── migration.md       # Nim → MetaScript porting notes
│   └── architecture.md    # Neon design principles
│
├── src/
│   ├── neon.ms            # Framework entry point
│   ├── App.ms             # Sacred API - user-facing syntax example
│   │
│   ├── core/              # Reactive runtime
│   │   ├── signal.ms      # Signal[T] - reactive state
│   │   ├── effect.ms      # createEffect - side effects
│   │   ├── memo.ms        # createMemo - cached computation
│   │   ├── batch.ms       # batch - deferred updates
│   │   └── cleanup.ms     # onCleanup - disposal
│   │
│   ├── macros/            # Compile-time transformations
│   │   ├── ui/
│   │   │   ├── element.ms # element macro - UI DSL
│   │   │   ├── style.ms   # createStyles macro
│   │   │   └── flow.ms    # Show, For, Index control flow
│   │   └── state/
│   │       └── reactive.ms # signal, derived, effect macros
│   │
│   ├── platform/          # Platform-specific renderers
│   │   ├── types.ms       # Cross-platform Element interface
│   │   ├── ios/
│   │   │   └── uikit.ms   # UIKit bindings (C FFI)
│   │   ├── android/
│   │   │   └── views.ms   # Android View bindings (C FFI)
│   │   ├── browser/
│   │   │   └── dom.ms     # DOM rendering (JS backend)
│   │   └── terminal/
│   │       └── tui.ms     # Terminal UI (C backend)
│   │
│   ├── yoga/              # Flexbox layout (C FFI)
│   │   └── bindings.ms    # Yoga extern declarations
│   │
│   └── starter/           # Example components
│       ├── Counter.ms
│       ├── TodoList.ms
│       └── AnimationDemo.ms
│
├── examples/              # Usage examples
│   ├── counter.ms         # Basic reactivity
│   ├── todo-app.ms        # CRUD operations
│   └── multi-platform.ms  # Cross-platform showcase
│
├── tests/                 # Test suite
│   ├── core/              # Reactive system tests
│   ├── macros/            # Macro transformation tests
│   ├── platform/          # Platform-specific tests
│   └── integration/       # End-to-end tests
│
└── build/                 # Generated artifacts
    ├── c/                 # Native binaries
    └── js/                # Browser bundles
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
| `src/App.ms` | User-facing syntax example | Breaks all user code |
| `src/core/signal.ms` | Reactive core API | Affects all reactivity |
| `src/macros/ui/element.ms` | UI DSL macro | Changes framework API |

**Decision Tree**:
```
Making changes?
├── Core (signal.ms, effect.ms) → ASK FIRST, test ALL platforms
├── Macros (element.ms) → Verify src/App.ms still works
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

### Phase 1: Reactive Core (Week 1-2)

**Goal**: Implement Solid.js-style reactivity in MetaScript

```bash
# Start with signal implementation
touch src/core/signal.ms
msc compile --target=raiser src/core/signal.ms

# Test reactivity
touch tests/core/signal.test.ms
msc test tests/core/signal.test.ms
```

**Files to create**:
- [ ] `src/core/signal.ms` - Signal[T] with get/set
- [ ] `src/core/effect.ms` - Auto-tracking dependency system
- [ ] `src/core/memo.ms` - Cached computations
- [ ] `src/core/batch.ms` - Deferred updates
- [ ] `tests/core/*.test.ms` - Unit tests for reactivity

**MetaScript Features Used**:
- Classes with generics: `class Signal<T>`
- Extension methods: `function get(this Signal<T> s): T`
- Closures for effect tracking

### Phase 2: UI Macro System (Week 3-4)

**Goal**: Build compile-time DSL transformation

```bash
# Implement element macro
touch src/macros/ui/element.ms
msc expand examples/simple.ms  # Preview generated code
```

**Files to create**:
- [ ] `src/macros/ui/element.ms` - DSL → platform calls
- [ ] `src/macros/ui/style.ms` - createStyles macro
- [ ] `tests/macros/element.test.ms` - Macro tests
- [ ] `examples/macro-preview.ms` - Show transformation

**MetaScript Features Used**:
- `macro element(body: ASTNode): ASTNode` - AST transformation
- `@comptime` blocks for compile-time logic
- AST node creation APIs

### Phase 3: Platform Backends (Week 5-8)

**Goal**: Implement renderers for each platform

```bash
# iOS backend
touch src/platform/ios/uikit.ms
msc compile --target=c src/platform/ios/uikit.ms

# Browser backend
touch src/platform/browser/dom.ms
msc compile --target=js src/platform/browser/dom.ms
```

**Files to create**:
- [ ] `src/platform/types.ms` - Cross-platform Element interface
- [ ] `src/platform/ios/uikit.ms` - UIKit extern bindings
- [ ] `src/platform/android/views.ms` - Android extern bindings
- [ ] `src/platform/browser/dom.ms` - DOM rendering (JS target)
- [ ] `src/yoga/bindings.ms` - Yoga layout extern bindings

**MetaScript Features Used**:
- `extern function` for C FFI (UIKit, Android, Yoga)
- `@target("c")` vs `@target("js")` conditional compilation
- `Owned<T>` / `Borrowed<T>` ownership tracking

### Phase 4: Compiler Co-Evolution (Ongoing)

**Goal**: Find and fix MetaScript compiler issues

```bash
# When you hit a compiler bug:
cd /Users/le/projects/metascript
git checkout -b fix/neon-issue-123
# Fix the compiler
zig build test

# Verify fix in Neon
cd /Users/le/metascript/neon
msc compile src/neon.ms  # Should work now
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
- ❌ Don't document workarounds in `docs/migration.md`
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
msc test tests/core/effect.test.ms
msc test tests/core/memo.test.ms
```

**Coverage**: 90%+ for core reactive system

### Macro Tests (DSL Transformation)

```bash
# Test element macro expansion
msc expand tests/macros/element.test.ms --output=/tmp/expanded.ms
diff /tmp/expanded.ms tests/macros/element.expected.ms
```

**Coverage**: 85%+ for macro correctness

### Integration Tests (Platform)

```bash
# iOS simulator
msc compile --target=c examples/counter.ms
ios-sim run build/counter.app

# Browser
msc compile --target=js examples/counter.ms
open build/counter.html
```

**Coverage**: Smoke tests for each platform

### Pre-Commit Checklist

- [ ] All unit tests pass: `msc test tests/core/*.test.ms`
- [ ] All macro tests pass: `msc test tests/macros/*.test.ms`
- [ ] No TypeScript syntax regressions: Verify `src/App.ms` compiles
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
# 1. Create component file
touch src/starter/MyComponent.ms

# 2. Implement with element macro
cat > src/starter/MyComponent.ms << 'EOF'
import { element } from "../macros/ui/element.ms";
import { signal } from "../core/signal.ms";

export function MyComponent(): Element {
  signal count = 0;

  return element:
    View(style = styles.container):
      Text: () => `Count: ${count()}`
      Button(onPress = () => count.set(count() + 1)):
        Text: "Increment"
}
EOF

# 3. Test it
msc run --target=raiser examples/use-component.ms
```

### Add Platform Support

```bash
# 1. Create platform directory
mkdir -p src/platform/myplatform

# 2. Implement Element interface
touch src/platform/myplatform/renderer.ms

# 3. Add extern bindings for platform APIs
# (see src/platform/ios/uikit.ms as reference)

# 4. Test on actual platform
msc compile --target=c src/platform/myplatform/renderer.ms
```

### Debug Macro Expansion

```bash
# View generated code from macro
msc expand examples/counter.ms --output=/tmp/counter-expanded.ms
cat /tmp/counter-expanded.ms

# Compare with expected output
diff /tmp/counter-expanded.ms tests/macros/counter.expected.ms
```

### Profile Performance

```bash
# Compile with profiling
msc compile --target=c --profile src/neon.ms

# Run benchmark
./build/neon-benchmark
```

---

## Troubleshooting

### MetaScript Compiler Crashes

**Symptom**: `msc compile` segfaults or panics

**Steps**:
1. **STOP Neon work** - don't try to work around this
2. Simplify code to minimal reproduction case
3. Switch to /Users/le/projects/metascript
4. Write failing test demonstrating the crash
5. Debug and fix the compiler issue
6. Verify fix with `zig build test`
7. Return to Neon - issue is now permanently resolved

### Macro Expansion Doesn't Work as Expected

**Symptom**: Generated code is wrong

**Steps**:
1. Use `msc expand` to see actual output
2. Check macro implementation in `src/macros/ui/element.ms`
3. Add test case in `tests/macros/element.test.ms`
4. Fix macro logic
5. Verify all existing tests still pass

### Platform-Specific Rendering Issue

**Symptom**: Works in browser but not iOS

**Steps**:
1. Check platform implementation: `src/platform/ios/uikit.ms`
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

### Phase 1 Complete When:
- [ ] Signals work: get/set with dependency tracking
- [ ] Effects work: auto-run on dependency changes
- [ ] Memos work: cached computations, lazy re-evaluation
- [ ] Tests pass: 90%+ coverage of core reactivity

### Phase 2 Complete When:
- [ ] `element` macro transforms DSL to platform calls
- [ ] `createStyles` macro generates style objects
- [ ] `src/App.ms` compiles with clean syntax
- [ ] Macro tests pass: Generated code matches expected

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
- Original Neon (Nim): /Users/le/projects/neon
- MetaScript Compiler: /Users/le/projects/metascript
- Solid.js (reactivity inspiration): https://solidjs.com
- Yoga (layout engine): https://yogalayout.com

**Documentation**:
- Neon architecture: docs/nim.md
- MetaScript capabilities: docs/metascript.md

**MetaScript Compiler**:
- Source: /Users/le/projects/metascript/src
- Tests: /Users/le/projects/metascript/tests
- Build: `zig build` in metascript root

---

**North Star**: Cross-platform UI framework with TypeScript syntax, compile-time metaprogramming, and native performance - while dogfooding MetaScript to make both projects production-ready.
