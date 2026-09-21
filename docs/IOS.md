# iOS Host — research notes for the port

Status: **research only**. No `src/platform/ios/` exists (ROADMAP "Next" #5 — iOS first, then
Android). Everything below was read from the named checkouts on 2026-09-21 and carries
`file:line` evidence; judgment calls are marked as such. The two decisions these notes feed:

- **Boilerplate (Xcode project, UIKit shell, yoga packaging) comes from ion's generator**,
  not from a neon-side generator — the Nim original's generator is the inventory, not the plan.
- **The native-component mapping is learned from the Nim original and from React Native.**

| source | what it is |
|---|---|
| `~/projects/neon` | the Nim original: a complete working iOS host (~250 KB: `src/platform/ios/`) |
| `~/projects/react-native` | RN main toward 0.83; Fabric is the mandatory default there |

Companions: `RENDER-LAYERS.md` (iOS = Neon Layer A over the OS's Core Animation B+C, Host
object `UIView`), `RENDER-MODEL.md` (the NeonNode mount contract), `ANDROID.md` (the same
research for Android; the shared C-ABI/tag/measure design is stated once there and only
delta'd here).

---

## 1. The reference architecture (verified)

```
Nim (neon tree)
  │  importc "apple_bridge.h"            apple.nim:19-27
  ▼
apple_bridge.m — a real ObjC TU, direct UIKit calls under C linkage
  │  alloc/initWithFrame return __bridge_retained void*  apple_bridge.m:268-272
  │  events: gesture/delegate → ObjC singleton → global cdecl fn ptr → tag lookup
  ▼
UIKit view tree (main thread; Auto Layout OFF for neon views — plain frames)
```

- **No `objc_msgSend` FFI**: the bridge is a compiled Objective-C translation unit; every
  bridge function is C-linkage with an ObjC body. This is also the natural shape for us:
  `apple_bridge.m` compiles beside the C that `msc` emits, gated by
  `when (ios) { @compile / @passL "-framework UIKit" }` over one extern surface.
- **Ownership**: `alloc/initWithFrame` return `(__bridge_retained void*)` — a +1 into the
  framework side; colors singletons unretained; per-view state (transform, maxLength,
  placeholder, tint) rides **objc associated objects**. The Nim side never releases
  (cleanup nils the pointer) — native views live for app lifetime. For the port: rely on
  ARC at the boundary + our Owner-tree cleanup for recognizers/state, and say so once.
- **Main-thread is assumed, not enforced**: render is called from `viewDidLoad` so it is
  main by construction; explicit `dispatch_async(main)` only for text-change callbacks,
  first-responder calls, selection, and image delivery.
- **No continuous render loop.** Layout is event-driven (initial render,
  `scheduleReLayout`, rotation). The only frame driver is a **one-shot CADisplayLink RAF**
  (`NeonRAF_request` fires once then invalidates, `apple_bridge.m:2091-2223`) — the
  `requestAnimationFrame` seam, used by the animation core.
- **Async wake-up**: Nim's self-pipe FD parked in the **main CFRunLoop** via
  `CFFileDescriptor` (re-armed before drain and on foreground); timers are main-queue
  `dispatch_source`s; HTTP completions deliver on main.

## 2. Component mapping (the part we learn from)

`makeElement` tag dispatch (`apple.nim:739-858`):

| tag | UIKit class | defaults set at creation |
|---|---|---|
| `View` / everything unknown | `UIView` | yoga flex column (`apple.nim:854-857`) |
| `Text` | `UILabel` | 14 pt, centered, white text, clear background, `numberOfLines 0`, yoga measure func (`:748-766`) |
| `TextInput` | `UITextField` (a `NeonPaddedTextField` subclass) | 14 pt, yoga height 40 (`:767-781`) |
| `TextInputMultiline` | `UITextView` | 14 pt, yoga height 100 (`:782-796`) |
| `ScrollView` | `UIScrollView` + content `UIView` | **two-view RN pattern**: children go to the content container and its `contentNode`; `alwaysBounceVertical`, `contentInsetAdjustmentBehavior = never`, `delaysContentTouches = 0` (`:797-839`) |
| `Image` | `UIImageView` | contentMode cover + `clipsToBounds`; async load by tag, NSCache (50 MB) + SHA-256-keyed disk cache (200 MB) with LRU prune (`apple_bridge.m:2412-2653`) |

No Button tag — same as Android: a View with `onPress`; recognizer choice is
`0 < activeOpacity < 1` (default 0.5) → press gesture with opacity feedback, else tap.

**Text nesting — the reference's answer and its hole.** `insertElement` merges a Text child
into a Text parent before any tree insertion (`apple.nim:875-898`, verified in the main
session): only the child's reactive `renderProc` transfers (an effect re-sets label text,
marks the yoga node dirty, calls `scheduleReLayout`); **a static nested `<Text>foo</Text>`'s
string is silently dropped** (`:881-892` has no static branch). `NSAttributedString` is used
only for placeholder color, never content.

