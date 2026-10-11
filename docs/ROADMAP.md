# Neon — Roadmap

What we build next, in order, and why that order. **Forward-looking only.**

| doc | owns |
|---|---|
| `docs/VISION.md` | the goal the order serves: one interface over every kind of rendering |
| this file | the order of work across the whole framework |
| `docs/STYLE.md` §9 | the style/theme stages (S1-S4) in detail |
| `docs/RENDER-MODEL.md` | the emission tiers, how a site picks one, and the lifecycle |
| `docs/PORT-STATUS.md` | the Nim → MetaScript module map, and history |
| `BUGS.md` | open FRAMEWORK bugs of Neon, and the sites parked on a compiler card — 157 lines, read it whole. A compiler bug is a card in `~/metascript/.inbox/compiler/`, never a row here |

**Rule for this file** (same as `BUGS.md` and `STYLE.md`): a row moves to *done* only with the
command that proved it. Never layer a correction on a stale row — rewrite the row.

---

## Now

**React surface on the Solid core** (user decision 2026-09-10; execution plan in
`~/.claude/plans/wiggly-wondering-treehouse.md`) — Neon keeps Solid's fine-grained reactivity and React
Native's component/event vocabulary, and uses the compiler to drop the three rules Solid has to teach only
because it is a library. Reactivity is decided by TYPE, never by syntax or by where a read sits. `setCount(v)`
stays; no React hook aliases.

| # | phase | owner | state |
|---|---|---|---|
| 0 | redeploy main; docs; loud-reject fragments; uniform spread walk | neon | done 2026-09-10 (`tests/macros/run.sh` rc=0) |
| 1 | `distinct` nominal, callable over a fn base, one-way widen | compiler | done, re-measured 2026-09-19 on msc v0.2.55 (`probe/rm1_distinct.ms`, `rm1b_nominal.ms`): an `Accessor<string>` reads as `() => string`, the reverse is rejected. The names `typeName` / `BrandWiden` are not in Neon's source — the row described an early shape |
| 2 | `Accessor<T> = distinct (() => T)`; `createSignal`/`createMemo` return it; `accessor()` | neon core | done, re-measured 2026-09-19 (`src/core/signal.ms:46`, `probe/rm1_distinct.ms`): the alias, `accessor()` and `valueOf` are all live |
| 3 | checker reads a value through the `valueOf` protocol where a bare read would fail (replaced the source-typed auto-call 2026-09-14) | compiler | done, re-measured 2026-09-19 (`probe/rm3_valueof.ms`): `const [x] = createSignal(2); x * 2` prints `4` with no call |
| 4 | props contract: every value prop is `Accessor<T>`; the macro wraps every value, literals too | neon macros | done, re-measured 2026-09-19 (`probe/rm4_props.ms`): `label="hi"` enters an `Accessor<string>` prop and `count={n()}` stays reactive (`hi:1` → `hi:2`). `propValueNode` no longer exists — one NeonNode replaced it |
| 5 | `{a && <X/>}` / ternary / `.map` lower to `Show`/`For` | neon macros | done for the three forms, re-measured 2026-09-20: `&&` (`probe/rm5a_and.ms`), `?:` (`rm5b_ternary.ms`) and `{xs.map((v: number): NeonNode => element(<s/>))}` (`rm5h_mapOneParam.ms`) each mount and update. `.map` lowers a row without an index only; a row with an index, `number` or `Accessor<number>`, is refused with a message that names `<For>` (`tests/macros/mapIndexRowRejected.ms`), and `.map(namedFn)` whose callback does not fit `map` is a permanent rejection (`mapNamedRowRejected.ms`), not a parked gap. `||` stays PARKED (BUGS §3). `lowerJsxChild` no longer exists. The macro emits bare `Show` / `For` calls; `src/converters.ms` re-exports them, so the prelude carries them into every file (`tests/render/preludeFlow.test.ms`). `<Index>` as a TAG is rejected at `createComponent`, reduced 2026-09-20 to a generic callee that cannot bind its own type parameter through a `distinct` alias — card `~/metascript/.inbox/compiler/2026-09-20-generic-callee-type-param-through-distinct-alias.md` |
| 6 | error on an implicit accessor read at function-body time (`const d = count * 2`) | compiler | dropped 2026-09-14: with `valueOf` an alias keeps the accessor, and a body-time operand read is an ordinary one-time value |
| 7 | real fragments: flatten in child position; multi-root at top level | neon | done 2026-09-15, root fragment and fragment rows 2026-09-19 with one NeonNode (`msc test tests/render/fragment.test.ms` rc=0 on C and `--target=js`; `tests/macros/run.sh` rc=0) — a fragment child is flattened at compile time, a root fragment places every root in front of `before`, a row may be a fragment, and inside an expression a fragment lowers exactly as an element does (`&&` / `?:` arm → `Show`, prop value or argument → converter) |

Emission is finished and needs nothing further: the tier is picked per JSX site at compile time, on
every target, and no build flag or user-visible knob exists (`RENDER-MODEL.md` §Selection).

Phase 7 dropped `regionNode` from its own description: reading `insertExpression` in
`dom-expressions/src/client.js` showed Solid reserves the effect + `reconcileArrays` path for arrays
holding a FUNCTION, and appends a static array directly. A region for a static fragment applies the
dynamic branch to a static value. Detail and the refutation are in this file's history:
`git show c00bd2b:BUGS.md`, §7.

---

## Package boundary — decided 2026-10-08, relocation pending

The person: Neon provides primitives at React Native's level; what an author can build from them
is not Neon's to carry ("mình cung cấp primitive cỡ như React Native thôi, còn mấy cái người dùng
tự build được thì mình không muốn ôm luôn"). Everything below stays in this repo for now; the
tiers say what is core and what moves.

1. **Core** — RN core's surface, or anything that needs the host and cannot be written by an
   author: `View`, `Text`, `Image`, `ImageBackground`, `TextInput`, `Pressable`, the Touchables,
   `ScrollView`, `FlatList` / `SectionList` / `VirtualizedList`, `RefreshControl`, `Switch`,
   `ActivityIndicator`, `Button` (kept: RN core ships it), `Modal`, `StatusBar`, `SafeAreaView`,
   `KeyboardAvoidingView`; `Animated`, `Easing`, `LayoutAnimation`, `PanResponder` and the
   responder system, `StyleSheet`; the RN APIs in `src/api/` that RN core ships (Alert, Linking,
   Share, AppState, BackHandler, Keyboard, Dimensions, PixelRatio, Platform, Appearance,
   AccessibilityInfo, Vibration).
2. **Native modules, opt-in** — need native code but are not RN core (RN community / Expo
   packages): `Slider`, `Picker`, `DateTimePicker`, `WebView`, `Video`, SVG, `CameraView`,
   `ImagePicker`, `Audio`, `Clipboard`, AsyncStorage, NetInfo, Permissions, Geolocation,
   Haptics, DeviceInfo, Localization, Notifications. Target: one module each, built only by apps
   that import it. When to split is open.
