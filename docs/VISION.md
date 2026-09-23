# Neon — vision

**One interface for every kind of rendering.** A developer writes Neon: JSX, function components,
lifecycle hooks, props, fine-grained reactive state. From that one interface they build application
UI, a game, a shader view, a 3D scene, or any mix of them, for iOS, Android, macOS, Windows, Linux
and the browser, with or without WebGPU. The developer never sees a boundary between these kinds of
rendering. The boundaries exist inside Neon, and Neon keeps them out of the developer's code.

`RENDER-LAYERS.md` says who paints on each platform, `RENDER-MODEL.md` how JSX becomes mount code,
and `ROADMAP.md` what is built next. This file holds the goal that those three documents serve.

## One interface, no runtime tree

The JSX macro emits the mount code for each site: the most efficient render function, which behaves
as if a tree existed, without keeping a VNode tree at runtime: a `NeonNode` is a function, and rendering a node is calling it
(`RENDER-MODEL.md` "The one concept").
Components, hooks, props and reactivity work the same way on every host, because the macro targets
the `Host` contract (`src/render/hostTypes.ms`) and never a platform.

## Worlds, nested one way

```
Application UI world         native host (iOS, Android, desktop) or DOM host (browser)
  View = UIView / android.view.View / <div>      Text = UILabel / TextView / <span>
  ├─ <Void>                  a tag like View, laid out like View
  │    Void world            one GPU surface; Void draws every pixel in it, as Flutter does on its canvas
  │    View = void2d rect                         Text = void2d text
  │    + Void's own tags: void2d, void3d, shader, …
  └─ <WebView>               a tag like View, laid out like View
       Web world             an embedded browser engine (WebView2, WKWebView) with its own JS runtime;
                             it talks to the app over IPC, as Tauri does
```

- **A component is written once.** A component built from `Text` and `View` runs on iOS, Android, the
  web and Void. **Where it is mounted** decides whether it becomes native views or void2d. The
  component neither knows nor chooses.
- **Nesting goes one way: Application UI → Void, never Void → Application UI.** A Void area holds
  only Void components. A game's HUD is written with `Text` and `View`, but inside the Void area
  they are void2d. No native view and no DOM element ever lives inside a GPU surface.
- **An embedded browser is one more element of the Application UI world.** `<WebView>` sits beside
  `View` and `<Void>`, and layout places it. Like a native view, it never lives inside a Void area.
  On the desktop this is Ion's webview laid out as an element (`ionWebviewSetFrame` in
  `ion/src/platform/bridge.h`: once it is called, native layout owns the frame).
- **A game is an app whose only child is one `<Void>` filling the window.** It uses the same
  interface as an app, with no separate mode for games.
- **An application UI can live entirely in Void,** the way Flutter does, and that is also an
  app-level choice. It buys the same pixels everywhere. It costs native look and feel, and it
  depends on everything in "What a Void area owes the app" below, accessibility first.

## Across the boundary

The developer sees one tree. Inside, a `<Void>` is a separate root on the void host
(`RENDER-LAYERS.md` "Void as a native component"). These rules are what keep that
separate root invisible.

- **One owner tree across the boundary.** The inner root is created under the owner of the
  `<Void>` element. Signals, memos, context and theme read inside a Void area track and update
  exactly as they do outside it. The outer owner's cleanup disposes the inner root and releases
  its surface. React Three Fiber shows what happens otherwise: React context does not cross a
  reconciler root there, and every provider has to be bridged by hand. Neon has one reactive
  runtime, so it has no reason to repeat that.
- **One change, one displayed frame.** A signal that updates a native label and a void2d text
  shows both changes in the same displayed frame. Otherwise the two worlds visibly drift apart,
  the tell of a boundary. That takes one commit that spans the platform compositor's transaction
  and Void's present (on iOS, `CAMetalLayer.presentsWithTransaction`).
- **What "written once" guarantees.** The same component in two worlds gets the same **layout**,
  because Yoga computes both. It gets the same **style** for every property both worlds support,
  and a property one world lacks is an error at the declaration, not a silent drop. It does
  **not** get the same pixels: outside Void, the platform draws. Text can **wrap differently**,
  because the OS measures text outside Void and Void's own shaper measures it inside. Only a
  shared font file narrows that gap.

