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
  not physical first-wheel latency proof. Indicator/modal Step timestamps still
  use callback-time `nowMs()` rather than the frame target.
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

Still owed: image/text profiles, production offloads justified by those measurements, and
a long-task report (main held longer than a frame) naming its owner. `AsyncStorage.mergeItem`
must retain read/merge/write ordering if its CPU work moves; blindly submitting independent
merges can lose updates. Its async surface alone proves neither offload nor safe concurrency.

On JS, WASM and workerd, `spawn` only schedules: Worker is same-thread until Web Workers back
it. On Android a worker must never call `ni*` (JNI binding), and one long flush on main is a
5 s ANR.

## Measured

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
