# Android Host

Status: the counter renders, rotates, backgrounds, counts presses and tears down on the Android 36
emulator through an Ion-generated Gradle project (§9, 2026-09-26); a tap reaches the host through
Neon's Android library (§6). The signed Release APK does the same on a physical phone under a
person's finger, and the Release AAB is signed with the same key (§10, 2026-09-30). The host is
shared with iOS: `src/platform/native/host.ms` over one bridge per platform,
`src/platform/android/bridge.c` here. `examples/android/` is the generated-project consumer,
`bash tests/android/run.sh` the emulator lane and `tests/android/device.py` its twin for a phone
in a person's hand. §1–§8 are the research the
port started from, read on 2026-09-21 with `file:line` evidence; judgment calls are marked as
such. The two decisions these notes feed:

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
2026-09-23: a listener in Ion's bootstrap (puts Neon's bridge in Ion), a runtime-loaded dex,
NativeActivity (only for self-painted surfaces). The first choice, msc copying declared `.java`
files and a keep rule beside the `.so` (wry's `build.rs` + `WRY_ANDROID_KOTLIN_FILES_OUT_DIR`),
was replaced with the user on 2026-09-25 by a standard Android library module, which AGP already
knows how to compile and whose consumer keep rules already reach R8: nothing is copied. Neon's
module is `src/platform/android/java/` (`Touch`, one `View.OnTouchListener` per event tag, and
`consumer-rules.pro`), declared once by `src/platform/android/library.ms` with Ion's
`androidLibrary`; Ion's `docs/PROJECT-GENERATOR.md` §Android application says how the generated
project includes it. The path given to `androidLibrary` must stay under the declaring module's
directory: a `..` fails in the macro until
`~/metascript/.inbox/compiler/2026-09-25-raiser-array-pop-fails.md` is fixed, which is why the
declaration is not in `src/platform/native/host.ms`.

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
- **Multiline** still selects a backing widget at creation. ScrollView's logical host node
  instead stays stable around a native vertical/horizontal control and refresh wrapper;
  the adapter moves the existing content when the axis changes. This preserves Solid row
  identity rather than rebuilding the app subtree. See `Scroll.replaceScroller` in
  `src/platform/android/java/src/main/java/dev/metascript/neon/Scroll.java`; the reference
  controls are RN's `ReactScrollView` and `ReactHorizontalScrollView`.
- **No echo-debug logging**: the reference `echo`es on every mount/prop/touch; we don't.
- **Async/timers**: no Neon queue. The std event loop owns timers and completions; one
  `timerfd` on the main `ALooper` is armed for its next deadline after every JNI entry, and
  its callback runs one loop pass inside the host's layout batch (`src/platform/native/loop.c`).
  The reference instead woke an eventfd from a sleeping thread per timer.

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
container frame. When the app is alive but another window holds the focus (`mCurrentFocus` in
`dumpsys window`), the lane names that window and its texts and exits 2 instead of 1: a system
dialog over the app is the emulator, not Neon. The app's own "isn't responding" or "has stopped"
dialog stays a failure (exit 1).

The 2026-09-23 run did not record how the emulator was started. Measured 2026-09-26 with
`emulator -avd Pixel_9_Pro -no-window -no-audio -no-snapshot-save` while the machine ran at load
95–108 on 14 cores: `sys.boot_completed` came first, and within 20 s the focus was
`Application Not Responding: com.google.android.apps.nexuslauncher` ("Pixel Launcher isn't
responding"); after "Wait" it was `Application Not Responding: com.android.systemui`, the dialog
that covered churn in the coach's run of 2026-09-23 (same command, load ≈ 10). Against that live
dialog the lane's check reported `a system window has focus: 'Application Not Responding:
com.google.android.apps.nexuslauncher' over the app (texts ["Pixel Launcher isn't responding",
'Close app', 'Wait'])`, and classified the same dialog as the app's own when asked for the
launcher's package. A second cold boot, started at load 11 (the boot itself took it to 28), showed
three such dialogs within 50 s of `sys.boot_completed` — System UI, Pixel Launcher, System UI.
After "Wait" on each the launcher kept the focus for 60 s and the lane passed. So start the
emulator with the command above, answer "Wait" to every `Application Not Responding` window until
`adb shell dumpsys window | grep mCurrentFocus` names the launcher for a minute, then run the lane.

Measured 2026-09-23 on code/test tree `3303aed1c4e24f50cc358cb938bf0e89eae74f80`, msc v0.2.55 build `e5f0ec68`, Ion `5b26122`,
Gradle 9.3.1, AGP 9.1.0, NDK 28.0.13004108, Zulu 17.0.18, Pixel_9_Pro emulator on Android 36:

- the command exits 1 at the parked step and nowhere before it. One process (the same PID)
  went portrait → landscape → portrait → home → launcher → foreground. Every text, `-`,
  `reset` and `+` included, lay inside the visible frame: `(0,156;1280,2784)` in portrait and
  `(156,156;2856,1208)` in landscape, where the display cutout takes the left 156 px. The
  title was `[453,228][825,309]` in portrait and `[1320,228][1692,309]` in landscape. A tap
  on `+` left the counter at `0`: there was no touch listener to receive it before §6's library;
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

Measured 2026-09-26 on code/test tree `9a552cf24ec346fc202f0548dcfe874139c3a42f`, msc v0.2.55
`227ebc34`, Ion `afe3c4f`, Yoga `f5a811d`, the same Gradle, AGP, NDK and emulator:

- the command exits 0. Churn reached `churned 20000` with the app alive. One process went
  portrait → landscape → portrait → home → launcher → foreground, then a tap on `+` showed `1`
  and `odd`, a rotation to landscape kept them, and a second tap showed `2` and `even`. Every text
  lay inside the visible frame at every step; the title was `[453,228][825,309]` in portrait and
  `[1320,228][1692,309]` in landscape;
- in 1 of 3 runs (the first, right after install) the first landscape put the title at
  `[1242,228][1614,309]`, centred on the full 2856 px instead of the visible frame; the second
  landscape of the same run and both landscapes of the two reruns were at `[1320,…]`
  (`BUGS.md` §3);
- red control, the `androidLibrary` line removed from `src/platform/android/library.ms`: the lane
  exits 1 at `build`, where Release fails at `verifyNativeClassesRelease` with "R8 removed
  dev.metascript.neon.Touch, but libmetascript.so implements its native method
  Java_dev_metascript_neon_Touch_touch"; the Debug APK of that build installs and aborts at `start`
  with `F Neon: dev/metascript/neon/Touch threw` after a `ClassNotFoundException`.

Measured 2026-09-26 before the counter built again, the Java half of the press without the host:
a probe app generated by Ion from its Android fixture shape — a C file that implements
`NativeApp`, puts one `TextView` in the root and attaches `new Touch(7)` to it, and an entry that
imports `src/platform/android/library.ms` instead of declaring a library of its own. Code/test
tree `581b91eb9635aff0ee3dd151807bccd3cc95a42b`, msc v0.2.55 `227ebc34`, Ion `afe3c4f`:

- `assembleDebug assembleRelease` exit 0, `verifyNativeClassesRelease` ran; `dexdump` finds
  `Ldev/metascript/neon/Touch;` in both APKs and R8's mapping keeps the name
  (`dev.metascript.neon.Touch -> dev.metascript.neon.Touch`); nothing is written under
  `src/platform/android/java/`;
- a tap on the label logs `touch tag=7 action=0` then `touch tag=7 action=1` from
  `Java_dev_metascript_neon_Touch_touch`, Debug and Release;
- red control, the `androidLibrary` line removed: Release fails at `verifyNativeClassesRelease`
  with "R8 removed dev.metascript.neon.Touch, but libmetascript.so implements its native method
  Java_dev_metascript_neon_Touch_touch"; Debug builds and installs, and `FindClass` finds no
  `Touch` (`listener=missing`).

The device-independent half is `tests/platform/nativeHost.test.ms`, on the C mock bridge in
`tests/platform/nativeBridgeMock.c`: removing a keyed row releases exactly its two views and
makes its tag inert, teardown releases every created view, and a remount starts clean; a
second release of one view aborts the mock. With the route removal or the view release in
`releaseNativeTree` dropped, it fails on the matching assertion. The same run exposed that a
closure handed to C is borrowed: `runApp` keeps the app in module state because Android calls
`start` after `MsMain` has returned.

Not measured: `pause`/`resume` beyond what the background step shows, and `destroy` followed by a
second `start` on a device (the mock remount covers the host side only). Yoga nodes are freed
through `freeLayoutTree` in the same two paths, but no test counts them.

## 10. Measured on a physical device

```bash
ANDROID_SERIAL=<serial> python3 -u tests/android/device.py <results>
```

drives the counter already installed on a phone, with a person's hands where `run.sh` uses
`input tap`. It refuses an `emulator-*` serial, the mirror of `run.sh`: an emulator has no finger.
It force-stops and starts the app, then waits up to 300 s at each step for the person — hold the
phone upright, tap `+` until the counter shows `1`, tap it again until `2`, turn to landscape,
press home, reopen from the launcher — and checks each step with `counter.py`'s snapshot: the
same pid, and every text inside the visible frame from `dumpsys window`. `getevent -lt` records
the touchscreen (the input device that reports `ABS_MT_POSITION_X`) for the whole run, and a
press passes only when a `BTN_TOUCH DOWN` arrived since the previous step: `input tap` enters at
the input dispatcher and never shows there. It restores `accelerometer_rotation` and
`user_rotation` and prints both. Two traps cost a run each on 2026-09-27: the script reads the
screen about every 2 s and waits for the exact value, so a second tap before the first shows
skips past `1` (tell the person "one tap, then wait"); and `uiautomator` serves one dump at a
time, so a dump taken from outside while the script runs makes the script's own dump fail.

The Release build that went onto the phone, measured 2026-09-27 on code/test tree
`812060de6123f0fcb06b75ccbe219a70bf55afd7`, msc v0.2.55 `013853dd`, Ion `4198106`, Yoga `dba68fd`,
Gradle 9.3.1, AGP 9.1.0, NDK 28.0.13004108, Zulu 17.0.18:

- generated from `examples/android/project.ms` and built with `assembleRelease bundleRelease`
  (exit 0), signed through Ion's `ION_ANDROID_*` variables with a dedicated key: PKCS12
  `~/.android/neon-counter-release.p12` on the machine that built it, alias `neon-counter`, RSA
  4096, valid until 2054-02-12. Its password lives only in the macOS keychain item
  `neon-counter-release` and reaches the build environment through
  `security find-generic-password -s neon-counter-release -w`; the build log contains no
  "password";
- `app-release.apk`: 1 257 837 bytes, sha256
  `ecd76fb03db89866e8bbaf612878f448a6781550a9559230e1f22910247bba75`. `apksigner verify
  --print-certs`: v1 + v2, one signer `CN=Neon Counter, O=MetaScript`, certificate SHA-256
  `7db19e7c02654ff1f6054cd115fd6e7837d2120ea03f92459010981c73b77c22`;
- `app-release.aab`: 842 652 bytes, sha256
  `15a3340473c797f41e30c978e32f5dcdb963f92763915929597838b96deae7f8`. `jarsigner -verify`: "jar
  verified.", the same DN; the only warnings are the self-signed certificate and the missing
  timestamp;
- `libmetascript.so`: 1 218 224 bytes, every LOAD segment aligned `0x4000`, NEEDED `liblog`,
  `libm`, `libdl`, `libc`; `zipalign -c -P 16` OK;
- red controls: with no signing variable set, `verifyReleaseSigning` exits 1 and names all four,
  `ION_ANDROID_STORE_FILE` (or `-Pion.android.storeFile`), `ION_ANDROID_STORE_PASSWORD`,
  `ION_ANDROID_KEY_ALIAS` and `ION_ANDROID_KEY_PASSWORD`, each with its `-P` form; with only
  `ION_ANDROID_KEY_PASSWORD` unset, `assembleRelease` fails at the same task and names that one.

Measured 2026-09-30 with that APK installed on the phone (the `base.apk` the package manager
holds has the sha256 above) and `device.py` as committed beside this section:

- Solana Seeker (`ro.product.model` `Seeker`), Android 16, API 36, arm64-v8a, kernel page size
  4096, touchscreen `/dev/input/event2`. The 16 KiB-aligned library loads on the 4 KiB kernel;
- the command exits 0 and one process holds every step. Portrait: window `(0,0;1200,2670)`,
  visible `(0,110;1200,2598)`, title `[414,182][786,263]`, `0` and `even`. The first tap is a
  hardware `BTN_TOUCH DOWN` at (763, 654), released 81 ms later, inside `+`'s `Pressable`
  `[720,530][819,668]`; the counter then shows `1` and `odd`. The second, at (764, 616) for
  109 ms, gives `2` and `even`;
- landscape keeps `2` and `even` with every text inside the visible frame `(78,110;2670,1128)`,
  where the display cutout takes the left 78 px; the title `[1188,182][1560,263]` is centred on
  that frame. After home and a reopen from the launcher the same process shows the same texts at
  the same bounds;
- the rotation settings are back to `accelerometer_rotation=1`, `user_rotation=0`.

Not measured on the phone: the Debug build, the churn app, and `destroy` followed by a second
`start`.

## 11. RN scrolling protocol — 2026-10-04

The portable surface is `ScrollViewProps` in `src/components/primitives.ms` and `FlatList`
in `src/components/flatList.ms`. Options and lifecycle events reuse `Host.setAttr` /
`Host.addEvent`; this slice adds no Host capability. Android's declared library dependency
is `androidx.swiperefreshlayout:swiperefreshlayout:1.1.0`, carried by Neon's library Gradle file,
not by Ion's bootstrap.

Reference constraints: RN `ReactScrollView.java` `onInterceptTouchEvent`, `onTouchEvent`,
`executeKeyEvent` and `handlePostTouchScrolling` govern disabling, drag/momentum and page
settlement; `RefreshControl.js` `_onRefresh` and `componentDidUpdate` require the app's
controlled value to win over a native gesture, even when that value remains false.
`ScrollView.js` documents interactive keyboard dismissal as iOS-only; Android keeps the
keyboard in that mode.

On source/test tree `d4f1963637acf2db1276453aaa99c44582797ed2`, installed compiler/support
`7a4af78c9` (deployment recorded at 13:17), both `examples/list/android/project.ms` and
`examples/flatlist/android/project.ms` generated, built as Debug and installed on Seeker
`SM02G40619100815`. The frozen-tree interaction lane was blocked before app assertions:
`mWakefulness=Asleep`, then `isKeyguardShowing=true` after a wake event. No keyguard
dismissal was attempted. An earlier candidate passed scroll/press/rotate/resume, but is
not the frozen-tree verdict.

### 11.1 Physical list acceptance — 2026-10-07

Source/test tree `4a4025c8962ded21c286b1a630232ceadc88f669`, installed compiler/support
`8506eaf03`, Ion generator from landed `94f7ad3` installed under an isolated HOME, Seeker
`SM02G40619100815` awake and unlocked. `examples/flatlist/android` now runs `ListAcceptance`,
the same consumer as iOS; `ANDROID_SERIAL=SM02G40619100815 python3 tests/android/flatlist.py`
drove the fixed 10,000-row lane, then measured row spacing (80/112 dp), a pinned `header 0`
after a drag and its press, inversion keeping `pressed header 0`, an inverted drag pinning
`header 8` at the list top and its press, and the measured end (`offset 4694`, `ends 1`,
`item 63` and `List end` on screen). Exit 0, one pid throughout.

The first run exposed an Android-only text bug: a label whose text changed after layout kept
its old frame (`offset 340000` clipped to the 168 px of `offset 0`). `place()` gives the label
fixed LayoutParams, so `TextView.setText` only invalidates, and `View.measure()` returned its
cached size for the unchanged spec. `niMeasureText` now calls `forceLayout()` first; the lane
asserts the label widens. Functional evidence only; load was not controlled.

Grid and sections (2026-10-07, source `9306954`, same Seeker, awake and unlocked):
`/private/tmp/neon-seeker-run.sh` with `tests/android/flatlist.py` ran every lane above, then
`grid_lane` (three cells per row 68.0 dp apart, `pressed cell 4 at 4`, a prepend that puts
`cell 60` first and moves `cell 0` to the second column, `pressed cell 4 at 5`, a press after
swiping) and `sections_lane` (`Section 0` pinned after a drag, `scrollToLocation(1, 0)` puts
`Section 1` at the pinned top, `pressed Section 1 item 1`); exit 0, one pid. The mode buttons
now wrap: five no longer fit one row. One earlier run on the rebased tree failed the existing
long-press step (`pressed none`); an isolated long-press probe and the full rerun both passed,
so it is recorded as an unexplained one-off, not a fix.

`examples/scrollmatrix` with `tests/android/scrollmatrix.py` covers native horizontal drag
(x moves, y stays 0, a drag presses nothing, a tap after it hits the card under the finger),
reactive axis replacement both ways with app state kept, and pull-to-refresh closed by the
app's `refreshing` value, then keyboard modes over the native TextInput: `on-drag` dismisses
on a drag, `never` spends the first tap on dismissal without pressing the card, `always`
presses with the keyboard kept, `none` keeps it across a drag (app signal and
`dumpsys input_method` agree); exit 0 on Seeker 2026-10-07. The first runs found two `Scroll.java`
faults, fixed in `1789560`: `SwipeRefreshLayout` caches its first child as the refresh target
and only lays out that view, so a replaced scroller never got a frame (content vanished);
and the old axis offset was carried into the new axis. The scroller now lives inside a stable
target, and a new axis starts at 0 as RN's remounted native view does.
