# Windows Host

Status: decided 2026-10-14; the View, Text, Pressable and ScrollView slices are built, hosted in an Ion window ("Built: View", "Built: Text", "Built: Ion window and Pressable", "Built: ScrollView" below), everything after them is not. The Windows Application UI world is a native host behind
`src/platform/native/bridge.h`, like iOS and Android (`IOS.md`, `ANDROID.md`), and its components
are Neon's own views drawn on DirectComposition. This document keeps the decision, the reference it
is ported from, the paths rejected and the one measurement taken. `VISION.md` "Worlds, nested one
way" holds the model; Void stays a component inside it, never the host.

## Decision

| layer | Windows choice | what RNW uses for it |
|---|---|---|
| component views (View, Text, TextInput, ScrollView, Switch, …) | ported from RNW's Fabric component views | `vnext/Microsoft.ReactNative/Fabric/Composition/*ComponentView.cpp` |
| compositor seam | RNW's `ICompositionContext` shape, implemented on DirectComposition | `vnext/Microsoft.ReactNative/CompositionSwitcher.idl` `ICompositionContext`, two implementations in `Fabric/Composition/CompositionContextHelper.h` |
| compositor | DirectComposition (`dcomp.h`), the tree Ion already owns per window | `Microsoft.UI.Composition` (WinAppSDK) by default, `Windows.UI.Composition` as `SystemCompositionContextHelper` |
| text | DirectWrite, drawn with Direct2D into a composition surface | `ParagraphComponentView`, `TextDrawing.cpp` (`IDWriteTextLayout`) |
| text input | windowless RichEdit (`ITextServices2` from `CreateTextServices`) | `Fabric/Composition/TextInput/WindowsTextInputComponentView.cpp` |
| scrolling | DirectManipulation driving the visuals (`DCompManipulationCompositor`) | `IScrollVisual` on `InteractionTracker` |
| accessibility | UI Automation providers per view | `CompositionDynamicAutomationProvider`, `CompositionTextProvider`, `CompositionTextRangeProvider` |

Reference: `~/projects/react-native-windows`, shallow clone at `1f59db1` (2026-10-12). RNW is to this
host what Nim is to the compiler: follow it where it can be followed, and record where it cannot.

The one planned divergence is the compositor, because of the constraint below. Every other layer
ports RNW's mechanism. RNW's code is C++/WinRT; the port is plain C++ over COM, built by `msc` like
Ion's `src/platform/windows/*.cpp`. `msc` compiles C++ against the mingw-w64 headers bundled with its
Zig (`~/.metascript/zig/lib/libc/include/any-windows-any/`), not the Windows SDK's, so a header the
port needs is checked there.

## Why DirectComposition and not RNW's compositor

- **`Microsoft.UI.Composition` cannot sit under a webview or a swapchain.** Microsoft's "Visual
  layer overview" (learn.microsoft.com, `windows/apps/develop/composition/visual-layer`, section
  "External content", page dated 2026-03-16): the WinAppSDK compositor "runs entirely within a
  Windows App SDK app and has access only to pixels that it drew". WebView2, SwapChainPanel and the
  Mica/Acrylic backdrops are external content: they render below the compositor's output through a
  hole, and "it's not possible to have compositor content behind external content". Neon's model
  puts a `<WebView>` and a `<Void>` (a swapchain) as elements among native views; Ion's DComp tree
  already composes a transparent WebView2 over a swapchain (`ion/docs/WINDOW-CONTENT.md`,
  `ion/src/platform/windows/core/composition.cpp`).
- **It brings WinAppSDK with it.** C++/WinRT, MSVC, the WinAppSDK runtime and its packaging, and an
  Ion window rebuilt on `AppWindow` + `DesktopChildSiteBridge` (RNW `CompositionHwndHost.cpp`).
  RNW's CLI also requires Visual Studio 18.6 (`cli/src/utils/msbuildtools.ts` `findAvailableVersion`),
  which refuses this box's Build Tools 2022 17.14.
