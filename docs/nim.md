# Neon Framework - Technical Deep Dive

**Last Updated**: 2025-12-20
**Analysis**: Cross-platform UI framework with compile-time metaprogramming

---

## Project Identity

**Neon** is a cross-platform UI framework written in Nim that targets Browser, iOS, Android, and Terminal from a single codebase.

**Core Philosophy**:
- React-like component model (familiar DX)
- Solid.js fine-grained reactivity (performance)
- Nim compile-time metaprogramming (zero-cost abstractions)

---

## Metaprogramming Architecture

### The Compile-Time Transform Pipeline

```
User DSL Syntax
      ↓
AST Analysis (macros detect reactive patterns)
      ↓
Code Generation (platform-specific calls)
      ↓
Native Binary (iOS/Android) | JavaScript (Browser)
```

### Key Macros

#### 1. `element` Macro (src/macros/ui/dsl.nim:346)

**What it does**: Transforms declarative UI into imperative rendering code at compile-time.

**Input**:
```nim
element:
  View(style = styles.container):
    Text: "Static text"
    Text: proc(): string = $count()
```

**Generated Output** (simplified):
```nim
let view1 = makeElement("View")
bindProps(ViewProps(style: styles.container), view1)

let text1 = makeElement("Text")
insertElement("Static text", text1, 0)
insertElement(text1, view1, 0)

let text2 = makeElement("Text")
createEffect(proc() =
  updateTextContent(text2, $count())  # Auto-wrapped in effect
)
insertElement(text2, view1, 1)

result = view1
```

**Compile-time intelligence**:
- Detects reactive expressions (function calls, signal reads)
- Wraps only reactive content in effects
- Static content → direct platform calls (zero overhead)
- Reactive content → wrapped in `createEffect()` for auto-updates

**Detection heuristics** (src/macros/ui/dsl.nim:10-64):
- Calls to tracked reactive symbols
- Function names ending in `getter`
- Method calls like `signal.get()`
- Expressions containing reactive children

#### 2. `createStyle` Macro (src/macros/ui/style.nim:218)

**Type-safe style definitions**:
```nim
let styles = createStyle:
  container(ViewStyle):
    backgroundColor: "#f0f0f0"
    padding: 20
    flex: 1
  title(TextStyle):
    color: "#ffffff"
    fontSize: 32
```

Compiles to efficient table lookups with type checking at compile-time.

#### 3. Reactive Macros (src/macros/state/)

**signal macro**:
```nim
signal count = 0  # Expands to Signal[int] with getter/setter
```

**derived macro**:
```nim
derived doubled = count() * 2  # Cached computation, auto-invalidates
```

**effect macro**:
```nim
effect:
  echo "Count: ", count()  # Auto-tracks dependencies at runtime
  cleanup:
    doCleanup()
```

#### 4. Flow Control Macros (src/macros/ui/flow.nim)

```nim
Show(condition, content)              # Conditional render
Show(condition, content, fallback)    # With else
For(collection, callback)             # List iteration
Index(collection, callback)           # With index
Switch(fallback, match1, match2...)   # Multiple conditions
Match(value): of pattern: content     # Pattern matching
```

---

## Reactive System

Inspired by Solid.js, implemented in Nim with compile-time optimizations.

### Signal Implementation (src/core/state.nim)

```nim
type
  Signal*[T] = ref object
    value: T
    effects: seq[EffectCallback]  # Subscribers

proc get*[T](signal: Signal[T]): T =
  # Auto-subscribe current effect context
  if globalEffectContext.currentEffect.isSome:
    let effect = globalEffectContext.currentEffect.get
    if effect notin signal.effects:
      signal.effects.add(effect)
  result = signal.value

proc set*[T](signal: Signal[T], newValue: T) =
  if signal.value != newValue:
    signal.value = newValue
    signal.trigger()  # Notify all subscribers
```

### Effect Tracking Flow

