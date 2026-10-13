# Windows Host

Status: decided 2026-10-14, nothing built. The Windows Application UI world is a native host behind
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
ports RNW's mechanism. RNW's code is C++/WinRT; the port is plain C++ over COM, built by `msc` with
clang/mingw like Ion's `src/platform/windows/*.cpp`.

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
  `DCompManipulationCompositor` (`directmanipulation.h`, present in the SDK and in mingw). No
  expression animations: `IDCompositionAnimation` curves (`dcompanimation.h`). Shadows and blur are
  `IDCompositionShadowEffect` / `IDCompositionGaussianBlurEffect` (`IDCompositionDevice3`).
  When an app needs what only WinRT composition has, a second `ICompositionContext` on
  `Windows.UI.Composition` is added beside the DComp one, as RNW keeps two; mingw ships
  `windows.ui.composition.h` and `windows.ui.composition.interop.h`.

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

2026-10-14, `msc` v0.3.3 (`~/.metascript/BUILD` `26150233`), clang 23.1.0, Windows 11, 96 dpi. A
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
