# iOS Host

Status: the first UIKit host and tracked Ion-generated integration app are implemented.
`src/platform/native/host.ms` owns the host and lifecycle handoff shared with Android;
`src/platform/ios/bridge.m` is its UIKit bridge; `examples/ios/` is the generated-project
consumer. This document keeps the measured
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
seams are `Target.iosApp` and `iosScript` in Ion, `runApp` in
`src/platform/native/host.ms`, and the process bootstrap in `examples/ios/entry.m`. Neon
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

Physical-device signing, provisioning and launch were unverified in this measurement;
§6.4 records the later physical-device run. Universal binaries, Swift library embedding
and MetaScript source-level debugging were outside this milestone.

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

```bash
bash tests/ios/run.sh
```

generates `examples/ios/project.ms` with Ion into a fresh temporary directory, builds it,
installs it on a throwaway iPhone 17 Pro simulator and runs `tests/ios/counterUITests.swift`
against it; the generated project is never edited. The XCUITest is its own bundle and
reaches the app by bundle identifier. Logs, the UI hierarchy on failure and named
screenshots stay in the printed results directory.

Measured 2026-09-23 on Neon `4c49e38`, Ion `a6cce63`, installed
compiler `d757c7e1`, Xcode 26.6 and iOS 26.5, one launched process driven
portrait → landscape → portrait:

- the process kept one PID and presses on the `+` static text changed the counter
  `0 → 1` in landscape and `1 → 2` after returning to portrait;
- every static text, `-`, `reset` and `+` included, lay inside the safe area
  `(0,62;402,778)` in portrait and `(62,0;750,382)` in landscape; the title frame was
  `(137,86;128,24)` in portrait and `(373,24;128,24)` in landscape;
- screenshots show the three pressable labels in the parent's text colour;
- with `4d2481c` reverted the command fails: the root's Yoga frame resets the container
  origin and the portrait title sits at `(137,24;128,24)`, under the status bar;
- without the label fix it fails with no `-` static text: each pressable is sized by its
  measured label plus padding (`32`, `61`, `34` wide) but the `UILabel` a string child
  materialises under a non-Text parent was never added to the parent's view.

### 6.4 Physical signing, Release archive and development IPA

Measured 2026-09-30 on Neon `1666e2c`, source tree
`8bcd6f9897bdfb0568ddc177751caf1550f5150a`, clean Ion
`c18f7035029af6c8866d53603c236fba482a4c7b`, clean Yoga `dba68fd`,
installed compiler `013853dd`, Xcode 26.6 / iPhoneOS SDK 26.5, and an iPhone
13 Pro running iOS 26.6.2. The phone was paired, Developer Mode enabled,
and `devicectl` reported `ddiServicesAvailable: true`.

- Fresh generation through Ion's generator (then its wrapper script, `ion generate`
  since Ion `5e5065e`) from the tracked
  `examples/ios/project.ms` succeeded. `plutil -lint` accepted the project;
  no PBX edits were made.
- Debug device build exited 0 with `CODE_SIGNING_ALLOWED=YES`,
  `CODE_SIGN_STYLE=Automatic`, `DEVELOPMENT_TEAM=4R7EAZY462`,
  `CODE_SIGN_IDENTITY=Apple Development`, `ARCHS=arm64`, and SDK `iphoneos`.
  No `-allowProvisioningUpdates` or account-settings change was used.
- Xcode selected certificate `EDE37BCFB4A07778B17022D7C59BAF1313F6234C`
  and wildcard development profile `6116108f-83fb-457f-940c-ad601b6f4895`,
  which includes this phone and expires 2027-05-11. The certificate's team is
  `4R7EAZY462`; `NA8RXR8UMR` in its display name is not the team.
- `codesign --verify --deep --strict` passed. Entitlements identify
  `4R7EAZY462.dev.neon.NeonCounter` and enable `get-task-allow`.
  The executable is arm64; both its Mach-O minimum OS and `Info.plist`
  `MinimumOSVersion` are `15.0`.
- `devicectl device install app` and `device process launch` succeeded
  wirelessly, after the person's permission. The fresh Debug app launched
  as PID `2153`; later process inventories retained that PID after a
  real press and rotation.
- The person confirmed finger presses increased the counter and that it
  worked in portrait and landscape. These are human observations, not
  captured exact values, parity transitions, screenshots or measured
  physical-device safe-area frames.