RN's answer (Fabric, the only text path left in that checkout — legacy `RCTText` is
deleted): `<Text>` maps to the **Paragraph** component — one native view per paragraph;
nested `<Text>` and raw strings are supplemental shadow nodes with **no native views**
(`RCTParagraphComponentView.mm:92-96`), flattened into one AttributedString in C++
(`ParagraphShadowNode.cpp:85-88`, verified), measured by a yoga measure func with
constraint-keyed prepared-layout caching (`:222-261`), pushed to the view as state only
when changed (`:145-177`); embedded non-text children are laid out as attachments
(`:377-413`); per-fragment press hit-testing asks the layout manager which fragment's
emitter is under the point. **This is the design Neon should port, not the merge.**

**TextInput echo guard** (RN, worth copying exactly): `_mostRecentEventCount` +
`_ignoreNextTextInputCall` + `_comingFromJS` so native typing and JS-driven value writes
don't loop (`RCTTextInputComponentView.mm:43-68`); commands (`focus` / `blur` /
`setTextAndSelection`) arrive as messages, not fake props. The Nim host has no guard.

## 3. Layout

- `performLayout` → `YGNodeCalculateLayout` → `applyLayout` reads
  `YGNodeLayoutGet{Left,Top,Width,Height}` and pushes `UIView_setFrame` per view
  (`apple.nim:2114-2233`). Points, no dp/px split (the Android twin's problem).
- Text measurement is **TextKit** (`NSTextStorage` + `NSLayoutManager` +
  `NSTextContainer`, `lineFragmentPadding=0`, `usesFontLeading=NO`, ceil+clamp) —
  `apple_bridge.m:789-866`; registered per text node via `NeonTextNode_setMeasureFunc`
  (`apple_bridge.h:37`). Text change → `YGNodeMarkDirty` (only legal on measure-func nodes).
- ScrollView content gets a **second** `YGNodeCalculateLayout(contentNode, w, NaN)` /
  `(NaN, h)` inside `applyLayout`, then `setContentSize` with a viewport clamp
  (`apple.nim:2160-2198`).
- **Rotation is a teardown + full re-render**, not a relayout:
  `viewWillTransitionToSize` removes all subviews and calls `neon_render` again
  (`ViewController.m.template:55-67`, verified in the main session). For us this is a
  first-host shortcut to note, not a design to keep — an owner-scoped dispose + re-mount
  of the root is the same thing expressed in our runtime.

## 4. Animation (for the later animation arc)

Transform + opacity only, never frames (`animation.nim:7-13`). Setters compose through a
per-view `NeonTransformState` associated object (the single source of truth, so
`setTranslate` preserves scale/rotation); `UIView_animateWithDuration` with `FLT_MAX` =
skip marker; springs via **CASpringAnimation** with mass 1, velocity normalized by
distance, `duration = settlingDuration`, model value set immediately
(`apple_bridge.m:1938-2051`). Cleanup matters here: `cleanupGestureRecognizers` +
`cleanupAnimationState` + `removeFromSuperview` before removal
(`apple_bridge.m:2055-2088`) — the reference's own TODO says general disposal is unwired.

## 5. The RN borrow list that shapes the host

From the Fabric layer (the checkout's default; the legacy paper machinery — shadow-tree
diff/commit, style-diff batches, `manageChildren` index math — is dead weight for a
no-VDOM framework):

- **The ComponentView protocol shape** — `{updateProps(new, old), updateEventEmitter,
  updateState, updateLayoutMetrics, mountChild, unmountChild, handleCommand,
  prepareForRecycle}` (`RCTComponentViewProtocol.h`, adopted at
  `RCTViewComponentView.h:25`, mount/unmount at `RCTMountingManager.mm:82-85`). An
  imperative per-view contract with `(new, old)` so setters can early-out — almost exactly
  a Neon Host; our `(host, parent, before) => void` mount IS their mount instruction,
  without the diff that produces it.
- **Compare-before-apply** (`RCTMountingManager.mm:111-113`) and **one finalizeUpdates per
  transaction** for props that must land together (Android border/background) — the right
  way to batch dependent setters without a VDOM.
- **Paragraph text architecture** — §2 above.
- **TextInput echo guards + commands-as-messages** — §2 above.
- **Frame-aligned flush, carefully** — RN coalesces native setter application and event
  flush to the frame clock (Choreographer on Android; run-loop-driven beats on iOS). We
  need at most a minimal per-frame host queue if effect storms ever thrash UIKit; not a
  batch architecture. Judgment.

## 6. Boilerplate inventory — what ion must generate

The Nim generator (`src/cli/generators/ios.nim:308-440`) emits into `platforms/ios/<Name>/`:

| generated | notes |
|---|---|
| `main.m`, `AppDelegate.h/.m`, `ViewController.h/.m` | static UIKit shell; ViewController owns a full-screen `neonContainer` + rotation re-render |
| `Info.plist` | classic entry; no Swift bridging header needed |
| `apple_bridge.h/.m`, `async_bridge.h/.m` | copied from the framework |
| nimbase + `@*.c` | from `nim c --os:ios --compileOnly --noMain` — for us, `msc build` output |
| `libyoga.a` + yoga headers | prebuilt for simulator, linked via `OTHER_LDFLAGS` |
| `project.pbxproj` | hand-built string emission: fixed UUIDs for app files, MD5-derived per C file, one app target, `-framework UIKit … -ObjC` |

**Ion today** (verified in the main session): the generator at
`~/metascript/ion/tooling/generator/` emits exactly two files (`project.pbxproj` +
`graph.json`) from a typed `project.ms` manifest, and its only emitter **rejects every
non-macOS target** (`xcode.ms:26`), while `enum Platform { Macos, Ios }` already exists in
the model (`description.ms:1`) and `Target.app` defaults to Macos (`description.ms:39-41`).

**Gap for iOS, in ion**: (1) an iOS emitter beside `xcode.ms` — `SDKROOT = iphonesimulator`
/ `iphoneos`, a real `Info.plist` file reference (the macOS emitter relies on
`GENERATE_INFOPLIST_FILE`), an app-bundle layout without `Contents/MacOS`, signing
allowed-for-simulator, and the frameworks list; (2) a `Target.iosApp(...)` helper so the
platform is explicit; (3) yoga + bridge .m/.c file references in the project (today the
shell phase just runs `msc build`, `xcode.ms:43` — an iOS app needs the ObjC bridge TU and
yoga compiled in, i.e. either msc `@compile` side-files or extra pbx file references).
Ion imports neither neon nor void by design (`ion/CLAUDE.md:3,49`) — the host must surface
as files + entry points, never a neon import.

## 7. What the MetaScript port does differently

- **The host is `Host`** (`src/render/hostTypes.ms`): `createElement` translates the WIRE
  tag to the UIKit class (the browser host's `htmlTagFor` pattern); `addEvent` keeps the
  per-node closures inside the host with one `NeonSet*Callback` registration at init.
- **Extern surface gated, not branched**: one backend-agnostic extern block over the
  bridge header, `when (ios) { @passL "-framework UIKit" … }` around it — the shape
  `void/src/sokol/gpu.ms` ships; an untaken branch is never type-checked.
- **Cleanup wired into the Owner tree**: the reference's unwired-disposal TODO (gesture
  recognizers, animation state, yoga nodes, handler maps) is exactly what `onCleanup`
  already schedules for every unmount in our runtime.
- **Nested Text**: RN's paragraph model (flatten to attributed runs on one UILabel via
  NSAttributedString, measure func + prepared-layout cache, per-fragment hit-testing when
  press handlers arrive) — not the reference's merge with its static-content loss.
