# macOS Host

Status: built 2026-10-18 to the level `WINDOWS.md` reached on Windows: a full-window `<Void>` in an Ion window, and the
native host behind `src/platform/native/bridge.h` with View, Text (styled runs, recolour without a relayout, press on a
run), Pressable, ScrollView and TextInput, frames on demand and app services through Ion. Past the Windows level:
Switch, ActivityIndicator, Image (with `Image.getSize`, `Image.prefetch` and `defaultSource`), Modal, WebView, Video,
CameraView and Svg (2026-10-19). Each of those but Image has its own `src/platform/macos/<name>.m`, compiled with its
frameworks only by the component's `src/platform/native/<name>.ms`, which registers its creator on import; an app
that imports none of them carries none of their classes (`tests/apps/run.sh` `bundleMacosApp`). WebView, Video and
Camera are ported from iOS's `webView.m`, `video.m` and `camera.m`, Svg from iOS's `svg.m`. Accessibility exposed to
VoiceOver aborts by name (`UNIMPLEMENTED` in `src/platform/macos/bridge.m`). Slider, Picker and DateTimePicker stay out
of the host's core: a component composable from the primitives is written once in Neon. WebView, Video and Camera are
core (the person, 2026-10-18), and Svg (2026-10-19).
`Camera.requestCameraPermissionsAsync` asks through Ion's `requestCameraAccess` (ion `b2e5c7e`) and shows the system prompt once.

## Decision

| layer | macOS choice | react-native-macos reference |
|---|---|---|
| component views | layer-backed, flipped `NSView`s; the centred transform rebuilt in `updateLayer` | `React/Views/RCTView.m` (`updateLayer`, transform), `React/Views/UIView+React.m` (layers anchored at (0,0)) |
| text | one `NSTextStorage` / `NSLayoutManager` / `NSTextContainer` per label, colour as a temporary attribute | `ReactCommon/react/renderer/textlayoutmanager/platform/ios/.../RCTTextLayoutManager.mm`, `React/Fabric/Mounting/ComponentViews/Text/RCTParagraphComponentView.mm` |
| single-line input | `NSTextField` over the window's field editor, its editing callbacks overridden on the field | `Libraries/Text/TextInput/Singleline/RCTUITextField.mm` |
| secure input | an `NSSecureTextField` subclass with the same overrides | `Libraries/Text/TextInput/Singleline/macOS/RCTUISecureTextField.mm` |
| multiline input | `NSTextView` in an `NSScrollView`, placeholder drawn in `drawRect:` | `Libraries/Text/TextInput/Multiline/RCTUITextView.mm` |
| Switch | `NSSwitch` centred at its fitting size; `thumbColor` and the track colours are accepted and not drawn, since `NSSwitch` has no tint API | `ReactApple/Libraries/RCTUIKit/RCTUISwitch.m` |
| ActivityIndicator | a spinning `NSProgressIndicator`, `color` as a `CIColorPolynomial` filter on its layer | `ReactApple/Libraries/RCTUIKit/RCTUIActivityIndicatorView.m` |
| Image | the decoded image as a layer's contents at one point per pixel, `resizeMode` as `contentsGravity`, `repeat` as a pattern colour, `blurRadius` in image pixels as on iOS; one `NSCache` shared with `Image.getSize` | `ReactApple/Libraries/RCTUIKit/RCTUIImageView.m` |
| Modal | a view filling the root above the app, where `src/components/modal.ms` portals it, as the iOS host does; `fade` and `slide` animate its arrival; Escape asks the app to close the topmost one (`onRequestClose`), the macOS stand-in for iOS's escape gesture | none: RN macOS compiles its Modal out (`React/Views/RCTModalHostView.m` is `#if !TARGET_OS_OSX`) |
| WebView | a `WKWebView` with react-native-webview's `ReactNativeWebView` script bridge, the iOS `webView.m` port; `onShouldStartLoadWithRequest` answered synchronously in the navigation policy; the web view takes an inactive window's first click | `react-native-webview` `apple/RNCWebViewImpl.m`, one implementation for iOS and macOS (its README: "compatible with iOS, Android, Windows and macOS") |
| Video | an `AVPlayer` drawn by an `AVPlayerLayer`, with an inline-controls `AVPlayerView` over it only while `controls` is set, the iOS shape; a `data:` source is written to a temporary file first | none read: RN macOS ships no video view; Neon's iOS `video.m` |
| CameraView | an `AVCaptureSession` with its preview layer and an `AVCapturePhotoOutput`; it reads the authorization and never prompts, reporting `onMountError` "Camera permission not granted" as expo-camera does; a facing with no camera falls back to the default one | none read: RN macOS ships no camera view; Neon's iOS `camera.m` |
| Svg | the display list of `src/components/svg/scene.ms` drawn by Core Graphics in a flipped `NSView` inside the `NeonView`, the iOS `svg.m` port with `NSFont` text | none read: RN core has no Svg; react-native-svg's macOS target was not read |
| `overflow` | `hidden` clips a view's children and masks its layer, on every view | `React/Views/RCTView.m` (`clipsToBounds`) |
| scrolling | `NSScrollView` over a flipped document view, overlay scrollers, `NSViewBoundsDidChangeNotification` for onScroll | `React/Fabric/Mounting/ComponentViews/ScrollView/RCTScrollViewComponentView.mm` |
| geometry (`niMeasureInWindow`) | the bounds in the window content, top-left origin, in points, through the model the hit test inverts (frame, centred transform, scroll offset), since `convertRect:toView:` misses the transforms set on layers; four corners to an axis-aligned box, unclipped | iOS host: `[v convertRect:v.bounds toView:v.window]` |
| pointer | the root takes AppKit's mouse events over Neon's views and runs Neon's own hit test, ported from the Windows host (`src/platform/windows/bridge.cpp`) | `React/Base/RCTTouchHandler.m` |

