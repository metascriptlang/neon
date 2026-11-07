# Scheduling — when Neon runs work, where, and how it reaches the screen

This doc owns what the code cannot say: the rules every host follows, why they have this shape,
what was measured, what was tried and rejected, and where the references do the same thing.
The code is the truth for how a host implements them (`src/platform/*/bridge.*`,
`src/platform/native/loop.c`, `src/animation/frame.ms`, `src/render/bind.ms`).

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

0. **Input.** Discrete input (tap, key) runs flush → layout → sink as one unit, at once.
   Continuous input (move, scroll) is coalesced into the next frame, ahead of step 1. Never
   flush effects now and leave layout and sink for later: that tears.
1. **Animation** ticks at the frame's *target presentation time*, clamped monotonic (Flutter
   `animator.cc:135` `GetVsyncTargetTime`). An animation started in a handler reads elapsed 0
   on its first frame (Flutter `ticker.dart:205`).
2. **Reactive flush**, with microtasks drained (Flutter midFrameMicrotasks).
3. **Layout**, only if dirty.
4. **Sink.**
5. **Post-frame** callbacks (onLayout, measured refs). Their writes are the only ones that
   request another frame. Writes during 1–4 never do (`binding.dart:909-921`).
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
| iOS, macOS | `CADisplayLink` / `NSView.displayLink` in common modes, on main | `targetTimestamp` (`CACurrentMediaTime` base) |
| Android | Java `Choreographer.postFrameCallback` (ANIMATION slot, same vsync as TRAVERSAL) | `frameTimeNanos` (`CLOCK_MONOTONIC`) |
| Windows | pacer thread on the frame-latency waitable or `DCompositionWaitForCompositorClock`, `DwmFlush` fallback; posts only when a frame is wanted | `DwmGetCompositionTimingInfo` (QPC) |
| Wayland | `wl_surface.frame`, requested before commit, plus a retry timer | callback ms |
| X11 | timer at the RandR refresh rate while visible | monotonic |
| terminal | monotonic timer, only while frames are requested | monotonic |
| browser | `requestAnimationFrame` | rAF time = `document.timeline` |

Traps the references hit:
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
  #35379). `WaitForVBlank` locks to the primary output. Inside `WM_ENTERSIZEMOVE` and menu
  loops, a `USER_TIMER_MINIMUM` timer drains the dispatcher and runs the frame (GPUI
  `events.rs:276-312`).
- **Linux.** Flutter's fixed 60 Hz timer is still an open bug (#191245); do not copy it.

## Waking the main thread

A finished worker signals the dispatcher's selector fd. The host adds that fd to the OS loop:
`CFFileDescriptor` in common modes on iOS, `ALooper_addFd` on Android. Before that, the
native loop ran only on its own timer, so a result waited for the next timer or touch.
Elsewhere:
- macOS: a common-modes `CFRunLoopSource`, not a posted `NSEvent`, which menus, `runModal`
  and live resize do not deliver.
- Windows: a hidden message-only window (Flutter `task_runner_window`).
- Linux: the epoll fd as a GLib source (`g_unix_fd_add`).

GPUI (`dispatch_async`, `PostMessageW`, an eventfd ping) and winit do the same.

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
path is paint-only on main: one batched JNI call of (view, prop, value) into
`setTranslation`/`setScale`/`setRotation`/`setAlpha`, with no Style rebuild and no yoga.

Rules learned from React Native and Motion:
- **Begin time.** The mirror and the platform take one frame stamp.
  - Core Animation: `targetTimestamp` via `convertTime`.
  - DComp: `nextEstimatedFrameTime`.
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
the caller, as in the browser. Flutter `compute`, Kotlin `withContext` and Swift 6.2
`@concurrent` are explicit too.

Neon and std move their *own* heavy work off main, behind APIs that are already async:
- candidates are large `response.json()`, image decode, and text shaping and measurement;
- each is measured before it moves, because a crossing costs more than a small task.

A user guide says when an author reaches for `spawn`, and a long-task report (main thread
blocked longer than one frame) points at where. IO (fetch, sockets, files) is non-blocking on
the dispatcher and needs no `spawn`.

On JS, WASM and workerd, `spawn` only schedules: Worker is same-thread until Web Workers back
it. On Android a worker must never call `ni*` (JNI binding), and one long flush on main is a
5 s ANR.

## Measured

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
