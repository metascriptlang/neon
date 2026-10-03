# Neon Studio — Editor Design Brief

> **Working title:** *Neon Studio*. A design tool where **the design IS the code**.
> This document is a **design brief for an AI UI designer**. It is self-contained — you
> do not need any other file. Read §0 first: it tells you your role, what to produce,
> and what to avoid.

---

## 0. Your job (read this first)

**You are a senior product designer for professional creative software** — the class of
tool that Figma, Unity Editor, and Linear belong to. You are designing the interface for
*Neon Studio*, a visual editor whose canvas edits **real source code** in a language
called MetaScript.

**Produce:** the desktop editor shell and its core panels, plus the key interaction
states listed in §5. Web app, desktop-sized (≥1440px wide), dark theme.

**Design decided, not generic.** Every screen below specifies real content, real labels,
real hierarchy. Use them. Do **not** fall back to placeholder lorem, do **not** invent a
"clean modern SaaS landing page," do **not** produce a mobile layout. This is a dense,
professional, information-rich tool — closer to a DAW or a game engine than to a marketing
site.

**The single idea every pixel must serve:** *there is no gap between the design and the
code — they are the same artifact, seen two ways.* The UI's job is to make that feel true.

---

## 1. The product in one paragraph

Every other design tool exports to code, and the export immediately drifts from the design.
Neon Studio deletes that gap: the file you edit visually **is** the source file that ships.
The canvas renders a Neon component tree (JSX-like MetaScript); when you drag, resize, or
restyle something on the canvas, the tool rewrites the exact tag in the `.ms` source. When
you edit the source, the canvas updates live. One source of truth, edited from both ends.
Beyond layout, you compose **behavior** in the same file (event handlers, state, effects),
running live while you edit, and compiling to native code when you ship. It is Figma's
directness + a game engine's scene/prefab model + a code editor's honesty, unified.

---

## 2. Who uses it, and what they get

- **User:** product engineers and design-engineers who are tired of the design→code
  handoff. They read code fluently but want direct manipulation for layout and styling.
- **The promise:** *"What you arrange on the canvas is committed to your repo as clean,
  human-authored code — not a generated export you can never touch again."*
- **The feeling:** precise, fast, trustworthy. Nothing is hidden; every value on screen can
  be traced back to the line of code that produced it.

---

## 3. The four pillars the UI must express

These are the load-bearing concepts. If the design communicates nothing else, it must make
these four legible at a glance.

### Pillar 1 — Scene & Prefab tree, not a flat layer list

Neon components are **reusable prefabs** (think Unity Prefab / Godot Scene), because each
one is literally a function in the source. So the left panel is **not** Figma's flat layer
list. It is a **scene hierarchy of component instances**, plus a **Prefab Library** of
reusable components you drag into the scene. Editing a prefab updates every place it is
used. This nesting is recursive and it is real code.

### Pillar 2 — Provenance inspector

Because the runtime tracks fine-grained reactivity, the tool knows *why every property has
the value it has*. The inspector must show, per property, one of three provenance states:

- **Literal** — a plain value (e.g. `width: 200`). Fully editable inline. Editing it
  rewrites the literal in source.
- **Bound** — references another value (e.g. `color: theme.primary`). Shows the reference
  with a "jump to source" affordance. Not a free-text edit.
- **Code-driven** — computed by a function/signal (e.g. `x: pos()`). **Locked** for direct
  manipulation, shown with a distinct badge; to change it you edit the code behind it.

This provenance system is the tool's signature — a thing Figma structurally cannot do.
Make it a first-class, visually confident part of the inspector, not a footnote.

### Pillar 3 — Layout-aware manipulation (never absolute x/y)

The layout engine is flexbox (Yoga). Dragging an element does **not** write absolute
coordinates — it adjusts **flex / margin / gap / alignment / order**. The canvas must show
layout intent while manipulating: flex direction arrows, gap handles, margin/padding bands,
alignment guides, insertion markers when reordering. Direct manipulation must feel like
Figma auto-layout, not free-floating absolute positioning.

### Pillar 4 — One canvas, two modes (Edit / Play)