**A `<WebView>` is not a transparent root, and the doc does not pretend it is.** A Void area runs
in the same process, the same runtime and the same owner tree, so the rules above can hold. A
webview runs another engine with its own JS runtime: no signal, context or owner reaches into it.
Everything crosses as a message over IPC, as in Tauri. Neon's DOM host running inside a webview is
a second Neon app joined to the first by IPC, not one shared tree. This boundary cannot be removed,
so Neon makes it explicit: the `<WebView>` element carries the channel, and nothing pretends the
content inside belongs to the outer tree.

## What a Void area owes the app

A Void area draws every pixel itself, so it must also provide what the platform gives a native view
for free. Without these, face 2 below cannot carry a real app's UI.

- **Accessibility.** A GPU surface has no accessibility tree, so text and controls drawn in Void
  are invisible to a screen reader. Void keeps a semantics tree beside its node tree and mirrors
  it to the platform's accessibility API, as Flutter does.
- **Text input.** `TextInput` with committed and composing text runs inside a Void area on the
  void host, which places the IME candidate window at the caret (`renderSurfaceSetImeRect`).
  Selection and clipboard are still missing.
- **Focus.** Focus inside one Void area exists; keyboard focus and tab order running through the
  boundary in both directions, from native views into a Void area and back out, do not.
- **A fallback chain.** The chain is WebGPU → WebGL2 → no GPU. What a Void area shows with no GPU
  at all, and what it renders server-side (`src/render/ssr.ms`), have to be decided, not left to
  fail silently.

## The hosts under the umbrella

| world | host | `View` / `Text` become |
|---|---|---|
| Application UI, iOS / Android | native, React Native's model | `UIView`, `android.view.View` / `UILabel`, `TextView` |
| Application UI, browser | DOM, react-native-web's model | `<div>` / `<span>` |
| Void, on every platform, browser included | void host (`src/platform/void/host.ms`) | void2d rect / void2d text |
| Terminal | terminal host (`src/platform/terminal/host.ms`) | ANSI lines; it speaks its own tags (`<box>`, `<text>`) today |

Which of these exist is recorded in `PORT-STATUS.md` and `ROADMAP.md`, not here.

## Void's two faces

1. **An advanced rendering area.** `<Void>` is one tag of the Application UI world. Inside it, Void's
   own tags draw 2D, 3D, shaders and games through a WebGPU-shaped interface. The backend is native
   on each platform: Metal, D3D11, GL/GLES3, WebGPU, WebGL2. The browser treats a Void area as one
   more native component, a canvas, so the same Void code runs there. That it runs as fast as on
   iOS or Android is a goal, not a measurement.

   **In the browser, Void is JavaScript that calls WebGPU directly**: MetaScript compiled with
   `--target=js`, not wasm. Neon's DOM host and Void then share one JS runtime, so signals, context
   and owners reach inside a `<Void>` exactly as they reach any other child, and no call crosses a
   JS↔wasm boundary. This path is not built yet. Today's web build is wasm: sokol and the bridge
   compiled by emscripten (`void/src/sokol/gpu.wms`, `--os=emcc`), shipped as a WebGPU artifact and a
   WebGL2 artifact (`void/README.md`). Getting to JS needs:
   - a GPU layer for the JS target, written in MetaScript over WebGPU, because sokol is C;
   - JS versions of the C pieces under the text stack (fontstash, stb_truetype, the shaper void2d P3
     brings);
   - an answer for the WebGL2 floor: a JS path over WebGL2 too, or WebGPU only on the JS target;
   - size budgets (`void/docs/VOID2D.md` guardrail 6) measured in JS bytes instead of wasm bytes;
   - a measurement of what the CPU side (walk, layout, shaping) costs in JS against wasm.
2. **A host for Neon's vocabulary.** Void understands `Text` and `View` and maps them to void2d. So
   a UI written for the browser or for React-Native-style mobile also runs inside Void, drawn with
   WebGPU into a canvas or a Metal view instead of with HTML or native components.

The mechanics of face 1, meaning what exists on Void's side and what is missing on Neon's, are in
`RENDER-LAYERS.md` "Void as a native component".