3. **Composed from primitives — relocate to a UI library (`neon-ui`)**: Chip, Card, Avatar, Badge,
   Divider, Snackbar, Toast, Tooltip, Dialog, BottomSheet, Stepper, SegmentedControl, the
   Neon-drawn Checkbox/Radio; PageView, TabView, Carousel, Collapsible/Accordion, DataTable, Wrap;
   Dismissible, ReorderableFlatList, GridList, MasonryList, CollapsingHeader, CustomScrollView,
   ListWheelScrollView; navigation (`src/navigation/`). Kept with their tests as a consumer of the
   core: they found core bugs (responder, touches inside scroll views, text measurement,
   `textAlign`). Open: a sibling repo `~/metascript/neon-ui` (clear boundary, own gate) or a
   package inside this repo (shared gate, core regressions surface at once).

## Next — app deliverability before full parity

Approved 2026-10-05: "chốt hướng, đi rồi mình sẽ bắt tay vào làm trong session mới".
The goal is an app author completing an ordinary app, not cloning the RN or Flutter catalog.
“20/80” is a prioritization hypothesis based on screen reach, not measured API coverage,
implementation size, or a promise that 80% of apps already work.

Keep the RN component surface and Solid's fine-grained model. Borrow Flutter's app contracts
where they expose missing behavior; do not import its widget-rebuild model. The order below
supersedes the earlier style-first and full-list-parity-first order.

| order | capability bundle | what it unlocks | owner / boundary |
|---|---|---|---|
| 1 | ordinary SDK consumption: normal browser bundles, named renderers, contextual props, signal types, typed text/attribute slots and public exports | app code written normally, without compiler-avoidance rewrites | compiler fixes only from recompiler; Neon validates real consumers and its public entrypoint |
| 2 | native forms and app environment: TextInput, focus/IME/selection, text measurement/truncation, dimensions/insets/keyboard, lifecycle after mount | search, login, settings and property inspection | Neon components/hosts; runtime scheduling reuses std before any new Host timing API |
| 3 | everyday UI: Image, Button, Switch, loading indicator, Modal/Portal; accessibility and keyboard/focus behavior included | content screens, forms, dialogs and menus | Neon; reuse Ion resource/packaging/runtime facilities rather than duplicating them |
| 4 | real-data path: store/reconcile, resource loading/error/cancellation/lifetime; variable-height FlatList, timed batching, Header/Footer/Empty/Separator and scroll-to-index failure handling | refetched data keeps row identity; a feed does not require fixed-height rows | Solid concepts localized to MetaScript; shared list engine, not a second list convention |
| 5 | developer loop and common feedback: build/run/deploy diagnostics with source locations, Neon refresh integration, opacity/transform/press feedback and common transitions | short iteration and understandable failures; responsive-feeling UI | compiler HCR and Ion foundations, Neon integration; no whole-engine animation port by default |

A compiler-blocked item is reduced, recorded and parked; it is never “completed” by making
the app author rewrite valid code. Continue reachable work in the next bundle while the
owning compiler session fixes it. Shared-contract changes and genuinely new mechanisms
retain their approval gates; this order does not grant land/push permissions.

On 2026-10-06 the user expanded the list part of bundle 4 to grid and inverted chat lists,
SectionList, sticky headers, viewability, public VirtualizedList and the deeper RN list
reference catalog. These are current scope, not a prerequisite to port the full RN/Flutter
ecosystem. Component and element slots both use declared-type JSX lowering; invalid initial
indices must clamp with a warning on every backend, not a native-only silent fallback.

