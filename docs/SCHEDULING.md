# Scheduling — when Neon runs work, where, and how it reaches the screen

This doc owns what the code cannot say: the rules every host follows, why they have this shape,
what was measured, what was tried and rejected, and where the references do the same thing.
The code is the truth for how a host implements them (`src/platform/*/bridge.*`,
`src/platform/native/loop.c`, `src/animation/frame.ms`, `src/render/bind.ms`).

The rules below are the intended contract, not a certificate that every host meets it.
Only §Measured records runtime evidence, within each entry's stated limits. The current
source-read gaps are listed separately; none is closed by inspecting its implementation.

## Three contracts

Neon's core asks a host for three things; each platform maps them onto its own machinery, as a
Flutter embedder maps task runners and vsync.

- **Loop** — the OS loop and the frame clock. Post and wake are a native event source of the
  OS's own loop, never a private wait, so every loop the OS runs (nested, modal, live resize,
  menu tracking) services Neon.
- **Worker** — `spawn` (a MetaScript language feature, `recompiler/docs/LANG.md` §Spawn). Pool
  threads; the result moves back by pointer; completion is queued to the owning thread's
  dispatcher and signalled on its selector fd (`msGetDispatcherSelectorFd`,
  `runtime/promise/dispatch.h`).
- **Sink** — host operations, written into each backend's `Host` adapter. The direct sink
  (in-order calls) is the default; `hostTypes.ms` does not change. A recording sink exists only
  if a measured case needs it; none does.

The main thread keeps the reactive graph, the frame and input. There is no app-thread mode.

Why: Flutter and Solid 2.0 share three choices: an update runs whole, consistency over
concurrency, and the clock owner decides. They differ only in the clock (vsync vs microtask).
Flutter merged its UI and platform threads on every platform (flutter#150525; mobile since
3.29, desktop since 3.35). The reason was correctness of synchronous platform APIs (IME,
accessibility, app delegate), not speed. Every Neon host has synchronous callbacks it could not
answer from another thread: the iOS responder claim, WebView navigation, Android back,
Windows `WM_GETOBJECT` and IME, macOS TextKit measurement inside yoga.

## The frame

Order, from Flutter's `SchedulerBinding` and Android's Choreographer
(INPUT → ANIMATION → INSETS → TRAVERSAL → COMMIT, `Choreographer.java:1097-1106`):

0. **Input.** Continuous input (pointer move, wheel) is coalesced into the next frame and runs
   ahead of step 1 (`requestInputFrame` in `src/animation/frame.ms`): a move keeps the latest
   position, wheel deltas of one mode and modifier set sum, and a different kind in between keeps
   the order (`DesktopInput` in `src/platform/native/desktopInput.ms`). Discrete
   input (press, release, leave, key, text, preedit, focus, resize) first delivers whatever
   continuous input is queued, then runs its handlers and flushes at once. Layout and sink follow
   on the frame that paints it, so no frame shows effects without their layout. The raw stream
   still reaches area subscribers per OS event (`VoidAreaHandle.onPointer`), as
   `getCoalescedEvents` keeps it in the browser. Desktop hosts: `src/platform/void/windowHost.ms`
   (Ion window, sokol), `src/platform/windows/ion.ms`, and macOS `bridge.m` `drainInputs`.
   Native ScrollView offsets may update immediately; their coalesced reports precede motion.
   Physical input-to-paint proof is still required on each host.
1. **Animation** ticks at the frame's *target presentation time*, clamped monotonic (Flutter
   `animator.cc:135` `GetVsyncTargetTime`). An animation started in a handler reads elapsed 0
   on its first frame (Flutter `ticker.dart:205`).