```
createEffect(callback)
    ↓
1. Push effect onto context stack
2. Run callback
3. Any signal reads during callback auto-subscribe
4. Pop effect from stack
    ↓
Signal.set(newValue)
    ↓
Trigger all subscribed effects
    ↓
Effects re-run → UI updates
```

### API Design

**Read**: Always use parentheses
```nim
let value = count()
if count() > 10: doSomething()
```

**Write**: Methods
```nim
count.set(5)                  # Replace
count.update(x => x + 1)      # Transform
count += 1                    # Shorthand
flag.toggle()                 # Boolean toggle
```

**Batching**:
```nim
batch:
  count.set(10)
  name.set("Updated")  # Effects run once after batch
```

### Known Limitation

**Effect cleanup not implemented** (docs/architecture.md:145-148):
- Effects never removed from signals
- May cause memory growth over time
- Planned fix: bidirectional dependency tracking + disposal

---

## Platform Architecture

### Abstraction Contract

All platforms MUST implement (src/core/types.nim, CLAUDE.md:54-60):

```nim
proc makeElement*(tag: string): Element
proc insertElement*(content, parent: Element, pos: int): Element
proc bindProps*(props: ViewProps|TextProps, el: Element): void
proc updateTextContent*(el: Element, text: string): void
```

### Platform Implementations

**iOS** (src/platform/ios/):
```
Nim (apple.nim)
    ↓ C FFI {.importc.}
Objective-C Bridge (apple_bridge.m)
    ↓
UIKit (UIView, UILabel, etc.)
```

Key bridge functions:
- `UIView_alloc()` - Create native view
- `UIView_addSubview()` - Build hierarchy
- `UIView_setFrame()` - Layout positioning
- `UILabel_setText()` - Update text

**Android** (src/platform/android/):
```
Nim (android.nim)
    ↓ C FFI {.importc.}
JNI Bridge (android_bridge.c, neon_jni.c)
    ↓ JNI
Java Layer (NeonBridge.java)
    ↓
Android Views (FrameLayout, TextView, etc.)
```

**Browser** (src/platform/browser/):
```
Nim (browser.nim)
    ↓
Nim's DOM module
    ↓
Web APIs (document.createElement, appendChild, etc.)
```

**Terminal** (src/platform/terminal/):
```
Nim (tui.nim)
    ↓
Terminal control sequences
    ↓
TUI rendering
```

### Layout Engine

**Facebook Yoga** (src/core/yoga.nim) - Unified flexbox layout across all platforms:

```nim
let node = YGNodeNew()
YGNodeStyleSetWidth(node, 100)
YGNodeStyleSetFlexDirection(node, YGFlexDirectionRow)
YGNodeCalculateLayout(node, parentWidth, parentHeight, YGDirectionLTR)

# Read computed values
let left = YGNodeLayoutGetLeft(node)
let width = YGNodeLayoutGetWidth(node)
```

---

## Build Pipeline

### iOS Build Flow

```
src/ios.nim
    ↓ nim c --os:ios --cpu:arm64 --compileOnly
nimcache/*.c (Generated C code)
    ↓ Copy to Xcode project
platforms/ios/*.xcodeproj
    ↓ xcodebuild / Xcode
MyApp.app (iOS application)
```

### Android Build Flow

```
src/android.nim
    ↓ nim c --os:android --cpu:arm64 --compileOnly
nimcache/*.c (Generated C code)
    ↓ Copy to Android project + NDK compile
platforms/android/ (Gradle project)
    ↓ ./gradlew assembleDebug
app-debug.apk (Android application)
```

### Browser Build Flow

```
src/web.nim
    ↓ nim js -d:ssl -o:out/release/web
out/release/web.js
    ↓ Vite bundling
dist/ (Production bundle)
```

---

## Project Structure

