# Platforms

What an app author gets on each host. The code says which bridge functions exist; this page says what that means for
a component, and owns the gaps a host accepts without drawing.

Two rules, the person's (2026-10-18/19):

- **Core is primitives and core components.** A component composable from them (Picker, Slider, DateTimePicker, Carousel)
  lives in neon-ui, is written once, and runs wherever the primitives below run.
- **A prop a host cannot honour is accepted and ignored**, so code written for one host does not abort on another. Every
  such gap is listed under the table. An unknown prop name still aborts by name.

| component | iOS | Android | Web | Windows | macOS |
|---|---|---|---|---|---|
| View, Text, Pressable | yes | yes | yes | yes | yes |
| ScrollView | yes | yes | yes | yes | yes |
| TextInput (single, multiline, secure) | yes | yes | yes | yes | yes |
| Image | yes | yes | yes | aborts | yes |
| Switch | yes | yes | yes | aborts | yes, colours ignored |
| ActivityIndicator | yes | yes | yes | aborts | yes |
| Modal | yes | yes | yes | aborts | yes, Escape closes |
| InputAccessoryView | yes, above the keyboard | renders nothing | renders nothing | renders nothing | renders nothing |
| WebView | yes | yes | yes, an iframe | aborts | yes |
| Video | yes | yes | yes | aborts | yes |
| CameraView | yes | yes | yes | aborts | yes; `facing` and `flash` not yet measured |
| Svg | yes | yes | yes | aborts | yes |
| `niMeasureInWindow` geometry export | not yet | not yet | not yet | not yet | yes |

"aborts" means the host stops with `<function> is not implemented on <host> yet`. That is a missing port, not a refusal:
`src/platform/windows/bridge.cpp` and `src/platform/macos/bridge.m` mark each one with `UNIMPLEMENTED`. A component
other than the primitives aborts on Windows with `native host: <tag> has no renderer on this host`, because no Windows
renderer registers with `src/platform/native/elements.ms`. The geometry export is macOS-only until pi-93968's common-host slice lands it
in `src/platform/native/bridge.h` and the other hosts.

Where each cell is proved:
- **iOS and Android:** the device lanes, `tests/ios/counterUITests.swift` and `tests/android/lane.sh`.
- **Web:** `tests/browser/`.
- **macOS:** the `examples/macosNative/*.ms --check` table in `docs/MACOS.md`.
- **Windows:** the same kind of table in `docs/WINDOWS.md`.

Two hosts render a narrower set:
- **The full-window `<Void>` host** (`src/platform/void/host.ms`) draws View, Text, TextInput and ScrollView, and renders
  any other tag as an empty group, without an error.
- **The terminal host** (`src/platform/terminal/host.ms`) maps View, Text, TextInput and Pressable to boxes. It drops layout styles except `display: "none"`, which hides the view and its descendants as in React Native.

## Device APIs on an Ion desktop host

macOS and Windows install each of these when the app imports it (`src/platform/ion/`); any other device API throws `<API> is not available on this host`.

| API | macOS and Windows | reference |
|---|---|---|
| Vibration | accepted, no effect | RN macOS `RCTVibration.mm:25` plays `kSystemSoundID_Vibrate`, which a Mac cannot do; react-native-web `Vibration/index.js` skips the call when `navigator.vibrate` is absent. RN macOS logs an error on `cancel` (`RCTVibration.mm:46`); Neon does not |
| Haptics | accepted, no feedback | the browser host does the same where `navigator.vibrate` is absent; expo-haptics is not on disk, so its unsupported-platform behaviour is not read |
| Notifications | an immediate one (`trigger: null`) posts through Ion's `notify`; a click is a response with the title, body and data posted under that id | a `trigger`, `content.badge`, cancel and dismiss throw naming the call; `subtitle` and `sound` are ignored; on macOS the process needs an app bundle (`~/metascript/.inbox/ion/2026-10-25-notify-aborts-a-process-outside-an-app-bundle.md`) |
| NetInfo | throws | Ion has no network API; react-native-netinfo is not on disk |

## Accepted and ignored

| host | prop | why |
|---|---|---|
| macOS | Switch `thumbColor`, `trackColorOn`, `trackColorOff` | `NSSwitch` draws in the system accent colour and has no tint API; RN macOS's `RCTUISwitch : NSSwitch` cannot either |
| macOS | ActivityIndicator `color` in an inactive window | the tint is a `CIColorPolynomial` filter and shows faintly while the window is inactive |
| Android, Web, macOS, Windows | TextInput `inputAccessoryViewID` | only iOS has a keyboard accessory; RN's `InputAccessoryView.js:95-113` renders null elsewhere (and warns on Android, which Neon does not) |
| macOS | dark mode, font scale | `niColorScheme` answers light and `fontScale` answers 1 (`docs/MACOS.md`, not measured) |

Per-host differences that change behaviour rather than drop a prop are in `WORKAROUND.md`. M2 and M3 cover the pickers,
R4 the browser WebView, R5 video playback, and X5 the camera.
