# Windows Host

Status: decided 2026-10-14; the View slice is built ("Built: View" below), text and everything after it is not. The Windows Application UI world is a native host behind
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
  already composes a transparent WebView2 over a swapchain (`ion/docs/RENDER-SURFACE.md`
  `SurfaceBelow`, `ion/src/platform/windows/core/composition.cpp`).
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
`handoff.h` is the whole surface the owner of the window uses (`niwAttach`, `niwPump`, `niwShutdown`).
`examples/windowsNative/` is the owner for now and plays Ion's part; `--check` samples its own window.
Every `bridge.h` function not implemented aborts with its name, and `niAppCall` answers only the queries
`installNativeAppServices` makes at startup.

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

## Port map: Text, TextInput, UI Automation

Read 2026-10-14 in RNW at `1f59db1`, paths under `vnext/Microsoft.ReactNative/Fabric/`; nothing below
is built or run yet. `WTI` is `Composition/TextInput/WindowsTextInputComponentView.cpp`.

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

## What Ion has to give

Ion's Windows window owns the `IDCompositionDevice` and its tree (`composition.cpp` `ionCompInit`);
`ionRenderSurfaceLayer` returns `nullptr` on Windows and no device leaves the module. The host needs,
per window, a content root it can parent visuals to, z-ordered with the webview and render surfaces,
plus the device (or a D2D-capable device) to create surfaces on, and pointer, key, IME, focus and
DPI events for that region. macOS (an `NSView` container in the content view) and Linux (a GTK3
widget, since Ion links `gtk+-3.0` and `webkit2gtk-4.1`, `ion/src/ipc.ms`) need the same contract.
Brief: `~/metascript/.wt/ion-native-content-root-prompt.md`.

## Order

1. Ion's content root on Windows, then this probe again inside an Ion window.
2. The bridge, smallest runnable first: View (frame, background, corner radius, opacity), Text with
   `niMeasureText` on DirectWrite, Pressable input, then ScrollView, then TextInput, then UIA. Each
   step runs a Neon example in an Ion window and keeps the mock-bridge tests
   (`tests/platform/native*.test.ms`) green.
