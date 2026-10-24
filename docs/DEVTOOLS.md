# Devtools: events and the control channel

A running Neon app built with `--hcr` reports what its refresh runtime did, and answers a tool or an LLM agent that asks for the UI tree, the state a refresh keeps, or a press or keystroke. This doc owns the wire contract and the reasons for its shape. The code is `src/devtools/` (`events.ms`, `control.ms`, `driver.ms`), with one driver per host: `src/platform/void/windowHost.ms` `openArea` (Ion and sokol windows) and `src/platform/native/host.ms` `mountApp` (iOS, Android, desktop native).

## Turning it on

| env, read once by the app | effect |
|---|---|
| `NEON_EVENTS=<path>` | append one JSON line per event to that file |
| `NEON_CONTROL=<port>` | serve the control channel on `127.0.0.1:<port>`, polled every `RELOAD_POLL_MS` with `reload()` |

Both exist only in an `--hcr` build: the reload poll is what drives them, so a release build carries no socket. Android takes no environment from `adb`, so `tools/androidHcr.sh` writes `NEON_CONTROL` into `files/hcr/devtools.env`, which `bridge.c` `loadDevtoolsEnv` applies before the first image loads, and runs `adb forward` on the same port.

## Events: JSON Lines

```
{"v":1,"t":1760967001234,"event":"reload","kind":"reloaded","modules":["counter"],"reason":""}
```

Every line carries `v` (the protocol version, `DEV_EVENTS_VERSION`), `t` (epoch ms) and `event`; the other keys belong to the event.

| event | keys | from |
|---|---|---|
| `ready` | `host`: the driver's name, `""` before a surface opened | the first reload poll |
| `reload` | `kind`, `modules`, `reason`, as the `HCR <kind> [modules] reason` log line | `pollReload` |
| `refresh` | `module` or `dependency`, `kept`, `rebuilt`, `remounted`, `ms` | a refresh that rebuilt or remounted anything |
| `refresh.failed` | `component`, `message` | a component that threw while it remounted |

The human output stays as it is: the terminal is for the person, the events are for the program. Neon's own drivers grep `^HCR [a-z ]+ \[` because msc prints `HCR reload module: …` lines with the same prefix, which is the failure a parsed format exists to prevent.

## Control channel: JSON-RPC 2.0, one message per line

A request is one line, `{"jsonrpc":"2.0","id":1,"method":"tree"}`. A request without an `id` is a notification and gets no reply, not even an error.

| method | params | result |
|---|---|---|
| `ping` | — | `{protocol, host}`, `host` null until a surface opened |
| `tree` | — | the root node: `{id, tag, text, value, focused, pressable, frame:[x,y,w,h], children}` in logical pixels from the window's top left; `id` is the child path (`"0.1.2"`) |
| `components` | — | `[{component, broken, state:{key: value}}]`: each mounted refresh boundary and the live values its `refreshState` keeps, formatted as `${…}` formats them |
| `press` | `target`: an `id`, or `text:<exact text>` (the first node in document order whose text or value is that) | `{x, y}` it pressed: the centre of the node |
| `type` | `text` | `true`; the text reaches the focused field |
| `subscribe` | — | `true`; from then on every event arrives as `{"jsonrpc":"2.0","method":"event","params":<event>}` |
| `eval` | `code` | not served yet: §Build events and eval |

Errors: `-32700` a line that is not JSON, `-32600` not an object with a string `method`, `-32601` an unknown method (its message lists the known ones), `-32602` a missing or wrong param, `-32000` the app failed (no surface yet, or the driver threw; the message says which).

`press` and `type` take the path a person's input takes, so what they prove holds for a person: the window driver sends a button down and up through `deliverPointer` and text through `deliverText`; the native driver hit-tests the laid-out tree to the deepest tagged view and sends touch phases 0, 1, 2 through `bubbleTouch` and the event registry, the sequence the bridges send.

### Why this shape