- After going Home and reopening the app, the person reported the retained
  value `1` and a real `+` press changing it to `2`. A subsequent `devicectl`
  process inventory confirmed the original PID `2153`, proving same-process
  background/foreground continuity. Parity text was not explicitly reported.
- Release `xcodebuild archive` exited 0 for scheme `NeonCounter` and
  destination `generic/platform=iOS`, with the same signing flags.
  Archive metadata, bundle identifier, arm64 executable and minimum OS agree;
  `codesign --verify --deep --strict` passed on the archived app.
  Release executable SHA-256:
  `0d4a3ce9dd1a92dc0f4721667a2271cb80d813af7555092f3532ab9603cc19c8`.
- With the person's approval to try a development-signed IPA, export exited 0
  using `xcodebuild -exportArchive` and ExportOptions `method=debugging`,
  `destination=export`, `signingStyle=automatic`, `teamID=4R7EAZY462`.
  The IPA SHA-256 is
  `5aa9fbf80db65c941876cc1c501fb716ea5e4d1926f4c680cfb3addc24ead47e`.
- The actual IPA payload passed `codesign --verify --deep --strict`.
  Its bundle id, executable, arm64 architecture, team, development certificate,
  minimum OS `15.0` and embedded phone provisioning agree with the archive.
  `get-task-allow` is true: this is development signing, not distribution signing.
- The `.app` extracted from the IPA installed and launched wirelessly through
  `devicectl`, as PID `2342`. The earlier PID `2153` observations belong to the
  Debug run; this intentional Release reinstall/relaunch starts a separate run.
  The person subsequently gave a positive confirmation ("ngon"), without
  explicitly reporting the Release value/parity transition or frame measurements.

Signing control: `CODE_SIGN_STYLE=Manual` with this explicit profile failed
with exit 65: the profile is Xcode-managed and cannot satisfy manually
managed signing. Automatic signing with the existing team selected the
installed profile successfully.

Do not attach LLDB during the finger run without accounting for its stop:
here it stopped the app with `SIGSTOP` while loading system libraries from
device memory, and taps stopped responding. Stopping the local debugger and
`devicectl device process resume --pid 2153` restored input, as confirmed
by the person, without relaunching. No synthetic touch was sent.

The person approved trying a development-signed IPA for this milestone.
No usable Apple Distribution identity is installed, and the existing store
profile names another application; App Store/ad-hoc distribution is not proven.
Exact `0/even → 1/odd` finger evidence and physical frame measurements remain
open, as does final acceptance. These observations do not close Phase 1.

### 6.5 Final mobile matrix — 2026-09-30

The run started from clean Neon `7caa23a`, tree
`3e12c79750f6978ab059292b6081dd2548ca099e`, clean Ion `c18f703`, tree
`7a483231f870f588d5e5836ce3e99c21fb08dcf5`, and clean Yoga `dba68fd`, tree
`6ad92281259c8cea5af178db7ec5e068f68d4f2d`. Installed compiler and support
stayed at `013853dd` before and after the run. Xcode 26.6, SDK 26.5,
Zulu 17.0.18, NDK 28.0.13004108, Gradle 9.3.1 and AGP 9.1.0 were used.

| lane / command | exit | observed result |
|---|---|---|
| Neon `bash tests/run.sh` | 1 | 92 green target-file lanes, exactly 8 known reds, 0 new / 0 absent |
| Yoga `sh scripts/test.sh` | 0 | layout/lifetime suite passed |
| Ion owning gate | 0 each | library check, ten test invocations, macOS example build, generator check |
| Ion `MSC=~/.metascript/bin/msc bash tooling/generator/tests/run.sh` | 0 | generator contracts and real macOS/iOS/Android fixtures passed |
| Neon `bash tests/ios/run.sh` | 0 | portrait → landscape → portrait, `0/even → 1/odd → 2/even`, safe-area assertions, one PID `29915` |
| Generated counter Release simulator build | 0 | arm64 `iphonesimulator`, ad-hoc signed, zero PBX edits |
| Neon `ANDROID_SERIAL=emulator-5554 bash tests/android/run.sh` | 0 | Debug/Release build, `churned 20000`, rotation, Home/resume, `0 → 1 → 2`, one PID `6156` |
| Physical iOS Release `0/even → 1/odd` and frame numbers | — | not explicitly captured; the person gave a positive confirmation only |