2. **Reactive flush**, with microtasks drained (Flutter midFrameMicrotasks).
3. **Layout**, only if dirty, then **onLayout** for each node whose frame changed. The handlers'
   writes flush and layout runs again in the same frame, so no frame shows a layout its handlers
   have not seen; a host refuses by name after 8 passes. This is the browser's place for
   ResizeObserver (HTML "update the rendering": layout and resize observations loop before
   paint), not Flutter's post-frame or React Native's asynchronous event (`docs/REFERENCE.md`
   SF-8). A measure (`measureInWindow`, `measureLayout`) lays a dirty tree out first, as
   `offsetWidth` does in the browser, so an `onSettled` that measures (Solid's idiom) reads the
   frame being built; before a host's first layout it is refused `NotLaidOut`.
4. **Sink.**
5. **Post-frame** callbacks, for work that needs the painted frame; nothing uses this step yet.
   Their writes are the only ones that request another frame. Writes during 1–4 never do
   (`binding.dart:909-921`).
6. **Idle.** No active animation and no request flag means no further frame. A request is
   one-shot and idempotent.

Rules around it:
- Between vsync and the frame, queued loop work (timers, worker results) waits. Flutter pauses
  its secondary task source (`vsync_waiter.cc:107`).
- A late frame is dropped and re-requested, never queued (`animator.cc:125` "PipelineFull").
- The first mount is a synchronous warm-up frame. A frame-callback mount shows a blank frame
  (flutter#163064).
- A frame request made while hidden is held, never dropped (flutter#45131).
- Emit nothing when clean.

## Frame clock per platform

| platform | source | timestamp |
|---|---|---|
| iOS native | `src/platform/ios/bridge.m` `NeonFrameTarget.tick` | display-link target rebased to the runtime monotonic clock |
| macOS native; Ion + Void on macOS | Ion `src/platform/macos/core/frame.m` `IonFrameTarget.tick` | display-link target rebased to the runtime monotonic clock |
| Android native | `src/platform/android/bridge.c` `frameTick` / `niRequestFrame` | native AChoreographer vsync stamp; 32-bit `long` path samples current monotonic time instead |
| Windows native; Ion + Void on Windows | Ion `src/platform/windows/webview/poll.c` `vsyncThread` / `tickMs` | QPC after the selected output's WaitForVBlank plus estimated refresh period; compositor-clock fallback |
| Linux, Ion + Void | Ion `src/platform/linux/core/frame.c` `onTick` | GDK animation clock; future presentation lead is not established |
| sokol canvas | `src/platform/sokol/canvas.ms` `frameCanvas` | callback-time performance.now(), not an exposed display target; idle callback pause not proved |
| terminal, native fallback | `src/animation/frame.ms` `platformDriver` | requested 16-ms timer, current monotonic time; no display-target clock installed by terminal host |
| browser | `src/animation/frame.ms` `platformDriver` | requestAnimationFrame callback timestamp |

Ion paths above were read at `0572d900c4468b8aeb20dab2ce20939f0fd19b62` (clean checkout).
These are implementation pointers and clock-domain limits, not new timing measurements.

GTK reference `bac4a949b151eedada8bc60a97429d2176b0b28b`,
[`gdkframeclockidle.c`](https://github.com/GNOME/gtk/blob/bac4a949b151eedada8bc60a97429d2176b0b28b/gdk/gdkframeclockidle.c)
`gdk_frame_clock_idle_get_frame_time`, returns smoothed animation time during a frame,
not the literal raw cycle-start time. GDK's
[`get_refresh_info`](https://docs.gtk.org/gdk3/method.FrameClock.get_refresh_info.html)
separately predicts a presentation time after a supplied base time, returning zero
when history is unavailable. Neither source reading certifies the installed Linux
backend's target lead; measure that before changing Ion. The earlier "frame-start"
label was too strong, just as "predicted presentation target" would be.

### Source-read conformance gaps

- `src/animation/frame.ms` `runFrame` performs synchronous input and animation flushes;
  it has no separate mid-frame microtask drain. The step-2 rule remains a target.
- `src/platform/browser/dom.jms` `flushLayouts` and its shared ResizeObserver do not
  implement the native host's named eight-pass refusal. Browser loop handling is not
  proof of the same Neon contract. Per-element cleanup is separately pinned in
  §Measured; that does not close the layout-drain bound.
- Android `bridge.c` `niSetTransform` / `niSetOpacity` still make separate JNI calls;
  the batched writer below is intended, not shipped by this arc.
- Windows `bridge.cpp` `niwFrame` / `reportScrolls` and `windows/ion.ms`
  `runNativeWindow` have sampler and controlled-clock queue pins in §Measured,
  not physical first-wheel latency proof. Indicator Step timestamps still use
  callback-time `nowMs()` rather than the frame target. Modal sampling receives the
  frame target; its console pixel pin passed 551 cases after one unattributed overrun of
  its own 200-ms guard; see the modal entry in §Measured.
- `requestFrameAt` has timer/cancellation/held-driver tests; those do not certify a real
  hidden window's wake behavior. No whole-host idle, late-frame, or nested-loop verdict
  follows from the driver unit tests.

Reference pitfalls (not claims that every mitigation below is implemented here):
- **Apple.** Pin `preferredFrameRateRange` to the window's screen. Sokol reads `mainScreen`
  (`void/deps/sokol/sokol_app.h:5421`), and an unpinned range throttles a static window to
  30 Hz (makepad). ProMotion on iPhone also needs `CADisableMinimumFrameDurationOnPhone` in
  Info.plist. Pause the display link after a few idle ticks, not after every frame: makepad's
  `LINK_IDLE = 4` exists because per-frame pausing delivered about 70 of 115 frames.
- **Android.** Native `AChoreographer` is a separate looper event. A View written there
  invalidates for the next vsync, possibly one frame late (inferred, not measured; verify with
  Perfetto). The `long` callback rolls over on 32-bit.
- **Windows.** `DwmFlush` returns at once while the display is off; a 1 ms guard falls back to
  sleep (GPUI `vsync.rs`). Present-vsync combined with on-demand drawing spun a core (Zed
  #35379). Follow the requesting window's output rather than assuming the primary.
  Inside `WM_ENTERSIZEMOVE` and menu loops, a `USER_TIMER_MINIMUM` timer drains the
  dispatcher and runs the frame (GPUI
  `events.rs:276-312`).
- **Linux.** Flutter's fixed 60 Hz timer is still an open bug (#191245); do not copy it.

## Waking the main thread

A finished worker signals the dispatcher's selector fd. The host adds that fd to the OS loop:
`CFFileDescriptor` in common modes on iOS, `ALooper_addFd` on Android. Before that, the
native loop ran only on its own timer, so a result waited for the next timer or touch.

Desktop windows run Ion's loop; read its `src/platform/*/webview/poll.*`, not a
proposed Neon wake primitive. At Ion `0572d90` (source read, not a modal-loop run):
- macOS `mscWatcher` / `postNudge` relays readiness with an NSEvent; it is NOT the
  common-mode CFRunLoopSource previously claimed here.
- Windows `mscWatcher` / `ionWakeLoop` signals events in the normal message wait;
  it is NOT a Flutter-style hidden message-only wake window.
- Linux `ionLoopArm` registers the dispatcher selector with GLib.

The Loop contract still requires all nested OS loops to service work. Ion has explicit
macOS live-resize and Windows size/move/menu pumps; menus/modal panels on macOS and modal
dialogs on Windows remain source-read gaps, not measured freezes or verified progress.

## Animation

Animation consumes the Loop's frame clock; it adds no contract. Ownership (2026-11-04): this
arc owns the frame driver and clock; the animation arc owns the motion phase, paint-only
`Host.setStyleProp`, and moving `LayerEngine` writes into the Host adapter in program order.

Who animates:
- Core Animation, DComp and WAAPI run a handed-off animation on the compositor.
- Android, Void, sokol, Linux and terminal tick on main every frame.

Android has no public off-main View animation:
- `RenderNodeAnimator` is `@hide` and blocklisted.
- `ViewPropertyAnimator` ticks on main; its RenderThread backend was never assigned and is gone
  by Android 10.

Compose `graphicsLayer`, RN's native driver, Litho and Flutter all tick on main. So Android's
target is paint-only on main: one batched JNI call of (view, prop, value) into
`setTranslation`/`setScale`/`setRotation`/`setAlpha`, with no Style rebuild and no yoga.
The batched JNI call is still owed; see the source-read gaps above.

Rules learned from React Native and Motion:
- **Begin time.** The mirror and the platform take one frame stamp.
  - Core Animation: `targetTimestamp` via `convertTime`.
  - DComp target: the matching frame clock. Current `dcompComposition.cpp`
    `DCompVisual::compositionStamp` uses frame statistics `currentTime` minus lag,
    not `nextEstimatedFrameTime`; mirror/platform alignment remains unproved.
  - WAAPI: an explicit `startTime`.
  - Cap a late start at 40 ms (Motion `resolve-start-time.ts`).
- **Reactive writes vs animation.** A reactive style write must merge the animated values
  rather than replace the style. `bind.ms` `writeStyleProp` falls back to a whole `setStyle`.
  That is RN's re-render-resets-the-animation bug (facebook/react-native#14219).
- **Reading.** Hit testing and measurement read the model, including paint-only transforms.
  Reanimated's `Pressable` broke when they did not (#10121).
- **Settling.** On settle, write the final value into the model.
- **Hand-off.** Hand off only what the mirror reproduces exactly. Motion keeps colours off
  WAAPI because sRGB and linear mixing jump on interrupt.

## Heavy work

`spawn` stays explicit. `new Promise` keeps its TS meaning: the executor runs synchronously on
the caller, as in the browser. Async syntax alone does not authorize moving the work
to another thread.

Neon and std move their *own* heavy work off main, behind APIs that are already async:
- candidates are large `response.json()`, image decode, and text shaping and measurement;
- each is measured before it moves, because a crossing costs more than a small task.

### Choosing async or spawn

Use async/await for I/O that can suspend. Use native `spawn` for substantial independent
CPU work, not every small calculation. A Promise executor and a synchronous parser still
run on their caller; putting either in an async function does not make a worker.

The runnable example is `bench/ownWork.ms` `sample`: compare whole-result round trips
with worker-side consumption, rather than assuming that moving construction moves every
cost. Submit independent jobs before joining them; awaiting each submission serializes
a batch. Keep borrowed inputs alive and unchanged until the join. Worker code must not
write signals or touch a Host, native view, JNI binding or GPU resource. Apply the result
on the owning loop, and discard it when its owner/request is no longer current. An abort
flag is not CPU preemption; completion and shutdown still need ownership.

On the checked native compiler, start UI jobs from their handler/async callback, not from
a pending module-level await: the entry control below observes different loop progress.
This is a scoped consumer recommendation, not a workaround that closes the compiler card
`2026-11-05-await-of-a-spawn-handle-blocks-the-event-loop.md`. Both entry forms remain in
the benchmark. For capture, move, actor and cancellation rules, see recompiler
`docs/LANG-PREFERENCE.md` §9; JS scheduling is not native thread execution.

Still owed: remaining-host/real-load profiles, production offloads justified by measurements, and
a long-task report (main held longer than a frame) naming its owner. `AsyncStorage.mergeItem`
must retain read/merge/write ordering if its CPU work moves; blindly submitting independent
merges can lose updates. Its async surface alone proves neither offload nor safe concurrency.

On JS, WASM and workerd, `spawn` only schedules: Worker is same-thread until Web Workers back
it. On Android a worker must never call `ni*` (JNI binding), and one long flush on main is a
5 s ANR.

## Parity with Flutter and React Native

The arc's goal, in the person's words (2026-11-22): "on par về rendering flow/mechanic so với
các mô hình hiệu quả như Flutter, React Native". One row per mechanism the two references use to
get a frame on screen on time. Status is per Neon host and is a claim only where §Measured holds
the run; anything else says "rule only" or "not measured".

References read: Flutter `f101991` (engine paths under `engine/src/flutter/`, framework under
`packages/flutter/lib/src/`), React Native `693e9628e8c` (under `packages/react-native/`),
read for this table on 2026-11-22; each anchor was opened at that commit.

| mechanism | Flutter | React Native (Fabric) | Neon |
|---|---|---|---|
| Which thread runs app logic, layout and commit | UI merged into the platform thread by default (`common/settings.h:381` `kEnabled`); raster and IO threads separate | JS thread renders, commits and runs Yoga (`ShadowTree.cpp:333`); main thread mounts | Main thread runs the reactive graph, layout and sink; native hosts leave raster to the OS compositor. Matches Flutter's merged thread. Void hosts (Ion + Void, sokol) present from main (`windowHost.ms` `scene.present`): Flutter rasterizes on its own thread; cost not measured |
| Frame order | `BeginFrame` → transient callbacks → microtasks → build → layout → paint → composite → post-frame (`platform_configuration.cc:483-491`, `scheduler/binding.dart:1259-1368`, `rendering/binding.dart:691-700`) | No frame phase: commit runs after each JS task (`RuntimeScheduler_Modern.cpp:352`) | §The frame, same order. Microtasks between phases: **gap**, `queueMicrotask` undefined on C (compiler card `2026-10-20-queuemicrotask-undeclared.md`) |
| Animation clock | Target presentation time (`animator.cc:114-118`; iOS `targetTimestamp`, Android frame time + period) | Native driver: `displaylink.timestamp` on iOS (`RCTNativeAnimatedNodesManager.mm:465`), `frameTimeNanos` on Android; C++ driver uses `steady_clock::now()` | Target time on iOS, Android, macOS, Windows: jitter 0-0.04 ms on a busy main (§Measured, frame delivery). Linux lead unverified (Ion); sokol canvas, terminal and Windows indicators use callback time: **gap** |
| Late frame | Pipeline depth 1-2; when full, the frame is skipped and re-requested, never queued (`animator.cc:99-107`) | iOS mounts as soon as main picks the transaction up (`RCTMountingManager.mm:197`); Android drains on Choreographer `DISPATCH_UI` | Rule only (§The frame). Native hosts have no pipeline of their own; Void hosts not checked |
| Input | Delivered when it arrives; iOS holds extra packets of one vsync until the next (`pointer_data_dispatcher.h:103-115`); a packet requests no frame (`engine.cc:587`) | Continuous events replace the queued one of the same target and type (`EventQueue.cpp:29-50`); beat before the run loop waits (iOS) or on Choreographer (Android) | Continuous input coalesced into the next frame, discrete flushed at once (§The frame step 0); pinned on macOS and Windows. Physical input-to-paint latency: **not measured** on any host |
| Mount / commit | Layer tree handed to raster through the pipeline (`animator.cc:142-154`) | One transaction applied in one main-thread call (iOS `RCTMountingManager.mm:243-265`); Android merges transactions into one `IntBufferBatchMountItem` per JNI call (`FabricMountingManager.cpp:884-900`) | Direct sink, in order, inside the frame. iOS: one Core Animation commit per run-loop turn. Android: one JNI call per property write (`bridge.c` `niSetTransform`, `niSetOpacity`), not batched like Fabric: **gap**, cost not profiled |
| onLayout | Post-frame | Asynchronous event after commit, before mount, latest only (`ShadowTree.cpp:370-373`, `BaseViewEventEmitter.cpp:37-82`) | Inside the frame, before paint, re-laid out up to 8 passes: a recorded departure ahead of both (`docs/REFERENCE.md` SF-8). Browser host lacks the 8-pass bound: **gap** |
| Image decode | Worker pool, texture upload on IO, result on UI (`image_decoder_impeller.cc:698-743`) | iOS background queues (`RCTImageLoader.mm:1003`); Android Fresco | Windows: MTA worker (§Measured). Android: background executor then `post` (`Picture.java` `fetch`). iOS: `UIImage imageWithData` off main, but UIKit decodes such an image lazily at first draw unless forced; RN forces it: **likely gap, not measured** |
| Text layout | UI thread, synchronous FFI (`text.dart:3236`) | Inside Yoga measure on the layout thread (`ParagraphShadowNode.cpp:222`) | Main thread, synchronous inside yoga measure. Matches Flutter; kept on purpose (synchronous platform answers, §Three contracts) |
| Idle | `scheduleFrame` only on request; iOS link re-paused every callback (`VSyncClient.swift:198`) | iOS fully idle; Android reposts `DispatchUIFrameCallback` every frame while resumed (`FabricUIManager.java:1505`) | One-shot requests, `requestFrameAt` sleeps to a deadline, iOS link paused after 4 idle ticks. Whole-host idle and hidden-window cost: **not measured** |
| Hidden app | Frames disabled while hidden, request dropped, one scheduled on return (`scheduler/binding.dart:425`, `:878-885`) | — | Rule only: held, not dropped (§The frame). Not measured |
| Nested OS loops | iOS display link and timers in common modes (`VSyncClient.swift:74`, `message_loop_darwin.mm:33`); macOS live resize pumps until the new size commits (`ResizeSynchronizer.swift:96-115`) | Run-loop observers and display links in common modes (`PlatformRunLoopObserver.mm:79`) | iOS wake source in common modes; Ion macOS menus and modal panels run frames (Ion `f3ed8ec`); Windows menu and size/move loops pumped. Ion `messageBox`/open-file from MS still block (Ion inbox note 2026-11-13): **gap, Ion owns** |
| Worker result | Platform task runners | — | Wakes the loop at once: 690 → 0 ms on iPhone, iPad, Seeker (§Measured). `await spawn(...)` at top level holds the loop: **gap**, compiler card `2026-11-05-await-of-a-spawn-handle-blocks-the-event-loop.md` |

"—" means the reference has no counterpart worth a row. Gaps Neon can close alone: mid-frame
microtasks once the compiler delivers `queueMicrotask`; sokol, terminal and Windows indicator
clocks; the browser layout bound; Android write batching, if a profile shows the per-call
JNI cost; iOS forced decode, if a profile shows main-thread decode; Void present placement,
if a profile shows it costs frames; and the unmeasured rows (input latency, idle, hidden).

## Measured

### Integrated Windows image decode, 2026-11-13

Checked implementation/test tree `969e503e566c870de90f9014186be8615ea73581`
(HEAD `b8ce83da` plus the offload and focused checks, before gate registration
and this documentation): d87, MinGW 16.2, C++17/O2, test-only decode probes.
`ImagePicture` now uses the existing bounded queue; no worker receives a view,
picture pointer or main-apartment COM object. The reference remains RN Windows
`WindowsImageManager::requestImage` / `ImageComponentView::didReceiveImage` at
`aedf6c5a400c6037f56078d066aa43db385fd456`: background image work, notification
serialized with view lifetime on UI, UI-owned drawing. The raw-transfer choice
and its independent WARP/MTA diagnostics are recorded below.

`tests/platform/windowsImageConsumer.sh`, through `run-remote.sh --windows
--no-msc --cores 2 --job … -- bash tests/platform/windowsImageConsumer.sh`,
passed **3 consumer groups**: destroy/reuse and main adoption with production
`ImagePicture::Draw` full 64² offscreen WARP readback equal to the transferred
buffer; ready cancellation, already-taken stale batch and replacement/error;
nonblocking shutdown with two held decodes and a queued request, no late decode
wake or report. It also passed the updated **4096² ImagePicture worker** check.
Three independently compiled mutations reached named **RED 1**: retaining a
destroyed request's owner; omitting queue cancellation; corrupting the adopted
pixel buffer. These are kernel-event lifecycle checks, not an Ion event loop.

The unchanged real-loop fixture from the next section now passes on the console:
**metadata 4×2, picture 4×4, 3 Ion wakes, 2 main reports, 1 MTA pixel decode,
0 host decodes, exit 0**. The app executable is
`2b5ffd3b71739d2a283caab119d4363a35f5bcd9a2bec007cdc4d1be1143699b`.
An independent PowerShell Get-FileHash read bound **9 local sources, 6 executables
and 2 PNGs** to the consumer and app logs. Consumer positive executable
`050b080b3c537aa4de7c522c5df0d1ac90683f7e6e40523784cdea1b01ad55ca`;
4096 worker executable
`2e4694bdb844ef38d31fd4c84751502d25cb6d4f7889e8310a4ba4b0fa51191f`.

The updated `tests/platform/windowsImageDecode.sh` also passed **11 producer
groups**, full 64²/4096² equality to the STA WIC reference, **IDs 1,2,3** with
header-only metadata, and the ImagePicture ownership positive. Its **5 expected
RED controls** passed. The former synchronous legacy control is now an explicit
host-probe injection, not a claim that the removed legacy decode path still
runs. The producer queue algorithm and output-budget exclusions are unchanged.

Raw artifacts: `/tmp/native-threads-image-consumer-{candidate,controls,fingerprint}.log`,
`/tmp/native-threads-image-loop-green.log`, and
`/tmp/native-threads-image-integrated-producer.log`. Its 8 sources, 8 executables
and 5 mutated sources independently match PowerShell fingerprints in
`/tmp/native-threads-image-integrated-fingerprint.log` plus
`/tmp/native-threads-image-nul-fingerprint.log`: Get-FileHash cannot resolve the
Windows reserved name `nul.cpp`; .NET ReadAllBytes using the extended path
returned the matching SHA256 `2f5892f7b8cbfb727ee9347167e811f3cad58ae885ac7f91437c47480225bfb3`.
Reservation times including
sync/build: candidate **128 s / 4 cores**, consumer/control recipe **121 s /
2 cores**, producer recipe **135 s / 2 cores**; console app **3 s** under its
quiet reservation. These are slow checks, not decode latency or speedup numbers;
do not repeat them unchanged in the edit loop. Executable guards remain 20 s.

Gate registration is in the Windows branch of `tests/run.sh`: both standalone
recipes run, the real-loop app only builds there; its guarded console run stays
separate. Full gate and land have not run. WARP identity draw is not a hardware
presentation/resize/blur certificate; lifecycle cases were isolated, not all
replayed through JSX/Ion. Shutdown with an in-flight URL download is source-read
only (publication and wake share the shutdown lock); no network cancellation or
new network-concurrency bound is claimed. No physical A/B, end-to-end performance,
modal-loop progress, all-codec coverage or compiler CLI certification is implied.
Synchronous geometry/layout and AsyncStorage ordering are unchanged.

### Windows image bridge and real Ion loop pin, 2026-11-13

`tests/platform/windowsImageLoop.ms` is a compiled app using `runNativeWindow`,
not a replacement event pump. On d87's console, msc `fca3f0a80cc6`, checked tree
`1088882e21cf4f02b9a5f0f27de3af6ae8a72d95` (HEAD `62a511f2` plus the fixture),
the owned HTTP server delivered metadata **4×2** and picture **4×4** through the
actual bridge. There were **2 Ion onWake callbacks, 2 reports on the host thread,
1 pixel decode**. Only then did the ownership assertion reach expected **RED 1**:
`pixel decode ran on host thread`. ImagePicture is still synchronous; this is
not an integrated worker GREEN.

Build through `run-remote.sh --windows --cores 4 --job … -- msc build
 tests/platform/windowsImageLoop.ms --passC=-DNEON_IMAGE_WORKER_TEST
 --output=out/windows-image-loop.exe`. Run on the console through
`desk.sh run --cores 2 --quiet 2 --cwd <remote worktree> -- powershell -NoProfile
 -ExecutionPolicy Bypass -File tests/platform/windowsImageLoop.ps1`. The runner
refuses to open the window after console input in the preceding 60 seconds,
uses a 20-second executable guard, and the app has a 5-second watchdog. No
screen pixels, foreign windows, topmost flag or synthetic wake function are used.

Build and independent console SHA256 agree on executable
`d815f42d868d381e5b4b9633b7f0e7c4005749ec718d9ec8bbf96c37f4b3b2fa`.
All eight fixture/production/input hashes printed on the console match the local
files. Raw logs: `/tmp/native-threads-image-loop-build.log` and
`/tmp/native-threads-image-loop-red-exit.log`. The first runner printed a blank
PowerShell Process.ExitCode; it did not certify RED 1. The corrected runner
retains the process handle and checks GetExitCodeProcess; the unchanged binary
then reached the same named failure with native exit code 1.

This proves current mixed metadata/picture routing and normal-loop notification,
not cancellation/replacement/shutdown, worker ownership, full-pixel equality,
modal-loop progress, frame latency, performance, the test-runner CLI or a full
host gate. The fixture is an explicit app build/run, not a renamed test used to
close the separately recorded Windows `msc test` CLI failure.

### Windows image request identity, 2026-11-13

`tests/platform/windowsImageIds.cpp` exercises two real decode queues alongside
`ImageFetch`/`ImageHeaderSizeOfFile` from `src/platform/windows/image.cpp`. A fixture-owned
HTTP loopback server supplies the64² PNG; a fresh URL prevents a cache hit from replacing
the request. All three outputs and the metadata header are validated before the ID
assertion. This is the producer/API boundary, **not niwDrainImages or the Ion loop**.

At tree `7d1317c5a348bb56aef5d491a0b05ebad18e4d97`, fixture SHA-256
`5267275a3730096fa34f968dfff92698d92b249b1f0aa32354a3072bb853d29b` reached
`request IDs collide across pixel and metadata producers`, exit1: valid
`pixel64/pixel64/metadata64 probes=2 ids=1,1,1`. Controlled job exit0; no setup failure
was counted as RED. This collision must be removed before merging these producers with
main-owned request maps. Reusing the existing request-counter idiom across producers
avoids introducing another routing namespace; these IDs are opaque, not author values.

Checked fixed code tree `fef8e756a67b87570b4c53e3915f81f2a213e7c9` (base above plus the
three owned source/test files; documentation and parked modal fixtures excluded), source
`7c671417`, unchanged fixture, runner `076efb18`: `ids=1,2,3` and
`image-id domains/header-only delivery passed`. The two pixel probes were MTA; metadata
used the header API without another pixel-decode probe. The11 producer groups and all
five intended RED controls from the queue check below passed again. Overall job exit0.
Run the same `bash tests/platform/windowsImageDecode.sh` through
`run-remote.sh --windows --no-msc --cores 2`; MinGW g++16.2.0, C++17/-O2, no MSC. Each
executable still has its20s guard. No quiet-host or timing-performance comparison.

Raw `/tmp/native-threads-image-ids-{red,green}.log`; five RED/eight GREEN source hashes
matched. RED executable `b068af46177007076157984c3957a093ff5671d898dd59e484f5be338ddda345`
and64² input were independently rehashed; GREEN executable
`37e23b43e724f4954c2f0b6306677dc4cb673a560d79e5c89da4d00f48f473e8`, the six other
executables and64²/4096² inputs match independent `*-{red,green}-fingerprint.log` records.
RED reservation124s plus22s admission; GREEN319s plus2s admission: recorded slow checks,
not automatic repeat recipes. This does not certify concurrent-allocation stress,
counter exhaustion, live size/picture routing, graph/report delivery, real-loop wake, production offload or a
normal-host/full-gate/physical-device run. Those integrated consumer pins still follow.

### Isolated Windows decode queue ownership, 2026-11-13

`src/platform/windows/imageDecode.h` `ImageDecodeQueue` and
`tests/platform/windowsImageDecode.cpp` are the isolated producer/result check; they are
**not wired into ImagePicture**. Checked code tree
`40c2a7fb072eee7c3fde08c0d9e7ad6f0e0bb551` (base
`7ff3302008a86e31aa0b59b34495c1c223fdfa58` plus the five owned source/test files,
excluding this documentation and parked modal fixtures). Source `32f9b9ac`, header
`ad7d0192`, protocol `fc78b597`, runner `0a421ae2`, legacy fixture `9de89c73`.

Run through `run-remote.sh --windows --no-msc --cores 2`:

```bash
bash tests/platform/windowsImageDecode.sh
```

On d87/MinGW g++16.2.0, `-std=c++17 -O2 -DNOMINMAX`, no MSC, **11 positive groups
passed**. Every PBGRA byte for64² and4096² matched the STA/WIC cached-bitmap reference
after queue close/destruction. Gates reached the two-worker ceiling, oversized-output
exclusion, reservation retained until main takes the result, queued/running/ready
cancellation, source replacement, error delivery, close with ready output and close during
a blocked decode. Main remained the consumer; successful decode probes reported MTA.
The completion callback is a process-lifetime event stub, **not real Ion-loop progress**.
The check does not wait for every OS worker thread to exit before the pixel comparison.

Five controlled failures reached their intended assertions, exit1 each: legacy
ImagePicture still decoded on host; changing the worker ceiling to3 failed the worker-cap
assertion; removing byte admission failed oversized exclusion; releasing reservation at
decode completion failed `ready pixels escaped byte reservation`; removing encoded-NUL
URI rejection loaded the prefix file and failed that assertion. Overall job exit0. The
last control covers the shared metadata URI path too, not only the new queue.

Admission/cancellation prior art is React Native macOS `RCTImageLoader.mm`
`dequeueTasks`/`decodeImageData`, commit `8941740a4ec1accbbccf5e8ccc251a60b5cead87`.
Its inclusive comparisons and once-computed active-decode count at471–530 are not proof
of a strict two-job ceiling. The checked queue's ceiling and handoff reservation are
established by the gates and mutations above, not by copying the reference's defaults.

An earlier active-decode-only candidate passed nine groups, but returned its reservation
before the loader transferred ownership. That leaves completed buffers outside the
budget; it was rejected before integration. The current output reservation is not a
process-RSS bound: compressed inputs, queued URI descriptors, codec working memory and
results already taken by the consumer are outside it. One oversized output is admitted
alone. There is no new network-loading bound, exhaustive codec/real-image coverage,
performance/quiet-host/device/GPU certificate, complete ImagePicture cancellation or
shutdown proof, normal-host/full-gate run, or production offload claim. Metadata-versus-
pixel requests, request-ID domains and actual Ion-loop delivery still need integration
pins; synchronous text geometry and storage ordering have not moved.

Raw `/tmp/native-threads-image-decode-handoff.log`; seven source hashes matched. Main
executable `6f285248af65d1aff2681c9360ab03b6d57a3d6e4e81506bfc3c89248bd93f5d`, legacy
executable `fbd33fe2a94abda56f2ac0516e70857bd2b42b7166a2632e123b7c4d07059baf` and all
four control executables were independently rehashed with the64²/4096² inputs in
`*-handoff-fingerprint.log`. Source mutations and their hashes are recorded by the runner.
Reservation132s plus1s admission: recorded slow check, not an automatic edit-loop repeat;
each executable retained the20s guard. A first log parser counted control runs' positive
preambles twice (20 rather than11); counting the initial GREEN block fixed the parser,
not the product. Earlier nine-group artifacts remain separately in
`/tmp/native-threads-image-decode-{protocol,fingerprint}.log` at their own source scope.

### Windows image decode ownership RED, 2026-11-13

`tests/platform/windowsImageWorker.cpp` with the opt-in `NEON_IMAGE_WORKER_TEST` seam in
`src/platform/windows/image.cpp` `ImagePicture::Decode` makes the current thread-owner gap
visible. Base tree `c4c6354e5e63a281a1963520ce517da4be3acf5e`, plus fixture SHA-256
`ced0d3f620ee9ea8fac34b6b3e13d5cd141f5a36cda5c194bfc84af1e0f972a0` and instrumented source
`647f052cce96be84171e8243f692b9ab3364ac35d07845d7bd483ecbea99ddc2`.
Header remains `667063f5`; generator remains `6ee637b5`. Removing only the macro blocks
exactly recovers native baseline `49fe51de`; this step does not move production work.

On d87/MinGW g++16.2.0, two reserved cores, standalone C++/no MSC, the4096² PNG passed
header/setup validation, then failed **`decode ran on host thread`**, exit1:
`host=22996 decode=22996 apartment=3` (MAINSTA). The controlled wrapper expected that
specific failure and exited0. This is a reached ownership RED, not a timeout/setup failure.
Only the first assertion was reached: later MTA/wake/main-delivery/one-report assertions
are not yet exercised, and the event stub is not a real Ion-loop wake certificate.
Integrated ImagePicture cancellation, replacement, bounded work, shutdown and production
offload remain unproved; the isolated queue result above does not close this consumer gap.
This standalone fixture is not yet registered with `tests/run.sh`.

Through `run-remote.sh --windows --no-msc --cores 2`:

```bash
g++ -std=c++17 -O2 -DNOMINMAX -DNEON_IMAGE_WORKER_TEST \
  tests/platform/windowsImageWorker.cpp src/platform/windows/image.cpp \
  -o out/windows-image-worker.exe \
  -lurlmon -lole32 -lwindowscodecs -ld2d1 -ldxguid -luuid
python3 bench/imageInputs.py out/image-worker
uri=$(python3 -c 'from pathlib import Path; print(Path("out/image-worker/4096.png").resolve().as_uri())' | tr -d '\r')
timeout 20 out/windows-image-worker.exe "$uri"
```

Raw `/tmp/native-threads-image-worker-red-retry.log`; all four source hashes matched.
Executable `9c68d3887ef8929ed3d1352bb513ee3b3fb2b15154aeaed877fc59aa1fe9f8a4` and input
PNG `aae368ca0f86f0c573c95dfadebdcbcb9dd20723f56782a6919c622a89c806c6` independently
rehashed in `*-red-fingerprint.log`. Reservation98s plus293s admission wait: a recorded
slow check, not an automatic edit-loop repeat. Earlier360s caller timeout produced only
`pick-host: still waiting after 308s`, no allocation/build/test output. No owned
runner/picker/waiter or matching remote test/compiler remained in cleanup snapshots
(`/tmp/native-threads-image-worker-{red,timeout-check,timeout-processes}.log`). Retry
extended the caller's admission budget, not the unchanged20s executable guard.

### Owned WARP image consumer diagnostic, 2026-11-13

The next `bench/imageTransfer.cpp` variant reaches the Direct2D bitmap consumer used by
`src/platform/windows/image.cpp` `ImagePicture::Draw`: `CreateBitmapFromWicBitmap` with
BGRA8/premultiplied alpha/96dpi. It compares the retained-MTA proxy with `CreateBitmap`
from the worker's packed PBGRA bytes. These are **owned offscreen resources**, not desktop
sampling, window presentation, the parked modal test or the full Neon image pipeline.

Base tree `a9c2e42e5b25552b82ca303ce266bc6fc0096aa1` plus benchmark SHA-256
`adeb0f79416d6eb81a4f40e33973f1a1c8e4ded54beb7581f89cce2905aa2bb7`, generator still
`6ee637b588f735a0c6b1a7b9ec5ce93c073119466172527641d72fd723095aaf`.
d87/MinGW g++16.2.0, no MSC, two reserved cores; WARP helper constrains process affinity to
mask3 (first two logical CPUs), refusing that diagnostic setup if unavailable. Device,
shader/target and both creation paths are warmed. Five paired rounds alternate path order.

All **40 size/path/round records** matched every byte of the raw-reference GPU readback;
reference was explicitly nonblank. Changing one reference pixel then failed the specific
GPU equality assertion, exit2. Same executable also retained no-cookie lifetime failure
(expected2) and a64² independent-MTA CPU pixel pass. Overall controlled job exit0.

| Size | Raw CreateBitmap ms, median/max | WIC-proxy creation ms, median/max |
|---|---:|---:|
| 64² | 0.0304 / 0.0543 | 0.3638 / 0.4030 |
| 512² | 0.1806 / 0.2375 | 0.5379 / 0.6002 |
| 2048² | 2.5834 / 2.7879 | 3.2467 / 3.6356 |
| 4096² | 9.1496 / 9.6140 | 9.2974 / 12.1332 |

These are synchronous API-call times on **software WARP**, not hardware GPU timings or a
quiet-host/tail/frame certificate. The separate draw/readback/copy field includes target
readback and CPU buffer collection, not presentation. Worker decode and its pixel copy,
resource initialization, callback scheduling, full Image resize/blur behaviour, cancellation,
shutdown and loop wake are outside these numbers. At4096² both creation paths still cost
about9ms here: transport success does not eliminate main resource-creation cost. No
end-to-end offload speedup or production payload choice is established by this diagnostic.

Current combined diagnostic build/run, through `run-remote.sh --windows --no-msc --cores 2`:

```bash
g++ -std=c++17 -O2 -DNOMINMAX bench/imageTransfer.cpp \
  -o out/image-transfer.exe -lwindowscodecs -lole32 -luuid \
  -ld3d11 -ld2d1 -ldxguid
python3 bench/imageInputs.py out/image-transfer
out/image-transfer.exe "$(cygpath -ma out/image-transfer/4096.png)" --warp
```

`--warp-corrupt` must exit2 with `GPU pixels differ from raw reference`, not a setup error.
Raw `/tmp/native-threads-image-gpu-smoke.log`; executable
`48aa9271c2dd204504ec02f74665d7bb17ab07b0058319b11b70e35504d51b3a` and all four
PNG hashes independently rechecked in `*-fingerprint.log`; both source hashes matched.
Reservation92s plus11s admission wait: recorded slow diagnostic, not an automatic edit-loop
run. This measurement used native baseline `image.cpp`/`image.h` `49fe51de`/`667063f5`;
no modal ownership safeguard was changed or exercised. The later isolated queue check
above exercises the raw-result option; it does not yet prove the complete production
pipeline's lifetime, bounded loading or real-loop delivery.

### Independent MTA lifetime diagnostic, 2026-11-13

A follow-up to the paired control below separates decoding-thread exit from MTA lifetime.
`bench/imageTransfer.cpp --mta-usage` pins MTA resources independently with
[`CoIncrementMTAUsage`](https://learn.microsoft.com/en-us/windows/win32/api/combaseapi/nf-combaseapi-coincrementmtausage),
then releases that usage once after the COM results are destroyed, before process shutdown
([release contract](https://learn.microsoft.com/en-us/windows/win32/api/combaseapi/nf-combaseapi-codecrementmtausage)).
The API explicitly supports MTA resources surviving zero MTA threads. Main's apartment is
checked to remain STA in every mode; this does not move the UI into MTA.

Base tree `877906b29ca6c00e0219b66136d7f30184e5e944` plus benchmark SHA-256
`0a6528da2dd4ee59dc33b669294dcece15054037407ff7e8da9c4d389cb768bc`, generator unchanged
`6ee637b588f735a0c6b1a7b9ec5ce93c073119466172527641d72fd723095aaf`.
d87/MinGW g++16.2.0, historical `-std=c++17 -O2 -DNOMINMAX` build with
`-lwindowscodecs -lole32 -luuid`, two reserved cores, no MSC:

- Same executable retained the no-cookie exit-before-consume failure (`GetSize`
  `0x80010108`, expected exit2) and live-worker64² pixel pass followed by disconnect.
- Independent usage cookie: **all four64²/512²/2048²/4096² dimensions and every PBGRA byte
  matched on STA after the decoding worker had exited**. Overall job exit0.
- All six processes checked main STA; all reported `IAgileObject` `E_NOINTERFACE`.
  Standard marshaling plus retained MTA resources, not an untested direct reference,
  provided this successful path.

The current combined build above retains this mode:
`out/image-transfer.exe "$(cygpath -ma out/image-transfer/4096.png)" --mta-usage`.
Raw `/tmp/native-threads-image-mta-usage-retry.log`; executable
`0f4525f1624ba4113cd1b4e8e0e4ed9121aa7a415580f89f376bc2f20a145cda` and all four
PNG hashes independently rechecked in `*-fingerprint.log`; both source hashes matched.
Reservation100s plus1s admission wait is a recorded slow diagnostic. An earlier180s caller
timeout spent86s waiting and95s reserved in admission/sync, produced no compiler/test
output, and left the old executable. LedgerEND, no local runner/matching remote
transfer/compiler process and the old executable were checked in
`/tmp/native-threads-image-mta-{usage,timeout-check}.log`; this attempt gave no test
result, not a product RED or test pass.

This is a functional stock-PNG transport/lifetime result, not an offload speedup, UI-frame,
GPU upload/paint, cancellation/replacement, shutdown or wake certificate. The timing field
still excludes pixel copying/comparison. A production owner must outlive its COM results
and pending jobs; that full lifetime has not been implemented or tested. No production
code changed. The reference's direct-reference path remains untested here.

### Windows image COM lifetime diagnostic, 2026-11-13

`bench/imageTransfer.cpp` tests an MTA-worker → STA-main transfer using
`CoMarshalInterThreadInterfaceInStream` / `CoGetInterfaceAndReleaseStream`, not the
production image pipeline. Worker-local decoder, converter, factory and bitmap references
are released before its ready signal; only the marshaled result and expected pixel bytes
remain. Default mode exits the worker before main consumes it. `--keep-mta` keeps that
worker's COM apartment alive while main compares every PBGRA byte, then exits the worker
and calls `GetSize` again on the same interface.

On d87/MinGW g++16.2.0, two reserved cores, `-std=c++17 -O2 -DNOMINMAX`, base tree
`d76f824563edb0e50f6038129b639a4d68e01d95` plus benchmark SHA-256
`ddf4dfeaba72b9c33edc99e22dd17a0580a21aceb36a754f186879c1d968985e`:

- Same executable: default64² case failed `GetSize` with `0x80010108`
  (`RPC_E_DISCONNECTED`), expected exit2.
- Keeping MTA/worker alive: 64², 512², 2048² and4096² all matched dimensions and **every
  pixel byte** after unmarshaling on STA. All four then returned that same disconnected
  error after worker exit. Overall controlled job exit0.
- `IAgileObject` query returned `0x80004002` (`E_NOINTERFACE`) in every process.

This control changes MTA **and worker-thread** lifetime together; it does not distinguish
last-apartment uninitialization from thread exit. It does not test the reference's direct
COM-reference path, nor prove that path unsafe. Do not infer a safe production handoff
from successful marshaling alone. The independent-MTA follow-up above separates those
lifetimes. Request replacement, cancellation, shutdown and UI-loop wake remain untested.
The owned WARP follow-up above observes a scoped Direct2D consumer, not the full window
renderer. Adoption timestamps exclude pixel copying/comparison and are not a main-frame
cost certificate.

The historical pre-GPU build linked `-lwindowscodecs -lole32 -luuid`; the current combined
recipe above retains `--keep-mta` for the same controlled lifetime check.

Generator SHA-256 remains `6ee637b588f735a0c6b1a7b9ec5ce93c073119466172527641d72fd723095aaf`.
Raw `/tmp/native-threads-image-transfer-control.log`; executable
`3d9017dae87f08b3f4e6e980b5d2f7a9676ef0bf493977ac50f6b2a9ce927deb` and all four
PNG hashes independently rechecked in `*-fingerprint.log`; both source hashes matched.
Reservation105s plus1s admission wait: another recorded slow diagnostic, not an automatic
edit-loop run. Earlier exit-only source `bce56a10`/exe `53789042` and first PNG also bound
`/tmp/native-threads-image-transfer{,-fingerprint}.log`; paired control above supersedes
that single observation, not its scope.

[WIC's MTA guidance](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-howwicworks)
says in-box codecs support MTAs and codecs must use COM model Both; that alone does not
establish an apartment-independent result lifetime.
[`IAgileObject`](https://learn.microsoft.com/en-us/windows/win32/api/objidlbase/nn-objidlbase-iagileobject)
marks apartment agility and is recognized by the Global Interface Table, but does not
change normal call marshaling. Neither API reading certifies the installed bitmap's
untested transfer paths. Production remains unchanged.

### Windows text CPU diagnostic, 2026-11-13

`bench/textWork.cpp` exercises the real `TextLabel`/DirectWrite measurement path, no
window or GPU. d87, MinGW g++16.2.0, `-std=c++17 -O2 -DNOMINMAX`, two reserved cores;
base tree `51e53cd6956903890d7793b3d7b016f0fe345d57` plus benchmark SHA-256
`1c64614c9ba6a1b61f1f580aa6fbe4966f5e7c6bdafafce1b02fe441aaaf126a`.
Native `dwriteText.cpp` `e02cf79355d81457d543564f853bbabbb1da4ac17819cb9df30161898c935bb3`,
`dwriteText.h` `5c1973d61ce50a856ff03f715069923cea4c58b03bc181c098c9354528459df5`,
`composition.h` `469d9aa41c0cb62a2803a5f4a58439e0ac281232db80fb4e683fe002b0ad2236`.
No MetaScript compiler was used for this standalone diagnostic.

```bash
g++ -std=c++17 -O2 -DNOMINMAX \
  bench/textWork.cpp src/platform/windows/dwriteText.cpp \
  -o out/text-work.exe -ldwrite -ld2d1 -lole32 -ldxguid -luuid
out/text-work.exe
```

Run through `.gate-host/run-remote.sh --windows --no-msc --cores 2`. Five rounds per
pattern/length/phase, 200 records, expected layout-object counts, finite wrapped bounds,
cache/paint metric stability and UTF-16 length checks passed, exit zero. Existing font
factory/fallback is warmed first; size17, scale1, width320 then160. The longest cases:

| Phase, median ms | Latin, 73,728 UTF-8 bytes | Mixed Arabic, 98,304 bytes |
|---|---:|---:|
| SetText + initial Measure | 13.1193 | 138.7843 |
| Cached Measure, per-call average over100 | 0.000015 | 0.000015 |
| Colour write + Measure | 0.0001 | 0.0002 |
| Width change + Measure | 13.8474 | 117.3574 |
| Text change + Measure | 14.2294 | 119.1023 |

A width change built **zero new layout objects** yet did substantial work: the object
counter is not a shaping/reflow cost counter. Cache hits and colour writes do not justify
a blanket worker crossing; large changed paragraphs are a different case. This is not a
thread-offload A/B, quiet-box, paint/latency or glyph-correctness certificate. Patterns are
synthetic and repeated; font coverage and fallback appearance were not checked. Tiny
cached values are averages of100 calls, not a promised per-call deadline or a tail percentile.

Raw `/tmp/native-threads-text-work-smoke.log`; executable SHA-256
`ba95857fd2a2b774ab6f126ece6f528c0704a81f674fba890138f5f1c7f1f0ee`, independently
rehashed in `*-fingerprint.log`; all four native/benchmark source hashes matched the run.
Reserved wall time103s plus1s admission wait: a recorded slow diagnostic, not an edit-loop
check to repeat automatically. `src/platform/native/host.ms` `measureLabel` and
`src/platform/windows/bridge.cpp` `niMeasureText` remain synchronous. No permission to
silently make layout asynchronous or call a live native label from a worker follows from
this measurement. A future offload must preserve the pre-paint geometry contract and
prove its own immutable-input/result handoff.

### Windows image CPU diagnostic, 2026-11-13

`bench/imageWork.cpp` calls the real `ImagePicture` load/report path without a window,
composition device or GPU. d87, MinGW g++16.2.0, `-std=c++17 -O2 -DNOMINMAX`, two
reserved cores; base tree `8179ee0db25f3bc861e887a91c3db30404f7b4e8` plus benchmark
SHA-256 `5d968044a1317da1da6abad245db76ed7c5591eb4928629b9a0289dd3f6dd3a5` and
`bench/imageInputs.py` `6ee637b588f735a0c6b1a7b9ec5ce93c073119466172527641d72fd723095aaf`.
Native sources `image.cpp` `49fe51dec0998e90e83e7ba62bd14c035ed8e6785d3fca79077279ff5d5e1c9b`,
`image.h` `667063f5d302df7a97570e3859e5d9af816bdd845dcc31daed26ce31df62be18`.
No MetaScript compiler was used for this standalone C++ diagnostic.

Build with:

```bash
g++ -std=c++17 -O2 -DNOMINMAX \
  bench/imageWork.cpp src/platform/windows/image.cpp \
  -o out/image-work.exe -lurlmon -lole32 -lwindowscodecs \
  -ld2d1 -ldxguid -luuid
```

Generate inputs with `python3 bench/imageInputs.py out/image-work` (Python3.15.2), then
run `out/image-work.exe "file://$(cygpath -ma out/image-work/SIZE.png)" SIZE SIZE`
for each generated size, through `.gate-host/run-remote.sh --windows --no-msc --cores 2`.

| PNG dimensions | Load/decode/release median | Max, ms |
|---|---:|---:|
| 64 × 64 | 0.110 ms | 0.215 |
| 512 × 512 | 0.728 ms | 0.860 |
| 2048 × 2048 | 9.064 ms | 9.159 |
| 4096 × 4096 | 30.744 ms | 31.482 |

Five samples per size, 20 records, expected load reports and dimensions, exit zero.
Executable SHA-256 `6a0c929607dce3f7ed2930284f0e41c880768cca25318d62a8e088121f326f27`;
raw output `/tmp/native-threads-image-work-smoke.log`. The executable and all four PNGs
were independently rehashed afterward in `*-fingerprint.log`; all matched the run.
This was not quiet or an interleaved worker A/B. Header inspection warms WIC/file access;
load timing includes pixel realization and release, not network, paint, GPU upload or
onLoad dispatch. Inputs are synthetic, not a photo corpus; no pixel checksum was checked.
The reserved run took100s plus34s admission wait: a recorded slow diagnostic, not an edit-loop
check to repeat automatically. No host/frame-latency certificate or byte cutoff follows.

The measured candidate is `src/platform/windows/image.cpp` `Load`/`Deliver` → `Decode`:
full WIC pixel materialization still runs on the host. Reference RN Windows
`aedf6c5a400c6037f56078d066aa43db385fd456`,
`vnext/Microsoft.ReactNative/Fabric/WindowsImageManager.cpp` `requestImage` and
`StreamImageResponse::ResolveImage`, resolves pixels before posting completion to the UI
and uses a weak observer coordinator. `wicBitmapSourceFromStream` creates a factory for
that resolve; `Composition/ImageComponentView.cpp` consumes the resulting WIC bitmap.
This supports an off-thread decode candidate, not moving Neon's shared STA-initialized
factory or a live `ImagePicture` onto an arbitrary worker. Still prove COM ownership,
cancel/source replacement/shutdown and actual main-loop handoff cost before adopting it.

### JSON worker-entry diagnostic, 2026-11-13

This is a CPU/loop diagnostic, **not** a physical frame-latency or final performance
certificate. RTX Ryzen 9 9950X, Linux x86-64, two reserved cores, release build,
compiler/support `260e884307c5`; base tree
`b8d490fa7fdbd6a1b113648c9fc75142b92c12d0` plus `bench/ownWork.ms` SHA-256
`59831c4355e15c662eb61e80217f69fa7707a5b782d23a0c8841281775f379f1`.
Consumer hashes: `src/api/asyncStorage.ms` `0ffc8f63289283385dae13bb89e9e7e7d4897818e2b435c46ca8f29113f941a7`,
`src/api/storageServices.ms` `e286bb22bcfaebf1344081a2f15a2baece5901936a5fa00037c0f9d6cd1c7e30`.
Executable SHA-256 `f7a7bf21c14c5080129c3fec96e9217cdc8581a9e5f93d2a9274feacd8cb428f`.

Recipe: build `msc build --release --output=out/native-threads-json.exe bench/ownWork.ms`;
run the unchanged executable once normally and once with `--timer-entry`, through
`.gate-host/run-remote.sh --host rtx --cores 2`. Raw output:
`/tmp/native-threads-own-work-json-entry-smoke.log`. Five samples per entry/mode/size,
200 records total, row-count/last-ID and merge-marker checks passed, exit zero; this is
not a whole-graph checksum. Modes alternate forward/reverse
within each entry. The two entries ran module first, timer second, not process-order A/B.

At 65,536 rows / 10,856,766 ASCII bytes, milliseconds (median; gap max in parentheses):

| Entry / work | Completion | Largest 2-ms heartbeat gap |
|---|---:|---:|
| module await / parse + scalar result | 22.57 | 22.56 (24.35) |
| timer callback / parse on main | 22.64 | 22.64 (25.98) |
| timer callback / return parsed graph from worker | 23.49 | 8.07 (9.23) |
| timer callback / consume graph in worker, return scalar | 23.76 | 2.15 (2.58) |
| timer callback / actual AsyncStorage merge | 38.29 | 38.29 (40.57) |

The storage case uses installed in-memory services: no disk/network cost is claimed.
The graph-return and scalar-return controls differ in where validation and final graph
ownership/destruction occur; they do not isolate destruction from every continuation or
transfer cost. The module and timer controls differ in entry/wait path, not workload or
executable. Treat the result as evidence to inspect both boundaries, not proof of a
particular compiler implementation defect. Returning a large graph is not a free handoff.

Earlier reserved-quiet data (benchmark `b2c1e53d…`, 75 records) sampled an unrelated `msc`
in lifetime-CPU output; this does not quantify its instantaneous load. The subsequent
same-candidate quiet repeat timed out before admission/output after 180 seconds. No
matching waiter, pending pick, ledger row or local job remained on cleanup. There is no
quiet-repeat result. Do not derive a universal byte threshold or promise these numbers on
Windows, Apple devices, browsers, escaped/Unicode JSON or a mounted rendering host.

### Host wake and frame measurements

Interleaved A/B; the control is the branch with that platform's wake commit reverted.

- **Worker wake, Android.** Seeker, Debug build, `spawn(fib(44))` (about 17 s of compute),
  screenshot 40 s after launch with nothing touching the app. Control showed "waiting"; with
  the fix it showed "done 701408733". A `uiautomator dump` wakes the control's loop, so only a
  screenshot discriminates.
- **Worker wake, iOS.** iPhone 17 Pro simulator, `spawn(fib(40))`, screenshot at 12 s. Control
  "waiting"; with the fix "done 102334155".
- **Result latency** (`bench/wake`, 20 jobs per run, 1 s heartbeat timer, 300 ms idle between
  jobs). iOS simulator, 5 rounds, n=100 each side:

  | | p50 | p99 | max |
  |---|---|---|---|
  | control | 694 ms | 698 ms | 698 ms |
  | fix | 0 ms | 2 ms | 2 ms |

  Physical devices, Release, 5 rounds, n=100 each side (2026-11-07):

  | | p50 | p90 | max |
  |---|---|---|---|
  | iPhone 13 Pro control | 686 ms | 694 ms | 696 ms |
  | iPhone 13 Pro fix | 0 ms | 0 ms | 0 ms |
  | iPad Pro 12.9 control | 687 ms | 689 ms | 795 ms |
  | iPad Pro 12.9 fix | 0 ms | 0 ms | 0 ms |
  | Seeker control | 689 ms | 691 ms | 695 ms |
  | Seeker fix | 0 ms | 0 ms | 0 ms |

  The control is locked to the heartbeat phase (1000 − 300 − work). In a real app the wait
  ranges from 0 to the nearest timer period, and is unbounded without one.
- **S1, scroll while streaming** (`bench/stream`, Release). Seeker, 5 rounds × 5 flings,
  `dumpsys gfxinfo`. Janky frames 13 vs 12; p50/p90/p99 8/11/18 ms on both sides; missed vsync
  12 on both. S1's 200 ms interval pumps the loop anyway, so the wake fix cannot show there.
  This is the smoothness baseline for the frame-order work. Repeated on the rebased branch
  (2026-11-07, n=25 flings per side): janky frames 13 vs 13, p50/p90/p99 8/11/18 vs 8/12/18 ms,
  missed vsync 12 vs 12.

  iOS, XCTest scroll signposts, 5 rounds × 5 flings, n=25 per side (2026-11-07), hitch time
  ratio in ms per s, median / mean:

  | | dragging | deceleration | fps decel. |
  |---|---|---|---|
  | iPhone 13 Pro control | 0 / 15.0 | 0 / 5.6 | 81.8 |
  | iPhone 13 Pro fix | 0 / 8.6 | 0 / 3.7 | 82.0 |
  | iPad Pro 12.9 control | 0 / 5.0 | 3.5 / 5.0 | 105.6 |
  | iPad Pro 12.9 fix | 0 / 0 | 0 / 2.4 | 105.9 |

  Dragging means are a few single flings of 67-167 ms/s on both sides. The iPad's deceleration
  gap holds with the order swapped (fix first in every pair, n=25): control 3.5 / 6.5, fix
  0 / 2.2 ms/s; hitches per fling 1.04 vs 0.52. S1 has no `spawn` and no IO, only a 200 ms
  `setInterval`, so why the selector source makes the iPad smoother is not traced yet. The
  fix is the baseline Phase 0 is measured against.
- **Frame delivery** (`bench/frames`, Release, a box moved on a main-thread `requestFrame`
  loop, 1 s warm-up then 5 s; iOS both sides with `CADisableMinimumFrameDurationOnPhone`).
  Control: `CADisplayLink` with no rate range, paused after every frame, and AChoreographer;
  frames stamped with `performance.now()` at the callback. Fix: iOS rate range pinned to the
  screen's maximum, paused after 4 idle ticks; frames stamped with `targetTimestamp` (iOS) and
  `frameTimeNanos` (Android). 5 interleaved rounds (2026-11-08);
  jitter is a step's distance from a whole number of periods:

  | | fps | missed vsyncs | jitter p50 / p90 / max |
  |---|---|---|---|
  | iPhone 13 Pro control | 60.0 | 0 | 0.01 / 0.04-0.07 / 0.10-0.15 ms |
  | iPhone 13 Pro fix | 120.0 | 0 | 0 / 0 / 0.03 ms |
  | iPad Pro 12.9 control | 119.9 | 0 | 0.02-0.03 / 0.08-0.10 / 0.15-0.22 ms |
  | iPad Pro 12.9 fix | 119.9 | 0 | 0 / 0 / 0.03 ms |
  | Seeker control | 120.4 | 0 | 0.14-0.17 / 0.34-0.40 / 0.68-0.89 ms |
  | Seeker fix | 120.4 | 0 | 0 / 0 / 0.01-0.05 ms |

  The iPhone runs main-thread animation at 60 Hz until the link names a rate; the iPad already
  ran at 120. On an idle main thread the callback is late by a fraction of a millisecond, so the
  target timestamp barely changes the steps; a loaded main thread is not measured yet. Per-frame
  pausing lost no frames here (makepad's loss was not reproduced). The Seeker's callback runs
  later after vsync than iOS's, so its control steps stray more (up to 0.9 ms), still under a
  ninth of a period.

  Loaded main (`FRAMES_PROJECT=loadedProject`: a 5 ms timer busies main 0-4 ms, seeded, as data
  arriving between frames does), 5 interleaved rounds (2026-11-08):

  | | fps | missed vsyncs | jitter p50 / p90 / max |
  |---|---|---|---|
  | iPhone 13 Pro control | 60.0 | 0 | 0.19-0.47 / 2.06-2.44 / 3.48-3.91 ms |
  | iPhone 13 Pro fix | 120.0 | 0 | 0 / 0 / 0.03 ms |
  | iPad Pro 12.9 control | 119.9 | 0-1 | 0.52-0.66 / 2.34-2.78 / 3.66-6.96 ms |
  | iPad Pro 12.9 fix | 119.9 | 0 | 0 / 0 / 0.01-0.03 ms |
  | Seeker control | 120.4 | 0 | 0.58-0.64 / 2.33-2.52 / 3.75-4.65 ms |
  | Seeker fix | 120.4 | 0 | 0 / 0.01 / 0.05-0.12 ms |

  Both sides deliver every frame; what differs is the time the animation samples at. Stamped at
  the callback, a step strays by up to half a period whenever the timer held main at vsync, so
  the box moves in uneven steps; stamped with the display's timestamp, every step is one period.
- **Landed-tree device recheck** (2026-11-22, Release, msc/support `45ec4b08095`, Ion
  `1f7dc8e76bde`). Candidate: Neon `f3f19186`, tree `4b1d92c94246`, everything this arc
  landed after the frame-clock step (input phase, onLayout in the frame, `requestFrameAt`,
  dirty-root drain). Control: the tree the 2026-11-08 tables were taken on, `1ecc51511773`
  (`1772fe73`). Each app was built once per side and reinstalled for every run, five rounds,
  side order swapped every round; the tracked `run.sh` files rebuild per run instead.

  iPad Pro 12.9, five runs per cell (S1: n=25 flings per side):

  | | control | candidate |
  |---|---|---|
  | frame delivery: fps / missed / jitter max | 119.93 / 0 / 0.02-0.05 ms | 119.93 / 0 / 0-0.04 ms |
  | loaded main: fps / missed / jitter max | 119.93 / 0 / 0-0.01 ms | 119.93 / 0 / 0-0.03 ms |
  | result latency p50 / p90 / max | 0 / 0 / 0-6 ms | 0 / 0 / 0 ms |
  | S1 hitch ratio, deceleration, median / mean | 3.5 / 7.4 ms/s | 0 / 4.9 ms/s |
  | S1 hitch ratio, dragging, median / mean | 0 / 0 ms/s | 0 / 2.5 ms/s |
  | S1 frame rate, deceleration / dragging | 104.8 / 112.1 fps | 105.5 / 111.3 fps |

  No cell is worse outside its run-to-run spread. The candidate's dragging mean is one fling
  of 25 with a single 8.3-ms hitch (62.7 ms/s over a 0.13-s drag); the 2026-11-07 runs showed
  such single flings on both sides.

  iPhone 13 Pro, same five-round design; S1 then ran a second set of six rounds with the side
  order reversed, because the first set's hitch durations differed (n=55 flings per side):

  | | control | candidate |
  |---|---|---|
  | frame delivery: fps / missed / jitter max | 120.0 / 0 / 0.03-0.04 ms | 120.0 / 0 / 0.03-0.04 ms |
  | loaded main: fps / missed / jitter max | 120.0 / 0 / 0.03 ms | 120.0 / 0 / 0.03-0.04 ms |
  | result latency p50 / p90 / max | 0 / 0 / 0-11 ms | 0 / 0 / 0-6 ms |
  | S1 deceleration, flings with a hitch / total hitch time, set 1 | 10 / 233 ms | 10 / 367 ms |
  | S1 deceleration, same, set 2 | 12 / 317 ms | 9 / 267 ms |
  | S1 dragging, flings with a hitch / total hitch time, both sets | 4 / 42 ms | 5 / 75 ms |
  | S1 frame rate, deceleration / dragging, both sets | 81.5 / 85.6 fps | 81.3 / 85.0 fps |

  The first set's gap reversed in the second, so it is spread, not a regression. Hitches come
  in whole frames (8.3 or 16.7 ms); one 16.7-ms hitch in a 0.12-s drag reads 143 ms/s, which is
  why dragging ratio means swing between sets on both sides.

  Seeker, five rounds (S1: 25 iterations of three swipes per side, `dumpsys gfxinfo`):

  | | control | candidate |
  |---|---|---|
  | frame delivery: fps / missed / jitter max | 120.4 / 0 / 0.01-0.04 ms | 120.2-120.4 / 0-1 / 0.02-0.24 ms |
  | loaded main: fps / missed / jitter max | 119.0-120.4 / 0-8 / 0.03-6.01 ms | 120.4 / 0 / 0.04-0.13 ms |
  | result latency p50 / p90 / max | 0 / 0 / 0 ms | 0 / 0 / 0-1 ms |
  | S1 janky frames, sum / frames rendered | 16 / 4240 | 17 / 4234 |
  | S1 p50 / p90 / p99, median | 8 / 9 / 12 ms | 8 / 9 / 12 ms |
  | S1 missed vsync / slow UI thread, sum | 0 / 5 | 0 / 6 |

  No regression on any of the three devices. The single worst run was the control's (loaded
  main, round 2: 8 missed vsyncs, 6-ms jitter). Logs in the worktree (ignored):
  `out/evidence/deviceab-{ipad,iphone,iphone-stream2,seeker}.log`; harness
  `out/evidence/deviceAb.sh` and `deviceCampaign.sh`.
- **Pointer input per frame** (`bench/input.ms`, window host, no GPU: k moves between two
  frames, a move handler writes a signal 200 texts read, then layout). m1m, 3 interleaved
  rounds, control = the branch before step 2 (2026-11-08):

  | k | handler runs / frame control → step 2 | ms / frame p50 control → step 2 |
  |---|---|---|
  | 1 | 1 → 1 | 3.24 → 3.22-3.24 |
  | 2 | 2 → 1 | 3.88-3.92 → 3.22-3.26 |
  | 4 | 4 → 1 | 5.16-5.23 → 3.22-3.25 |
  | 8 | 8 → 1 | 7.73-7.83 → 3.23-3.30 |

  One move per frame costs the same; every extra move the OS delivers before the frame cost
  ~0.65 ms here and now costs nothing. How many moves a real desktop delivers per frame (mouse
  rate, OS coalescing) is not measured yet.
  Mobile hands touches over once per frame already; the step only adds an empty input phase
  there. `bench/frames` with a busy main, control vs step 2 (2026-11-08/09): iPhone 13 Pro 3
  rounds and Seeker 3 rounds identical on both sides (120 fps, 0 missed, jitter max ≤0.11 ms);
  iPad Pro 12.9 5 rounds, 4 identical, and the branch's first round right after the iPad was
  unlocked missed 2 vsyncs (max 0.92 ms). Rounds 4-5 on the iPad also carried the uncommitted
  native onLayout bound.
- **Desktop frame time** (m1m, 120 Hz, 60 `requestFrame` callbacks, lead = frame time −
  `performance.now()` in the callback, 2026-11-13). Ion window (`examples/voidFrames.ms`):
  median 7.22 ms, min 4.63 ms; macOS native host (`examples/macosNative/ionFrameLead.ms`):
  median 7.16 ms, min 3.20 ms; gaps 8.33 ms. Before, both hosts stamped `performance.now()`
  just ahead of the callback, so the lead could not exceed 0. Windows built, not run.
- **Windows Ion queued-wheel ordering** (2026-11-13, d87 desktop console,
  msc/support `c62ba752f7de`). Checked code tree
  `7a6dd73218ff6367820ad873a7a3f30fa3f60430`, before this entry.
  `msc test tests/platform/windowsIonWheel.ms` builds; the parked CLI still returns127.
  Run its unchanged generated executable through the desktop runner:
  `out/debug/_test_windowsIonWheel_d6b71d2403a999e6.exe`.
  Corrected consumer fixture **508 passed / 1 failed** (first-motion report **−1**)
  → **509/509** (report **120**); earlier setup-only failures are excluded.
  Four adapter/fixture hashes plus Ion's queue implementation match the remote files.
  Job `20261113-081634-68602` checked executable SHA-256
  `1210e3a1dc139daa1e2684fd11311ffb2240fcfe0306c7d83577f878ad2c2819` before running.
  The real `runNativeWindow` consumes adjacent synthetic wheel/frame records through
  Ion's queue with a deliberately future target, then observes the report in the first
  motion callback. This proves queue/phase order, not physical wheel delivery, display
  latency, idle behavior, modal-loop progress or the CLI.
- **Windows native scroll target-time sampling** (2026-11-13, d87 desktop console,
  msc/support `c62ba752f7de`, WARP composition fixture, no displayed window).
  Checked code tree `4508bc0b05aa978c471922fc466f923f1d9cd231`, before this entry.
  `msc test tests/platform/windowsFrameOrder.ms` compiled but the parked CLI still
  returned **127**; the unchanged generated executable ran through the desktop runner
  using the runner described under **Windows native frame/loop order**. Initial scroll cases:
  **495 passed / 3 failed** → **498/498**. Removing only the sampler clamp (plus the
  control file's CRLF rewrite) gives **497 passed / 1 failed**, with a stale-target
  offset of **−2155.54** → restored **498/498**. The strengthened fixture that snapshots
  the scroll report at app-frame entry also passes **498/498**. Five final source hashes
  match; desktop job `20261113-075335-3072` checked executable SHA-256
  `975238a923988cfc5348ed861bc66972265d36f16b2e9b03357d96596b4f1175` before running.
  This proves animated/direct-wheel offset and report sampling before the app-frame
  callback, including a target before the animation starts. It does not certify Ion's
  queued first wheel, indicator/modal clocks, physical input, display latency or the CLI.
- **DOM shared-observer cleanup** (2026-11-13, m1m, Chrome, playwright-core 1.63.0,
  msc/support `c62ba752f7de`). Checked code tree
  `8f7d98d90864e21768261f4e8ede01faf4321c4d`, before this entry.
  `bash tests/browser/run.sh tests/browser/dom.test.ms`: **158/158** → removing only
  `observer.unobserve(el)` **157 passed / 1 failed** → restored **158/158**.
  Production/test source hashes match the remote checkout. This pins target-specific
  cleanup, a retained detached node receiving no app callbacks, and a live sibling
  still reporting external CSS resizes. It is not a layout-loop-bound or latency proof.
- **Native host timestamp forwarding** (2026-11-13, m1m, msc/support `c62ba752f7de`).
  Checked code tree `27ce1faf311da24ec0dc09c29109a79f20f8ccd9`, before this entry.
  `msc test tests/platform/nativeFrameClock.test.ms`: mock-stub control
  **493 passed / 1 failed** → opt-in frame seam **494/494**. The default mock-path
  consumer `tests/platform/nativeHost.test.ms` remains **567/567**. Three source
  hashes match the tested remote checkout. This checks niFrameTime forwarding through
  the real native Host adapter into input/motion, monotonicity and one-shot/reentrant
  scheduling; it does not measure a physical display or change a production bridge.
- **macOS native pointer phase** (2026-11-13, m1m, msc/support `c62ba752f7de`,
  real AppKit bridge with synthetic NSView events, no physical device input).
  Checked code tree `ea1e43f1cf11fb8740e31239b9f421ec5121dfc4`, before this entry:
  `msc test tests/platform/macosPointerInput.test.ms` is **501/501**;
  `msc test tests/platform/macosFrameOrder.test.ms` remains **495/495**.
  Old immediate dispatch: **493 passed / 7 failed**. The added shutdown case then
  exposed **500 passed / 1 failed** before shutdown cancellation was fixed.
  Four local/remote source SHA256 hashes matched after the final run.
  This tree did not include scroll-report coalescing; physical input latency remains
  unmeasured. Coalescing before delivery follows RN macOS
  `RCTEventDispatcher.mm` `sendEvent` (135–190 at `8941740a4`); the frame boundary
  follows this document's existing main-thread contract, not a JS-thread dispatch.
- **macOS ordered native input** (2026-11-13, m1m, msc/support `c62ba752f7de`).
  Checked code tree `4e569793e83d312913b4acabe1cdba9ed538bf27`, before this entry.
  The same pointer pin now includes real NSScrollView offset changes: ten added
  cases are red on the preceding code (**501 passed / 10 failed**); final
  `msc test tests/platform/macosPointerInput.test.ms` is **512/512**, including
  19 bridge cases and a weak-target release check. Frame-order remains **495/495**.
  Four local/remote source hashes match. Native offsets change immediately;
  reports and drags preserve order before the frame callback, with only consecutive
  matching reports coalesced (the existing `DesktopInput` rule). AppKit wheel
  processing is unchanged. These are callback/order/lifetime checks, not a physical
  wheel test, input-latency measurement, or allocator/performance result.
- **Windows native frame/loop order** (2026-11-13, d87 desktop console, msc/support
  `c62ba752f7de`, WARP D3D11 + D2D + DirectComposition; no displayed window).
  Code tree `3dee2979fc35a82fb3cbaf090ad22d008699bc36`, before this measurement entry;
  control uses the identical pin with only `bridge.cpp` restored from tree
  `281de3e792c1e237c43a2a8701fa0e81c10f9405`. Green → red → green:
  **495/495 → 493 passed / 2 failed → 495/495**. The old order reports loop then frame
  (21); the candidate reports frame then loop (12), and a loop write requests the next frame.
  Pin: `tests/platform/windowsFrameOrder.ms`. Compile with `msc test` on that file;
  this compiler builds the executable but its plain-basename test runner exits 127.
  The unchanged generated `out/debug/_test_windowsFrameOrder_b0b3bc268f29c030.exe`
  was run through `~/metascript/.gate-host/desk/desk.sh run`, one core, in the synced checkout.
  Source hashes matched local files; each executable hash was checked in its desktop job.
  Final green job `20261113-061658-10301`, executable SHA256
  `8972ec65d4890d5f785c2969688c90414f9b81236c99c875c0a80d7bdf6b3f5a`.
  This is a console-scoped pin, not a certified ordinary SSH gate test.
  It proves bridge ordering and rearming, not the compiler CLI path, physical input
  latency, target-time lead, nested OS-loop progress, or a performance improvement.
- **Windows modal clock and capture qualification, one overrun unattributed** (2026-11-14–21, d87 console).
  The preserved baseline executable `61c844287b2841f76301ea16dd34cf00de5eaba481fbe6207057da435b435dcb`
  passes the harness's own-window check after console unlock, then reports
  **508 passed / 1 failed**, exit **1**: expected green `(0,255,0)`, actual `(144,58,0)`.
  The prior own-window refusal was a setup failure, not a clock measurement.
  `tests/platform/windowsModalFrame.ms` pins a synthetic target ten seconds ahead,
  with a sample before 200 ms of the 300-ms transition; ownership and deadline guards
  remain mandatory. The ordinary build entry permits separate build/console execution,
  like `windowsImageLoop.ms`; the test entry remains. Neither entry fixes the compiler's
  previously recorded plain-file test-launch failure.

  Candidate code tree `4bdb7fa3b1e37cda51c81275d5c46c86279851db`, msc/support
  `bac1b95e1948`: fade executable
  `af2216609b4c05374dd55f2850b6a687cafc8b6ebde544a84d671d8aa917ff4a`
  still fails, actual `(1,14,23)`, exit **1**. The four-core remote stage/build of fade,
  slide and the image-loop app took **186 s**; do not repeat that unchanged build as
  an edit-loop check. This is not a controlled red/green comparison: compiler, fixture
  entry and bridge code differ from the preserved baseline.

  A diagnostic build on that candidate logs `Modal::Step` receiving a sample
  **10006.856 ms** after `Present`, with a 220×220 modal and 180×180 child, while
  the screen sample remains `(9,157,7)`. Diagnostic executable:
  `03efc0faa807fb2c884c788d11dadac0ddb4c8d8a9321a7ca05bf402eb08471b`;
  bridge source `87562c2b458f66f48148834af75f7a00d2f2e1c3895819635a821681c6c55be8`,
  modal source `c000933f193b7c14e6bea35817245f023f0ff029080305ab28db2be437736d4a`.
  The temporary print-only instrumentation was restored after building. CPU clock/layout
  evidence does not certify presented pixels. No wait or ownership-check weakening
  may turn this result green.

  Follow-up controls used `bac1b95e1948`, code tree
  `4a25e2875aca1de62d59b2aa65f3a4ae2a89d434` (before this documentation update),
  `tests/platform/windowsModalFrame.c` `nmfPrepareWindow`, and the console runner
  with input desktop `Default`, at least 60 s since input, own-window capture,
  the unchanged <200-ms sample bound and 20-s executable guards. Disabling this
  HWND's transitions after show did not help: executable `e5fb843f…` still sampled
  `(1,13,9)`. A no-animation control `83839385…` also failed. Ordered diagnostic
  builds `888f3ed3…` / `84ad6ca8…` confirmed green RGBA, opacity 1, submission and
  even `WaitForCommitCompletion` returning `S_OK` before capture, yet sampled
  `(6,107,17)` / `(4,155,11)`. Those temporary changes were restored; production
  has no added compositor wait. Acknowledged composition is not a display receipt.

  A pre-show, thread-local hook produced `S_OK` while the HWND was still invisible:
  fade **28.29 ms**, slide **31.78 ms**, both RGB `(0,255,0)`, exit **0**.
  Fade executable `acb900c668b1213c7b4131cfe6d1c2b39cf993dc84a1950074dd53598598a5fd`
  was reused byte-for-byte from code tree `b9b2bd389798ab330dc8006d9f2d1e03937095b3`;
  slide: `e8d1acdeb5f9bbf0eb754546f6e30b766577fdb4e42f3ce14b08ede3185471fc`.
  Wrapper-only changes between those trees added input-desktop/receipt validation.
  Two one-change controls then produced native exit **1** specifically at the pixel
  assertion, not setup, ownership, timeout or compiler failure:
  - Callback-time sampling: `stepModals(nowMs())` in `niwFrame`, otherwise unchanged,
    executable `25e05c458a8c5c9361288fc3209049b07213f4c98577d399bdfd80025c02d727`;
    expected green, actual **(0,1,0)**.
  - Window transitions enabled: only `BOOL disable = FALSE` in the pre-show hook,
    executable `fc4b8526bb2a3e87f7e6d09a433323d307bca6a596969b5aa745a1dcdbadc1f5`;
    expected green, actual **(0,13,22)**.

  **The following restored fade nevertheless failed**, actual **(1,14,23)**, exit **1**.
  This was not a stable GREEN→RED→GREEN proof. Interference from an unmanaged closing
  window remained a hypothesis, not a finding; the later clock-only sequence below
  tested whether that control was necessary to trigger the failure. The first temporary control runner failed C# compilation before either
  control launched and is excluded; its corrected generator asserts unique body-only
  replacements and preserves the C# heredoc. Evidence:
  `/tmp/native-threads-modal-{preshow,controls}-build.log`,
  `/tmp/native-threads-modal-controls{,-v2}-run.log`.
  The 4-core stage/build of slide and two controls took **118 s**; reuse these
  unchanged artifacts rather than rebuilding. No full gate, first-mount latency,
  physical performance or TIME-MACHINE isolation verdict follows.

  A subsequent clock-only sequence reused those artifacts: both initial cases and
  restored fade passed, but restored slide failed `(12,1,41)`. Thus the deliberately
  enabled window-transition control is not the sole trigger. In a later diagnostic
  variant, compiler `74ae464d8f4`, eight cases passed; an interleaved sixteen-case
  run had fifteen passes and one failed slide. Its first `GetPixel` returned white
  `(255,255,255)`, while immediate follow-up `GetPixel` and both `BitBlt` modes
  returned green. That HWND was visible, not iconic/cloaked, DPI 96; both `DwmFlush`
  calls returned `S_OK`. This pins one stale capture observation, not a common root
  for every earlier failure or a compiler A/B. Logs:
  `/tmp/native-threads-modal-clock-only-resume.log`,
  `/tmp/native-threads-modal-capture-{trace,mixed}-run.log`.

  Two candidate alternatives were rejected: both original and diagnostic binaries
  have PE subsystem **2** (GUI), so a newly created console was not established as
  the cause; native DWM timing probe `bc04fe25…` returned `S_OK` but
  `qpcFrameDisplayed`, `cFrameDisplayed` and `qpcFrameComplete` were **zero**,
  while `qpcCompose` could be in the future. These are not usable display receipts
  on this host. Microsoft documents [DwmFlush](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/nf-dwmapi-dwmflush)
  in terms of the caller's outstanding DirectX work, and
  [Commit](https://learn.microsoft.com/en-us/windows/win32/api/dcomp/nf-dcomp-idcompositiondevice-commit)
  as an atomic transaction per device; neither cited page establishes a
  particular commit's physical visibility at callback return.

  **Tagged desktop snapshot candidate**, code tree
  `28c6c52d7c6eb7fa91c5370362fe28f0557bfedc` (private code-only index, docs excluded),
  compiler/support `74ab138f79f`: see `checkModalTarget` in
  `tests/platform/windowsModalFrame.ms` and `nmfSampleFrame` in its C companion.
  The receipt is independent of the modal's expected green, on the ordinary render
  path; the capture retains ownership checks, Default desktop, idle ≥60 s, the
  unchanged <200-ms bound, 2-s guest watchdog and 20-s process guards. It is not
  a second renderer or a production wait. The four-core stage/four-build job took
  **252 s**; reuse these artifacts:
  - Fade `466459f40738767b53f1959071ff4058ee108561e03f256dce51b91ca8625bc9`.
  - Slide `2b47f48435d444d52a38454b2651173b0106adec16c25c18b0d89cf467cac2ab`.
  - Clock control `9a8aebd16b47f647a3b93923d106387ac03fc9506b546775b4ee53f421e19d84`:
    only `niwFrame`'s `stepModals(timeMs)` changed to callback time.
  - Missing-receipt control `cf13202b88ecbd09deeb3d41c1f6b69c7199d9ee5359b913dcc3caafda1ac23b`:
    only the target callback's receipt assignment changed to black.

  Sequence **GREEN → clock RED → GREEN → missing-receipt RED → GREEN** passed:
  six positive cases **28.15–47.31 ms**, exact green and native exit **0**;
  clock control observed its receipt but modal RGB **(0,1,0)**, native exit **1**
  at the named transition assertion; missing-receipt control exited **1** at the
  named 200-ms receipt timeout, with no receipt observed. Restored pairs both passed.
  Source/artifact fingerprints were checked before launch, and the specific native
  errors excluded setup, ownership, timeout-guard and compiler failures.
  `/tmp/native-threads-modal-receipt-{build,sequence}.log` owns raw evidence.

  **The first stability-repeat case nevertheless failed:** receipt and green were
  observed, but elapsed **257.3349 ms**, native exit **1**. Pair one stopped before
  slide; this was one attempted case, not sixteen executed cases. The 200-ms
  assertion was not relaxed. `/tmp/native-threads-modal-receipt-repeat.log`.

  A phase-only diagnostic of the same code tree retained its operations and
  deadlines, adding QPC milestones and reporting after elapsed was recorded.
  Compiler `74ab138f79f`, executable
  `175734687ffb8f28df36e0a664c28cd7442e983b10d5254b3e4d59b687897a11`;
  stage/build **167 s / four cores**. Eight then thirty-two **fade** cases passed,
  maximum elapsed **52.429 ms**. Across the thirty-two runs' slowest capture calls:
  setup **0.105–0.761 ms**, copy/flush **3.753–20.395 ms**, log I/O
  **3.355–27.168 ms**, cleanup **0.044–0.089 ms**. This did **not** reproduce or
  attribute the 257-ms overrun. Instrumentation and a different executable are not
  proof that the uninstrumented candidate is stable; normal logging cost does not
  establish that logging caused that outlier. Logs:
  `/tmp/native-threads-modal-receipt-timing-{build,run}.log`,
  `/tmp/native-threads-modal-receipt-timing32-run.log`.
  On 2026-11-19, the same pinned fade/slide binaries ran with one authorized
  d87 WPR CPU + DesktopComposition capture (`desk.sh run --quiet 2`, same console
  guards). Stop was requested **18.572 s** after starting the wrapper's recording
  stopwatch; WPR confirmed it had stopped. **95/95** passed, **24.75–80.65 ms**.
  The ETL remained on d87; it contains no reproduced overrun. A separate run with
  WPR off and the same executables passed **16/16** (eight fade, eight slide),
  **18.41–39.76 ms**. Logs: `/tmp/native-threads-modal-{wpr-run,unprofiled16}.log`.
  Neither passing sample explains the earlier 257-ms failure.

  On 2026-11-20 a phase diagnostic of the same code tree (QPC marks kept in memory
  and printed after `elapsed` was recorded; operations, deadlines and log calls in
  place; compiler `042e4d5e23e`, fade `25b79d2f…`, slide `70333fa9…`, patch
  `out/evidence/modal-phase-v2.patch` `4132c918…`) ran interleaved with the pinned
  candidate binaries, on d87 through `desk.sh run --quiet`:
  - 24 fresh PowerShell rounds of eight cases, gaps 0–30 s between rounds:
    **192/192** passed, **15.1–48.3 ms**.
  - 0/12/24/48 CPU-spinning threads at normal priority beside the cases:
    **96/96**, maximum **52.7 ms**.
  - 0/4/12 threads writing, reading and deleting 2-MB files: **96/96**, maximum
    **57.3 ms**.

  A passing case spends **1.7–4.0 ms** from mount to the target frame entering
  `niwFrame`, **4.6–10.4 ms** more to `Commit` returning, then one or two desktop
  compositions before `BitBlt` returns the marker (the capture call that sees it
  blocks **5.8–26.8 ms**; a slow case is one missed capture plus the next). Logging
  inside the bound cost **1.2–18.8 ms**. Neither CPU saturation, file churn nor idle gaps
  moved any phase.

  The ledger shows what the earlier windows shared: `desk.sh run --quiet` does not
  ask for the whole host, so the failing window (2026-11-14 21:00:34Z) opened
  beside `gpu-ms: build UM scenes`, a 12-core build in its last two minutes, and the
  WPR, unprofiled and thirty-two-case windows also opened beside other sessions'
  8- or 12-core jobs and passed. Overlap is therefore a difference between that
  window and a quiet host, not a demonstrated cause. After the one overrun,
  **551** cases passed and none failed; the overrun stays unattributed. Logs:
  `out/evidence/modal-hunt-{1,load,disk}.log` in the worktree (ignored files).

  The person accepted on 2026-11-21 that the clock fix and this pin are committed with
  the 200-ms guard unchanged and the overrun recorded as unattributed: the guard only
  qualifies a sample (past it, wall time alone could have finished the transition), so a
  trip names an unusable sample, not a wrong clock, and the pin stays a hand-run console
  check outside `tests/run.sh`, which only builds it. Not tried: memory pressure from a
  concurrent link on d87. The `/tmp` logs named in this entry up to 2026-11-15 were
  reaped by macOS; the 2026-11-19 pair survives beside the hunt logs in `out/evidence/`.
  No physical Flutter comparison or TIME-MACHINE certificate follows. Keep the hard
  bound; do not retry the expected green until it passes.

  Independently, the normal image-loop executable on the candidate,
  `f39d21cb18967ae3967bf6f0e059c745d28f18766d2844536b21d7a017f1be0e`,
  passes again on `bac1b95e1948`: metadata **4×2**, picture **4×4**, **3 wakes,
  2 main reports, 1 MTA decode, 0 host decodes, exit 0**. It does not close the
  modal failure, a full gate, or physical performance. Build the fixtures through
  `run-remote.sh --windows`; run `windowsModalFrame.ps1` and `windowsImageLoop.ps1`
  separately through `desk.sh run --quiet 2`, each executable guarded at 20 seconds.
- **Frame-driver cross-backend check** (2026-11-14, rtx, requested compiler pin
  `bac1b95e1948`, host-reported prefix `bac1b95e194`). Code tree
  `62e92efe9c7837b490817677ee9e190569e8741d`, frame source SHA-256
  `909c2386bdc2801f7e4f4f471fb32f7d8acc3256fc9f29ab570346d240eef73f`,
  test SHA-256 `c4b01ff45d4157aa2bfe53897dd39d1ffc9be075dc37e496af373612ac5c7918`.
  `msc test tests/animation/frame.test.ms`: **40 files / 515 tests passed**;
  the same command with `--target=js`: **9 files / 128 tests passed**, exit **0**.
  Counts include imported test modules, not 515 frame-specific cases. The 2-core
  stage/bootstrap/two-check job took **221 s**, including the first host compiler
  build; it is not a per-file timing. This checks the frame driver's C/JS contract,
  not a full suite, native presentation, physical performance, VM due-work admission
  or session isolation. Log: `/tmp/native-threads-frame-bac1.log`.
- **Field trace** (lightcube-core, iPad Pro 12.9, Release, Time Profiler 25 s). 99% of samples
  on main; 77% under the timer-driven `loopPump` → `msRunOnce` → socket pump → app; recompute
  11%, relayout 12%. About 62% of the busy time was Lightcube's own re-reads.

## Tried and rejected

- **An app thread for the reactive core and layout**, as in Fabric's JS/UI split. Flutter
  merged its threads back, and every host has synchronous callbacks. The person did not ask
  for a split.
- **React-style priority lanes.** Solid 2.0 has no priority scheduling: its 1.x slicer was
  deleted in e295dc8d9, and transitions serve consistency. Neon follows Solid: each flush runs
  whole, and *when* it runs depends on the change's source.
- **Compile-time priority tagging and pre-ordered graphs.** Handlers escape the macro,
  dependencies are dynamic, and heap inserts are O(1). Static props already skip effects
  (`element.ms` static path).
- **A RenderThread animation engine on Android.** No public API exists (see Animation).
- **Automatic offload of user code** (`new Promise`, heavy sync calls). It changes TS meaning,
  heaviness is input-dependent, and a running function cannot migrate between threads.
- **Re-arming the iOS timer from the worker**, as Flutter's `message_loop_darwin` does. It
  needs a runtime `msLoopPost` that msc lacks; the selector fd uses existing API.
- **Linux fixed-rate timer as vsync** (Flutter's open bug).

## Open runtime gaps (compiler cards to write)

- `msLoopPost(closure)`, safe from any thread.
- One wait-handle getter (fd on POSIX, IOCP on Windows).
- `msRunOnce` with a time budget (unbounded today).
- `queueMicrotask` on C.
- QoS for pool threads.
- `msNextTimerDelayMs` on wasm.
