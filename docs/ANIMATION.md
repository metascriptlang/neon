# Animation — one motion model for Neon, Void and the editor

State: design agreed on 2026-10-11, prototyped on 2026-10-12, built in `src/motion/` (entry
`src/motion/index.ms`, tests `tests/motion/`) from 2026-10-29. `src/animation/` is something else: React Native's `Animated` surface on Neon signals (ROADMAP
Bundle 5). The scene clocks in `src/components/scene2d.ms` (`Anim`) and `src/components/scene3d/animation.ms`
(`ObjectAnimation`, `MeshFrameAnimation`) are also separate, and each plays Void's own frame data.
The person decided on 2026-10-31 that this core replaces their clocks and hands motion to each
platform's engine where one exists (§Decided); where the core lives is open again (§Open).

## What it has to be

These are the person's requirements (2026-10-08 to 2026-10-15). Each one rules a design out.

1. **Universal.** One core describes values that change over time. It knows nothing about View,
   Solid, Void or the GPU. Neon uses it, and Void uses it standalone without Neon. A program with
   no renderer runs it on a manual clock. This rules out a core built on signals or on a host.
2. **Editable.** An animation is data that an editor (Lightcube, a Figma-like tool) drags, scrubs,
   saves and reopens. Code is one way to create and drive that data, not the place where it lives.
   The editor and the app play the same document. This rules out a chain of function calls as the
   stored form.
3. **Composable.** Clips nest inside clips, each placed at an offset with its own rate. One clip is
   reused many times without being cloned, and each instance maps its target slots to its own
   targets.
4. **Stateful playback, as a browser user expects.** A player has a playhead: play, pause, seek,
   reverse, rate, cancel, finish and retarget. Players of one document are independent, so pausing
   instance A leaves B and the asset alone.
5. **Strong in the browser, JS and WASM alike.** The browser renderer (JS, DOM) hands an
   animation to the browser engine through WAAPI when the browser can express it, and runs the
   evaluator for the rest. Void in the browser (WASM, canvas) always runs the evaluator, because
   CSS cannot reach a node inside a canvas.
6. **Interactive motion.** A spring takes over from a gesture with the gesture's position and
   velocity, and it can be retargeted mid-flight.
7. **One behaviour contract on every backend, not identical frames.** The browser interpolates on
   its own, so a frame may differ. What the app relies on (§Contract) must not differ. A track a
   backend cannot run is refused, never run with another meaning.
8. **Checked early.** Metaprogramming types the bindings, validates a document before it plays,
   and lowers it to a backend's plan. An editor-made document passes the same validation as a
   coded one, and authoring never requires a macro DSL.
9. **No threads in author code.** The app author writes a document, `useMotion` or
   `value.animate(…)` and never names a thread, an engine or a platform. Each adapter hands a
   track to the platform's own animation engine wherever one can run it, so a busy app thread
   does not stall that motion; callbacks stay on the app's thread, and the same document gives
   the same result everywhere (2026-10-31).

## Shape

| part | holds | depends on |
|---|---|---|
| Document | clips, tracks, keyframes, curves, placements, target slots; versioned | MetaScript data types only |
| Evaluator | the value at a time: interpolation, easing, spring | the document |
| Player | clock, playhead, playback state, bindings | the evaluator, or a backend that executes |
| Bindings | a slot and property written to a DOM style, a Neon value or a Void scene property | its consumer |
| Editor | timeline, curve handles, preview, save and undo | document and player; outside the core |

A document holds no live node, closure or callback: only slots and properties a file can store.
A player binds them to real objects. A spring that does not change target can be baked to
keyframes for preview and export. A spring a gesture keeps retargeting cannot, and the two are
never treated as one.

## Which reference owns which concern