Reference: `~/projects/react-native-macos`, shallow clone at `8941740` (2026-10-14). iOS's `src/platform/ios/bridge.m` is
the closest Neon code: the same RN component views on UIKit.

**Input goes through AppKit, not through Ion's records.** On Windows the host reads Ion's pointer, key, text and IME
records and feeds a windowless RichEdit. On macOS AppKit is the compositor and the event router: `NSTextField` and
`NSTextView` bring the IME, the key bindings and accessibility that Windows had to port. So the host adds its root view
(`NeonRoot`) above Ion's content host. That root answers AppKit's `hitTest:` only where a Neon view lies, so clicks
elsewhere still reach Ion's host and a webview under it; ion-66 measured that a view over a webview must consume
`mouseDown`. A click on a TextInput goes to the field, or to its field editor once editing (`nativeTarget`). Blurring
gives the first responder back to whatever held it at `nimAttach`, which is Ion's content host, so Ion's key records
resume.

**The full-window `<Void>`** (`src/platform/ion/voidVisual.m`) is the other way round. A view holding Void's
`CAMetalLayer` takes no events (`hitTest:` nil, never first responder), because Ion's contract on macOS reads pointer
records from a process-wide event monitor and keys, text and IME from its first-responder host
(`ion/src/platform/bridge.h`).

## Traps, each paid for once

- **`@compile` builds Objective-C without ARC unless told.** Pass `"-fobjc-arc"`, as iOS does
  (`src/platform/native/host.ms`). Without it, code written for ARC compiled with one warning, and stored autoreleased
  objects (`[NSMutableDictionary dictionary]`, `rgba(...)`) in ivars without a retain. Only a `__weak` declaration
  turned it into an error. Every macOS `.m` here, including the example harness, now passes the flag.
- **Text measures to whole points.** Yoga lays out on points. A device-pixel ceil at scale 2 handed yoga a width a
  fraction under the drawn line, and "Hello macOS" wrapped. `niMeasureText` ceils to points, as iOS does. The Windows host
  ceils to device pixels (`src/platform/windows/dwriteText.cpp`), which is the same trap above 96 dpi; unmeasured there.
- **AppKit resets `layer.transform` during its display cycle.** Its layers anchor at (0,0), so `NeonView` rebuilds the
  centred transform and re-applies it in `updateLayer` (RN macOS `RCTView.m` does the same).
