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
- **A data door beside it**, decided 2026-10-15: `<Text spans={…}>`, each `TextSpan { text, style? }`
  (`src/render/hostTypes.ms`). It is Flutter's `Text.rich(TextSpan)`, for content that is already data, such as
  terminal and editor lines. A span is the data form of a nested `<Text>`.
  - On a host with the `setSpans` capability (Void), the spans go straight into the paragraph's runs, with no
    node per span.
  - On any other host, `src/render/spanHost.ms` `spanNodes` lays them out as nested Texts, keeping each
    span's nodes by position.
- **One mechanism for both doors**, decided 2026-10-15. This is RN Fabric's, where nested `<Text>` and `RawText` are
  shadow nodes with no view, and `ParagraphShadowNode` flattens them into one `AttributedString`.
  - On a host with `setSpans`, a Text's children render into `SPAN_HOST` (`src/render/spanHost.ms`), whose nodes are
    plain records. The outermost Text flattens its records and hands the host the same `TextSpan[]` the `spans`
    prop does.
  - It does that once per update, from a deferred `createEffect` that runs after every render effect of the update.
    A paragraph of one string skips the effect and goes straight to the host.
  - The native host takes spans too (`setSpansOf` in `src/platform/native/host.ms`). A span with `onPress` keeps its
    own tag by position, and a touch on it bubbles from its Text. The `textSpans` wire format the bridges read is
    unchanged (`tests/platform/nativeParity.test.ms`).
  - Hosts that draw nested text as real nodes keep them: DOM and SSR (`<span>`s, CSS classes, hydration), and the mock
    host. A framework site that builds a label by hand writes its string through `setTextContent`.
  - Rejected: `runs` as `{ len, color… }` beside one string. Its only gain is skipping a substring per span
    (about 0.05 ms per frame, measured below). Against that, the lengths must sum to the string's UTF-16 length,
    a terminal parser that counts code points breaks it, and the fields are void2d's rather than Text's.
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

`createVoidHostWith` gives each `<Text>` one void2d label, filled through `setSpans`; a Text has no host children,
and `append` into one is refused. The label wraps at the Text's laid width. It gets runs once a span is styled or the
Text itself carries a decoration line.

A Text's or span's `fontFamily`, `fontWeight` and `fontStyle` pick its face through void2d's `registerFace` and
`resolveFont`, a span's own over its Text's. A Text with no `fontFamily` takes the host's default family; an Ion window
registers its `font` file as that family. A weight or slant the family has no file for is synthesised by void2d, as
Ghostty, WezTerm, DirectWrite and CSS `font-synthesis` do (RN iOS takes the nearest weight instead,
`RCTFont.mm:480`), and the person chose synthesis on 2026-10-16. A family with no registered face, or a weight asked
for with no family at all, is refused by name. `textDecorationStyle: "wavy"` maps to the run's `wavy`. The native
hosts refuse every line style but `solid`, and they do not read `fontFamily` yet.

A press over a span with `onPress` fires that span's handler and not its Text's (`clickAt`, `spanAt`): the point's
grapheme comes from void2d `indexAt` and `xForIndex`, and a point past a line's end hits no span. Like every Void Text,
a Text that takes presses needs a height until yoga has its measure hook.

Refused by name until the slice that adds each one:
- a `View` inside a `Text` (inline views);
- a nested `fontSize` (a void2d label has one size);
- `textDecorationStyle` `double`, `dotted` or `dashed`;
- `cellWidth` on a nested Text. `<Text cellWidth={n}>` maps to void2d `setForceWidth`, so grapheme k sits at k×n. The
  browser and native hosts refuse `cellWidth` by name.

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

Spans against plain text, 80 rows of 120 characters all new every frame, 400 frames, two alternating runs, tree
`9ef44f1a`, before nested Texts moved onto `SPAN_HOST`. The probe is `tests/zzprobe/spansBench.ms`, uncommitted.

| rows | ms per frame | building the lines | reactive set |
|---|---|---|---|
| plain text | 3.32–3.39 | 0.34 | 0.07 |
| 8 spans of 15 characters, two shared styles | 3.59–3.74 | 0.38–0.40 | 0.22–0.24 |

Off-screen rows cost nothing: the list is virtualized, holding only the visible lines.

The same 80×120 rows with 8 spans per row written as nested JSX `<Text>`, three pairs of `main` (`8d5c0cf`) and
`SPAN_HOST` run alternately on a busy box:

| rows | `main` | `SPAN_HOST` |
|---|---|---|
| plain text | 3.44–3.71 ms | 3.40–3.51 ms |
| spans | 3.76–4.11 ms | 3.72–3.75 ms |
| nested JSX | 5.86–7.04 ms (reactive set 2.30–2.96) | 4.08–4.22 ms (reactive set 0.60–0.67) |

On `main`, each of a row's eight string bindings rebuilt the paragraph on its own, so a row was rebuilt eight times
per frame.

## Order

1. Paragraph on the Void host: done, with the yoga measure hook outstanding.
2. The data door: done. `spans`, and `setSpans` on Void. `cellWidth` → `setForceWidth`: done on Void.
   Damage per binding needs no contract field: a host compares a node's last style with the new one.
3. Paint-only updates: done on Windows (DirectWrite keeps one layout per label and recolours through drawing effects;
   `docs/WINDOWS.md` "Built: styled runs"); on Void once the Void request lands.
4. Per-span press: done on Void, native (tags) and Windows (DirectWrite hit-testing). Hover, cursor and accessibility
   per span are not built: Void has no accessibility tree, and the Windows bridge has no UI Automation yet.
5. Placeholders (inline views).
6. iOS and Android on the same contract.
