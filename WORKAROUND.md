# WORKAROUND.md — provisional decisions taken overnight (2026-10-07)

The person went to sleep and said: "có gì không quyết định được thì WORKAROUND.md note lại và làm ẩu luôn, khi nào tao thức dậy tao sẽ check lại sau".
Every entry below is a choice made without the person's decision. Each says what was chosen, what the proper path is, and how to undo it.

| # | where | decided | proper path | undo |
|---|---|---|---|---|
| A1 | `src/render/hostTypes.ms` `Host.focus?` | Optional host capability `focus(node, focused)` (same idiom as `scrollTo`/`voidArea`), implemented by the native, DOM and mock hosts; `TextInput` ref now receives a `TextInputHandle` (`focus`/`blur`/`clear`/`isFocused`, `node`) like `ScrollViewHandle`, instead of the raw `HostNode` | Approve the contract field, or move focus onto a different seam (e.g. a host command channel) | Drop the field and the three host entries; restore `ref?: RefFn` on `TextInputProps` and `tests/render/ref.test.ms` |
| A2 | `src/render/environment.ms` | Module-level signals written by hosts: `useWindowDimensions()`, `useColorScheme()`, `useKeyboard()` return Accessors (RN names, Solid reads); native host publishes on resize and on a new bridge environment callback (Android `Environment.java` insets/uiMode, iOS keyboard notifications/trait changes) | Decide whether environment belongs on the Host contract (per-host, multi-window) instead of one global store | Delete the module, `publish*` calls in `src/platform/native/host.ms`, `niSetEnvironmentHandler`/`niKeyboardHeight`/`niColorScheme` |
| A3 | `src/platform/native/bridge.h` | Controls (text input, later switch/indicator/image) go through a generic `niSetProp(view, rnName, string)` + one control-event channel (`niLastControlPhase` 0..6) instead of one bridge function per prop | Per-prop typed bridge functions if string marshalling shows in profiles | Replace `niSetProp` callers with typed functions |