The iOS UI test measured value frames `(422,60;31,58) → (426,60;23,58)`
and parity frames `(424,186;27,15) → (426,186;22,15)` in landscape.
Screenshots show the labels and updated counter in both orientations.
These presses were XCUITest-synthetic; they do not replace the physical
finger observations in §6.4.

On Pixel 9 Pro / Android 36, all text bounds stayed inside the visible
frame. The first landscape title was `[1320,228][1692,309]` inside
`(156,156;2856,1208)`; the previously recorded cutout miscentring did not
appear in this run, which does not close its intermittent bug.
The emulator held launcher focus for 60 s before testing and was shut
down afterwards. The physical Seeker and its installed Release APK were
not modified. Lane entry waited for load ≤14 on this 14-core Mac;
the Neon Android lane started at 12.62. Emulator startup separately
waited for load ≤12; its exact startup load was not retained.

The eight reds match `BUGS.md` §3: the macro rejection-message fixture,
Chrome's missing bundle, three native Void/style files, two native theme
files, and JS `native.test.ms`. The full gate imports Void `69e1f7c`;
that checkout had unrelated metadata, asset and documentation changes,
left untouched. Do not describe every workspace checkout as clean.

The automated mobile lanes pass, but the full Neon gate still exits 1.
Phase 1 remains active; land past the measured reds needs permission
for this round. Distribution and exact physical iOS frame/parity
measurements are not claimed.

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
- **Timers**: no main-queue `dispatch_source` per timer. The std event loop owns timers;
  one repeating `CFRunLoopTimer` in the common modes (so it fires while a scroll view
  tracks) is set to its next deadline after every bridge entry, and fires one loop pass
  inside the host's layout batch (`src/platform/native/loop.c`).
- **Safe area and resize**: UIKit owns the container frame through
  `safeAreaLayoutGuide`; `viewDidLayoutSubviews` notifies `createNativeHost`, which
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

## 9. RN scrolling protocol — 2026-10-04

The portable surface is `ScrollViewProps` in `src/components/primitives.ms` and `FlatList`
in `src/components/flatList.ms`. The adapter uses the existing Host attribute/event channels
and UIKit's native scroll properties and delegate phases; it adds no Host capability.

Reference anchors: RN `ScrollView.js` keyboard contracts and bounce defaults,
`RCTScrollViewComponentView.mm` user-offset preservation, and `RefreshControl.js`
`_onRefresh` / `componentDidUpdate`. A native refresh gesture does not override the
controlled value: leaving it false stops the indicator immediately. The browser rejects
interactive keyboard dismissal explicitly; Android treats it as none, as RN documents.

On source/test tree `d4f1963637acf2db1276453aaa99c44582797ed2`, compiler/support
`7a4af78c9` (deployment recorded at 13:17), the Ion-generated
`examples/list/ios/project.ms` and `examples/flatlist/ios/project.ms` Debug applications
were installed on the Wi-Fi-connected iPhone 13 Pro (`00008110-001411093CEA801E`).
`CounterUITests/ListUITests` and `CounterUITests/FlatListUITests` passed through
`xcodebuild test -project tests/ios/counter.xcodeproj -scheme CounterUITests` with that
device destination. FlatList had 93 rows in the initial tree and 187 after index 5000;
press state survived rotation and Home/resume without a PID change.

`ScrollMatrixUITests` (`examples/scrollmatrix`) drives native horizontal drag and press,
axis replacement both ways with app state kept and the offset restarting at 0, and
pull-to-refresh, and `testKeyboardModes` the same four keyboard modes as Android against
`app.keyboards`; both passed on an iPhone 17 Pro simulator with the software keyboard
2026-10-07. On the physical iPhone 13 Pro (source `5cd5bf3`, compiler `8506eaf03`) both
`ScrollMatrixUITests` cases and all three `FlatListUITests` cases (fixed rows, measured/sticky/
inverted, grid and sections) passed the same evening. Two physical-only failures were the
harness, not Neon: Control Center opened over the app by a touch during the run, and an
downward drag starting near the bottom edge that iOS took as Reachability (the inverted drag now starts
mid-window, `tests/ios/counterUITests.swift`). The simulator has neither.
The real-Chrome per-module lane passed 12 ScrollView and 2 FlatList cases, including
horizontal geometry, paging, controlled refresh and disposal. A normal
`msc build --target=js` bundle of a horizontal 10,000-row FlatList app mounts in Chrome,
and its jump to row 3000 lands at x=300000, y=0 with scroll width 1000000, no page
error (installed msc `2d428dc42`, 2026-10-05).

