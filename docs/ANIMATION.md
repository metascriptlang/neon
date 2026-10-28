# Animation — one motion model for Neon, Void and the editor

State: design agreed on 2026-10-11 and prototyped on 2026-10-12. Nothing of it is in `src/` yet.
`src/animation/` is something else: React Native's `Animated` surface on Neon signals (ROADMAP
Bundle 5). The scene clocks in `src/components/scene2d.ms` (`Anim`) and `src/components/scene3d/animation.ms`
(`ObjectAnimation`, `MeshFrameAnimation`) are also separate, and each plays Void's own frame data.
How these three relate to the model below is an open decision (§Open).

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

Every row except Solid was chosen from official documentation. No engine's source has been read
yet, so no row carries a `file:line`. Tracing them is milestone A. Until it is done, whether any
part is a **NEW MECHANISM** is "not traced yet": the 2026-10-11 proposal used the label before
any source was read.

## Where it runs

| consumer | clock | execution | value reaches |
|---|---|---|---|
| browser renderer, JS | the browser's animation clock or rAF | WAAPI when expressible, evaluator otherwise | DOM style |
| Void in the browser, WASM | Void's loop, on rAF | evaluator | Void scene properties, no CSS |
| Void native, standalone | Void's frame source | evaluator | Void scene properties, no Neon |
| Neon on Void | the Void area clock (`src/render/voidClock.ms`) | evaluator, no second scheduler | Neon → scene |
| Neon native hosts | the host's display frame (`src/animation/frame.ms`) | evaluator | native view properties |
| tests, headless | manual clock | evaluator | values or mock bindings |
| Lightcube preview | the editor drives the player | the preview's backend | the same document the app ships |

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
- **capability:** when a backend falls back to the evaluator, and what it refuses.

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
| later | Rive-style state machine, interchange | only when a workflow needs it |

F belongs to Lightcube and is built there, not in Neon.

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

## Open

- **The existing surfaces.** Does RN's `Animated` in `src/animation/` become a surface over this
  core, stay beside it, or go? Do Void's `Anim` and `ObjectAnimation` play through it? The VISION
  question "one animation model for both worlds" (`docs/VISION.md`) is the same question.
- **The code API for a single value.** `x.animate(withSpring(…))`, which returns a real
  `Animation<T>`, against Reanimated's `x.set(withSpring(…))`. The 2026-10-08 proposal
  recommended `.animate`, with `.set` meaning an immediate value. Not decided.
- **The contention policy:** replace, blend or error. The prototype errors.
- **NEW MECHANISM:** not traced yet (§Which reference).

The discussion is in a pi session:
`~/.pi/agent/sessions/--Users-le-metascript-neon-wt-rn-components--/2026-10-08T14-31-21-954Z_01a11bed-0a61-73fa-bdc0-7cd6357809ac.jsonl`.
The requirements date from 2026-10-08 15:23 to 17:51 UTC, the design from 2026-10-11 12:41,
and the prototype report from 2026-10-12 17:06.
