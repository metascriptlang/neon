# iOS Host

Status: the first UIKit host and tracked Ion-generated integration app are implemented.
`src/platform/ios/host.ms` owns the reusable host and lifecycle handoff;
`examples/ios/` is the generated-project consumer. This document keeps the measured
boundary and the reference research that code cannot express.

Two decisions still shape the platform:

- **Boilerplate and the Xcode build environment come from Ion's generator**, not from a
  Neon-side generator.
- **The native-component mapping is learned from the Nim original and React Native.**

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

## 6. Executable handoff to Ion

The production boundary is a compiler-linked executable handoff. Ion resolves the typed
manifest and emits the deterministic Xcode application target. Xcode invokes the pinned
compiler with its SDK, architecture, deployment and configuration context. The compiler
then owns generated C, runtime selection, package-native directives and the final link;
Xcode owns metadata, bundling, simulator signing and launch.

```text
examples/ios/project.ms
  → Ion Target.iosApp
  → deterministic NeonCounter.xcodeproj
  → Xcode Compile MetaScript phase
  → msc build examples/ios/app.ms --os=ios
  → Neon/Yoga native directives + compiler runtime
  → bundle, sign, install and launch
```

There is no PBX inventory of compiler runtime, Neon bridge or Yoga sources. The ownership
seams are `Target.iosApp` and `iosScript` in Ion, `createIosHost` and `registerAndRun` in
`src/platform/ios/host.ms`, and the process bootstrap in `examples/ios/entry.m`. Neon
remains the sole owner of `UIApplicationMain`; Ion imports neither Neon nor Yoga.

### 6.1 Measured generated-project proof

Measured 2026-09-22 on source/test tree
`35d1e99db827b857f06e71f2571d6c8ab891858f`, installed compiler
`d757c7e1`, Xcode 26.6, arm64 host and iPhone 17 Pro simulator on iOS 26.5:

- two fresh generations from `examples/ios/project.ms` were byte-identical for
  `graph.json` and `project.pbxproj`; `plutil -lint` accepted the project;
- generated-project Debug and Release arm64 simulator builds both exited 0 with no PBX
  edits, and the Debug bundle installed and launched as `dev.neon.NeonCounter`;
- the launched `examples/components/counter.ms` changed `0 → 1` and `even → odd`;
  UIKit reported the value frame changing `(186,60;31,58) → (190,60;23,58)` and the hint
  frame changing `(188,186;27,15) → (190,186;22,15)`;
- before/after simulator screenshots visually showed both state changes.

The interaction was synthetic, not physical input: LLDB invoked
`touchesBegan`/`touchesEnded` on the actual `NeonTouchView` tagged for the `+` pressable.
That proves native event dispatch, signal update, dynamic text, Yoga measurement and frame
application. Physical finger input was not exercised.

Physical-device signing, provisioning and launch remain unverified. App Store
archive/export, universal binaries, Swift library embedding and MetaScript source-level
debugging are also outside this milestone.

### 6.2 Measured lifecycle proof

Measured 2026-09-22 on source/test tree
`92271c31252a20ec06ef3f5bdf9ffa8776b72fed`, installed compiler `d757c7e1`,
Xcode 26.6 and the same iPhone 17 Pro simulator:

- `tests/platform/ios.test.ms` passed 295/295 and proves a removed native tag no
  longer dispatches;
- fresh Ion-generated Debug and Release arm64 simulator builds exited 0;
- the portrait container used the safe-area bounds `(0,0;402,778)`, below the
  status region rather than the full `(402,874)` screen;
- foregrounding Settings and returning preserved PID 4387; post-resume native
  press routing still updated and remeasured the counter;
- a temporary native teardown app removed its only `NeonTouchView`: UIKit's
  hierarchy changed from one tagged child to none, and a second dispatch to the
  removed tag was inert.

### 6.3 Measured rotation proof

Measured 2026-09-23 on Neon `4d2481c`, Ion `a6cce63`, installed compiler `d757c7e1`,
Xcode 26.6 and the same simulator, with an XCUITest driving one launched process
portrait → landscape → portrait:

- the process kept one PID and native presses changed the counter `0 → 1` in
  landscape and `1 → 2` after returning to portrait;
- every counter static text lay inside the safe area `(0,62;402,778)` in portrait and
  `(62,0;750,382)` in landscape; the title frame was `(137,86;128,24)` in portrait and
  `(373,24;128,24)` in landscape, centred at x=437;
- before `4d2481c` the root's Yoga frame reset the container origin to `(0,0)`: the
  portrait title sat at y=24 under the status bar and the landscape column centred at
  x=375;
- screenshots matched the frames. The `-`, `reset` and `+` pressables render without a
  visible label.

## 7. What the MetaScript port does differently

- **The host is `Host`** (`src/render/hostTypes.ms`): `createElement` translates the WIRE
  tag to the UIKit class (the browser host's `htmlTagFor` pattern); `addEvent` keeps the
  per-node closures inside the host with one `NeonSet*Callback` registration at init.
- **Extern surface gated, not branched**: one backend-agnostic extern block over the
  bridge header, `when (ios) { @passL "-framework UIKit" … }` around it — the shape
  `void/src/sokol/gpu.ms` ships; an untaken branch is never type-checked.
- **Cleanup follows discarded host rows**: owner disposal removes reactive wiring;
  `Host.removeChild` then drops native event routes, frees the detached Yoga subtree
  and releases each UIKit view retained across the C boundary.
- **Nested Text**: RN's paragraph model (flatten to attributed runs on one UILabel via
  NSAttributedString, measure func + prepared-layout cache, per-fragment hit-testing when
  press handlers arrive) — not the reference's merge with its static-content loss.
- **multiline**: UITextField vs UITextView differ at creation; pick the wire tag in the
  `TextInput` component from a static `multiline` prop (RN picks the backing control at
  init from default props, `RCTTextInputComponentView.mm:70`).
- **Safe area and resize**: UIKit owns the container frame through
  `safeAreaLayoutGuide`; `viewDidLayoutSubviews` notifies `createIosHost`, which
  refreshes the root dimensions and reruns Yoga only when the frame changes. The root's
  Yoga frame is recorded but never applied to the container.

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
