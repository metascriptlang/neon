# Render Layers — Neon × Void × the Platform

How a declarative UI (JSX) becomes pixels, and **who owns each step** across platforms. This is the model that keeps Neon and Void from duplicating work.

> Companion: `RENDER-MODEL.md` — the render lifecycle and the two emission tiers
> (**tree emission** vs **direct emission**). "Layer A/B/C" here names
> reconcile/paint/GPU ownership; the emission tiers are a different axis and are
> never called A/B.

## The 3 layers

| Layer | Name | Runs when | Decides | Owner |
|---|---|---|---|---|
| **A** | Reconcile | on state change (signal flip) | **what** changed → mutate host object + set dirty | Neon (`src/render/reconcile.ms`) |
| **B** | Paint / walk | every frame (display refresh) | **how** to draw the current tree efficiently — honor dirty flags, cull, batch, static buffers | platform-dependent (see table) |
| **C** | GPU | every frame | the actual pixels | platform-dependent |

**Layer A is optional.** Void-standalone (no JSX) skips it — you mutate the retained tree imperatively and Layers B+C paint every frame. Layer A exists only when Neon drives the platform through JSX.

**Layers B+C are inseparable** — together they are "the renderer". The only question is whether you **borrow** them from the OS or **carry** your own.

> **Heaps has no Layer A.** Heaps users build the tree imperatively (`new Bitmap(tile); s2d.add(bmp); bmp.x = 10`) and Heaps' entire engineering investment is a high-quality Layer B (`sync()` lazy transforms, per-tile culling, `BatchDrawState`, `TileGroup` static buffers, filters). Void's Tier 0/1/2 quality plan is building that same Layer B, design-borrowed from Heaps. See `~/metascript/void/docs/HEAPS.md`.

## The Host seam (Layer A ↔ platform)

Neon's reconciler is **renderer-agnostic**. It walks a VNode tree and emits operations against a **Host contract** (`src/render/host.ms:12-23`):

```
createElement(tag) → HostNode       // make a host object
createText(s) / setText(node, s)     // text leaves
setAttr(node, name, value)           // mutate a field
append / insertBefore / removeChild  // tree edits
addEvent(node, name, handler)        // input wiring
nextSibling(node)                    // list reconciliation
```

Each platform implements `Host`. The reconciler never knows what a "node" really is — a `UIView`, a DOM `Node`, or a Void `Node2D`. `mockHost()` (`host.ms:97`) is a ~50-line in-memory reference implementation.

**This is the React host-config / R3F pattern, exactly:**
- React = reconciler; ReactDOM / React Native / R3F = Host implementations over DOM / native / THREE.
- Neon = reconciler; `neon-dom` / `neon-ios` / `neon-void` = Host implementations over DOM / UIKit / `Node2D`.

No reconciler ever lives in a renderer. Void does not build a reconciler — it implements `Host`.

## Cross-platform — who owns B+C

| Platform | Layer A (reconcile) | Layer B (paint walk) | Layer C (GPU) | Host object |
|---|---|---|---|---|
| **iOS native** | Neon | **Core Animation** (CALayer tree, render server) ◀ borrowed | **Metal** ◀ borrowed | `UIView` / `CALayer` |
| **Android native** | Neon | **RenderNode tree / HardwareRenderer** ◀ borrowed | **GLES / Vulkan** ◀ borrowed | `android.view.View` |
| **Browser DOM** | Neon | **browser engine** (Blink/WebKit layout + paint + composite) ◀ borrowed | browser GPU process ◀ borrowed | DOM `Node` |
| **Void** (any OS) | Neon | **`void2d` walk** (`src/void2d/`) ◀ owned | **`sokol_gfx`** ◀ owned | `Node2D` |

**Native modes are light** because B+C are the OS's — Neon contributes Layer A only and mutates native objects; the OS repaints every frame. **Void is heavy** because Void *is* the B+C renderer (the void2d scene walk + sokol GPU calls). Same Layer A on top; swappable B+C below the Host seam.

The retained-tree architectures mirror each other:

```
   iOS-native:        CALayer tree  →  Core Animation walk  →  Metal
   Void:              Node2D tree   →  void2d walk           →  sokol_gfx
```

Same 3-layer shape, different B+C supplier.

## Why Void is a platform at all

If every OS ships a mature B+C for free, why carry your own?

1. **Pixel-identical cross-platform** — native widgets render differently per OS; Void draws the same pixels everywhere (Metal / D3D11 / GL / Vulkan / WebGPU / WebGL2 from one source).
2. **Shaders / custom draw** — GPU effects can't be expressed as a native-widget tree.
3. **Games / canvas / data-viz** — need raw draw primitives, not widget composition.
4. **Browsers without a suitable native painter** — the DOM is the painter, but canvas-style GPU work wants WebGL2/WebGPU directly.

Void = the opt-in heavy backend for apps whose pixels the native B+C cannot produce. Neon-default (native) stays light for the apps that don't need it. See Void's `CLAUDE.md` "Direction" for the scope discipline that keeps Void from drifting into a game engine.

## What this means per repo

- **Neon** (`~/metascript/neon`) owns **Layer A** and the **Host contract**. It contains no B+C code. Adding a platform = implementing `Host` + binding to that platform's B+C (native objects, or Void).
- **Void** (`~/metascript/void`) owns **Layers B+C** and ships a **Host adapter** (`voidHost`) so Neon's Layer A can drive `Node2D`. Void-standalone uses B+C without Layer A (imperative).
- They meet only at the **Host interface**. No reconciler in Void; no renderer in Neon.

## Consequence for Layer B quality

The reconciler (Layer A) can blindly mutate host-object fields (`node.x = 10`) and go to sleep. **Layer B is what makes that cheap**: each frame it honors dirty flags and skips unchanged work. If Layer B's dirty machinery is broken (e.g. a forced `parentChanged=true` defeats the transform cache), then even a single-field reconcile change causes Layer B to re-walk the whole tree — making the reconciler pointless.

This is why Void's Tier 0/1/2 quality work (lazy transforms, culling, batching, static buffers) is a **dependency for the reconciler being cheap**, not a detour from it. See `~/metascript/void/docs/HEAPS.md` "2D Quality Parity".

## References

- **Neon**: `src/render/host.ms` (Host contract + `mockHost`), `src/render/reconcile.ms` (reconciler), `src/render/node.ms` (VNode), `src/platform/browser/dom.ms` (DOM Host reference).
- **Void**: `docs/VOID2D.md` "Where it sits", `src/void2d/{node,draw}.ms` (Layer B), `src/sokol/{bridge,gpu}` (Layer C), `docs/HEAPS.md` (Layer-B quality parity plan).
- **Analogues**: React host-config (`react-reconciler`), React-Three-Fiber (R3F), React Native.