The canvas is a self-drawn surface (the tool renders its own pixels, like Flutter — it does
not borrow native widgets), so the same canvas can eventually show 2D UI, and later GPU/3D
scenes and shaders. A prominent **Edit ⇄ Play** toggle switches between *arranging* the UI
and *running* it live (the behavior executes, state updates, you interact with the real
thing). Play mode is the "hit play in the game engine" moment.

---

## 4. The editor shell — panels and their content

A single-window, multi-panel desktop layout. Dense, dockable-feeling, dark. Regions:

```
┌──────────────────────────────────────────────────────────────────────────┐
│  TOP BAR:  ◧ Neon Studio   [file: TodoApp.ms ▾]   ⟳   ▶ Play   ⇧ Share   │
├────────────┬──────────────────────────────────────────┬────────────────────┤
│            │                                          │                    │
│  LEFT      │                CANVAS                    │   RIGHT            │
│  Scene     │   (self-drawn surface, rulers, the       │   Inspector        │
│  + Prefab  │    live component tree, selection        │   (provenance)     │
│  Library   │    handles, layout guides)               │                    │
│            │                                          │                    │
├────────────┴──────────────────────────────────────────┴────────────────────┤
│  BOTTOM:  CODE VIEW  ⇄  synced with selection   |   DATA panel   |  Console │
└──────────────────────────────────────────────────────────────────────────┘
```

### 4.1 Top bar
- App mark, current file name (`TodoApp.ms`) as a dropdown (open other files).
- **Edit ⇄ Play** toggle — the single most prominent control after the file name.
- Live-sync status (a small indicator that canvas ⇄ source are in sync).
- Right side: Share / collaborators (avatars), and a "commit" affordance (this writes to a
  git repo — surface it, quietly).

### 4.2 Left panel — Scene Tree + Prefab Library (two stacked sections)

**Scene Tree** (top): the component hierarchy of the open file. Real example content:

```
▾ App
  ▾ Header
      Title  "My Tasks"
      AddButton
  ▾ TodoList
    ▾ For  (todos →)                      ← loop node, shown distinctly
        Card × 4                          ← instances produced by the loop
  Footer
```

- `For` / `Show` (control-flow) nodes look **different** from element nodes — they are logic,
  not boxes. A loop shows how many instances it currently produces.
- Selecting a node selects it on the canvas and in the code view.
- Prefab instances (e.g. `Card`) show a small prefab glyph; expanding is optional.

**Prefab Library** (bottom): reusable components, drag-to-place:

```
── Prefabs ─────────────
[ Card ]  [ Button ]  [ Header ]  [ Avatar ]  [ TextField ]   + New
```

### 4.3 Canvas (center) — the live surface

- Renders the real component tree. Selection shows handles; hovering shows the element's
  name + prefab origin.
- **Layout-aware manipulation affordances** (Pillar 3): gap handles between flex children,
  margin/padding bands on the selected element, flex-direction indicator, alignment guides,
  and an insertion bar when dragging to reorder.
- Rulers, zoom control, a small breadcrumb of the selected node's ancestry.
- In **Play mode**, all editing chrome disappears; the surface is just the running app.

### 4.4 Right panel — Inspector with provenance (Pillar 2)

The heart of the tool. For the selected element, group properties (Layout, Style, Text,
Events). Each property row shows its **provenance state**. Example, a selected `Card`:

```
CARD  ·  prefab instance  ·  ↳ open prefab

▾ Layout
   width      320            · literal      [ editable field ]
   padding    16             · literal      [ editable field ]
   gap        12             · literal      [ editable field ]
   align      center         · literal      [ segmented ]

▾ Style
   background surface.raised  · bound        theme →  [ jump to source ]
   radius     12             · literal      [ editable field ]

▾ Content
   title      todo.title     · code-driven  🔒  [ badge: from For item ]

▾ Events
   onPress    () => remove(todo)   · code-driven  🔒  [ open in code ]
```

Three provenance states must be **instantly distinguishable** by color/iconography:
`literal` (editable, neutral), `bound` (linked, with jump), `code-driven` (locked, badged).
This is the screen to get right above all others.