```
src/
├── core/               # Reactive runtime
│   ├── state.nim       # Signal/Effect/Memo (createSignal:347, createEffect:353)
│   ├── types.nim       # Element, ViewStyle, TextStyle, Props (Types at :10-91)
│   ├── style.nim       # Style object definitions
│   └── yoga.nim        # Flexbox layout bindings
│
├── macros/             # Compile-time transformations
│   ├── ui/
│   │   ├── dsl.nim     # element macro (364 lines of AST transformation)
│   │   ├── style.nim   # createStyle macro
│   │   ├── flow.nim    # Show, For, Index, Switch, Match
│   │   ├── component.nim
│   │   ├── helpers.nim # AST manipulation utilities
│   │   └── reactive.nim
│   └── state/
│       ├── dsl.nim     # signal, derived, effect macros
│       └── reactive.nim # Compile-time symbol tracking
│
├── platform/           # Platform implementations
│   ├── ios/
│   │   ├── apple.nim   # UIKit bindings (makeElement:128)
│   │   └── apple_bridge.m
│   ├── android/
│   │   ├── android.nim # JNI bindings (makeElement:106)
│   │   ├── android_bridge.c
│   │   └── NeonBridge.java
│   ├── browser/
│   │   └── render.nim  # DOM rendering (makeElement:8)
│   └── terminal/
│       └── tui.nim
│
├── cli/                # CLI tool
│   ├── neon.nim        # Entry point
│   ├── commands/
│   │   ├── init.nim    # Project creation
│   │   └── build.nim   # Build orchestration
│   └── generators/     # Platform project generation
│
├── starter/            # Example components
│   ├── Counter.nim
│   ├── ApiDemo.nim
│   ├── AnimationDemo.nim
│   └── ...
│
├── App.nim             # Sacred API - user-facing syntax example
├── neon.nim            # Framework exports
├── web.nim             # Browser entry point
├── mobile.nim          # iOS/Android entry point
└── tui.nim             # Terminal entry point
```

---

## Sacred Files (CLAUDE.md:5-10)

**DO NOT MODIFY API**:

| File | Reason |
|------|--------|
| `src/App.nim` | Target syntax - API must remain stable |
| `src/core/state.nim` | Reactive core - affects ALL platforms |
| `src/macros/ui/dsl.nim` | DSL macro - complex AST transforms |

---

## Design Principles

### Core Philosophy (docs/architecture.md:7-14)

1. **One way to do things** - Like Go/Zig, avoid multiple approaches
2. **React-like interface** - Familiar declarative UI patterns
3. **Solid.js reactivity** - Fine-grained updates without virtual DOM
4. **Native performance** - Compile to native code, not interpreted
5. **Sacred API** - `src/App.nim` syntax must remain stable

### Development Rules

**From CLAUDE.md:69-75**:
```
Making changes?
├── Core (state.nim, types.nim) → ASK FIRST, test ALL platforms
├── Macros (dsl.nim) → Verify src/App.nim still compiles
├── Platform-specific → Update generators, test fresh builds
└── CLI/Templates → Safe to modify independently
```

---

## Known Constraints

| Platform | Constraint | Source |
|----------|------------|--------|
| All | `element` macro: single root child only | By design |
| Android | No nested Text elements | Platform limitation |
| iOS | Call `NeonSetButtonCallback` before button creation | Bridge requirement |
| iOS | Yoga headers must be at `$(SRCROOT)/NeonApp` | Xcode config |

---

## CLI Usage

```bash
# Project creation
neon init MyApp --platforms browser,ios,android

# Development
neon dev                    # Browser dev server with HMR
nimble test                 # Run test suite
nimble tui                  # Terminal TUI with hot reload

# Build
neon build browser          # Web bundle
neon build ios              # iOS + generate Xcode project
neon build android          # Android + generate Gradle project

# Run
neon run ios                # Build and launch iOS simulator
neon run android            # Build and launch Android emulator
```

---

## Testing Layers (docs/testing/)

1. **Layer 1**: Core unit tests (reactive system, signals, effects)
2. **Layer 2**: Macro tests (DSL transformation correctness)
3. **Layer 3**: Terminal debug (visual integration testing)

