# Android Host

Status: the counter renders, rotates, backgrounds and tears down on the Android 36 emulator
through an Ion-generated Gradle project; **a press does not reach the host yet** (§9, parked on
`~/metascript/.inbox/compiler/2026-09-23-design-android-java-handoff.md`). The host is shared
with iOS: `src/platform/native/host.ms` over one bridge per platform, `src/platform/android/bridge.c`
here. `examples/android/` is the generated-project consumer and `bash tests/android/run.sh` the
lane. §1–§8 are the research the port started from, read on 2026-09-21 with `file:line`
evidence; judgment calls are marked as such. The two decisions these notes feed:

- **Boilerplate (gradle project, manifest, JNI packaging) comes from ion's generator**, not
  from a neon-side generator — the Nim original's generator is the inventory, not the plan.
- **The native-component mapping is learned from the Nim original and from React Native.**

| source | what it is |
|---|---|
| `~/projects/neon` | the Nim original: a complete working Android host (~250 KB: `src/platform/android/`) |
| `~/projects/react-native` | RN main toward 0.83 (`packages/react-native/package.json` deps `0.83.0-main`); Fabric is the mandatory default there |

Companions: `RENDER-LAYERS.md` (Android = Neon Layer A over the OS's RenderNode/GLES B+C, Host
object `android.view.View`), `RENDER-MODEL.md` (the NeonNode mount contract), `IOS.md` (the
same research for iOS).

---

## 1. The reference architecture (verified)

```
Nim (libneon-android.so)
  │  importc "android_bridge.h"          android.nim:11-230
  ▼
C: android_bridge.c / async_bridge.c
  │  JNI static calls, method IDs cached  AB.c:58-160
  │  Java→Nim: Java_com_..._NeonBridge_* → global fn ptrs  AB.c:239+
  ▼
Java: NeonBridge.java (view factory) / NeonRuntime.java (async)
  │  addView / setLayoutParams
  ▼
Android View tree (main thread only)
```

- **One C ABI, `void*` view handles, int-tag event routing.** Every view gets an int tag;
  all native→Nim events are global `cdecl` function pointers receiving that tag
  (`android_bridge.h:75-78, 111-121, 154-158, 217-236`). Nim keeps per-kind tables
  (`touchHandlers`, `textInputHandlers`, …) mapping tag → element → user closure.
- **JNI plumbing**: `JavaVM` stored in `JNI_OnLoad` (`async_bridge.c:952`); `NeonGetJNIEnv`
  attaches detached threads and never detaches (`async_bridge.c:59-77`); one global class
  ref + one `g_methods` struct of ~100 `jmethodID`s fetched once
  (`android_bridge.c:55-160`); `NeonBridge_initJNI(env)` must run on the main thread before
  anything else — `FindClass` from ALooper callbacks hits the wrong class loader
  (`android_bridge.c:2234-2249`, pthread_once-guarded at `:193-195`). Views returned by Java
  are `NewGlobalRef`-wrapped and released by `AndroidView_destroy` (`android_bridge.h:164-165, 180`).
- **Everything runs on the Android main thread** — tree build, yoga, JNI view ops, touch,
  timers, HTTP completions (posted to the main Handler before re-entering native:
  `NeonRuntime.java:44-47`). No render thread.
- **Async wake-up is eventfd → ALooper**: Nim's callback queue writes an eventfd registered
  with the main looper (`async_bridge.c:88-158`); zero idle CPU, sub-ms wake. Timers and
  HTTP cross JNI by **int id → lock-protected closure table** because `cdecl` closures
  cannot capture (`async.nim` timer/http dispatch).
- **Yoga is compiled from source into the same .so** (vendored `external/yoga` via CMake,
  `templates/android/CMakeLists.txt.template:18-36`) — not a prebuilt, not the Maven artifact.

## 2. Component mapping (the part we learn from)

`makeElement` tag dispatch (`android.nim:714-795`) + Java factory (`NeonBridge.java`):