### 4.5 Bottom dock — Code view / Data / Console (tabbed)

- **Code view:** the actual `.ms` source, **two-way bound to selection**. Selecting a node
  on the canvas highlights its tag here; editing here updates the canvas live. This panel is
  what makes "design is code" undeniable — show them side by side, synced.
- **Data panel:** the values driving loops/state (e.g. the `todos` array). Editing an item's
  data changes what the canvas shows, *without* touching the design/template. (This is how a
  list of 4 different cards is authored: one template, four data rows.)
- **Console:** logs/errors from Play mode.

---

## 5. States & screens to produce

Design these explicitly — do not leave them implied:

1. **Default edit state** — everything above, a `Card` selected, inspector showing mixed
   provenance, code view synced to the selection.
2. **Provenance close-up** — a zoomed inspector panel that makes the three states
   (literal / bound / code-driven) visually unmistakable. This is the money shot.
3. **Layout manipulation in progress** — an element mid-drag inside a flex row: gap handles,
   insertion bar, alignment guides visible. Show that drag = layout intent, not x/y.
4. **Play mode** — same file, editing chrome gone, the app running; the Edit⇄Play toggle
   clearly in "Play."
5. **Prefab library + place** — dragging a `Button` prefab from the library into the scene;
   show the drop indicator in both the canvas and the scene tree.
6. **Loop / data** — a `For` node selected: the canvas highlights all instances it produces,
   the Data panel shows the backing array, and the inspector explains that per-item content
   is code-driven.
7. **Empty state** — a new/empty file: an inviting canvas prompting "drop a prefab or start
   typing," not a blank void.

---

## 6. Visual constraints (decided)

- **Theme:** dark, professional-tool palette. Deep neutral grays for chrome; the **canvas
  surface a slightly lighter stage** so content reads as "the thing," chrome as "around it."
- **Density:** high, but calm. Unity/Linear-grade information density — many controls, tight
  spacing (~2–8px field rhythm), foldout groups — without feeling noisy. Group with spacing
  and subtle dividers, not heavy boxes.
- **One accent color** used with intent (selection, primary action, sync-ok). Reserve a
  distinct **second signal color for the "code-driven / locked" provenance state** so it
  never blurs with the accent.
- **Typography:** a clean geometric/grotesk sans for UI; a **monospace** for the code view,
  property values, and anything that is literally source. The monospace/UI split visually
  reinforces "this is code."
- **Iconography:** crisp, minimal, engine-editor style (foldouts, tree chevrons, prefab
  glyph, lock badge, jump-to-source arrow).
- **References for tone:** Linear (restraint, polish), Unity Editor Foundations (dense
  inspector + hierarchy patterns), Figma (canvas directness + handles), a code editor
  (the source panel). Blend, do not copy any one.

---

## 7. What NOT to do

- **No absolute-coordinate framing.** Never present the layout tools as "set x/y." Layout is
  flex-based; the visuals must reflect that.
- **No flat layer list.** The left panel is a component/prefab hierarchy, not Figma layers.
- **No hiding the code.** The code view is a co-equal surface, not a hidden "developer mode."
- **No generic SaaS look, no marketing hero, no mobile layout, no light theme.**
- **Don't blur provenance.** Literal vs bound vs code-driven must be unmistakable — this is
  the product's signature, not decoration.
- **Don't over-round or over-shadow.** This is a precise instrument; favor sharp, quiet
  surfaces over soft consumer styling.

---

## 8. Appendix — the example file the screens depict

All screens use one running example so content stays coherent: **a Todo app**
(`TodoApp.ms`). Scene = `App › Header(Title "My Tasks", AddButton) · TodoList(For todos →
Card × 4) · Footer`. `Card` is a prefab with: `title` (code-driven, from the loop item),
`width` 320 / `padding` 16 / `gap` 12 (literal), `background` bound to `surface.raised`,
`onPress` code-driven `() => remove(todo)`. The `todos` array (4 rows) lives in the Data
panel. Use these exact values across every screen so the tool feels like one real product.