- **DirectComposition is current.** The Windows SDK `10.0.26100.0` `dcomp.h` adds
  `IDCompositionDevice4` (Windows 11 22H2), `IDCompositionDevice5` (24H2) and the compositor-clock
  calls `DCompositionWaitForCompositorClock` / `DCompositionBoostCompositorClock` (21H2).
  Chromium `main` composes with it (`ui/gl/dc_layer_tree.cc` `CreateTargetForHwnd`, an
  `EXPERIMENTAL_IDCompositionDevice6`; `ui/gl/direct_composition_support.cc` `DCompositionCreateDevice3`)
  and scrolls with DirectManipulation (`content/browser/renderer_host/direct_manipulation_helper_win.cc`).
- **What it lacks, and the substitute.** No `InteractionTracker`: DirectManipulation with
  `DCompManipulationCompositor` (`directmanipulation.h`, in the SDK and in msc's Zig headers). No
  expression animations: `IDCompositionAnimation` curves (`dcompanimation.h`). Shadows and blur are
  `IDCompositionShadowEffect` / `IDCompositionGaussianBlurEffect` (`IDCompositionDevice3`).
  When an app needs what only WinRT composition has, a second `ICompositionContext` on
  `Windows.UI.Composition` is added beside the DComp one, as RNW keeps two. msc's Zig headers lack
  `windows.ui.composition.h` and `windows.ui.composition.interop.h` (a standalone mingw-w64 has them),
  so that context starts by bringing those headers in. `directmanipulation.h`, `dcompanimation.h`,
  `textserv.h`, `uiautomationcore.h`, `dwrite.h` and `d2d1_1.h` are there.

## Rejected

- **Mapping to XAML controls.** RNW's old architecture (Paper) did this on UWP XAML; RNW's CLI warns
  it "will begin to be removed starting with react-native-windows@0.82.0"
  (`cli/src/utils/oldArchWarning.ts`). WinUI 3 XAML needs WinAppSDK, for the reasons above.
- **One HWND per view.** A child window has no per-view opacity, transform or rounded clip, and Ion
  measured that an adopted `HWND` always sits under the whole DComp tree (`ion/TODO.md` "Adopt on
  Windows"), so it cannot stack with a webview or a Void area.
- **Void as the Windows Application UI.** Void is the free-rendering world inside a `<Void>`; it
  does not replace the native host model (`VISION.md`).

## Measured

2026-10-14, `msc` v0.3.3 (`~/.metascript/BUILD` `26150233`), its Zig 0.16.0, Windows 11, 96 dpi. A
probe of about 150 lines, not tracked: one `.ms` that `@compile`s one `.cpp` and links `d3d11`,
`dxgi`, `d2d1`, `dwrite`, `dcomp`, `dwmapi`, `gdi32`, `user32`, `uuid`. It creates a
`WS_EX_NOREDIRECTIONBITMAP` window, a D3D11 device with BGRA support, a D2D device on it,
`DCompositionCreateDevice2(d2dDevice)` as `IDCompositionDesktopDevice`, one visual whose content is
an `IDCompositionSurface` filled by `BeginDraw` → `ID2D1DeviceContext` with a DirectWrite
`IDWriteTextLayout` line, a 24 px `IDCompositionRectangleClip` and an `IDCompositionEffectGroup`
opacity of 0.85. It built on the first try and every HRESULT succeeded. Output:

```
ok text 347.0x37.2
pixel card-center    ( 90,100) =  37 112 207
pixel card-corner    ( 81, 81) =  54  66 103
```

The card centre is the cleared blue `(28,115,217)` blended at 0.85 over what lay behind; the
corner pixel is outside the rounded clip. A screen capture showed the rounded card and the text.

Not measured: drawing inside Ion's DComp tree (Ion exposes no device or visual yet, see below), a
DPI other than 96, DirectManipulation, RichEdit windowless, UI Automation.

## Built: View

`src/platform/windows/` holds the bridge. `bridge.cpp` implements the view-tree half of `bridge.h` over
`composition.h` (`ICompositionContext`, `IVisual`, named after RNW's `CompositionSwitcher.idl`);
`dcompComposition.cpp` is its one implementation, on `IDCompositionDevice2`. The bridge creates no window:
`handoff.h` is the whole surface the owner of the window uses. Two owners exist: `examples/windowsNative/app.ms`
and `text.ms` own a plain Win32 window (`niwPump`), and `src/platform/windows/ion.ms` owns an Ion window
("Built: Ion window and Pressable"); `--check` samples the owner's own window.
Every `bridge.h` function not implemented aborts with its name, and `niAppCall` answers only the queries
`installNativeAppServices` makes at startup. App services do not go through it on an Ion window. `ion.ms` hands
`useAppServices` the services of `src/platform/ion/appServices.ms`, the same ones the full-window `<Void>` installs.
In them, the clipboard and the microphone permission go through Ion, and every other service throws an error
that names it.

A build links the bridge only when the entry module imports `src/platform/windows/library`; `host.ms` has no
Windows block, so the mock-bridge tests, which also see `windows` as true on this box, link their own mock.

Measured 2026-10-14 on the setup above, 96 dpi, `msc build examples/windowsNative/app.ms` then
`out/windowsNative.exe --check`: all 11 sampled pixels match (tolerance 3), among them the half-opacity child
`(141,185,236)` against an expected `(142,185,236)`, a `rgba(0,0,0,0.5)` background `(14,58,109)`, a point
inside a rounded child's box and outside its corner, and a point in a `scale(0.5)` child's box outside its
scaled box. Facts that took the measurement to find:

- `msc` compiles `.cpp` with Zig's bundled mingw-w64 headers, not the Windows SDK headers `clang` uses by
  default: `IDCompositionVisual3` does not exist there, so opacity is an `IDCompositionEffectGroup` on the visual
  and `IDCompositionRectangleClip` comes from `IDCompositionDevice2`.
- A visual's rounded `IDCompositionRectangleClip` is in its local space before `SetTransform`, so a scaled
  rounded view scales its corner radius, and the clip also clips the visual's children (RNW's
  `SetClippingPath`, `CompositionViewComponentView.cpp` `updateClippingPath`).
- `SetTransform` is applied before `SetOffsetX/Y`: a transform about the view's centre is built in local
  coordinates and the frame position goes into the offset.
- `ID2D1DeviceContext::Clear` on an `IDCompositionSurface` with `DXGI_ALPHA_MODE_PREMULTIPLIED` takes a
  straight-alpha colour and premultiplies it.

Not measured: a DPI other than 96 (frames, radius and translation scale by `GetDpiForWindow`, but only 96 ran),
resize, a second window, device loss.

## Built: Text

`dwriteText.cpp` is `niTextCreate`, `niSetText`, `niSetTextColor`, `niSetFont`, `niMeasureText`, `niMeasuredW`
and `niMeasuredH` on DirectWrite, drawn with Direct2D into a drawing surface. A text label is a view whose
visual's content is that surface, and it draws on its own visual: Neon never gives a Text a background
(`host.ms` `applyPaint` skips it), so `niSetBackgroundColor` on a Text aborts by name instead of clearing a
colour into the same surface as RNW does. The seam gained `IDrawingSurface` (`BeginDrawD2D(dpi)` returns the
`ID2D1DeviceContext`, origin at the surface's top-left in DIPs at that dpi; `EndDraw`),
`ICompositionContext::CreateDrawingSurface` and `IVisual::Content`; `Content` replaces a colour brush and a
later `Brush` replaces the surface. `Size` now marks colour content dirty only while a colour is set, which
was the trap that cleared a text surface on every frame change. The bridge draws the dirty labels in
`niwPump` after the loop runs and before `Commit`.

Measure is `ceil(width × scale) / scale` of `IDWriteTextLayout::GetMetrics` `width` and `height` at
`maxWidth`, Segoe UI, weight 700 when bold else 400, no font fallback set. `niSetProp(textAlign)` is
implemented (`auto`/`left`, `right`, `center`, `justify`); every other prop, `numberOfLines` and `textSpans`
among them, aborts by name. Invalid UTF-8 in `niSetText` aborts.

Measured 2026-10-14 on tree `adc65f5aa1e924966dbfb94989dd803e73179342`, 96 dpi, `msc build
examples/windowsNative/text.ms` then `out/windowsText.exe --check`: all 13 checks hold. The centre of a 96 px
bold `I` is `(255,255,255)`; a label's box corner shows the parent's blue; 1116 pixels of a 32 px `Hello
Windows` are within 60 of its yellow; 3 wrapped lines at `maxWidth` 200 measure 180x80 against DirectWrite's
179.17x79.80 (the harness measures with its own factory and allows one device pixel above); a right-aligned
label has 273 pixels in its right half and none in its left; a label changed from red `A` to `Updated text`
by a timer shows 0 red pixels and 822 mint ones. `out/windowsNative.exe --check` still matches 11 of 11.
The harness now pumps for 500 ms before sampling: with 30 pumps, which took under 100 ms, the
pixel counts varied run to run and a `setTimeout` did not fire.

Not measured: a DPI other than 96, resize of a text label, emoji and other colour fonts, text the system
falls back for, a label wider than its frame after pixel rounding (its layout box is the frame, so it wraps).

## Built: Ion window and Pressable

`src/platform/windows/ion.ms` `runNativeWindow(options, app, onMounted)` creates an Ion window with no webview and
runs the app under Ion's `runLoop`; `onMounted` receives the Ion `Window`. The first `onResize` record (Ion queues one when it creates the window) gives the
DPI and the client size: it calls `niwAttach(windowDevice, windowRoot, dpi, logicalW, logicalH)` and `runApp`. Every
later record calls `niwResize`, which sets the screen size, re-applies frames, corner radii and text surfaces when the
DPI changed, and runs the host's resize handler (a relayout). `src/platform/ion/window.ms` is the pattern for this wiring.

- **Frames on demand.** The window runs `FrameOnDemand`. The bridge calls a requester closure (`niwSetFrameRequester`,
  which `ion.ms` points at Ion's `requestFrame`) when a bridge call changed something, or when Neon's frame driver calls
  `niRequestFrame` (which answers 1 under an owner that set a requester and 0 under the Win32 harness, so the harness
  keeps its 16 ms timer). Ion's frame record calls `niwFrame`: the host's loop handler, Neon's pending frame callback,
  the dirty text labels, then the DComp `Commit`. Timers and promises run in Ion's own `msRunOnce`, so `niwFrame` never
  waits on `niLoopNext`. A change made during `niwFrame` is committed by that frame and asks for no further one.
- **Pointer.** `ion.ms` forwards Ion's left-button down and up, motion and leave records, and a focus loss, as
  `niwPointer(down | up | move | cancel, pixelX, pixelY)`. The bridge divides by the scale to window points and hit-tests
  its view tree: children in reverse child order (child order is z-order, `niBringChildToFront` reorders it), each view's
  point taken back through its `niSetTransform` / `niSetRotation` matrix about its centre, children tried when the point
  is inside the view or the view does not clip (a corner radius clips, as in the visual), the view itself when the point
  is inside it. A Text is hit only when `niViewSetPressable` marked it, as on iOS (`NeonLabel`). RNW's
  `ViewComponentView::hitTest` has the same order and the same clip rule; Neon's host passes no `pointerEvents`
  (`style/fields.ms` ignores it on native), so none is applied. A rounded corner does not shrink the hit area.
- **Phases.** A down starts a touch on the chain of tagged views from the hit view up to the root and reports phase 0 to
  each, innermost first, as iOS does through the responder chain; a move while the touch is held reports 4. An up
  hit-tests again: a chain view that still contains the point gets 1 then 2 (press), a chain view that does not gets 3
  (cancel, which Neon turns into `pointercancel` and `pointerleave`). iOS and Android report 1 and 2 wherever the finger
  lifted; Windows cancels instead, so `<Pressable onPress>` does not fire for down inside and up outside. Leave and focus
  loss cancel. `niLastTouchTag/Phase/X/Y/Time` read the last report; the time is the performance counter in
  milliseconds. `niSetResponder` and `niClearResponder` store the view only: a ScrollView scrolls by the wheel alone, so no touch is taken from it.
- **Accessibility props.** `niSetProp` stores `accessible`, `accessibilityLabel`, `accessibilityHint`, `accessibilityRole`
  and `accessibilityState` on the view, for the UI Automation slice; nothing exposes them yet. Any other name, an
  `accessib*` one included, still aborts by name. `ionPress.ms` logs how many views store a given value.

Measured 2026-10-15 on tree `67268ba2b71069d8fa23b270bb0f773f7c2efaae`, 96 dpi, msc v0.3.3 (BUILD `9cf5708c`), Ion
`e28af34`, one build at a time:

- `msc build examples/windowsNative/ion.ms` then `out/windowsIon.exe --check`: 12 of 12 pixels, then the window is
  resized to a client of 800x400 and 4 of 4 more (a pin anchored right and bottom moved from (570,290) to (770,370)).
  `ionText.ms` (the `text.ms` content in an Ion window) matches 13 of 13. `out/windowsNative.exe --check` 11 of 11 and
  `out/windowsText.exe --check` 13 of 13 still hold; `tests/platform/nativeHost.test.ms` 395 tests green.
- Again on Ion `6d324a6` and BUILD `cf18cd1d`, with decorated topmost check windows: `ion.ms` resizes through Ion's
  `setSize(win, 800, 400)`, which sizes the client in DIPs, and matches 16 of 16; `ionText.ms` 13 of 13.
- Idle: `out/windowsIonPress.exe` ran 6 s with no input and `niwFrame` ran once (the mount's frame), counted with a
  temporary counter that is not committed.
- `examples/windowsNative/ionPress.ms` driven by PostMessage mouse messages to its window (client 384x221):
  `press A 1 at 50,50` (inside), `press A 2 at 90,50` (on A's Text, bubbled to A), nothing for a click on the background,
  nothing for down in A and up outside, `press A 3` for down in A, a move inside, up inside, `press B` on B's left half and
  nothing on its right half under a later sibling View, `press C` inside a `scale(0.5)` Pressable's visual box and nothing
  in its layout box outside it, `press E` inside a `rotate(90deg)` Pressable's visual box (outside its layout box) and
  `press D` at a point where E's unrotated layout box lies over D. A Pressable with `onPressIn` and `onPressOut` logged
  `in D`, `press D`, `out D`, and for down inside, up outside `in D`, `out D` and no press.

Not measured: a DPI other than 96 (the `niwResize` path that re-applies the tree has never run with a changed DPI, and
text is not re-measured on it), a second window, device loss, a minimized or cloaked window, touch and pen, a right or
middle button, `hitSlop`, `pointerEvents`, mouse capture leaving the window with the button held (the PostMessage driver
posted an up outside the client, not a real drag out of the window), and a physical foreground session.

## Built: styled runs, recolour without a relayout, press on a run

`src/platform/windows/dwriteText.cpp` `TextLabel` keeps one `IDWriteTextLayout` per label and reads Neon's `textSpans`
(`src/platform/native/host.ms` `encodeSpan`). It changes the layout according to what changed:
- Text, size, weight, italic, underline or line-through rebuild the layout.
- A new width only breaks lines again (`SetMaxWidth`), so `niMeasureText` and the draw share one layout.
- A change that leaves every run's text and shape as they were only redraws. Each run's colour reaches its glyphs
  at draw time through `SetDrawingEffect`, which is applied at drawing time (learn.microsoft.com,
  `IDWriteTextLayout::SetDrawingEffect`).

On a press, `bridge.cpp` `niwPointer` hit-tests the label's layout (`TagAt`, `HitTestPoint`), and a pressable run
reports first, as its own tag, as the iOS and Android bridges do.

This goes further than RNW, which drops its layout on every state and builds a new one (`ParagraphComponentView.cpp:125`,
`1f59db1`), so a colour change there costs a full layout.

Measured 2026-10-15, tree `faf6e462`, 96 DPI, msc `a2b3e36a`, Ion `c995edb`. `out/windowsIonText.exe --check` passes,
and on top of the 13 earlier expectations:
- A nested `<Text style={{ color }} onPress>` run draws red inside white text.
- Recoloured to blue, it shows blue pixels and no red left, and `niwLayoutsBuilt()` counts 0 layouts built by the
  change.
- Pressing along y=320 every 4 px fires the run's `onPress` 33 times, the first at x=116, past the run's leading
  "white ", and never over the plain text.

`text.ms` 13/13, `ion.ms` 16/16 and `app.ms` 11/11 still hold.

## Built: ScrollView

`src/platform/windows/scrollView.cpp` `Scroller` is RNW's `CompScrollerVisual` (`Fabric/Composition/CompositionContextHelper.cpp`
at `1f59db1`) without its `InteractionTracker`, which DirectComposition does not have. `niScrollCreate` gives the scroll view a
content visual, and the bridge parents the ScrollView's children under it. The content visual's offset is minus the scroll
position (RNW drives the offset with the expression `-tracker.Position`, `:816`). The scroll visual clips its children to its
bounds, as RNW's inset clip does (`:801`): the seam gained `IVisual::ClipsChildren`, a rectangle clip without a radius. Hit-testing
adds the position to a point before it tries the children, so a press lands on the content now under the pointer.

- **Wheel.** `ion.ms` forwards Ion's wheel records as `niwWheel(x, y, notchesX, notchesY)`. The bridge hit-tests the point and
  walks from the view it finds up to the root. The first ScrollView that can move in that direction scrolls, and a ScrollView
  already at its limit passes the wheel to the one above it. This is RNW's `OnPointerWheelChanged`
  (`ScrollViewComponentView.cpp:964`): one notch is `WHEEL_DELTA`, 120 points, the move is animated, and a wheel during a move
  adds to the target (`ScrollBy`, `:1136`). The animation lasts 5 ms per pixel, at least 50 ms and at most 1000 ms, from RNW's
  `GetPositionAnimation` (`:1123`). The curve is a cubic ease-out, which was not compared with RNW's keyframe easing. A
  horizontal wheel follows `WM_MOUSEHWHEEL`, where positive means right. `scrollEnabled={false}` stops the wheel only;
  `scrollTo` still moves, as RNW's `scrollTo` comment says (`ScrollViewComponentView.cpp:1194`).
- **Bounds.** The position stays within 0 and content minus frame. It is clamped again when the content size or the frame
  changes, as the tracker's `MaxPosition` does (`UpdateMaxPosition`, `:1194`).
- **Events.** A frame steps each moving ScrollView before Neon's loop runs. Each position change reports phase 0 (`onScroll`)
  with the offset, the frame size and the content size, which is at least the frame size (`getScrollMetrics`,
  `ScrollViewComponentView.cpp:1300`). A wheel or `scrollTo` reports no drag or momentum phases, as in RNW, where a move from a
  `Try*` request carries a request id and fires neither. An animated move asks Ion for frames until it ends, then asks for none.
- **Options.** `horizontal` and `scrollEnabled` are read. The scroll bar props and the keyboard props are accepted and do
  nothing, because this host draws no scroll bar and has no software keyboard. `pagingEnabled`, `refreshEnabled` and
  `refreshing` abort by name when true, and so does any other option.

Measured 2026-10-16, msc BUILD `5631dd3e5`, Ion `b9b5e8b`, 96 DPI. `msc build examples/windowsNative/ionScroll.ms` then
`out/windowsIonScroll.exe --check` exits 0. The check posts real `WM_MOUSEWHEEL` and `WM_LBUTTONDOWN`/`UP` messages to the window:
- Before input, a 200x200 ScrollView of ten 100-point bands shows bands 0 and 1. The pixel below it is the window background, so
  the clip holds, and no `onScroll` fired.
- Two notches down move it to y=240 in 165 `onScroll` events over the animation, the last at exactly 240. Bands 2 and 3 are
  then where 0 and 1 were.
- A click at band 3's new place presses band 3.
- `scrollTo({ y: 900, animated: false })` clamps to 800 and shows bands 8 and 9.
- A wheel outside the ScrollView fires no event and moves nothing.

`ion.ms` 16/16, `ionText.ms`, `app.ms` 11/11 and `text.ms` 13/13 still pass.

Not built or measured:
- Touch and pen panning: RNW redirects touch to its `VisualInteractionSource` (`CompositionContextHelper.cpp:828`); here that is
  DirectManipulation, not built. Mouse drag does not scroll, in RNW either.
- Keyboard scrolling (RNW `OnKeyDown`, arrows and Page keys), scroll bars, inertia, paging and snap points, pull to refresh.
- Nested ScrollViews in a real window, and a DPI other than 96.

## Port map: Text, TextInput, UI Automation

Read 2026-10-14 in RNW at `1f59db1`, paths under `vnext/Microsoft.ReactNative/Fabric/`; only the Text part below
is built, in "Built: Text"; TextInput and UI Automation are not. `WTI` is `Composition/TextInput/WindowsTextInputComponentView.cpp`.

**Text.**
- **Measure.** `platform/react/renderer/textlayoutmanager/WindowsTextLayoutManager.cpp`
  `TextLayoutManager::measure` builds an `IDWriteTextLayout` per call (cached globally). The format
  is Segoe UI, the weight cast straight to `DWRITE_FONT_WEIGHT`, and the constraint is the layout
  box. Ellipsis is `SetTrimming` with `CreateEllipsisTrimmingSign`; `numberOfLines` only clamps the
  measured height. RNW sets no `IDWriteFontFallback` and no antialias mode, so fallback is
  DirectWrite's implicit one.
- **Draw.** `Composition/ParagraphComponentView.cpp` `DrawText` draws into a surface the size of the
  frame in pixels, on a DC whose DPI is 96 × scale, with `DrawTextLayout(…, ENABLE_COLOR_FONT)`
  (`Composition/TextDrawing.cpp`). Per-run colour is a drawing effect; underline and strike are
  layout ranges.
- **Neon mapping.** `niMeasureText` lays out at `maxWidth` and keeps
  `ceil(width × scale) / scale` (and the same for height) for `niMeasuredW/H`. The ceil matters
  because `host.ms` `measureTextWithin` turns the measured size into a fixed width and height, with
  no yoga measure function; iOS's `niMeasureText` ceils too. Use `width`, not
  `widthIncludingTrailingWhitespace`. Bold is weight 700, otherwise 400. `niSetFont` and
  `niSetTextColor` run on every paint, so a change marks the label dirty only when a value differs.
- **Seam.** The seam grows a drawing surface in the shape of RNW's `CreateDrawingSurfaceBrush`
  (`Composition/CompositionContextHelper.cpp`): the context creates it, it begins a draw at a DPI,
  and a visual takes it as content. `DCompVisual::Size` marks colour content dirty today, so a
  visual that owns a text surface must not have that content overwritten.

**TextInput.**
- **Mechanism.** Windowless RichEdit: `LoadLibrary("Msftedit.dll")` and `CreateTextServices`
  (`WTI`). The host is an `ITextHost` that reports `TXTBIT_D2DDWRITE`, and drawing is
  `ITextServices2::TxDrawD2D` on the composition surface's D2D context, not GDI. Initialisation
  sets plain-text mode, `SES_USECTF` (IME through TSF) and the change/selection event mask. Every
  key, character, mouse, focus and clipboard message reaches RichEdit through `TxSendMessage`;
  Enter is caught first for submit. The caret is a separate visual that blinks through an opacity
  animation, driven by `TxCreateCaret`, `TxSetCaretPos` and `TxShowCaret`.
- **Neon mapping.** Phase 0 comes from `EN_CHANGE`, with a host-write flag so a `value` set by Neon
  does not echo back (iOS does the same). Phases 1 and 2 come from `niSetFocused`, phase 3 from
  Enter, phase 9 from `EN_SELCHANGE` as "start,end". `editable`, `secureTextEntry` and `maxLength`
  map to `TXTBIT_READONLY`, `TXTBIT_USEPASSWORD` and `EM_LIMITTEXT`. Derive `TxGetPropertyBits` from
  the input's state; RNW's version returns a constant mask.
- **Header gap.** msc's Zig `textserv.h` has `ITextHost`, `ITextServices` and `CreateTextServices`
  but no `ITextServices2`, `TxDrawD2D`, `TXTBIT_D2DDWRITE` or `TXTBIT_D2DSIMPLETYPOGRAPHY`; the SDK
  `TextServ.h` 10.0.26100 has them. RNW itself declares the `ITextServices2` IID locally
  (`8D33F741-CF58-11CE-A89D-00AA006CADC5`); the port declares that interface's vtable the same way.
  `EM_SETDPI` is absent too (`WM_USER + 328`).
- **What the window owner has to give.** Keyboard focus on a real HWND, `TranslateMessage` in the
  pump, the forwarded key, character, mouse, wheel and focus messages, `SetCapture`,
  `WM_SETCURSOR`, `WM_DPICHANGED`, and the HWND for caret and IME placement.

**UI Automation.**
- **Mechanism.** A root provider (`Composition/CompositionRootAutomationProvider.cpp`) is the
  fragment root, with `UiaHostProviderFromHwnd` as its host provider. Each view gets a fragment
  (`Composition/CompositionDynamicAutomationProvider.cpp`) with RuntimeId
  `{UiaAppendRuntimeId, tag}`, bounds from the view rect plus the root's screen origin, and the
  Invoke, Value, Toggle, Scroll, RangeValue and Selection patterns. Events are raised only when
  `UiaClientsAreListening`. RNW leaves `WM_GETOBJECT` to the app (`CompositionHwndHost::UiaProvider`).
- **Owner.** The window owner answers `WM_GETOBJECT` (`UiaRootObjectId`) with
  `UiaReturnRawElementProvider`. Every interface and function named here is in msc's Zig headers
  (`uiautomationcore.h`, `uiautomationcoreapi.h`).

Not verified: TSF IME without `ITextHost2`; the `TxDrawD2D` rectangle's unit above 96 dpi;
mingw-compiled `ITextHost` and UIA providers called by the system's Msftedit and UIAutomationCore.

## What Ion gives

Ion's window is an empty root, and the contract is in `ion/docs/WINDOW-CONTENT.md` and `ion/src/platform/bridge.h`.
On Windows `windowRoot` is the window's root `IDCompositionVisual*` and `windowDevice` an `IDCompositionDevice*`
created on a D2D device, so `CreateSurface` hands out D2D-drawable surfaces; `commit` commits the transaction.
Pointer, key, text, IME, focus, resize and frame records arrive per window in client-area pixels, and Ion does
no hit-testing: the host parents its visuals under the root, z-orders them, and routes input itself. macOS (the
content view) and Linux (a `GtkFixed`) give the same contract. `src/platform/ion/window.ms` is the first host
on it, for a full-window `<Void>`; `src/platform/windows/ion.ms` hosts the native host of this document.
`createWindow(width, height)` and `setSize` size the client area in DIPs on Windows since Ion `6d324a6`, as on macOS.

## Order

1. ~~This probe again inside an Ion window, on Ion's content root (`windowRoot`, `windowDevice`).~~ Done in
   "Built: Ion window and Pressable".
2. The bridge, smallest runnable first: ~~View~~, ~~Text with `niMeasureText` on DirectWrite~~, ~~Pressable input~~,
   ~~ScrollView~~, then TextInput, then UIA. Each step runs a Neon example in an Ion window and keeps the mock-bridge
   tests (`tests/platform/native*.test.ms`) green.