| concern | reference | taken | not taken |
|---|---|---|---|
| authoring data | Theatre.js | property tracks, keyframes, curves, one data for editor and runtime | its project and editor structure |
| composition, playback | GSAP | nested timelines, position parameter, labels, repeat, reverse, time scale; play, pause, seek | a global timeline; runtime objects as the saved form |
| browser execution | Anime.js, WAAPI | choosing between browser-run and self-computed per animation | a promise that every animation lowers to CSS |
| interactive motion | Reanimated | timing and spring, gesture-driven values, cancel and retarget | worklets, a second JS runtime, a required `Animated.View` |
| clock and controller | Flutter | clock separate from controller; an explicit lifecycle | Widget, State and TickerProvider |
| interactive authoring, later | Rive | states and transitions bound to app data | `.riv`, artboards, its renderer |
| asset interchange | Lottie | versioned assets, markers | its whole graphics schema |
| reactive integration | Solid 2.0 (`~/projects/solid-next`) | ownership and cleanup on the Neon side | making the core depend on signals |

The rows were chosen from documentation on 2026-10-11 and traced in source on 2026-10-29.
Sources: `~/projects/refs-animation/` (tarballs; `COMMITS` there): Theatre `6ea82b93`, GSAP
`13e2b790`, anime.js `01b81be1`, Reanimated `bd4d3fcf`; Flutter `~/projects/flutter` `f1019913`.

| part | our file | followed |
|---|---|---|
| keyframe data | `document.ms` | Theatre `core/src/types/public.ts:496-506` (`BasicKeyframe`: handles `[leftX, leftY, rightX, rightY]`, `connectedRight`) |
| sampling | `evaluate.ms` `sampleTrack` | Theatre `core/src/sequences/interpolationTripleAtPosition.ts:98-197` |
| colour | `evaluate.ms` `interpolate` | Theatre `core/src/propTypes/index.ts:508-526`, `utils/src/color.ts:80-150` (Oklab) |
| clock split | `clock.ms` | Flutter `scheduler/ticker.dart:24,291,313` |
| playback | `player.ms` | GSAP `gsap-core.js` `class Animation` :1148-1470 |
| cancel, revert | `player.ms` | anime `timer/timer.js`, `animation/animation.js` |
| composition | `compose.ms` | GSAP `_parentToChildTotalTime` :245, `_addToTimeline` :287, `Timeline.render` :1537-1669, `_parsePosition` :390-412 |
| stagger | `compose.ms` `stagger` | anime `utils/stagger.js` |
| spring | `spring.ms` | Reanimated `animation/spring/springUtils.ts:162-395`, `springConfigs.ts:6-95`; Flutter `physics/spring_simulation.dart` (overdamped) |
| decay | `decay.ms` | Flutter `physics/friction_simulation.dart`; Reanimated `decay/rubberBandDecay.ts:7-46` |
| animated value | `value.ms` | Reanimated `valueSetter.ts:10-76`, `timing.ts:90-158`, `spring.ts:146-196`, `sequence.ts`, `delay.ts`, `repeat.ts` |
| reduced motion | `policy.ms` | Reanimated `animation/utilCommon.ts:113-132,460-478` |
| browser execution | `waapi.ms` | anime `waapi/waapi.js:127-162,231-235,396-505`, `waapi/composition.js:36` |
| Neon ownership | `neon.ms` | Neon's SR-3 (`docs/REFERENCE.md`) over Solid 2.0 `signals.ts:92-101` |

Nothing traced so far needed a **NEW MECHANISM**: every part is a port of one of these.

### Where we depart from a reference, and why

- **Decay is a pure function of elapsed time.** Reanimated's rigid decay multiplies the
  already-decayed velocity by `exp(total elapsed)` each frame (`decay/rigidDecay.ts:15-19`), so
  the result depends on the frame rate. That breaks "the same result on every backend", so decay
  follows Flutter's friction simulation.
- **A true overdamped spring.** Reanimated uses the critical solution for every ratio ≥ 1
  (`spring.ts:115-130`); `spring.ms` uses Flutter's overdamped solution above 1.
- **Velocity crosses sequence, delay and repeat.** Reanimated hands 0 out of a wrapper; a spring
  after a wrapped spring then jumps. Criterion 6 asks for continuous retargeting.