Preserve Solid item identity when extending grid layout. RN's multi-column row key joins
every item key (`FlatList.js`, `_keyExtractor`, lines 554–569 in the reference checkout),
so regrouping changes row identity. Copying that key model would not establish Solid state
preservation across row parents; cross-parent ownership/reconciliation needs its own
mechanism approval. The reference list cases are in
`packages/virtualized-lists/Lists/__tests__/VirtualizedList-test.js`.
Until that approval, grid is provisional (`WORKAROUND.md` L1): an item keeps its state while
it stays in its row and remounts when regrouping moves it to another row; the grid cases in
`tests/render/flatList.test.ms` and `tests/browser/flatList.test.ms` pin it.
Public `VirtualizedList` (`getItem`/`getItemCount`), viewability (`onViewableItemsChanged`,
`viewabilityConfig`, `viewabilityConfigCallbackPairs`, `recordInteraction`) and
`SectionList`/`VirtualizedSectionList` run on the same engine; their provisional parts are
`WORKAROUND.md` L3–L7. Cases: `tests/render/{virtualizedList,sectionList}.test.ms`,
`tests/components/list/viewability.test.ms`, `tests/browser/sectionList.test.ms`; the invalid
`initialScrollIndex` warning is pinned on native and JS by `tests/apps/listWarnApp.ms`.
`scrollToItem`, `ListItemComponent` and `disableVirtualization` follow RN's cases in the same
files (L8–L9). `maintainVisibleContentPosition` (approved 2026-10-07) is a ScrollView attribute through
`Host.setAttr`, kept by each host around its own write batch the way RN's ScrollView keeps it
around a mount: the native host records the first visible child at or after
`minIndexForVisible` before its yoga pass and shifts the offset by that child's move after it
(`niScrollShift`, `niScrollOffsetX/Y` in `bridge.h`; Android waits for its layout pass and
restarts a running fling, iOS writes `contentOffset`), the DOM host records before the first
host write of a task and shifts in a microtask with CSS `overflow-anchor: none`. The list ports
RN's `getDerivedStateFromProps` window shift and counts the header slot. Cases:
`tests/render/{scrollView,flatList}.test.ms` (RN's two `VirtualizedList-test.js` cases),
`tests/platform/nativeHost.test.ms`, `tests/browser/{scrollView,flatList}.test.ms`; the consumer is
the `chat` mode of `examples/components/bigList.ms`, passing on the iOS simulator
(`docs/IOS.md` §9.1); the Seeker lane is written but not yet run (`docs/ANDROID.md` §11.1).

Flutter's list capabilities that RN lacks, and the gesture layer under them (`wt/rn-flutter-lists`,
2026-10-07, provisional as `WORKAROUND.md` F1–F11): RN's responder system and `PanResponder`
(`src/render/responder.ms`, `src/components/panResponder.ms`) over touch events every host now
delivers with window coordinates and moves, and the optional `Host.setResponder` that keeps native
scrolling from taking a claimed touch; `Dismissible`, `ReorderableFlatList` (drag from `drag()`,
`onReorder(from, to)` with `to` after removal, rows keep their identity), `GridList` (`maxItemWidth`,
Flutter's max-extent delegate) and `MasonryList`, `CollapsingHeader` and `CustomScrollView`
slivers, and `ListWheelScrollView`. Several lists and grids in one scroll are one
`VirtualizedList` over the slivers' rows laid end to end, which is what Flutter's viewport does with
one shared scroll offset; pinned headers are its sticky rows. Cases:
`tests/components/{panResponder,dismissible,reorderableList,gridList,sliver,listWheel,flutterListsApp}.test.ms`
(native and JS), `tests/platform/nativeHost.test.ms` (a pan row inside a ScrollView takes a drag
from the Pressable in it and blocks native scrolling), `tests/browser/gesture.test.ms`. The consumer
is `examples/components/flutterLists.ms`: real mouse drags in Chrome pass
(`node tests/browser/flutterlists.mjs <playwright>`: swipe to archive and delete, tap through a
swipeable row, long-press reorder, max-extent grid and masonry, collapsing header, pinned slivers,
wheel snap), and the iOS simulator passes `FlutterListsUITests` with the same steps
(`/private/tmp/neon-sim-run.sh … FlutterListsUITests`, results `/private/tmp/neon-sim.f2A6ZK`).
The Seeker lane `tests/android/flutterlists.py` is written and its APK built; its one run stopped
at the locked screen (exit 2, `/private/tmp/neon-seeker.gbYoCQ`), so Android is not yet measured.

Flutter widgets and their RN community equivalents (`wt/rn-flutter-widgets`, msc `0d83c4867`,
2026-10-08, provisional as `WORKAROUND.md` W1–W9): `PageView` with `PageController` (Flutter page
physics over a PanResponder, `setPage`/`setPageWithoutAnimation`, loop, `viewportFraction`, vertical)
and `PageIndicator`; `Carousel` (react-native-reanimated-carousel: auto-play held by a finger, loop,
parallax); `TabView`/`TabBar` (react-native-tab-view: swipe, indicator between measured tabs, lazy
scenes, scrollable bar); `Collapsible`, `ExpansionTile` and `Accordion`; `DataTable` (sortable
columns, row and select-all selection, intrinsic column widths, horizontal scroll); `Wrap`.
`RefreshIndicator`, `SnackBar` and `BottomSheet` are the existing RefreshControl, Snackbar and
BottomSheet; a Hero shared-element transition is not done. Cases:
`tests/components/{pageView,carousel,tabView,collapsible,dataTable,wrap,widgetsApp}.test.ms` (native
and JS) and `tests/platform/nativeWidgets.test.ms` (a Collapsible opens under native Yoga). The
consumer `examples/components/widgets.ms` passes real mouse drags in Chrome
(`node tests/browser/widgets.mjs <playwright>`: page swipe and spring-back, dots, tab swipe and
indicator, scene scroll inside the pager, auto-play, pause and drag, accordion, sort and select,
wrapped chips) and the iPhone 17 Pro simulator (`WidgetsUITests`, the same steps,
`/private/tmp/neon-sim.V0gFm7`), after two native fixes found there: a swipe over a scene's vertical
ScrollView now reaches the pager (W9) and a first opening of a Collapsible is measured (W8). The
web bundles of every example load again (W6). The Seeker lane `tests/android/widgets.py` is written
and not run (the phone is locked overnight); Android is not measured, and W9 names the swipe over a
native ScrollView as its likely gap. Not verified: a screen reader on any of these widgets.

Media (`wt/rn-media`, msc `0d83c4867`, 2026-10-08, provisional as `WORKAROUND.md` R1–R5):
`WebView` (react-native-webview: `source` uri or html + `baseUrl`, `onLoadStart/onLoad/onLoadEnd/
onError`, `onNavigationStateChange`, `onMessage` with `window.ReactNativeWebView.postMessage`,
`injectedJavaScript`, `javaScriptEnabled`, `originWhitelist`, a synchronous
`onShouldStartLoadWithRequest`, ref `goBack/goForward/reload/stopLoading/injectJavaScript/
postMessage`) on WKWebView, `android.webkit.WebView` and an `<iframe>`; `Video` (react-native-video:
`source`, `paused`, `muted`, `volume`, `rate`, `repeat`, `resizeMode`, `controls`,
`progressUpdateInterval`, `onLoadStart/onLoad/onProgress/onEnd/onError`, ref `seek/pause/resume`) on
AVPlayer, MediaPlayer and `<video>`; no `Audio`/`Sound` player yet. Cases:
`tests/components/{webView,video}.test.ms` (native and JS), `tests/platform/nativeMedia.test.ms`
(mock bridge), `tests/browser/media.test.ms` (Chrome: html page ↔ app messages both ways, a refused
and an allowed link, back and forward; the bundled 3 s clip loads 160x90, progresses, seeks and
ends). The consumer `examples/media` passes in Chrome (`node tests/browser/media.mjs <playwright>`)
and on the iPhone 17 Pro simulator (`MediaUITests`: a tap inside the page reaches the app, the app's
message reaches the page, injection, https example.com → example.org → back → forward, the clip
plays and ends; `/private/tmp/neon-sim.DHnfJA`). The Android APK builds; `tests/android/media.py`
is written and not run (the Seeker is locked), so Android is not measured.


### Acceptance — three complete author workflows

1. Data list → search → detail → edit/save form, with images, variable-height rows,
   loading/error/empty states and normal source syntax.
2. Settings with input, toggle, adaptive layout/theme, keyboard focus and screen-reader use.
3. A Lightcube slice: select a node → edit a property → observe the canvas update without
   losing state/focus. Pan/zoom, drag/resize, selection, clipboard and undo/redo remain
   product priorities when required by that slice, even if not common mobile-core controls.

State 2026-10-07 (`wt/rn-apps`, msc `8506eaf03`): workflows 1 and 2 run as
`examples/catalog` and `examples/settings`. Proven on the mock host and JS
(`msc test [--target=js] tests/apps/workflows.test.ms`), in Chrome
(`tests/browser/run.sh tests/browser/workflows.test.ms`), on the Seeker
(`tests/android/catalog.py`, `tests/android/settings.py`, exit 0) and on an iPhone 17 Pro
simulator (`CatalogUITests`, `SettingsUITests` in `tests/ios/counterUITests.swift`, run with the
software keyboard), then on the physical iPhone 13 Pro at `18f4baa` (both classes passed in one
7/7 run with the list and scroll classes). Not proven: a screen reader driving the app (the
accessibility tree was read through `uiautomator` and XCUITest; TalkBack's first-run tutorial
covered the app); a system appearance change from XCUITest (`XCUIDevice.appearance` did not reach
the app, `xcrun simctl ui <device> appearance dark` did). Provisional choices are rows A1–A11 of
`WORKAROUND.md`.

App APIs, bundles 2/3 (`wt/rn-apis`, msc `0d83c4867`, 2026-10-07): `src/api/` holds RN's
Platform, Dimensions, PixelRatio, Appearance, Keyboard, AppState, BackHandler, Alert, Linking,
Share, Vibration, Clipboard (the community package's surface) and AccessibilityInfo, exported
from `src/index.ms`; listeners return subscriptions and the reactive ones also read as Accessors
(`useAppState`, `useScreenReaderEnabled`). Hosts install them (`WORKAROUND.md` P1–P9). Proven:
`tests/api/apis.test.ms` (16, native and JS), `tests/platform/nativeApis.test.ms` (7, mock
bridge), `tests/browser/apis.test.ms` (9, Chrome), and the `examples/apis` demo on an iPhone 17
Pro simulator, iOS 26.5 (`ApisUITests`: UIAlertController choice, copy/paste, the share sheet's
Copy resolving `sharedAction`, keyboard dismiss, AppState `inactive>background>active` through
Home and through `Linking.openSettings`). The Android build and install of the demo succeeded on
the Seeker; the device lane `tests/android/apis.py` is pending because the phone stayed locked.
Not verified: vibration on any device (the simulator has none), a screen reader, `tel:` on a
real phone (the simulator cannot open it), url events (P7).

Bundle 3 components, 2026-10-07 night (`wt/rn-ui-comps`, msc `0d83c4867`): `Modal` (over Solid's
`Portal`), `SafeAreaView`, `KeyboardAvoidingView`, `StatusBar`, `ImageBackground`,
`TouchableOpacity`/`TouchableHighlight`/`TouchableWithoutFeedback`, `RefreshControl` (ScrollView and
list `refreshControl`), `Text` `numberOfLines`/`ellipsizeMode`/`selectable`, multiline `TextInput`;
`Pressable` accessible by default (A10) and the per-platform `Button` look (A6). Proven on the mock
host and JS (`tests/components/*.test.ms`, `tests/apps/gallery.test.ms`), the native mock bridge
(`tests/platform/nativeHost.test.ms`, gallery included), Chrome (`tests/browser/components.test.ms`)
and the iPhone 17 Pro simulator (`GalleryUITests`, `/private/tmp/neon-sim.6Z5Km4`: modal over the app,
status bar hidden/shown, keyboard lifts the input 634 → 333, pull to refresh, two-line clamp, multiline
typing). The Android build compiles (`examples/gallery` APK); `tests/android/gallery.py` waits for the
Seeker, locked overnight. Provisional choices are rows U1–U10 of `WORKAROUND.md`.

Input and display controls, bundle 3 (`wt/rn-controls`, msc `0d83c4867`, 2026-10-07): RN
community and Material controls in `src/components/`: native `Slider`, `Picker`
(`items` array) and `DateTimePicker` (ISO text values) created through one bridge call
(`niControlCreate`); Neon-drawn `Checkbox`, `RadioButton`/`RadioGroup`, `SegmentedControl`,
`Chip`, `Card`, `Avatar`, `Badge`, `Divider`, `ProgressBar`, `Snackbar`, `Toast`/`ToastHost`,
`Tooltip`, `Dialog`/`DialogAction`, `BottomSheet` and `Stepper`, with an `accessibilityState`
wire attribute mapped by every host (`WORKAROUND.md` M1–M8, K1). Proven: mock host and JS
(`tests/components/{controls,material,overlays}.test.ms`, `tests/apps/booking.test.ms`),
the native mock bridge (`tests/platform/nativeHost.test.ms`), Chrome
(`tests/browser/{controls,booking}.test.ms`), and the `examples/controls` booking form on an
iPhone 17 Pro simulator (`ControlsUITests`: UIDatePicker popover pick, UISlider drag, UIMenu
room pick, tooltip long press, segmented/checkbox/radio/chip presses, bottom sheet, dialog,
progress, snackbar undo and toast; re-run on `wt/rn-web-base`, `/private/tmp/neon-sim.AmL6AX`). Android: the APK builds and installs on the Seeker; the
lane `tests/android/controls.py` is pending because the phone was asleep behind its keyguard.
Not verified: any control on a real Android screen, a screen reader, `Stepper` in an app.

Navigation (`wt/rn-navigation`, msc `0d83c4867`, 2026-10-07): `src/navigation/` holds React
Navigation's surface — `NavigationContainer` (`ref`, `linking`, `theme`, `onReady`,
`onStateChange`), stack (`createStackNavigator`, `createNativeStackNavigator`), bottom and material
top tabs, and drawer navigators, each with `Navigator` / `Group` / `Screen`; the per-screen
navigation object (`navigate`, `push`, `pop`, `popToTop`, `replace`, `reset`, `goBack`,
`canGoBack`, `setParams`, `setOptions`, `getParent`, `getState`, `isFocused`, `dispatch`, drawer
actions, `addListener` for focus/blur/state/beforeRemove/tabPress); `useNavigation`, `useRoute`,
`useIsFocused`, `useFocusEffect`, `useNavigationState`, `useLinkTo`, `useTheme`, `Link`; headers
with back button and left/right slots, tab bars with icons and badges, the drawer panel, transparent
modals, deep links through `Linking` with nested paths. Covered screens stay mounted (state kept),
tabs mount lazily, Android back reaches the focused navigator through `BackHandler`. Exported from
`src/index.ms`. Proven: `tests/navigation/` (6 files, 35 tests, native and JS),
`tests/browser/navigation.test.ms` (Chrome), and the `examples/navigation` demo on an iPhone 17
Pro simulator (`NavigationUITests`: list → detail → edit and save, back with the list's state
kept, per-tab state, a badge, the drawer, a theme switch, rotation). The Android build and install
of the demo succeeded on the Seeker; `tests/android/navigation.py` is pending because the phone was
asleep behind its lock. Rebased onto `wt/rn-web-base` (2026-10-08): stack push/pop slide, modal
slide-up and transparent-modal fade on `Animated`, a drawer slide, an iOS left-edge back swipe and a
drawer edge swipe through `PanResponder` (`tests/navigation/transition.test.ms`, 7 tests on the
manual frame clock; Chrome checks a pushed screen moves and settles; on the simulator
`NavigationUITests` swipes back from the left edge and swipes the drawer open). Provisional choices
are rows V1–V11 of `WORKAROUND.md`. Not verified: gestures on a physical phone, url
events on a device (P7), hardware back on a device, browser history.

Device and storage modules (`wt/rn-device`, msc `0d83c4867`, 2026-10-08): the first hand-ported
RN/Expo native-module domains, on the P1 app channel (new commands and app events 9–12):
`AsyncStorage` (+ `useAsyncStorage`), `NetInfo` (+ `useNetInfo`), `Permissions` (expo's
`PermissionResponse` for camera, microphone, location, notifications) and `PermissionsAndroid`,
`Geolocation` (`@react-native-community/geolocation`) with an expo-location subset, `Haptics`,
`DeviceInfo`, expo-localization's `getLocales`/`getCalendars` with react-native-localize's
helpers, and local `Notifications` (expo-notifications), exported from `src/index.ms`. Proven:
`tests/api/deviceApis.test.ms` (19, native and JS), `tests/platform/nativeDevice.test.ms` (8, mock
bridge), `tests/browser/deviceApis.test.ms` (7, Chrome), and `examples/device` on an iPhone 17 Pro
simulator, iOS 26.5 (`tests/ios/device.sh`, `DeviceUITests`, `/private/tmp/neon-device-run2`): a note
and a merged JSON item survive terminate and relaunch, NetInfo reads wifi/connected/reachable, the
location alert is answered and `getCurrentPosition` reads the simulated 10.7769,106.7009, a watch
reports fixes, the notification alert is answered, a 2 s notification reaches the received listener
and the handler, and a banner tapped from the home screen reaches the response listener. Android:
the demo's APK builds (`tests/android/devicemodules.sh --build-only`); the lane
`tests/android/devicemodules.py` is written but not run (the Seeker is locked). Provisional choices
are rows D1–D8 of `WORKAROUND.md`. Not verified: any module on an Android device or emulator,
haptics felt (the simulator has none), battery on a device, a network change event on a device,
camera and microphone requests (only their refusal path is tested), notification taps while an
Android app is alive (needs Ion's `onNewIntent`, P7).

Prove each workflow through its real consumer on the declared targets. A public symbol,
mock pass or separate-module test artifact is not proof of the normal packaged app.
The reactive concepts still owed live in `docs/SOLID.md`; they are dependencies of these
workflows, not a separate checklist to finish before writing an app.

### Bundle 5 — animation (state 2026-10-07, `wt/rn-animated`, msc `0d83c4867`)

RN's `Animated` / `Easing` / `LayoutAnimation` surface runs on Neon signals: an `AnimatedValue`
is a signal, a style that reads `value.get()` follows it per property, and every running
animation shares one frame loop (`src/animation/`; import from `src/animation/index`). Covered:
`Value`/`ValueXY`, `interpolate` (numbers, clamp/extend/identity) and `interpolateString`
(colours, `"90deg"`, paths), timing/spring (tension-friction, bounciness-speed,
stiffness-damping-mass)/decay, `parallel`/`sequence`/`stagger`/`loop`/`delay`, tracking,
`add`/`subtract`/`multiply`/`divide`/`modulo`/`diffClamp`, listeners and offsets,
`Animated.event` onto NeonEvent fields, `Animated.View/Text/Image/ScrollView`,
`LayoutAnimation.configureNext/create/Presets` (native frame tweens and create-fade; browser
size transitions) and a `Presence` mount/unmount transition. Native gained `rotate` in
transforms, `rgb()/rgba()` colours, `overflow: "hidden"` clipping and display-link frames.

Proof: RN's own Animated, Easing, bezier and Interpolation test values on a manual clock
(`msc test [--target=js] tests/animation/*.test.ms`, 43 cases, both lanes), the mock native bridge
(`tests/platform/nativeAnimation.test.ms`, `nativeLayoutAnimation.test.ms`), Chrome
(`tests/browser/run.sh tests/browser/animated.test.ms`: opacity/translate/rotate across real
frames, a LayoutAnimation height transition), the `examples/motion` consumer on the mock host
and JS (`tests/apps/motion.test.ms`) and on an iPhone 17 Pro simulator on display-link frames
(`/private/tmp/neon-sim-run.sh <wt> examples/motion NeonMotion MotionUITests`, exit 0: spring
card at x 193 mid-flight then +160 pt, fade, LayoutAnimation panel +28 pt mid-way then +160 pt,
loop spinner, header 137 → 83 pt with scroll). The Android APK builds (ion generate + gradle).
Not run: the Seeker lane (`tests/android/motion.py`, written; the phone was asleep behind its
lock overnight), so Choreographer frames, rotation and clipping on Android are unproven. Provisional
choices are rows N1–N9 of `WORKAROUND.md`; the compiler findings are cards dated 2026-10-07 in
`~/metascript/.inbox/compiler/`. Not covered: `Animated.FlatList/SectionList` (generic
components cannot sit in a static field), `Animated.Color`, `useNativeDriver` (accepted, every
animation is JS-driven), LayoutAnimation `delete` and `scale*` properties.

### React Native gaps (state 2026-10-08, `wt/rn-gaps`, msc `0d83c4867`)

Closed on the three hosts: real safe-area insets (`niSafeAreaInset`; the root stays inside the safe
area until `<StatusBar translucent />` takes it edge to edge), native `textAlign` (an aligned label
spans its parent), nested `<Text>` spans in one native label (`textSpans`: colour, size, bold,
italic, underline, line-through) with `Text.onPress` and pressable spans, multiline `TextInput`
growth to `maxHeight` and `selection`/`onSelectionChange`, `Image` `resizeMode="repeat"`,
`blurRadius`, `defaultSource` and `ImageLoader.getSize/prefetch`, `StyleSheet` runtime members,
`Pressable` `hitSlop`/`android_ripple`, and Dialog/BottomSheet closing on the Android back press.
Proof: `msc test tests/platform/nativeParity.test.ms` (mock bridge, 10 cases including the gallery's
parity screen), `tests/components/{image,pressableParity,backDismiss}.test.ms` and
`tests/api/styleSheet.test.ms` on both lanes, Chrome `tests/browser/textParity.test.ms` (7 cases),
and the iPhone 17 Pro simulator (`/private/tmp/neon-sim-run.sh <wt> examples/gallery NeonGallery
GalleryUITests`, exit 0: insets 62/34 edge to edge, span and text presses apart, input growth,
native selection, `size 600x240`, `hairline 0.333`, a tap 18 pt outside the slop target presses,
dialog). The gallery APK builds (ion generate + `gradlew assembleDebug`, `Spans`/`Slop`/`Picture.size` in
the dex). Not run: the Seeker lane (`tests/android/gallery.py` `parity`, written; the phone was
locked), so Android insets, gravity, spans, ripple, TouchDelegate slop and back dismissal are
compile-checked only. Provisional choices: `WORKAROUND.md` U3, U8, U9, M7 (updated) and G1–G4;
compiler cards `2026-10-08-function-component-cannot-carry-static-members.md`,
`2026-10-08-macro-called-through-namespace-import-reaches-codegen.md` and sightings added to
`2026-10-04-string-literal-union-signal-rejects-its-function-layout.md` and
`2026-10-06-js-cast-object-arrow-body.md`. Not done: `pressRetentionOffset`, `onContentSizeChange`,
`StyleSheet.create` under that name, innermost-only press for nested Text.

### Vector graphics (state 2026-10-08, `wt/rn-svg`, msc `0d83c4867`)

react-native-svg's surface (`src/components/svg/`): `Svg` (width, height, viewBox,
preserveAspectRatio, color), `G`, `Path` (the full SVG 1.1 path grammar, arcs to cubics per F.6),
`Rect` (rx/ry), `Circle`, `Ellipse`, `Line`, `Polyline`, `Polygon`, `Text`/`TSpan`, `Use`, `Defs`,
`LinearGradient`/`RadialGradient`/`Stop`, `ClipPath`, the presentation props (fill, stroke and their
opacities, width, caps, joins, miter, dashes, fill and clip rules, opacity, transform and RN's
rotation/scale/origin props) as Accessors, and `SvgXml`. Every host draws one display list encoded
in MetaScript (browser: real `<svg>` markup; iOS: CoreGraphics in `NeonSvgView`; Android: a canvas
in `SvgView`), so the geometry is the same everywhere. Proof: `tests/components/svg/{pathData,svg,
markup,xml}.test.ms` and `tests/components/svgGalleryApp.test.ms` (native and JS),
`tests/platform/nativeSvg.test.ms` (mock bridge), Chrome `tests/browser/svg.test.ms` (getBBox,
hit tests, clip, viewBox) and `node tests/browser/svg.mjs <playwright>` (16 pixel samples of the
gallery, Animated ring included), and the iPhone 17 Pro simulator `SvgUITests` (the same 17 pixel
samples, exit 0; same colours as Chrome within 1/255). The consumer is `examples/components/svgGallery.ms`
(icons, donut, gradient line chart, Animated progress ring, SvgXml logo) with `examples/svg/{ios,android,web}`.
The APK builds (`SvgView` in the dex); the Seeker lane `tests/android/svg.py` is written and not run
(phone locked), so Android drawing is compile-checked only. Provisional choices: `WORKAROUND.md` S1–S9;
compiler card `2026-10-08-number-local-into-result-of-float64-fails-at-clang.md`.

### Capture: image picker, camera, audio (state 2026-10-08, `wt/rn-capture`, msc `0d83c4867`)

expo-image-picker (`launchImageLibraryAsync`, `launchCameraAsync`, permissions; mediaTypes, quality,
base64, multiple selection), expo-camera's `CameraView` (`facing`, `flash`, `active`, `mirror`,
`onCameraReady`, `onMountError`, ref `takePictureAsync/pausePreview/resumePreview`, `Camera`
permissions, `useCameraPermissions`) and expo-av's `Audio` (`Sound` load/play/pause/stop/seek/volume/
loop/mute/rate with status updates and `didJustFinish`; `Recording` prepare/start/pause/stop, `getURI`,
`createNewLoadedSoundAsync`; `setAudioModeAsync`) on Android, iOS and the browser. Proof:
`tests/platform/nativeCapture.test.ms` (mock bridge, 7 cases), `tests/api/captureApis.test.ms` (native
and JS), Chrome `tests/browser/capture.test.ms` (file input pick and cancel, the fake camera streams and
takes a JPEG, the chime plays to its end, a recording plays back) and `node tests/browser/capture.mjs
<playwright>` on the consumer `examples/capture` (pick a png, camera input, preview, 640x480 picture,
flip, chime, record and play back: all passed). iPhone 17 Pro simulator `tests/ios/capture.sh`
(`CaptureUITests`, exit 0, `/private/tmp/neon-capture-run6`): a sample photo picked through PHPicker
shows at 4032x3024, a denied camera keeps the view closed, an allowed camera with no device reports
the mount error and refuses a picture, the simulated system camera opens and cancels, the chime plays
to its end, the microphone prompt is answered. The APK builds with the provider and permissions; the
lane `tests/android/capture.py` is written and not run (Seeker locked, emulator reserved). Not
verified: Android at runtime, a real camera preview or picture on iOS/Android, recording on iOS (the
host's audio input times out; `NEON_IOS_RECORD=1`), real microphone capture in Chrome. The web
bundle needed `netInfo.ms` read by index (W6). Provisional: `WORKAROUND.md` X1–X6; compiler cards
`2026-10-08-arrow-with-a-function-return-type-does-not-parse.md` and sightings added to
`2026-10-08-test-block-awaiting-a-rejected-nullable-promise-segfaults.md` and
`2026-10-07-js-outer-function-made-async-by-nested-async.md`.

### Reference and ownership constraints

- RN's core catalog: `packages/react-native/index.js`, component exports and app/runtime APIs.
  Navigation is a community library, not an omitted RN-core widget
  ([RN navigation](https://reactnative.dev/docs/navigation)).
- Flutter contracts: `packages/flutter/lib/src/widgets/editable_text.dart` `EditableText`,
  `media_query.dart` `MediaQueryData`, `navigator.dart` `Navigator`, `overlay.dart` `Overlay`,
  `async.dart` `FutureBuilder` / `StreamBuilder`, and `basic.dart` `Semantics`.
- Development expectations: [RN Fast Refresh](https://reactnative.dev/docs/fast-refresh)
  and [Flutter hot reload](https://docs.flutter.dev/tools/hot-reload). Existing compiler HCR
  platform support and Neon integration boundaries are in `recompiler/docs/HCR.md`;
  do not confuse the missing mobile/Neon integration with an absent HCR implementation.
- Ion owns the implemented project generator and desktop runtime services:
  `ion/docs/PROJECT-GENERATOR.md`, `ion/src/index.ms`. The older Neon generator design
  is not authority for current implementation ownership.
- Framework layers remain separate: Neon UI/reactivity, Ion runtime/packaging,
  Void rendering, compiler language/toolchain, Lightcube editor/collaboration.
  Camera/auth/storage and similar ecosystem domains enter through concrete consumers,
  not a blanket RN/Flutter API-cloning requirement.

### Carry-forward constraints

The typed-slot protocol question is not dropped: see
`~/metascript/.inbox/compiler/2026-09-19-design-typed-slots-value-read-and-text-coercion.md`.
The author's `null` and boolean children use the same general protocol as numbers,
not a Neon-only special case. Once the language covers it, remove `isNumberTyped` / `asText`,
replace name-based type matching, and give attributes the same rule. Re-run the actual
JSX consumers after a protocol sync.

Do not restart implemented spread/classification or style-table generation from stale
roadmap rows: inspect `tests/render/spread.test.ms` and `src/macros/style/fields.ms`.
ErrorBoundary is existing; `docs/SOLID.md` owns its remaining concepts. Basic typography,
runtime adaptation and accessibility precede more pseudo-state or animation machinery.

Timing is std's `setTimeout`, with no Host timer. The iOS and Android adapters pump the
std event loop from the UI loop (`src/platform/native/loop.c`, armed by a `CFRunLoopTimer` /
`timerfd` on the main looper after every bridge entry, each pass inside the host's layout
batch). Before that pump a held FlatList row read `pressed row 5001` on the iOS simulator
and the Android emulator, with `onLongPress`'s timer never fired. After it, both read
`pressed long row 5001` (2026-10-06, msc `c96ea1d1f`). Physical phones were not run.

---

## Later — retained scope, not current prerequisites

- List ecosystem contracts beyond the RN list reference catalog already approved above.
- Full Material/Cupertino-style catalogs, gesture arbitration, complex animation graphs
  and pseudo-state surfaces beyond the common workflows.
- SSR hydration/resource serialization when a real SSR consumer needs them.
- Terminal parity and GPU embedding across every host; self-sizing Void Text remains
  required for the applicable app/editor workflow, not silently removed.
- Void's own vocabulary inside a Void area (`VISION.md` "Inside a Void area"): `Scene3D`, `Group`, `Mesh`,
  `Light`, `Camera3D` and the HUD over the scene on what Void has now; a `View` drawn into a texture on a mesh
  after Void's items in `void/docs/NEON.md`
- Mobile `<Void>`, desktop native vocabulary, multiple embeds, cross-boundary focus/
  accessibility and shared frame behavior (`docs/VISION.md`, `docs/RENDER-LAYERS.md`).
- Distribution/store acceptance through Ion; broader native-service/plugin domains
  chosen from actual apps.
- Editor/collaboration depth belongs to Lightcube. Preserve the canonical-source and
  render-boundary goals without making all of them gates for ordinary Neon screens.

---

## Recently done

- **Mobile App Foundation, Phase 1** (closed 2026-10-01 by the person) — the tracked Neon counter, generated by Ion and
  compiled by msc, runs signed on a physical iPhone and a physical Android phone with a real finger, through
  rotation, Home and resume. Evidence: `docs/IOS.md` §6.5 (final matrix on msc `013853dd`: iOS simulator and
  Release simulator, Android emulator, generator fixtures all green; full Neon gate 8 known reds, 0 new) and
  `docs/ANDROID.md` §10 (signed Release APK and AAB, Seeker finger and lifecycle). Decided at the close, not
  measured: the physical iOS Release counter and frame were observed by the person; a Distribution `.ipa`
  belongs to store upload, which Phase 1 left out; the mobile lanes re-run as part of each msc sync's
  consumer check (they have not been re-run on `e5e932d0` yet).

- **an Ion window whose content is one full-window `<Void>`** (2026-09-24) — `runWindow` in
  `src/platform/ion/window.ms`, `<Void>` over the optional `Host.voidArea`, React Native's key, focus,
  layout and submit handlers, and a Flutter-style text client for content drawn by hand. Measured on
  Windows 11 (96 DPI, UniKey running in Telex mode) with `examples/voidWindow.ms` driven by synthetic
  input: three clicks on `+1` read `Count: 3`; typing `ab cd`, Backspace and Enter logged each
  `changetext` and `submit "ab c"`; typing `vieetj` through UniKey logged
  `vi → vie → vi → viê → viêt → viê → vi → việ → việt` and drew `việt` with the caret after it; resizing
  the window from 640×360 to 900×500 re-ran `onLayout` (header 576 → 836 wide) and stretched the
  field. Not verified: a TSF IME's preedit (no Vietnamese IME is installed on this box; the composing
  path is pinned by `tests/platform/voidInput.test.ms` only) and a DPI change. The DOM host's key
  fields are pinned in real Chrome by a dispatched `KeyboardEvent` (`tests/browser/dom.test.ms`). The
  void host compiles again: it wrote `"50%"` strings into yoga's `float32` dimensions, which msc 0.2.55
  rejects; a string dimension now fails loud with its field name. The Chrome lane runs on Windows now:
  `playwright-core` driving the installed Chrome, a node static server, and the bundle read from beside
  the test file, where `msc test --target=js` writes it. Re-run after the example on msc `2f306532` and
  void2d's Font API: `xin chaof vieetj` through UniKey → `xin chào việt`.
  Proved: `bash tests/run.sh` on msc `2f306532`, tree `34595404` — macros ok, apps ok
  (`moduleSignalApp` native red, known L46), native 50 files and js 47 + 3 deliberate skips with 0 test
  failures, browser 81/81; exit 1 only on `tests/render/reconcile.test.ms` native, parked on a compiler
  card (`BUGS.md`).

- **tail of one NeonNode** (2026-09-19) — what the merge left behind. `on*` is an event by ONE rule,
  `on` + an uppercase letter, for a tag, a spread field and a component prop (`isEventName`; `<p once="x">`
  did not compile before). A function-typed value is a row and a raw child, so `<For>{namedRow}</For>`
  works. An `Accessor<string> | null` attribute and a `NeonNode | null` child attach only when present,
  `{maybe ?? <X/>}` lowers to `Show`, and View / Text / Pressable are written in JSX — which fixed a
  reactive `class` that froze at its first value on the whole vocabulary. Proved: `bash tests/run.sh`
  rc=0 — macros 17, apps 3, native 40, js 38 + 2 deliberate skips, browser 80/80;
  `msc build examples/counterDom.ms --target=js` and `msc run examples/counter.ms` rc=0. Left on the
  compiler: `{a || <X/>}` (the typed-slot protocol work in the first bundle). BUGS §3 has the measurements.
- **bare JSX catches up with `element(...)`** (2026-09-20) — after recompiler `0f1e6735`, `76a6a9bd`,
  `0b283fd4` reached the installed `msc` (`7f80b93b`). Every nullable slot (handler, ref, style,
  `Accessor<string> | null` attribute, `NeonNode | null` child) works in bare JSX; `Show` and `For` are in
  the prelude, so `&&` / `?:` / `??` / `.map` need no import. `.map` lowers a row without an index only:
  a callback that does not fit `map` is an error by the person's ruling, and a For row's index is an
  `Accessor<number>`, so a row with an index is refused with a message that names `<For>`. Proved:
  `bash tests/run.sh` rc=0 on `4e1602c` — macros, apps, 41 native, 41 js, browser 80/80; the four
  "— bare JSX" cells in `emit.test.ms`,
  `preludeFlow.test.ms`, `tests/macros/mapIndexRowRejected.ms`.
- **twin test cells folded** (2026-09-19) — no test compares `element` against itself any more. A cell
  that repeated another cell's JSX and assertion is deleted (`fragment` 6, `spread` 4, `ref` 2, `event` 1,
  `context` 1); a cell that pinned something of its own keeps a hand-written golden under a name that says
  what it pins (`ref`, `event`, `spread`, `host`, and the `treeRoot` halves of `emit.test.ms`). Proved:
  `grep -rnE '^test ".*(direct emission|tree emission|tree and direct|under direct)' tests` and
  `grep -rn treeRoot tests` both print nothing; `msc test` rc=0 on C and `--target=js` for each of the
  seven files.
- **one NeonNode** (2026-09-19) — a JSX expression is `(host, parent, before) => void` on every
  target: a function that puts the host nodes it owns into `parent`, in front of `before` (Svelte 5's
  shape). The description tree, its walker, the second macro and the second boundary type are gone;
  ONE macro picks the template tier or the flat tier per site, and component bodies, region rows,
  root fragments and `renderToString` all go through it. `render` owns the mount in a root and returns
  its dispose; `children` is always one NeonNode; the reconciler mounts a row at its final position
  and never detaches a live one (`RENDER-MODEL.md`). Proved at `e93dcdb`: `bash tests/run.sh` —
  macros 16, native 40, js 38 + 2 deliberate skips, browser 80/80 in real Chrome (in a worktree the
  browser lane needs `NEON_PLAYWRIGHT` pointed at the main checkout's playwright). Measured
  (`bench/nativeEmit.ms`, `RENDER-MODEL.md` §Gate): a component body mounts 2.3–2.7x faster, every row
  1.6–2.0x faster than the tree, void not slower; against the retired per-site emitter, rows with
  static attributes read up to 1.1 µs per mount slower on the no-clone mock host, unattributed and
  inside the bench's noise (accepted by the user 2026-09-19). `examples/counterDom.ms` builds `--target=js`
  and the vite-counter check is green in real Chrome: render, two clicks, sourcemap, edit → reload, zero
  console errors (`8ddfc0e`).
- **a numeric child renders as text** (2026-09-19) — `{count}` over an `Accessor<int32>`, `{n()}`,
  `{n() + 1}` and a plain `{k}` were all type errors ("expected string, got int32"), which is why the
  suite is full of `{count() + ""}`. The macro now emits `.toString()` when the child's type, or the
  payload of its `Accessor<T>`, is a number type. `msc test tests/render/emit.test.ms` rc=0 on C and
  `--target=js`, both tiers, red first; `bash tests/run.sh` rc=0 at `8036e96`.
- **Pressable runs RN's gesture machine** (2026-09-03) — `onPressIn`/`onPressOut`/`onLongPress`
  ported from `Libraries/Pressability/Pressability.js`: long press at 500ms (`delayLongPress`
  overrides), a minimum 130ms held state so a fast tap still shows feedback, and RN's
  `isPressCanceledByLongPress` rule — a gesture that fired `onLongPress` does NOT also fire
  `onPress`. Two tiers picked from the props actually declared: `onPress` alone stays ONE click
  listener (unchanged cost and behaviour), any gesture prop opts into pointer tracking
  (down/up/leave/cancel) where the machine owns the press. Timing is the LANGUAGE's, not a host
  capability: `Pressable` calls the std JS-shaped `setTimeout`/`clearTimeout` (std/core/system,
  msc ≥ 7f3d58bd) directly — every lane has a clock, `Host` carries no timer seam, and the
  earlier `Host.setTimer`/`NeonNode.mount` experiments were removed again. Tests use the real
  timer with small delays + wide margins (`delayLongPress={120}`, await `sleepAsync`), pinned by
  `tests/render/press.test.ms` (8 cells, both lanes). A fix fell out: both macros wrapped EVERY
  non-string prop in a thunk, so `delayLongPress={200}` against a flat `number` field miscompiled
  on C — constants now cross RAW, which is what the call-based reactive law already implied.
  The native UI loops pump those timers (the first bundle's carry-forward constraint). The older handover is `~/metascript/.inbox/compiler/2026-09-20-neon-bugs-md-compiler-rows-handover.md`.
- **the universal component vocabulary** (2026-09-03, user decision — div/span are HTML-isms
  users must not meet) — `View`/`Text`/`TextInput`/`Pressable` are real components
  (`src/components/primitives.ms`, the createComponent seam) rendering lowercase WIRE tags; every host
  translates in its own createElement (browser + SSR: `htmlTagFor` — view→div, text→span,
  textinput→input, pressable→button; terminal: box; void ignores tags; mock records as
  written; unknown tags pass through as the escape hatch). Two prop-contract rules landed with
  them: arrow-literal attrs cross RAW and take the field's flat type (handlers declare
  `(e: NeonEvent) => void`; withDynStyleAll keeps style thunks — the call-based law), and
  children rules in BOTH macros (starter tags wrap a single child as `[element(…)]`/text
  arrays; arrows stay raw for For/Show; non-arrow expressions are dynText). `class` is the
  RN-web escape hatch. Starter counter/todoList + counterDom/showcaseDom migrated — no div in
  the public surface. Sweep: C 29/29, JS 28/29 (same single pre-existing red). Two compiler
  debts filed (handed over, `~/metascript/.inbox/compiler/2026-09-20-neon-bugs-md-compiler-rows-handover.md`): engine-synthesized thunks around user arrows, and the converter
  registry's array-target gap.
- **the event surface speaks React Native** (2026-09-03, user decision — mobile-first) —
  `onPress` replaces `onClick` everywhere; `e.type` uses the neon spelling ("press",
  "changetext") and the browser host alone projects it onto DOM listeners (press→click,
  changetext→input). `onChangeText` hands the handler the TEXT, not the event: both macros wrap
  the user handler at the emit site (`__msCte` param, inline in each macro body — flat Node
  fields only type inside macro bodies), so the Host contract stays `(e: NeonEvent) => void` on
  every host. Pressable semantics beyond the name (pressIn/Out/LongPress) come with the starter
  RN components. Sweep: C 28/28, JS 27/28 (same single pre-existing red).
- **events carry a typed object** (2026-09-03) — `Host.addEvent` handlers take `NeonEvent`
  (flat v1: `type`/`value`/`x`/`y`/`key`, zero-filled where a host can't supply a field; built by
  `neonEvent`/`eventType` in `src/render/event.ms`); all four hosts construct it, the browser host
  maps `input`/`key*`/`mouse*` DOM fields, the mock host fires through `fireEventWith`. Shipping
  this exposed a compiler miscompile: a zero-arg arrow into an `(e) => void` slot type-checked at
  param position but called through the SLOT's ABI on C (garbage frame → double-free in the event's
  destructor) and was rejected at field position. Fixed at the root in msc **v0.2.53**
  (`padLiteralParams` — a literal lambda pads to its slot's arity at its own contextual-typing
  site; recompiler bug118). Fn VALUES keep strict arity (handed over, `~/metascript/.inbox/compiler/2026-09-20-neon-bugs-md-compiler-rows-handover.md` — annotate the decl). Sweep:
  C 28/28, JS 27/28; the one JS red is a PRE-EXISTING int64→number return-conversion drop
  (handed over, `~/metascript/.inbox/compiler/2026-09-20-neon-bugs-md-compiler-rows-handover.md`, A/B-proven against a self-built v0.2.52 control).
- **the JSX boundary stopped being per-target** (2026-09-03) — both `when (js)` blocks (`render/host.ms`,
  `converters.ms`) are gone: a native build reaches the same per-site emission a browser build does.
  Justified by the C-lane measurement nobody had taken: 2.6-2.8x static, 2.0x half-dynamic, 1.5x
  all-dynamic (`probe/nativeEmit_q4m.ms`, release, min of 3 rounds × 3 runs), which refuted the "small —
  allocations only" prediction. Regions, component bodies and SSR stayed on the description tree until
  one NeonNode removed it (2026-09-19, above). (The "27 files bad=0" sweep recorded here at the time was
  later found false-green — broken zsh harness; the honest gate is the 2026-09-03 sweep above.)
- **theme tokens, static and swapped** — `createTheme` bakes one `:root` rule, `createStyles` spells
  `var(--token)` with the unit applied at the use site, `setTheme({…})` replaces the rule by key.
- **`variants`** (2026-09-02) — the caller picks at the use site; `when` stays for what the
  environment picks. `msc test tests/render/styleVariants.test.ms` + `styleVariantsDyn.test.ms`,
  both lanes.
- **sheet lifecycle** (2026-09-02) — `flushSheet` rewrites the whole `<style>` on every change
  (browser), `renderToString` resolves the three style channels exactly as a mount does and
  registers the rule it uses, `mountSheet()` prints the registry as one block for SSR.
  `msc test tests/render/ssrStyle.test.ms` and `--target=js`, both green, both `when` branches
  proven live by mutation.

---

## Not our queue

The gate is `bash tests/run.sh`, read by its exit code: `tests/macros/run.sh`, every test file native,
every test file `--target=js` except the two that import the C-only Void host
(`tests/style/style.test.ms`, `tests/platform/void.test.ms`), then `tests/browser` in real Chrome. It was
green on all four lanes on 2026-09-19 (`e93dcdb`), so measure against that before attributing a red to
new work.