- JSON, not the terminal text: a tool and an LLM read a parsed object, and a wording change in a log line breaks a grep without failing anything.
- JSON-RPC 2.0 because it is what MCP speaks, so an MCP server is a pipe, and it is what Chrome DevTools Protocol, Flutter's VM service and React Native's inspector proxy speak in spirit: RN serves page lists at `/json/list` (`react-native/packages/dev-middleware/src/inspector-proxy/InspectorProxy.js` `PAGES_LIST_JSON_URL_2` at `18f5ddb`) and reports dev-server events to an `eventsSocketEndpoint` (`packages/community-cli-plugin/src/dev-server/runDevServer.js` `reportEvent`); Flutter's inspector registers `getRootWidgetSummaryTree` as a service extension (`flutter/packages/flutter/lib/src/widgets/widget_inspector.dart` `_registerObjectGroupServiceExtension` at `6f0e0db`).
- Newline-delimited over plain TCP, not a WebSocket: the app already links `std/net`, a client is three lines of Python (`examples/refreshWindow/drive.sh` `rpc`), and `adb forward` carries it to a device unchanged.
- Polled from the reload timer, not a thread: a request runs on the UI thread between frames, so `press` and `tree` see the same state the next frame paints, and nothing in the reactive runtime needs a lock.

### Limits

- A client that closes is noticed only when the app next writes to it (`recvNonBlock` cannot tell end of stream from no data); its subscription lives until then.
- The native host has no `type`: the bridges have no call that inserts text into the focused platform input. Upgrade trigger: a bridge entry such as `niInputInsertText`, after which `type` follows the window driver.
- The browser serves neither: under `when (js)` the event file is off and there is no socket. The Vite plugin's `import.meta.hot.send` is the channel to wire when a browser consumer exists.
- `components` shows the state a refresh keeps (`refreshState`, `refreshKeep`), not every signal: a signal no refresh keeps has no name the runtime knows.

## Build events and eval

Two halves belong to the compiler, because only `msc` knows them. Build events exist: `msc run --hcr --events=<path|->` writes JSON Lines from the watch session (`build.start`, `build.done`, `build.failed` with diagnostics, `reload` with its kind, modules and reason, `exit`) in the envelope Neon uses, so a tool reads whether an edit built from the compiler's file and whether it reached the screen from the app's. `eval`, which compiles a snippet against the running build and runs it in the app, is a new mechanism in the compiler (a module outside the import graph, linked against a live generation and dropped after one call) and waits on the person's decision in `~/metascript/.inbox/compiler/2026-10-20-run-hcr-events-and-eval.md`; until it lands, `eval` answers `-32601` with that pointer.

## Measured

2026-10-24, msc `f2debffda`, Windows: `examples/refreshWindow/drive.sh` 18 of 18, the 16 below plus msc's own events: one `build.done` for the first build and each of two edits, one `reload` with `kind:"reloaded"` per edit.

2026-10-21, msc `b1f63337f`, Windows:

- `examples/refreshWindow/drive.sh`, a real Ion window with OS input: 16 of 16. Over the socket, `ping` names the host, `tree` shows the field unfocused after a real click on the button, `press` by id focuses it, `type` reaches it (`RW text "Y"`), `press` by text runs the reloaded handler (`count=8`), and `components` reports `Counter` with `"state":{"count":"6"}`. The event file holds one `ready`, one `reload` per edit and a `refresh` for the template edit.
- `tests/devtools/control.test.ms`: 365 native, 66 JS. `tests/platform/windowHost.test.ms` 383 and `tests/platform/nativeHost.test.ms` 406 drive the window and native drivers through `handleRequest`.
- `examples/refreshAndroid/drive.sh` on the `pixellight` emulator: RESULT PASS, step (g) included: through `adb forward`, after a core restart and an activity recreation, `ping` names the native host, `tree` holds `Counter v7`, `press` on `text:tap` goes through the touch path (`count 1`) and `components` reports `"state":{"count":"1"`. Edit to reloaded 2.8 to 4.0 s over nine edits, of which the build is 2.4 to 3.2 s.