- **Refusals instead of warnings or silent defaults.** An invalid spring config, an empty
  `sequence()`, an unknown label, an unreadable or percent position, and a placement that ends
  after its parent's duration all throw `motion: …`. The references warn, snap, or substitute 0.
- **The root clip's duration is authoritative.** GSAP grows a timeline to fit its children
  (`totalDuration` :1929); Theatre stores the length (`Sequence.ts:188-211`). The editor and the
  runtime read one stored number.
- **Contention is decided by position, not history.** GSAP's backward render pass can show a
  later child's first value inside a gap (:1669). `compose.ms` takes the forward reading, so a
  backward scrub shows what a forward one shows: among writers covering a time the later start
  wins; else the writer that ended last holds.
- **Reduced motion is an explicit `MotionPolicy`.** Reanimated's System mode reads a process
  global (`ReducedMotion.ts:12-14`); Neon and a standalone Void scene in one process need their
  own.
- **Contention between writers is anime's composition, with no hidden writer.** `target.ms`:
  writers that carry one `MotionTarget` replace (default, `core/globals.js:54`), blend
  (`composition.js:221-259`, `additive.js:53-73`) or ignore each other (`none`). Two departures:
  a Replace writer and a Blend writer on one target stop each other instead of both writing with
  the blend applied last (`engine.js:92`), which shows the same value; and a blended player keeps
  its own document keyframes, scaling its delta by (base − end)/(start − end) where anime drops an
  explicit `from`, because a document's keyframes are data the editor owns. Not ported: anime's
  absolute-timeline truncation (`render.js:197-205`), so seeking a replaced player backwards does
  not replay the part it wrote before the takeover.
- **`dispose` follows Flutter** (`animation_controller.dart:902-920`): it ends the running
  animation with `finished = false`, notifies no listener, and refuses every later call.

## Where it runs

| consumer | clock | execution | value reaches |
|---|---|---|---|
| browser renderer, JS | the browser's animation clock or rAF | WAAPI when expressible, evaluator otherwise | DOM style |
| Void in the browser, WASM | `VoidClock`, ticked from Void's loop | evaluator | Void scene properties, no CSS. `examples/motionVoid/headless.ms` built with `--os=emcc -d:webgl2` (emsdk loaded) prints the same frames under node as natively (2026-10-29, yoga `6a1cc06`) |
| Void native, standalone | `void.ms` `VoidClock`, ticked by the program's frame closure beside `Scene2D.tick(dt)` | evaluator | `VoidBindings`: 2D node and 3D object properties, no Neon |
| Neon on Void | the Void area clock (`src/render/voidClock.ms`) | evaluator, no second scheduler | Neon → scene |
| Neon native hosts | the host's display frame (`src/animation/frame.ms`) | evaluator | native view properties |
| tests, headless | manual clock | evaluator | values or mock bindings |
| Lightcube preview | the editor drives the player | the preview's backend | the same document the app ships |

The table above is what runs today. `useMotion` and `useAnimatedValue` run the evaluator through
signals on every platform, the browser included; only `BrowserMotionPlayer` hands tracks to WAAPI,
and its master clock still ticks in JS every frame.

The target (2026-10-31, checked against sources the same day): three layers. The author writes a
document and calls the sugar (`useMotion`, `useAnimatedValue`) or the engine directly, and never
names a thread. The engine is the core: pure data and pure functions of time. Each adapter sorts a
track into one of three ranks: handed to a platform engine that runs it without app code per
frame, run by the evaluator on the app's thread, or refused at construction. Callbacks,
`subscribe` and contention stay on the app's thread on every platform, so no author code meets a
thread.