- **A secure field editor's delegate must be an `NSSecureTextField`.** A plain `NSTextField` with an
  `NSSecureTextFieldCell` throws `NSInternalInconsistencyException` ("NSSecureTextFieldCell is not secure because the
  secure field editor's delegate must be an NSSecureTextField") on its first focus. Hence two field classes sharing
  `NEON_FIELD_METHODS`.
- **`NSTextField` takes an inactive window's first click and `NSTextView` does not.** `NeonTextView` answers
  `acceptsFirstMouse:` with YES, so every TextInput focuses on that click, as `NeonRoot` presses a Pressable on it.
- **An `NSEvent` made from a `CGEvent` has no window.** The harness wheel sets the `CGEvent` location to the window
  point and calls `-[NSWindow sendEvent:]`. `postEvent`, the window-under-pointer fields and `CGEventPostToPid` did not
  reach the root.
- **Events posted from outside the process are dropped** while the shell lacks Accessibility permission
  (`AXIsProcessTrusted()` false). Every check therefore drives its window from inside, through the harness
  (`examples/macosNative/harness.m`). The harness posts with `[NSApp postEvent:]`, which is asynchronous: a step that
  clicks and then composes in the same tick composes into the old focus.
- **Activating the app from a check steals the user's keyboard.** One run typed the user's own keys into the secure
  field. The checks never activate their window.
- **`renderInContext` cannot see a `WKWebView`'s page.** The harness samples it through
  `-[WKWebView takeSnapshotWithConfiguration:]`, which is colour-managed: CSS `#27ae60` came back as `#29b973`, so the
  WebView check compares each channel within 24.
- **A `WKWebView` drops an inactive window's first click**, like `NSTextView`. A subclass answers `acceptsFirstMouse:`
  with YES.
- **A paused exact seek can hold its completion until playback resumes.** With the player layer on screen in a window,
  `seekToTime:toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero` on a paused `AVPlayer` finished in 4 ms on most
  runs and only on resume on the others, while `currentTime` already read the target. A plain AppKit program shows it
  too: 1 of 8 with an `AVPlayerLayer`, 1 of 3 with an `AVPlayerView` without controls, 0 of 16 with no view. So the
  `onProgress` after a seek on a paused Video can arrive late; the check seeks during playback.
- **Pressable holds its pressOut for `MIN_PRESS_DURATION_MS` (130 ms)**, so press steps wait 300 ms.

## Measured

2026-10-18, `msc` 9029133ef (`~/.metascript/BUILD`), Ion `d0ae755`, Void `215c3e2`, a Retina display at scale 2,
neon tree `9a65d36`. Each line is `msc build examples/macosNative/<name>.ms --output=out/<out>` then
`out/<out> --check`, run from the checkout. The checks sample pixels from `renderInContext` of the content view's
layers (not the window server), so one `screencapture -l <window>` per example was compared by eye.

| example | result |
|---|---|
| `ion` | 16/16 pixel checks, including after a resize to 800x400 |
| `ionText` | 17 checks: pixels, sizes within one point of an `NSLayoutManager` measure, 0 layouts built by a recolour, 31 presses along the run with the first at x=112 |
| `ionPress` | 13/13 steps: hit-testing in child order, transforms, press, cancel and gesture phases |
| `ionScroll` | 10 checks: clip, a wheel to y=240, a press on band 3, `scrollTo` clamped to 800, a wheel outside moving nothing |
| `ionVoid` | 3 clicks on +1, "hi" and Return through Ion's records; the drawn frame shows "Count: 3" and "Hello, hi" |
| `ionControls` | 27 checks: `cover`, `contain`, `repeat` and `blurRadius` sampled, onLoad at the pixel size, onError for a missing file with and without a `defaultSource` (which stays drawn), `Image.getSize`, a controlled Switch flipped by a click, a fixed one returning to its value, a disabled one ignoring the click, a spinner drawn and hidden once stopped; 3 runs of 3 green (`msc` 212a678c2, Ion `0e31151`, neon tree `393f007` plus this change, which re-ran the five checks above unchanged) |
| `ionModal` | 13 checks: a press opens an opaque Modal over the app, onShow, the Modal takes a click over the app's Pressable, Escape calls onRequestClose and onDismiss follows, the app takes clicks again, a `slide` Modal settles in place, a press inside closes it, Escape with no Modal does nothing; 3 runs of 3 green, same tree as `ionControls` |
| `ionWebView` | 11 checks: an HTML source with a base url loads once, the page's own message, `postMessage` echoed back, `injectJavaScript`, the page's background and element sampled through WebKit's snapshot, a refused navigation asked and never loaded, an AppKit click on the page's element reaching its listener; 3 runs of 3 green (`msc` e16a76c25, Ion `e572da0`, neon tree `f85af81` plus this change, which re-ran `ion`, `ionText`, `ionPress`, `ionScroll`, `ionInput`, `ionControls` and `ionModal` 3 times each at their counts) |
| `ionVideo` | 7 checks: load start, onLoad with "3s 160x90", progress while playing, onError for a missing file, no progress while paused, a seek during playback landing at the end within 0.7 s, one onEnd; 3 runs of 3 green |
| `ionCamera` | 3 checks on the branch this machine takes, the shell without camera authorization: one answer, onMountError "Camera permission not granted" with no prompt shown, and the status `Camera.getCameraPermissionsAsync` reads from Ion (`undetermined`) agrees with that branch; 3 runs of 3 green (2026-10-19, ion `b2e5c7e`) |
| `ionCamera`, authorized | 3 checks after the person allowed the camera once by hand (2026-10-19): onCameraReady once, Ion reads `granted`, `takePictureAsync` writes a sized `file://` picture; 3 runs of 3 green |
| `ionMeasure` | 9 checks: the mounted root (0,0,480,320), plain, inside a `scale(0.5)` parent, `rotate(90deg)`, inside a ScrollView before and after `scrollTo`, hidden (0), never attached (-1); 3 runs of 3 green (`msc` e16a76c25, from main `f85af81`) |
| `ionInput` | 26 checks, the Windows set: placeholder, typing, backspace, submit and blur, controlled uppercase, maxLength, newline and growth in multiline, an IME composition through the field editor's `NSTextInputClient` reporting no change until its commit, secure bullets; 3 runs of 3 green |
| `ionSvg` | 13 checks: the Svg laid out at 200x100, a `viewBox` scaling a rect, a circle's centre and edge, a linear gradient red at its start and blue at its end, a stroke at its width, text drawn above its baseline and upright, the circle grown by a signal; 3 runs of 3 green (2026-10-19, `msc` c235d7de9, Ion `b2e5c7e`, branch `wt/pay-for-use`) |
| renderer split | after each component moved into its own `.m` (2026-10-19, same toolchain), `ionControls` 27, `ionModal` 13, `ionWebView` 11, `ionVideo` 7, `ionCamera` 3, `ionNeonUi` 4, `ionMeasure` 9 and `ionSvg` 13 checks, 3 runs of 3 green each, the counts main gave |

Hot reload (`examples/macosNative/hcr`, `cd` there and `msc run --hcr app.ms`). The cold build took 28-40 s. A template
edit reloaded `[counter]` in 2.1-2.9 s and kept the count: 3, then 4 after one click. A handler edit applied (4 to
14). A type error failed the build in 326 ms with the window alive, and the next edit reloaded (14 to 114).

Not measured:

- VoiceOver: the accessibility props are stored, not exposed. `nativeID` is stored beside them (react-native-macos `RCTViewManager.m:417` only tags the view).
- Scroll gesture phases: begin and end drag, and momentum. RN macOS does not map them either.
- Dark mode (`niColorScheme` answers 0), font scale, right-to-left, Tab focus order.
- A multiline input capped by `maxHeight` and scrolling.
- A resize while editing.
- Text drawn at scale 1.

- CameraView with the camera authorized: what the preview shows on screen, `facing` and `flash`.
  No `--check` run reaches it without a permission prompt.
- Video pixels, `controls`, `resizeMode`, `rate`, `volume` and `repeat`; WebView `goBack` / `goForward` / `reload` and
  a `uri` source.
- A Modal's `fade` and `slide` mid-way: the checks sample after the animation ends.
- The ActivityIndicator `color`: `renderInContext` skips layer filters, so the checks see the spinner, not its tint. By eye
  it is a faint red in an inactive window.

Seen in passing: a single-line field's text sits about 2 points right of a multiline input's at the same padding,
which is `NSTextFieldCell`'s own inset.

Ctrl-C ends `msc run --hcr`: SIGINT to its process group, started with SIGINT at its default, ended msc in 19 ms and
took the HCR host with it. A first try said the opposite, and it measured the shell. A job started with `&` from a
non-interactive shell ignores SIGINT, and so does every process it starts, `script` and its pty included. A script
that stands in for Ctrl-C starts its child with `signal.SIG_DFL`, as `/tmp/hcr_sigint.py` did here.