### 9.1 Physical list acceptance — 2026-10-07

Source/test tree `4484f0da16dd140a506101ea107d7f5088ec1cef`, installed compiler
binary/support `8506eaf03`, real Ion generator from landed `94f7ad3`, Xcode 26.6 /
iPhoneOS SDK 26.5, physical iPhone 13 Pro. Shared machine; load was not retained,
so these are functional results, not performance evidence.

The consumer is `examples/components/bigList.ms` `ListAcceptance`; assertions are
`tests/ios/counterUITests.swift` `FlatListUITests`. A fresh Ion package installation
under an isolated HOME generated `examples/flatlist/ios/project.ms`; no patched
export or hand-edited generated project was used.

- `xcodebuild -project <generated>/NeonFlatList.xcodeproj -target NeonFlatList
  -configuration Debug -sdk iphoneos -jobs 1 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=4R7EAZY462
  CODE_SIGN_IDENTITY="Apple Development" build` emitted `Built 44 module(s)` and
  `** BUILD SUCCEEDED **`.
- `xcrun devicectl device install app --device 505D81BC-8417-521C-AD69-424A9BC6E4D6
  <products>/Debug-iphoneos/NeonFlatList.app` reported `App installed` for
  `dev.neon.NeonFlatList`.
- `xcodebuild build-for-testing -project tests/ios/counter.xcodeproj
  -scheme CounterUITests -destination id=00008110-001411093CEA801E` with the same
  signing settings built and signed the UI runner.
- `xcodebuild test-without-building` with that project/scheme/destination and
  `-only-testing:CounterUITests/FlatListUITests` first failed before runner bootstrap
  (`Unlock Le’s iPhone to Continue`). Rerun on the unlocked phone against the same
  installed app and runner: `testMeasuredStickyAndInverted` passed (29.2 s),
  `testTenThousandRows` passed (44.7 s), `Executed 2 tests, with 0 failures`,
  `** TEST EXECUTE SUCCEEDED **`.

The attached screenshots show header 0 pinned over measured rows at offset 267,
header 8 pressed and still pinned after inversion with row order reversed, and the
measured end at offset 4747 with `ends 1` and the footer in view. This closes the
iPhone fixed/measured/sticky/inverted acceptance on the current source and compiler;
it is functional evidence only, with no performance comparison.

Grid and sections, simulator only (2026-10-07, source `9306954`, compiler `8506eaf03`;
the iPhone was not available): `/private/tmp/neon-sim-run.sh` generated, built and installed
the same consumer on a fresh iPhone 17 Pro simulator and ran `FlatListUITests`, 3/3 passed.
`testGridAndSections` checks three cells per row 68 pt apart, a prepend that puts `cell 60`
first and moves `cell 0` to the second column while `cell 4` reads index 5, `Section 0` pinned
over a slow drag, `scrollToLocation(1, 0)` bringing `Section 1` to the list top, and a press on
`item 101` as `Section 1 item 1`. A fast drag flings past the 149 pt first section, so the test
drags slowly and holds. Not yet run on the physical iPhone.

Grid item ownership, simulator only (2026-10-07, `wt/rn-grid-own`, compiler `0d83c4867`): each grid
cell of `examples/components/bigList.ms` counts its own taps in a signal created inside the cell.
`testGridAndSections` taps `cell 2` and `cell 4`, prepends, and finds `cell 2 tapped 1` opening the
second row in the first column, then `cell 2 tapped 2` with `pressed cell 2 at 3` and
`pressed cell 4 at 5`; it passed twice. The same run with `src/components/virtualizedList.ms` of
`5e3fb7e` fails at "cell 2 keeps its own counter", the remount the pool removes.
`testMeasuredStickyAndInverted` failed in all three runs, the control included (BUGS.md §3).

### 9.2 Earlier list gate boundary — 2026-10-06

On source/test tree `58fa59202ac69a7cdc09ad837c60392c3cef4b85` with compiler
binary/support `31c88d4e8`, the normal `bash tests/run.sh` gate with the configured
Chrome runner returned 1: 142 green selections, four known-red selections,
zero new reds. Diagnostics matched the retained main export exactly: native
void 104, voidInput 110, style 95; JS native module export 1.
This is not a gate verdict for the later compiler or physical acceptance fixtures.