- **multiline**: UITextField vs UITextView differ at creation; pick the wire tag in the
  `TextInput` component from a static `multiline` prop (RN picks the backing control at
  init from default props, `RCTTextInputComponentView.mm:70`).
- **Safe area**: the reference container is edge-to-edge and the Neon app handles insets
  (`ViewController.m.template:23-24`) — that stays our call, and pairs with the runtime
  object `rt` (ROADMAP "Later").

## 8. Sources — what was and was not verified

Read and verified in the main session (2026-09-21): `apple_bridge.h` (whole), `apple.nim`
structure + `makeElement`/`insertElement`/text-merge/`bindProps` map (merge block
`:860-948` read whole), `ViewController.m.template` (whole), ion `description.ms` +
`xcode.ms` (whole), RN `ParagraphShadowNode.cpp:70-98` and the `RCTComponentViewProtocol`
conformances (`RCTViewComponentView.h:25`, `RCTInputAccessoryComponentView.mm:97-105`).

Scout-read (compressed, line-anchored, not line-by-line): `apple_bridge.m` between the
verified anchors (text measurement `:789-933`, image cache `:2412-2653`, springs
`:1938-2051`, cleanup `:2055-2088` are grep-anchored), `async_bridge.m` (anchored via
targeted grep; gaps ~`:195-330, :675-745, :960-1130` sampled only), `src/core/yoga.nim`
(NOT read), `src/core/animation.nim` beyond `:274-329`, `AppDelegate`/`ViewController.h`
templates, the `platforms/ios/` example output tree. The reference's iOS `CLAUDE.md`
mentions `NeonSetButtonCallback` (`:25, :79`) — no counterpart exists in code (stale doc).
Nothing above rests on an unverified region.