| platform | handed to the platform, no app code per frame | the rest | handed over as |
|---|---|---|---|
| browser | WAAPI. On the compositor only for `opacity`, `transform`, `translate`, `rotate`, `scale` and `filter` (Firefox: not `filter`) with `replace` composite and no `endDelay` (Chromium `compositor_animations.cc:388-405,810`); released Safari also needs cubic-bezier or keyword easing (WebKit bug 312407). Other properties run in the browser's style engine on its main thread | evaluator per frame | merged keyframes per CSS property (X and Y as one `translate`, as motion groups one `transform`); stagger as `delay`; spring as a sampled `linear()` (Chrome 113, Firefox 112, Safari 17.2), as motion does (`linear.ts:3-15`); decay stays on the evaluator, as motion keeps inertia in JS |
| macOS, iOS (Neon on AppKit, UIKit) | Core Animation, run by the render server outside the app's main thread (WWDC 2014 sessions 236 and 419) | evaluator on the main thread | sampled `CAKeyframeAnimation` or `CASpringAnimation` on `transform`, `opacity`, `backgroundColor`, `cornerRadius`; the final value written to the model at hand-over and on cancel; on macOS the centred matrix `updateLayer` applies (`platform/macos/bridge.m:80-98`) |
| Windows | DirectComposition, run by DWM on its own thread (Microsoft DirectComposition docs) | evaluator on the UI thread | `IDCompositionAnimation` cubic segments, a spring sampled, on the visual's offset, opacity, transform (`platform/windows/dcompComposition.cpp:139-156`) |
| Android | none through a public API: `ViewPropertyAnimator` runs on the UI thread (`ViewPropertyAnimator.java:858`) and `RenderNodeAnimator` is `@hide` | evaluator on the UI thread | |
| Void, native and WASM | none: Void draws on the app's thread (`CADisplayLink`, rAF, Choreographer) | evaluator inside Void's frame, beside the scene | bindings as data (node, property) |
| terminal | none | evaluator on the terminal's frame | |
| SSR | static `@keyframes` | none | for motion in the first paint |

A retarget samples position and velocity from the core's closed form, cancels what the platform is
running and hands over the new motion, as motion's `NativeAnimationExtended.ts:119-145` does, so
seek, cancel and contention keep one meaning. A property that changes layout (`width`, `left`)
runs on the app's thread on every platform.

Void off the app's thread is not in the target. It needs a thread pinned to one OS thread for the
GPU device, which ULTRALOCK does not have (M1, V2); WASM has no threads in MetaScript's emcc
runtime, and browser threads need COOP/COEP. Bevy samples animation on the app side and renders an
extracted copy (`pipelined_rendering.rs:70-71`), which is the reference to follow if Void ever
renders on its own thread.

3D asset playback stays a sampler below the core. A glTF clip holds vec3 and quaternion channels
with Hermite tangents, slerp and morph weight arrays on shared time arrays (`gltfCurve.ms`,
`gltfPose.ms`), which a scalar `MotionTrack` cannot carry, and skinning (`skinPose.ms`) reads joint
matrices rather than animating. The core drives such a sampler by time, speed, loop and crossfade
weight, as Godot keeps typed 3D transform tracks beside property tracks
(`doc/classes/Animation.xml:31,702-714`).

## Contract

What an app relies on, the same on every backend:

