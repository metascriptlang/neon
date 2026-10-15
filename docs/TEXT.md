# Text: one paragraph model on every host

Neon's `<Text>` is to be stronger than React Native's and Flutter's. The person approved the direction on
2026-10-15. This file keeps the decision, the reference evidence it rests on, the measurements and the order of work.
The code is the truth for everything else: `src/platform/void/host.ms` (`refreshParagraph`, `adopt`) and
`src/platform/native/host.ms` (`LabelRun`, `refreshLabel`).

## The decision

- **Surface:** React Native's nested `<Text>` as the author writes it. Flutter's capability set sits under it:
  - styled runs;
  - inline views as placeholders with an explicit alignment and baseline;
  - press, hover, cursor and accessibility per span.
- **A data door beside it.** This is Flutter's `Text.rich(TextSpan)`, for content that is already data, such as
  terminal and editor lines. The prop name and its element shape were still open when this was written. The
  proposal is `spans`, each `{ text, style, …Text props }`, so that a span is the data form of a nested `<Text>`.
  Both doors lower to the same paragraph host call.
- **Damage per Solid binding, not per tree diff.** Each change is classed with Flutter's `RenderComparison`
  levels:
  - text, font, size or spacing: `layout`;
  - colour, background or decoration: `paint`;
  - handlers, cursor or accessibility: `metadata`, and never dropped.

  Solid already delivers each update to its binding with the old and the new value. dom-expressions
  `solid-next 47d2346` emits `effect(() => c(), (v, prev) => setProp(el, "style", v, prev))`.
- **NEW MECHANISM, approved 2026-10-15: a persistent platform layout per paragraph on native hosts.**
  - Each damage level gets its own platform call:
    - layout rebuilds the layout;
    - paint goes to DirectWrite `SetDrawingEffect`, an Android appearance-span swap plus `invalidate`, or iOS
      `invalidateDisplay(forCharacterRange:)`;
    - metadata touches neither.
  - A run table (UTF-16 offset to span) is kept beside the layout, so hit-testing and accessibility need no rebuild.
  - What it can break: a layout out of step with its string misplaces hits, drawing and accessibility, so a test
    must catch any drift.

## What the references do (read 2026-10-15)

React Native `18f5ddb`, react-native-windows `1f59db1`, Flutter `6f0e0db`, Skia `430885776a` (Flutter's DEPS pin).

**Neither has a real paint-only path.**
- In RN a colour change costs the same as a text change:
  - new children dirty Yoga unconditionally (`YogaLayoutableShadowNode.cpp:156-160`);
  - iOS rebuilds TextKit for every draw, touch and accessibility query (`RCTTextLayoutManager.mm:135,469,500`);
  - Android builds a new Spannable, then `setText` and `requestLayout`;
  - RNW drops its `IDWriteTextLayout` on every state (`ParagraphComponentView.cpp:125`).
- Flutter's `paint` class still rebuilds and re-lays out the `ui.Paragraph`. `text_painter.dart:1336-1339`: "there's
  no API to only make those updates". Only Skia's `ParagraphCache` saves the shaping, because its key leaves paint
  out (`TextStyle.cpp:102-115`).

**The platforms do allow a paint-only update.**
- Android: an `UpdateAppearance` or `CharacterStyle` span change only `invalidate()`s (AOSP `TextView.java`
  `13000-13008`).
- DirectWrite: drawing effects are applied at draw time (`IDWriteTextLayout::SetDrawingEffect`, learn.microsoft.com).
- iOS: `NSLayoutManager.invalidateDisplay(forCharacterRange:)` "does not actually cause layout".
- Whether TextKit 1 re-lays out on an attribute-only edit is not verified.

**Holes to avoid.**
- Flutter `TextSpan.compareTo` ignores the cursor, hover handlers and the semantics label, although `==` does not.
  `RenderParagraph.text` returns on `identical` without storing the new span (`text_span.dart:481-517`,
  `paragraph.dart:420-422`). This was read, not run.
- RN's measure-cache key leaves out `textTransform` (`TextMeasureCache.h:120-173`), so a change of only that can
  return a stale size. Classify each property by what it does, not by a hand-kept list.
- RNW draws a nested underline or background only when the colour also differs (`TextDrawing.cpp:71-73`).
- RNW's UIA text range widens UTF-8 byte by byte (`CompositionTextRangeProvider.cpp:285`).
- Per-span accessibility is weak everywhere:
  - iOS gives a wrapped link the rect of its first line only (`RCTTextLayoutManager.mm:529`);
  - Android makes virtual views only for `role=link` and ignores a span's `accessibilityLabel`
    (`ReactTextViewAccessibilityDelegate.kt:229-230,313`).

## Void today

`createVoidHostWith` gives each outermost `<Text>` one void2d label. Strings and nested Texts inside it are spans with
no scene node: a span's handle is a freed row, so any use of it fails loud. The label wraps at the Text's laid width.
It gets runs only once a span styles a piece.

Refused by name until the slice that adds each one:
- a `View` inside a `Text` (inline views);
- `onPress` on a nested `Text` (per-span hit-testing);
- a nested `fontSize` (a void2d label has one size).

**A Text's height does not yet come from its content.** Yoga's binding has no measure hook; the request, approved
2026-09-30 and still waiting on a session started in `~/metascript/yoga`, is
`~/metascript/.inbox/yoga/2026-09-30-neon-text-measure-hook.md`. RN sizes a paragraph through exactly that hook
(`YGNodeSetMeasureFunc`, `YogaLayoutableShadowNode.cpp:80`). Until it lands, a Text is as tall as yoga makes it, and
rows in a list need an explicit height.

**A colour-only run change still reshapes.** void2d's `setLabelRuns` sets `reshape` unconditionally, although draw
reads a glyph's colour from its run. That is the Void request `~/metascript/.inbox/void/2026-10-15-label-runs-paint-only.md`.

## Measured

`msc run --release`, Windows, headless. The numbers are CPU-side shaping, layout and scene recording; there is no GPU.
Rows are 80 labels of 120 glyphs. The probes are `tests/zzprobe/bench.ms` and `neonBench.ms`, uncommitted.

void2d alone (Void `7b9ec3ae`):

| case | ms per frame |
|---|---|
| idle | 0 |
| one row re-typed | 0.04 |
| all 80 rows new text | 3.05 |
| all 80 rows colour-only runs | 2.81 (it reshapes) |
| all 80 rows re-wrap only | 1.65 |
| new text with `setMaxWidth` set, against without | 3.38 against 3.01–3.11 (three pairs) |

Through Neon's Void host, 400 frames per case, old main and this slice run alternately, three pairs, with the box
busy with other sessions. This slice is tree `6a9d6858`.

| case | before | paragraph |
|---|---|---|
| mount 80 rows | 0.80–1.21 ms | 0.95–1.01 ms |
| one row re-typed | 0.062–0.065 ms | 0.052–0.059 ms |
| all 80 rows new text | 3.26–3.32 ms | 3.42–3.59 ms |
| scroll one line | 0.52–0.54 ms | 0.51–0.52 ms |

All 80 rows new text is slower by about the cost of wrapping, which the void2d rows above isolate. Before this slice a
label never wrapped.

## Order

1. Paragraph on the Void host: done, with the yoga measure hook outstanding.
2. Carry runs and the damage level through `src/render/hostTypes.ms`; add the data door; add `cellWidth` →
   `setForceWidth`.
3. Paint-only updates: on Void after the Void request lands; DirectWrite keeps its layout.
4. Per-span press, hover, cursor and accessibility.
5. Placeholders (inline views).
6. iOS and Android on the same contract.