| tag | Java class | defaults set at creation |
|---|---|---|
| `View` / everything unknown | `FrameLayout` (`NeonBridge.java:49`) | yoga flex column (`android.nim:792-795`) |
| `Text` | `TextView` (`:68`) | gravity 17 (CENTER), **white** text, `flexShrink: 1`, yoga measure func (`android.nim:722-737`) |
| `TextInput` | `EditText` (`:926`) | yoga height fixed 44 (`android.nim:738-746`) |
| `TextInputMultiline` | multiline `EditText` (`:1114`) | yoga minHeight 100 (`android.nim:747-755`) |
| `ScrollView` | `ScrollView` (`:1375`) / `HorizontalScrollView` (`:1395`) | **two-view pattern**: inner content `FrameLayout` with its own `contentNode` yoga node; children go there, never into the ScrollView (`android.nim:756-783`, `:833-837`) |
| `Image` | `ImageView` (`:1996`) | scaleType cover; async load by tag, LruCache + DiskLruCache, downsampling (`android_bridge.h:167-204`) |

No Button tag — "buttons" are Views with `onPress` (press feedback = opacity swap on
touch-down/up, `android.nim:528-544`). Props are applied by overload
(`bindProps(ViewProps|TextProps)` `:877`, `TextInputProps` `:1359`, `ScrollViewProps`
`:1612`, `ImageProps` `:1891`), each mapping style strings to yoga enums / Android
constants (`mapKeyboardType :1295` → InputType bits, `mapReturnKeyType :1319` → IME,
`mapTextAlign :1348` → gravity).

**Text nesting — the reference's answer and its hole.** Android has no nested TextViews, so
`insertElement` merges a Text child into a Text parent *before any tree insertion*
(`android.nim:808-828`, verified in the main session): only the child's reactive
`renderProc` is transferred, the child's yoga node freed, the child never enters any tree.
**A static nested `<Text>foo</Text>`'s string is silently dropped** — the merge branch has
no static-content path (`:814-822` has no else). No Spannable anywhere except measurement
(StaticLayout inside `measureTextView`, `NeonBridge.java:853-908`).

RN's answer (Fabric, the architecture this checkout forces): **one native text view per
paragraph**; nested `<Text>` and raw strings become shadow nodes with no native views,
flattened into an AttributedString in C++ (`ParagraphShadowNode.cpp:85-88`, verified) and
converted to an Android **Spannable** (`ReactTextViewManager.kt:141-145`) — nested Text =
style spans on one view. Measured through a yoga measure function with constraint-keyed
layout caching (`ParagraphShadowNode.cpp:222-261`); the built string is pushed to the view
as *state* only when changed (`:145-177`). Per-fragment press hit-testing walks the spans.
**This is the design Neon should port, not the merge.**

**TextInput echo guard** (RN): `mostRecentEventCount` + `comingFromJS` flags so native
typing and JS-driven value writes don't loop (`RCTTextInputComponentView.mm:43-68`, iOS but
the same problem on Android — `ReactEditText` text watchers carry the event count).
The reference Nim host has no such guard.

## 3. Layout

- Yoga runs **in dp**; `setViewFrame` converts dp→px (`round(dp * densityDpi/160)`) and
  lands positions as `FrameLayout.LayoutParams` margins — absolute framing, Android's own
  measure/layout pass is bypassed (`NeonBridge.java:188-238`).