## Many Void areas in one app

An app may hold several independent `<Void>` tags. That is an anti-pattern, but it must work.

- **Shared once per process:** the GPU device (`MTLDevice`, D3D11 device, EGL context, `GPUDevice`),
  pipelines and shaders, the glyph atlas, textures. This is the expensive part.
- **Owned by each `<Void>`:** its drawable or swapchain, its size and DPI, its frame policy. This is
  the cheap part: a `CAMetalLayer` is one layer with a pool of about three buffers, and one
  `GPUDevice` can configure several canvases.
- **Rejected: render every area into one large offscreen target and copy a slice into each area.**
  Each area is still its own native view and still needs its own surface to display into, so the
  surfaces are not saved and every area pays one extra copy per frame. The one-pass benefit comes
  just as well from the shared device, with one pass per area in one command buffer.
- **An optimisation for one backend, not the model: one window-sized surface under the Application
  UI, with each `<Void>` a viewport of it.** It is worth it only where the number of contexts is
  the real limit, as on WebGL2, where each canvas is its own context and cannot share resources.
  The trap is that when native UI scrolls or animates, the OS compositor moves native views in that
  frame, while the Void viewport follows only in Void's next frame. The area then trails its
  frame by one visible step. A surface per tag has no such lag, because the compositor moves it
  with its parent.

## Window, frame and input: Ion and Neon

Whether an app is application UI, a game, or both at once, each part runs at its most native cost,
or its laziest.

- **One vsync source per window, owned by Ion.** Each rendering area declares its own frame policy.
  Application UI redraws on demand, when something changed. A Void area is on demand or continuous.
  An idle app draws nothing.
- **A Void area's frame never passes through reconcile.** It has its own clock. The host drives Void
  (`viewFrame` on one view per area, `void/docs/EMBED.md`), and Void owns no loop and no window.
  A game keeps control of simulation step, present timing and pacing.
- **What a game needs is exposed through Neon, not around it:** raw and relative pointer input,
  pointer lock, exclusive fullscreen, vsync mode. Input reaches a Void area without a per-event
  allocation at high polling rates.
- **Ion treats a surface and a webview alike:** each is an element with a frame that layout sets,
  a z-order and its own input region. Today only the webview has a frame (`ionWebviewSetFrame`).
  A render surface always fills the window (`ionRenderSurfaceSyncFrame`) and its input sink is one
  per process (`ionRenderSurfaceSetInputSink`). Ion's frame clock exists: a surface declares
  `FrameOnDemand` or `FrameContinuous` and draws on `onSurfaceFrame` (`ion/docs/RENDER-SURFACE.md`).
  An app that is one full-window `<Void>` does not need the first two, and it runs today on Windows:
  `runWindow` in `src/platform/ion/window.ms`, measured in `ROADMAP.md` "Recently done". Everything
  else does.
- **Audio never goes through the tree.** It runs on the device's own thread; Neon only carries
  control.

## Open

- **A native sibling drawn over a Void area**, for example a UIKit button floating over a game.
  Either it is allowed, and the OS compositor stacks the views, or a Void area is always opaque
  and nothing overlaps it.
- **One Yoga tree or two.** Either the Void world runs its own layout from the size the Application
  UI gives the `<Void>` tag, or one Yoga tree runs through the boundary.
- **What `View` and `Text` are on the desktop.** The desktop Application UI world is a native host
  on an Ion window, and a webview is one of its elements, not the root. What `View` and `Text`
  map to there is open: AppKit, Win32 or GTK widgets, or nothing yet while the first desktop apps
  are entirely Void.
- **Void's own tag vocabulary.** The void host maps every tag to a `group()` today.
- **One animation model for both worlds.** Native animation runs on the platform compositor's
  thread, while Void animates on its own clock. The Animation API in `ROADMAP.md` has to drive
  both, with the same timing curve.
- **Shared resources.** An image or font used in both worlds is decoded and loaded twice today.
  Text that has to match needs the same font file on both sides.
- **Threads.** UIKit runs on the main thread, and Void may render on its own thread. A reactive
  update then crosses a thread boundary, and the one-frame rule above has to hold across it.
