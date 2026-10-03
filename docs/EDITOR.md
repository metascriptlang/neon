# Neon Studio — the Editor

A visual editor (Figma-class) built on Neon, where **the design *is* the code**. There is
no separate design format and no "export to code" step: the file you edit visually is the
`.ms` source that ships.

> Design-facing brief for generating the UI lives in `EDITOR-DESIGN.md`. This file is the
> concept + architecture note.

---

## The core bet

**rendering tree === editing tree === source file.**

Every other tool keeps two worlds — a proprietary scene graph for design, and code for
shipping — and spends enormous effort keeping them in sync (they always drift). Neon Studio
collapses them: the Neon component tree (JSX-like MetaScript) is simultaneously

1. the **source** that compiles to a real app,
2. the **render tree** drawn on the canvas,
3. the **scene graph** the editor manipulates.

Edit the canvas → the exact tag in `.ms` is rewritten. Edit the source → the canvas updates
live. One artifact, two views, zero drift.

---

## Two execution modes (Unreal-style)

Same source, two ways to run it — because Raiser and the native backends **share the first
4 compiler phases** (parse → check → macro-expand), differing only in codegen:

| Mode | Backend | Used for |
|---|---|---|
| **Edit / Play** | **Raiser** (interpret/bytecode) | live editing, hot reload, "hit play" |
| **Ship** | **msc → C / JS** | production build, full native perf, no Raiser |

Shared frontend ⇒ **semantic parity is essentially free**. No "works in editor, breaks in
build" — the drift we killed on the design side cannot reappear on the behavior side.

---

## Why this is buildable now — the pieces we already own

The hard parts are not research; they are engines Neon already has. The editor **queries**
them instead of inventing inference.

| Capability | Already exists | Editor uses it for |
|---|---|---|
| **Code ⇄ AST ⇄ code** | `recompiler/src/compiler/fmt/` (printer + layout, preserves comments) | write-path: edit the AST, serialize back with the formatter |
| **Flex layout, both directions** | Yoga engine (computed box + flex inputs) | drag ⇒ layout intent (margin/gap/order), never absolute x/y |
| **Fine-grained reactivity** | Solid-style signals/effects (`src/core/`) | provenance per property; surgical live re-render |
| **Self-drawn cross-platform renderer** | Void — Layer B+C, `void2d` + `sokol_gfx` | the canvas surface; pixel-identical everywhere; opens GPU/3D |
| **Renderer-agnostic reconciler + Host seam** | Neon Layer A (`src/render/`) + `voidHost` | drive the Void canvas from the same tree the app uses |

See `RENDER-LAYERS.md` for the Neon (Layer A) × Void (Layer B+C) split.

---

## How editing works

The editor **never touches text**. It is a structured AST editor; the formatter is the
serializer.

```
   file.ms ──parse──▶ AST ──▶ [ EDITOR mutates AST nodes ]
                       ▲                      │
                       │                mutate node
                       │                      ▼
   file.ms ◀── fmt/printer (existing) ◀───────┘

   Read-path  (live): .ms → Raiser → Neon reconcile → Void canvas
   Write-path (edit): gesture → AST node change → formatter → .ms
```

Read-path and syntactic write-path are both **free** (already built). The only real work is
the **semantic layer**: mapping a canvas gesture to *which AST node changes, and how*. And
even that is mostly *reading two engines*:

- **Is this property editable?** Ask the reactive graph. No dependency edge → **literal**,
  edit freely. Edge to a value → **bound**, jump to source. Computed by a signal →
  **code-driven**, locked. (Not a heuristic — the graph states it.)
- **What does this drag mean?** Ask Yoga. It knows the box *and* the constraint that placed
  it, so a 12px drag becomes `+marginLeft` / reorder / `flex-grow`, not `x = 132`.

### Where the per-node data comes from: the macro, not a runtime tree

The scene panel and the provenance inspector need, for every node on the canvas, the tag's
position in the source and whether each property is a literal or bound to an expression.
Since the one-NeonNode merge (`RENDER-MODEL.md`) there is no description tree at run time to
walk: a NeonNode is a function that mounts host nodes. The tree it replaced would not have
served either — its fields (`tag`, `attrs`, `children`, `componentProps`, …, at `5c2802e`
`src/render/node.ms`) carried no source position and no literal/bound distinction.

The `element` macro already knows both at compile time: the line and column of every JSX
site, and for each attribute whether it is a string literal or an expression, and whether
that expression is reactive (`isReactiveExpr`, `isAccessorTyped`). So the editor's data is
emitted by the macro, in dev builds only: a source position and a provenance per host node
and per property, handed to the host beside the mount. The reactive graph then answers the
remaining question at run time — which bound values are live. Nothing of this reaches a ship
build. Not built yet; this records where it belongs.

---

## What's unique (vs the field)

- **No drift, structurally** — not "good sync," but *the same file*. (vs Figma, v0, Webflow,
  Builder.io — all maintain a design↔code gap.)
- **Provenance on every value** — the tool always knows *why* a value is what it is
  (literal / bound / code-driven) and shows it. Figma cannot; it has no reactive graph.
- **Prefabs are real code** — a component is a `.ms` function, so the Unity/Godot
  prefab/scene model *is* the module system. Reuse, nesting, and overrides are code, not a
  proprietary component feature.
- **One reactive model drives everything** — the same signal graph that sets a button's
  width can drive a shader uniform, a 3D transform, or a physics parameter. Unified by
  reactivity instead of Unreal's Blueprint↔C++ split.

---

## Cross-boundary rendering

Because the canvas is self-drawn (Void), the tool is not limited to app UI. The **same
Neon/Solid reactive model** targets any render surface:

```
        fine-grained reactivity  (universal driver)
        ┌───────────┬───────────┬──────────────┐
      DOM UI     Void 2D     WebGPU / 3D    shader / physics
        └────────── all provenance-tracked ──────────┘
```

This makes Neon Studio closer to a reactive **engine** than to a design tool — but the v1
surface stays deliberately narrow (below).

---

## Decisions locked

| # | Decision |
|---|---|
| 1 | Editor operates on the **AST**; serialize via the existing formatter (no text patching). |
| 2 | Drag ⇒ **layout-aware** (flex/margin/gap/order), never absolute x/y. |
| 3 | Editing an element inside a `<For>` edits the **template** (all instances); per-item difference is a data/refactor concern, deferred. |
| 4 | Code-driven props are **locked + badged**, never silently clobbered into literals. |
| 5 | Component/instance = **Neon component/usage**; UX is a **prefab/scene tree**, not a flat layer list. |
| 6 | **v1 = 2D UI on Void, dark desktop web**. Architecture stays open to GPU/3D; not in v1 scope. |

---

## Open / deferred

- **Per-instance override** inside a loop (Figma "instance override" for `<For>` items) —
  how/whether to express it without polluting the template. Deferred.
- **Provenance UX policy** — hard-lock code-driven props vs offering inline "edit the
  signal source." Small; decide during build.
- **Collaboration** — multiplayer editing on top of an AST/CRDT model. See `COLLAB.md`.
- **Naming** — "Neon Studio" is a working title.