- **time:** units, delay, duration, repeat, direction, rate;
- **seek:** the value at a chosen time, and whether a scrub fires events;
- **cancel and finish:** cancel holds the current value, finish goes to the directional endpoint
  (the prototype's choice); restoring a baseline is a separate decision;
- **retarget:** starts from the current state, and a spring keeps its velocity;
- **contention:** two writers of one property are replace, blend or an error, never an implicit
  "last write wins";
- **lifecycle:** what a player and its callbacks do when a target unmounts or is disposed;
- **reduced motion:** one policy with one meaning everywhere;
- **capability:** when a backend falls back to the evaluator, and what it refuses. In the
  browser (`waapi.ms` `BrowserMotionPlayer`) a track goes to WAAPI only when its property is in
  the CSS table, it is the property's only writer, its placement starts at 0, its keyframes lie
  inside the clip and there is no repeat delay; every other track runs on the evaluator in the
  same player, and a track with neither path is refused at construction. WAAPI interpolates
  colour in sRGB where the evaluator uses Oklab, so a colour frame may differ; transforms use the
  individual `translate`, `rotate` and `scale` properties, not anime's `var()` transform
  (`waapi.js:196-216`), so the element keeps its own `transform`. Each element and CSS property
  has one `MotionTarget`; a newer writer commits and cancels the older browser animation there,
  as anime's `addWAAPIAnimation` removes the previous one (`waapi/composition.js:26-80`). A
  player that blends runs its tracks on the evaluator, because the blend is computed by the
  target, not by WAAPI's `composite: add`.

Seeking a keyframe clip and seeking a simulation with interaction history are not the same. A
timeline the editor scrubs must be reproducible, while a live gesture keeps its own state.

## Milestones

| | what | proof |
|---|---|---|
| A | settle semantics: document and player, ownership, cancel, seek, retarget; trace the references | app and editor examples that tell the options apart |
| B | minimal core: numeric keyframes, curves, bindings, manual clock | runs with no renderer; seek, repeat, cancel pinned |
| C | two real consumers: browser JS and Void, native and WASM | one document, one behaviour suite |
| D | composition and browser delegation: nested clips, WAAPI | mixed execution still pauses, seeks and cancels right |
| E | interactive motion: spring, gesture, retarget, Neon reactivity | interrupts, disposal and ownership right |
| F | editor proof in Lightcube: edit, save, reopen | round-trip loses no structure; playback uses the same document |
| G | a Neon app in the browser plays through WAAPI: `useMotion` and `useAnimatedValue` bind DOM elements, merged keyframes per CSS property, stagger as `delay`, spring as `linear()`, no JS master tick when every track is handed over; fixes found on 2026-10-31: `bezier()` builds its table and closures on every sample (`easing.ms:50-79`), `commitStyles` swallows its error (`waapi.ms:362`) | Chrome shows no per-frame style write from JS for a handed-over track |
| H | Void bindings become data (node, property); a rotation binding writes a quaternion, not one Euler axis read back through `eulerOf` (`void.ms:164-168`); the core, `easing.ms` and `void.ms` move to where §Open decides, while `neon.ms` and `waapi.ms` stay in Neon with closure bindings | Void standalone imports the core without Neon |
| I | one system for UI motion: derived values (interpolate, arithmetic, `diffClamp`), gesture and scroll events, 2D values, `parallel` and `loop`; `Presence` and `LayoutAnimation` (native and browser) rebuilt on the core; every consumer of `src/animation/` moved (navigation, drawer, header, collapsible, pageView, examples, tests), then `src/animation/` deleted except `frame.ms`; Void's sprite `Anim` clock and `ObjectAnimation`/`MeshFrameAnimation` clocks replaced by the core, which drives Void's glTF and mesh-frame samplers by time and weight | every former consumer runs on the core; a skinned glTF driven by the core matches today's `Clip` crossfade; cost per joint measured against `syncPose` |
| J | platform engines: Core Animation on macOS and iOS, DirectComposition on Windows, for `transform` and `opacity` | motion stays smooth while the app thread is blocked on purpose |
| later | Rive-style state machine, interchange | only when a workflow needs it |

F belongs to Lightcube and is built there, not in Neon. G to J run in that order (2026-10-31).

## Prototype, 2026-10-12

The person asked for a trial that role-plays each user of the design. The sources are kept
outside Git at `~/metascript/.scratch/animation-prototype-20261012/`, a machine-local copy of
the ignored `probe/` in `neon-wt-rn-components` at `cc5d1764`, built with msc `ea7ae4d17`. The
manifest is `animationDesignEvidence.json`. The run reported 54/54 cases green on C, JS and
Chrome, with a C/JS/WASM smoke of the standalone core. That count comes from the session that
ran it. Its logs were in `/tmp` and are gone, so nothing has been rerun.

| file | shows |
|---|---|
| `animationDesign.ms` | `MotionDocument`, `MotionClip`, `MotionTrack`, `MotionPlacement`, `MotionSlotMapping`, `MotionPlayer` |
| `animationDesign.test.ms` | play, pause, seek, reverse, cancel with no renderer; reuse with independent players; editor save, load and scrub; composition; refusal of cycles and bad keyframes |
| `animationEditor.test.ms` | an editor user scrubs, moves a keyframe, saves, reloads and undoes through real controls |
| `animationSpring.ms` | `MotionSpring`: an analytic spring, gesture release keeping velocity |
| `animationNeon.ms` | `runMotion`: Neon ownership stops the shared clock; players share a frame, not a playhead |
| `animationVoid.ms` | a standalone Void scene plays a document without Neon |
| `animationWaapi.ms`, `animationBrowser.test.ms` | `BrowserOpacityPlayer`: WAAPI playback with no per-frame JS writes, cancel, disposal, refusal of unsupported tracks |

What it found:

- **Two instances of one clip collided on their target slots.** It surfaced when the prototype
  played a library author. The fix is a slot mapping per placement (`MotionPlacement.slots`),
  kept in the document so the editor can still edit it and the author never clones a clip.
- **An editor recompile published a transient zero before the requested playhead.** The test
  "editor recompilation does not publish…" pins it.
- **Not production:** bindings are written by hand; two players writing one property are refused
  rather than resolved; the clock must be restarted after it stops; WAAPI is proven for `opacity`
  only.

## Not taken

- **One library ported whole.** No single engine covers editor data, composition, browser
  delegation and interactive motion. Each concern takes its own reference.
- **Reanimated's worklets and runtimes.** They exist to cross JS runtimes. MetaScript compiles to
  C and has no such boundary.
- **A required `Animated.View`.** The prototype binds a document to an ordinary `View` style.
- **Lowering arbitrary callbacks to CSS.** `style={() => ({ opacity: f(x.get()) })}` cannot be
  translated. Only a declared binding (target property plus animation) can go to WAAPI.
- **Mandatory CSS `@keyframes`.** WAAPI is the browser path. Exporting static CSS is optional.
- **A WASM↔CSS adapter for Void.** Void in the browser draws to a canvas, and CSS never reaches it.
- **One global scheduler shared by every consumer.** The semantics and algorithms are shared.
  Each consumer keeps the lifecycle that fits it, and no animation is ticked twice.

## Decided

The person, 2026-10-30 and 2026-10-31:

- **One system.** RN's `Animated` in `src/animation/` and the animation clocks of Void (sprite
  `Anim`, `ObjectAnimation`, `MeshFrameAnimation`) go once the core covers their consumers
  (milestone I), with no compatibility surface over the core. Void's glTF and mesh-frame samplers
  stay, driven by the core (§Where it runs). This answers the VISION question "one animation model
  for both worlds" (`docs/VISION.md`).
- **A standalone engine.** The core is not driven by Neon's effects or syntax; `useMotion` and
  `useAnimatedValue` are sugar for Neon. The engine's single-value API stays
  `value.animate(spring(…))`, with `value.set(v)` meaning an immediate value.
- **The three layers and criterion 9** above, built in the order G to J.

## Open

- **Where the core lives.** Decided as `void` on 2026-10-31, reopened the same day: `void/CLAUDE.md`
  rules Void a thin GPU layer with "No scene graph, ECS, physics, asset pipeline", while the same
  repo carries `void2d`, `void3d` and their animation clocks. The code allows the move (the core
  and `easing.ms` import nothing from Neon; nothing in Void imports Neon).
- **Void off the app's thread.** Left out of the target (§Where it runs) until the compiler has a
  thread pinned to one OS thread.

The discussion is in a pi session:
`~/.pi/agent/sessions/--Users-le-metascript-neon-wt-rn-components--/2026-10-08T14-31-21-954Z_01a11bed-0a61-73fa-bdc0-7cd6357809ac.jsonl`.
The requirements date from 2026-10-08 15:23 to 17:51 UTC, the design from 2026-10-11 12:41,
and the prototype report from 2026-10-12 17:06.