**Pre-merge checklist** (TODO.md:37-42):
- [ ] `nimble test` passes
- [ ] Browser platform works (`neon dev`)
- [ ] iOS builds and runs
- [ ] Android builds and runs
- [ ] `src/App.nim` syntax unchanged

---

## Active Development Status

**Last Updated**: 2024-11-24 (TODO.md)

**Completed Recently**:
- Deep project analysis
- CLAUDE.md optimization for LLM efficiency

**Pending Improvements** (TODO.md:28-34):
- Medium priority: Animation system
- Medium priority: Hot reload improvements
- Low priority: Terminal platform completion
- Low priority: IDE support

**Known Issues**:
- Single root element only (by design)
- No nested Text on Android (by design)
- Effect cleanup not implemented (monitoring)

---

## Key Insights

### Why This Architecture Works

1. **Compile-time wins**: Maximum work done at compile-time
   - Reactive detection during macro expansion
   - Type-safe style definitions
   - Dead code elimination
   - Zero-cost abstractions

2. **Runtime efficiency**: Fine-grained reactivity
   - No virtual DOM diffing
   - Direct platform updates
   - Only changed values trigger re-renders
   - Automatic dependency tracking

3. **Cross-platform without compromise**:
   - Shared reactive core
   - Platform-specific rendering
   - Unified layout engine (Yoga)
   - Single source of truth (src/App.nim)

4. **Developer experience**:
   - Familiar React patterns
   - Type safety from Nim
   - Hot reload support
   - CLI for project scaffolding

### The Metaprogramming Edge

**Nim's macro system enables**:
- **AST transformation**: Convert high-level DSL to low-level platform calls
- **Static analysis**: Detect reactive patterns at compile-time
- **Code generation**: Generate boilerplate for each platform
- **Type inference**: Maintain type safety through transformations
- **Zero runtime cost**: All macro magic happens during compilation

**Example power**: The `element` macro (364 lines) automatically:
- Parses nested UI structure
- Detects which expressions are reactive
- Wraps reactive content in effects
- Generates platform-specific rendering code
- Preserves type information
- All at compile-time, no runtime penalty

---

## Example: Full Stack Trace

**User writes** (src/App.nim):
```nim
let (count, setCount) = createSignal(0)

element:
  View(style = styles.container):
    Text: $count()
```

**Compile-time**:
1. `createSignal` macro → `Signal[int]` + getter/setter procs
2. `element` macro analyzes AST
3. Detects `$count()` is reactive (function call)
4. Generates wrapper: `createEffect(proc() = updateTextContent(el, $count()))`

**Runtime**:
1. Effect runs, calls `count()` getter
2. Getter registers effect as subscriber to signal
3. User calls `setCount(5)`
4. Signal triggers all subscribers
5. Effect re-runs with new value
6. `updateTextContent` calls platform-specific update
7. UI updates (UILabel.setText on iOS, TextView.setText on Android, textContent on Browser)

**Result**: Reactive UI with zero virtual DOM, minimal overhead, type-safe end-to-end.

---

## Reference Documentation

- Root: CLAUDE.md - Quick reference, sacred files, decision tree
- Core: src/core/CLAUDE.md - Reactive API reference
- Macros: src/macros/CLAUDE.md - DSL syntax, transformation pipeline
- Platforms: src/platform/CLAUDE.md - Platform interface contract
- Architecture: docs/architecture.md - Deep dive into system design
- Reactivity: docs/reactive-design.md - Signal/Effect specification
- Getting Started: docs/getting-started.md - User documentation

---

## External Dependencies

- **Yoga**: Facebook's flexbox layout engine (external/yoga/)
- **Nim**: >= 2.2.0
- **parsetoml**: >= 0.7.0 (for neon.toml config)
- **Vite**: For browser bundling (package.json)
- **TypeScript**: For browser type definitions

---

*This document captures the technical architecture and metaprogramming design of Neon framework as of 2025-12-20.*