- Text intrinsic size goes through a yoga **measure func** that JNI-calls
  `measureTextView` (StaticLayout with the TextView's paint, returns dp) —
  `NeonBridge.java:853-908`, registered via `NeonTextNode_setMeasureFunc`
  (`android_bridge.h:161`).
- Recalc is event-driven: initial layout after the container's `OnGlobalLayout`
  (`templates/android/MainActivity.java.template:36-43`), then `scheduleReLayout()` on
  reactive updates ("mark dirty → recalculate → apply frames", `android.nim:496-511`).
  `YGNodeMarkDirty` is only valid on nodes with a measure func (text).

## 4. Animation (for the later animation arc)

Only **transform + opacity, never layout** — the header forbids animating
width/height/padding/margin (`animation.nim:7-14`). Setters
(translate/scale/rotation/pivot/opacity) are one JNI call each; `setTranslate` is a combined
x+y call for gesture tracking. One-shot animations ride `ViewPropertyAnimator`
(`FLT_MAX` = skip property) and AndroidX `SpringAnimation` with initial velocity to
preserve gesture momentum (`NeonBridge.java:620-810`);
`setHardwareLayer` toggles `LAYER_TYPE_HARDWARE` during gestures.

## 5. Cleanup — what the reference gets wrong that we get for free

`removeElement`/`clearChildren` must remember the whole ladder: remove from global handler
maps (`cleanupHandlerMaps`, `android.nim:422`), free yoga nodes recursively, release JNI
global refs (`AndroidView_destroy`). The Nim original's iOS twin has an explicit TODO that
general disposal (For-list reconciliation) is unwired. In Neon the ladder is one host
function, `releaseNativeTree` in `src/platform/native/host.ms`, reached from `removeChild` and
from teardown; §9 has what pins it.

## 6. Boilerplate inventory — what ion must generate

The Nim generator (`src/cli/generators/android.nim`) emits into `platforms/android/`:

| generated | notes |
|---|---|
| root `build.gradle` | pinned `ndkVersion 27.1.12297006`, AGP version |
| `app/build.gradle` | namespace/applicationId, Java 17, **`abiFilters "arm64-v8a"` only**, `externalNativeBuild` cmake 3.22.1, deps appcompat + dynamicanimation |
| `settings.gradle`, `gradle.properties`, wrapper | androidx + jetifier flags |
| `AndroidManifest.xml` | INTERNET + ACCESS_NETWORK_STATE, NoActionBar theme |
| `MainActivity.java` | `System.loadLibrary("neon-android")`, FrameLayout container, OnGlobalLayout → render |
| `NeonBridge.java`, `NeonRuntime.java` | copied from the framework with `com.neon.app` → app package **rewritten** (JNI symbol names follow the package) |
| `cpp/CMakeLists.txt` | one SHARED lib = neon_jni.c + bridges + Nim `@*.c` + yoga sources |
| `cpp/neon_jni.c` | JNI entries → `NeonBridge_initJNI` + `neon_init` + `neon_init_async` / `neon_render` |

Ion now generates the project (Ion `6e3b88e`, `docs/PROJECT-GENERATOR.md` §Android
application): Gradle wrapper, manifest, and a package-stable bootstrap
`dev.metascript.app.NativeApp` whose five native methods (`start`, `resize`, `pause`, `resume`,
`destroy`) `bridge.c` implements; msc builds `libmetascript.so` with no CMake inventory.

What the table above has and Ion's bootstrap does not: `NeonBridge.java`. Every Java→native
event of the reference (touch, text, scroll, image, gestures, the async runtime) goes through a
listener class in that file, and JNI cannot define a Java class. Rejected with the user on
2026-09-23: a listener in Ion's bootstrap (puts Neon's bridge in Ion), a Neon Gradle module (a
second build description), a runtime-loaded dex, NativeActivity (only for self-painted
surfaces). Chosen: Neon declares its Java and keep rule and msc hands them to Gradle beside the
`.so` — the shape of wry's `build.rs` + `WRY_ANDROID_KOTLIN_FILES_OUT_DIR` (tauri-apps/wry
`build.rs`). A `/tmp` probe proved it on the emulator, keep rule included; the brief with the
numbers is the card named in the status line.

## 7. What the MetaScript port does differently

- **The host is `Host`** (`src/render/hostTypes.ms`): `createElement` receives the WIRE tag
  (`view`, `text`, `textinput`, `pressable`, …) and translates to the native class — the
  browser host's `htmlTagFor` pattern, not a new mechanism. `addEvent` takes a per-node
  closure; the host impl keeps the tag→closure tables the reference keeps, but they live
  inside the host, one `NeonSet*Callback` registration at init.
- **Extern surface gated, not branched**: one backend-agnostic extern block, the platform
  directives gated around it with `when (android) { @passL … }` — the shape
  `void/src/sokol/gpu.ms` ships; an untaken branch is never type-checked.
- **Nested Text**: port RN's paragraph model (flatten to one TextView + Spannable runs at
  the `Text` component level, measure func + cache) — decision to make when `Text` grows
  nested styles, until then the merge-with-static-loss must NOT be copied silently.
- **multiline / horizontal**: widget class differs at creation, so pick the wire tag at the
  component (`TextInput` branches on a static `multiline`, `ScrollView` on `horizontal`) —
  compile-time, no host-side recreation. The reference warns and refuses to swap at runtime
  (`android.nim:1621-1627`); RN chooses the backing control at init from default props.
- **No echo-debug logging**: the reference `echo`es on every mount/prop/touch; we don't.
- **Async/timers**: neon's own queue — `Pressable` already runs on the std timer
  (ROADMAP). The ALooper+eventfd wake pattern is the piece worth re-implementing when a
  native event loop lands; it is not needed for a first host that only renders and handles
  input synchronously on the main thread.

## 8. Sources — what was and was not verified

