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
as if a tree existed, without keeping a VNode tree at runtime (direct emission, `RENDER-MODEL.md`).
Components, hooks, props and reactivity work the same way on every host, because the macro targets
the `Host` contract (`src/render/hostTypes.ms`) and never a platform.

## Two worlds, nested one way

```
Application UI world         native host (iOS, Android, desktop) or DOM host (browser)
  View = UIView / android.view.View / <div>      Text = UILabel / TextView / <span>
  └─ <Void>                  a tag like View, laid out like View
       Void world            one GPU surface; Void draws every pixel in it, as Flutter does on its canvas
       View = void2d rect                         Text = void2d text
       + Void's own tags: void2d, void3d, shader, …
```

- **A component is written once.** A component built from `Text` and `View` runs on iOS, Android, the
  web and Void. **Where it is mounted** decides whether it becomes native views or void2d. The
  component neither knows nor chooses.
- **Nesting goes one way: Application UI → Void, never Void → Application UI.** A Void area holds
  only Void components. A game's HUD is written with `Text` and `View`, but inside the Void area
  they are void2d. No native view and no DOM element ever lives inside a GPU surface.
- **A game is an app whose only child is one `<Void>` filling the window.** It uses the same
  interface as an app, with no separate mode for games.

## The hosts under the umbrella

| world | host | `View` / `Text` become |
|---|---|---|
| Application UI, iOS / Android | native, React Native's model | `UIView`, `android.view.View` / `UILabel`, `TextView` |
| Application UI, browser | DOM, react-native-web's model | `<div>` / `<span>` |
| Void, on every platform, browser included | void host (`src/platform/void/host.ms`) | void2d rect / void2d text |

Which of these exist is recorded in `PORT-STATUS.md` and `ROADMAP.md`, not here.

## Void's two faces

1. **An advanced rendering area.** `<Void>` is one tag of the Application UI world. Inside it, Void's
   own tags draw 2D, 3D, shaders and games through a WebGPU-shaped interface. The backend is native
   on each platform: Metal, D3D11, GL/GLES3, WebGPU, WebGL2. The browser treats a Void area as one
   more native component, a canvas, so the same Void code runs there. That it runs as fast as on
   iOS or Android is a goal, not a measurement.
2. **A host for Neon's vocabulary.** Void understands `Text` and `View` and maps them to void2d. So
   a UI written for the browser or for React-Native-style mobile also runs inside Void, drawn with
   WebGPU into a canvas or a Metal view instead of with HTML or native components.

The mechanics of face 1, meaning what exists on Void's side and what is missing on Neon's, are in
`RENDER-LAYERS.md` "Void as a native component — not built".

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
  (`voidEmbedFrame`, the idiom of `void/src/sokol/bridgeIos.m` and `bridgeAndroid.c`), and Void
  owns no loop and no window. A game keeps control of simulation step, present timing and pacing.
- **What a game needs is exposed through Neon, not around it:** raw and relative pointer input,
  pointer lock, exclusive fullscreen, vsync mode. Input reaches a Void area without a per-event
  allocation at high polling rates.
- **Audio never goes through the tree.** It runs on the device's own thread; Neon only carries
  control.

## Open

- **A native sibling drawn over a Void area**, for example a UIKit button floating over a game.
  Either it is allowed, and the OS compositor stacks the views, or a Void area is always opaque
  and nothing overlaps it.
- **One Yoga tree or two.** Either the Void world runs its own layout from the size the Application
  UI gives the `<Void>` tag, or one Yoga tree runs through the boundary.
- **The Application UI world on the desktop.** Native widgets through Ion, or Ion's webview under the
  DOM host.
- **Two runtimes in one browser page.** Neon's browser host runs on the JS backend, and Void's web
  build is separate. The JS↔wasm crossing is unmeasured.
- **Void's own tag vocabulary.** The void host maps every tag to a `group()` today.