Read and verified in the main session (2026-09-21): `android_bridge.h` (whole),
`android.nim` structure + `makeElement`/`insertElement`/text-merge/`bindProps` map
(grep-anchored, merge block `:795-870` read whole), `apple`-side equivalents,
`ViewController.m.template` (iOS twin), ion `description.ms` + `xcode.ms` (whole),
RN `ParagraphShadowNode.cpp:70-98` and the `RCTComponentViewProtocol` conformances.

Scout-read (compressed, line-anchored, not line-by-line): `android_bridge.c` bodies
between ~`:300-2090`, `async_bridge.c` HTTP/timer internals, `NeonBridge.java` image
pipeline and gesture listener bodies, `animation.nim:240-346`, `async.nim` bodies,
`src/core/yoga.nim` (NOT read — which yoga symbols the Nim side binds is unverified),
`templates/android/gradle-wrapper.properties`, `commands/init.nim` config keys. The Android
platform `CLAUDE.md` in the reference is stale on paths (`out/android/NeonApp` vs actual
`platforms/android/`) and on `NeonSetButtonCallback` (no counterpart in code — iOS CLAUDE.md
only). Nothing above rests on an unverified region.

## 9. Measured on the emulator

```bash
ANDROID_SERIAL=emulator-5554 bash tests/android/run.sh
```

generates `examples/android/project.ms` and `tests/android/churn/project.ms` with Ion into a
fresh temporary directory, builds the counter Debug and Release (Release signed with a
throwaway key) and the churn app Debug, installs both Debug apps and drives them with
`tests/android/counter.py`. It refuses an `ANDROID_SERIAL` that is not `emulator-*`. The
visible frame it checks against is read from `dumpsys window` (status bar, navigation bar,
display cutout), not from the host. It waits for two identical `uiautomator` dumps before
each check: a dump taken right after a rotation can show the rotated window with the old
container frame.

Measured 2026-09-23 on code/test tree `3303aed1c4e24f50cc358cb938bf0e89eae74f80`, msc v0.2.55 build `e5f0ec68`, Ion `5b26122`,
Gradle 9.3.1, AGP 9.1.0, NDK 28.0.13004108, Zulu 17.0.18, Pixel_9_Pro emulator on Android 36:

- the command exits 1 at the parked step and nowhere before it. One process (the same PID)
  went portrait → landscape → portrait → home → launcher → foreground. Every text, `-`,
  `reset` and `+` included, lay inside the visible frame: `(0,156;1280,2784)` in portrait and
  `(156,156;2856,1208)` in landscape, where the display cutout takes the left 156 px. The
  title was `[453,228][825,309]` in portrait and `[1320,228][1692,309]` in landscape. A tap
  on `+` left the counter at `0`: there is no touch listener to receive it (status line);
- churn: 20000 cycles of three `Pressable` rows mounted and removed (120 000 native views,
  each a JNI global ref) finished with the app alive. With `DeleteGlobalRef` removed from
  `niViewRelease` it aborts with `JNI ERROR (app bug): global reference table overflow
  (max=51200)`;
- with the root guard in `layoutSetFrame` reverted (the iOS fix `4d2481c`), the lane fails at
  `portrait-initial`: the title sits at `[453,72][825,153]`, under the status bar;
- the Release APK installs and launches with the same six texts at the same bounds;
- `libmetascript.so` Debug 1 597 600 bytes, Release 1 179 176; both need only `liblog`,
  `libm`, `libdl`, `libc` (Yoga links libc++ statically) and load at 16 KiB alignment
  (`0x4000`). APKs: Debug 2 455 796 bytes, Release 1 217 970.

The device-independent half is `tests/platform/nativeHost.test.ms`, on the C mock bridge in
`tests/platform/nativeBridgeMock.c`: removing a keyed row releases exactly its two views and
makes its tag inert, teardown releases every created view, and a remount starts clean; a
second release of one view aborts the mock. With the route removal or the view release in
`releaseNativeTree` dropped, it fails on the matching assertion. The same run exposed that a
closure handed to C is borrowed: `runApp` keeps the app in module state because Android calls
`start` after `MsMain` has returned.

Not measured: a physical device (slice 8), a press, `pause`/`resume` beyond what the
background step shows, and `destroy` followed by a second `start` on a device (the mock
remount covers the host side only). Yoga nodes are freed through `freeLayoutTree` in the same
two paths, but no test counts them.
