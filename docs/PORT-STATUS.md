# Neon Port Status — Nim → MetaScript

**Last Updated**: 2026-07-27 (late)

---

## ⚡ CURRENT STATE (2026-07-27 late) — read this before the older sections below

**The suite is 15/15 green for the first time. Neon has zero open bugs on its own path.**
Recompiler battery 3340/3340 (163 files). Committed: recompiler `de322f8`, neon `4f97082`,
void `5152755`. Bug detail + root-cause ledger: `BUGS.md` (§1 clean, §2 = 7 compiler debts that do
NOT block Neon, §7 = small debts).

⚠ Sections below this block predate 2026-07-26 and describe the port as "đang dở" with a ~546 LOC
core. Treat them as history for the Nim→MS module mapping, not as current status.

### What is DONE

| area | state |
|---|---|
| reactive core | signal / effect / memo / owner / cleanup / runtime / array — green |
| render layer | node / host / reconcile — green, and NOT in the Nim original (cleaner split) |
| macros | `element` (JSX → VNode, incl. Babel whitespace rules) + `flow` (Show/For) |
| hosts | browser DOM (JS, partial) · terminal (green) · **void / Node2D + yoga flexbox (green)** |
| yoga | DONE — binding lives in `~/metascript/yoga`, `deps/yoga` symlinks a real checkout |

### What is LEFT — none of it is compiler-blocked

| # | work | state | size |
|---|---|---|---|
| 1 | ~~`createStyles` macro~~ | **DONE (S1b)** — `style.ms` is a real styleOf-rewrite macro; checker validates each entry against `Style`. Remaining style work is S3 (spread, blocked by §2 row 8) + S4 (reactive fields) | — |
| 2 | component macro (function components) | **runtime path DONE 2026-08-08** — capitalized-tag JSX through `element()` green E2E (reactive props, nested-arrow capture, cleanup via `<Show>`); remaining = converter surface (bare JSX, zero `element()` calls) | small–medium |
| 3 | attribute classification (animatable / event / static) | not started | small–medium |
| 4 | `src/starter/` example components | empty dir | small |
| 5 | iOS host | empty dir | large |
| 6 | Android host | empty dir | large |

Suggested order: **2 → 4** unlocks "you can actually write an app", then 5/6.

#### #2 component macro — what already exists vs what is missing (measured 2026-07-29)

"not started" was misleading: the **render layer half is already built and green**.

| piece | state |
|---|---|
| `VNode.componentFn` / `componentProps` fields | ✅ `src/render/node.ms` |
| `ComponentFn<P>` / `ComponentProducer` types | ✅ `src/render/node.ms` |
| `componentNode(fn, props)` constructor | ✅ `src/render/node.ms` |
| lazy expansion at mount (host path) | ✅ `src/render/host.ms` (3 sites: mount, keyed child, region) |
| lazy expansion in `renderToString` | ✅ `src/render/node.ms` |
| **`src/render/component.ms`** — `createComponent` (wraps `Comp(props)` in `untrack`) | ✅ landed 2026-08-03, 12 lines |
| **element macro emitting `createComponent` for capitalized JSX tags** | ✅ `element.ms` capitalized branch: expression props → thunks, string literals pass through, children structural (1 child as written, n children as array) |
| tests | ✅ `tests/render/component.test.ms` — 7 green: 4 static (defer / nest / children 1-n) + 3 reactive E2E (dynText updates + body-runs-once, prop expr with nested-arrow capture, `onCleanup` fires on `<Show>` unmount) |

**Runtime path CLOSED 2026-08-08** (msc v0.2.38 — both compiler prerequisites below are
fixed and deployed). The E2E pass surfaced and fixed one renderer hole: `renderNode`'s
child loop expanded `componentFn` blind — a component expanding to a REGION (`<Show>`
behind `createComponent`) fell into the text branch and never mounted; the loop now peels
the componentFn chain, then dispatches region vs node (`src/render/host.ms`). Probing the
fix filed one new §2 row (calling a cast-of-nullable-closure expression in-place
miscompiles C — `probe/closureCastCall.ms`). DX decision recorded in
`docs/RENDER-MODEL.md` §"Props typing".

**Design LOCKED 2026-07-30 (full design session with user) — the component/JSX contract:**

- **User surface = React**: components are PLAIN functions `(props) => VNode`, bare JSX
  everywhere, zero `element()` calls. Mechanism = new `converter` routine kind in MS
  (compile-time body, compiler-invoked at settled type boundaries). Normative spec:
  recompiler `docs/LANG.md` §"Converter Declarations" + `docs/LANG-JSX.md` §"Boundary
  Lowering via Converter"; implementation plan `docs/JSX-ROADMAP.md` Phase 9.
  `element.ms` only changes its declaration line to `export converter element(node: Node): VNode`.
- **Props reactivity = thunks** (`count: () => number`); the converter wraps dynamic
  attr exprs into arrows (same rule as dynText). Defer + untrack at the boundary via
  `componentNode` — semantics MEASURED green in `probe/componentSemantics.ms`
  (defer / body-runs-once / untrack / owner-inherit+cleanup all pass, block-bodied producer).
- **Emission V1 = tree emission** (VNode layer — host-agnostic: dom/terminal/void/mock +
  renderToString ride free; smallest compiler-bug surface). Direct host-call emission
  (Nim-original / Solid-DOM style) = **direct emission**, a later per-target optimization
  tier via build.ms — zero user-code change when it lands. Both tiers, the lifecycle, and
  the invariants are specified in `docs/RENDER-MODEL.md`.
- Nim-original `core/component.nim` ruled out as reference (ComponentContext threadvar +
  `cast[pointer]` + React-style useEffect deps — all superseded by our Owner tree).
- **ORDER (2 compiler prerequisites measured, filed as BUGS.md §2 rows 2026-07-30):**
  bug "thunk-field closure garbage" (SILENT — also latent in Show/For) → converter arc
  (Phase 9) → bug "expr-bodied-arrow env" → `src/render/component.ms` + element
  capitalized-tag branch + tests.


⚠ **`src/yoga/` and `src/platform/{ios,android}/` are empty dirs, not work-in-progress.**
⚠ **iOS/Android are NOT blocked on `@target`** (an older claim in CLAUDE.md, now corrected): use
`@platform("ios"|"android"|"macos")` around `@compile`/`@passC`/`@passL`/`@link` with one
backend-agnostic extern surface — exactly what `void/src/sokol/gpu.ms` already ships. Note
`@platform` filters **directives only**; it does not gate arbitrary MS code.

---

**Scope**: Báo cáo tình trạng port + cơ hội tận dụng MetaScript power

---

## Context

- **Reference (Nim)**: `/Users/le/projects/neon` — production Neon gốc (~8.260 LOC core)
- **Port (MetaScript)**: `/Users/le/metascript/neon` — port đang dở
- **Compiler**: `/Users/le/metascript/recompiler` — MetaScript compiler (rebuild)
- **Mô hình**: React Native-style component API + Solid.js reactivity (signals/effects/memos, fine-grained, không VDOM diff). Compile ra C (native) + JS (browser).

---

## Module Mapping (Nim → Port)

```
NIM (~8260 LOC core)                METASCRIPT PORT (~546 LOC core)
═══════════════════════════════════════════════════════════════
core/state.nim        1041 ───┐
core/macros.nim         26  ──┤   core/signal.ms    69  ✓
                              ├── core/effect.ms    11  ✓
                              ├── core/memo.ms      29  ✓
                              ├── core/owner.ms     34  ✓
                              ├── core/runtime.ms  149  ✓
                              ├── core/cleanup.ms   10  ✓
                              └── core/types.ms     31  ✓
                              (≈ 70% của state.nim, tách gọn hơn)

core/types.nim        454  ───── chưa port (enums, Component, Props)
core/style.nim        572  ───── chưa port (CSS-like style system)
core/style_binding    96   ───── chưa port
core/theme.nim        255  ───── chưa port
core/component.nim    199  ───── chưa port (component runtime)
core/flow.nim         55   ┐
core/keyed_list        140  ┤── render/reconcile.ms 106 ✓ (1 phần)
                              └── render/node.ms      66 ✓
                              └── render/host.ms     168 ✓
core/animation        2055 ───── CHƯA (lớn nhất, ~25% tổng)
core/async             645 ───── chưa
core/http             517  ───── chưa
core/resource         913  ───── chưa
core/error_boundary   203  ───── chưa
core/config           172  ───── chưa
core/yoga             590  ───── chưa (yoga/ trống hoàn toàn)
core/enums             150 ───── chưa
core/common            158 ───── chưa

macros/ui.*            ~?? ───── macros/ui/element.ms 66 ✓ (mảnh)
                              └── macros/ui/flow.ms   76 ✓
                              └── macros/ui/style.ms   6  (stub)
macros/state.*              ───── KHÔNG có tương đương

platform/browser/*          ───── platform/browser/dom.ms 102 ✓ (1 phần)
platform/ios/*              ───── KHÔNG có
platform/android/*          ───── KHÔNG có
platform/terminal/*         ───── KHÔNG có
```

### Đã có & test được

- **Reactivity core đầy đủ**: signal/effect/memo/owner/cleanup/runtime + `array.ms` (keyed list helper). 4 test file core.
- **Render layer riêng** (điều Nim gốc không tách rõ): `host.ms`, `node.ms`, `reconcile.ms` + **9 test file** (reconcile, hostOps, flow, element, region, counter, renderToString...). Kiến trúc sạch hơn Nim.
- **Browser DOM**: `dom.ms` 102 dòng.
- **Macro UI**: `element.ms` + `flow.ms` (Show/For) — sơ sài so với Nim.

### Khoảng cách lớn (ưu tiên theo impacto)

| Module Nim | LOC | Ghi chú |
|---|---|---|
| **component.nim + macros/ui/component** | ~400 | API người dùng — không có = không "React Native" được |
| **style.nim + style_binding + theme + enums** | ~1075 | Style system là xương sống UX |
| **macros/state/** (dsl/reactive/signals) | — | Hiện port dựa vào compiler trực tiếp, chưa có macro layer |
| **animation.nim** | **2055** | Lớn nhất; defer sau MVP |
| **yoga.nim + yoga/** | 590 | Layout engine — cần cho native, không cần browser MVP |
| **ios / android / terminal** | — | Platform backends — chỉ browser có |

---

## MetaScript Power — Tận dụng khi port

### Port đang dùng

- ✅ **JSX (Node compile-time)** — `macros/ui/element.ms`, `flow.ms`
- ✅ **Macro (Node in → Node out)** — `element.ms:14` nhận JSX, trả CallExpr tree
- ✅ **NodeKind.* rewrite** — inline literal trong macro body (Phase D)
- ✅ **Extension methods** — `core/signal.ms` (get/set trực tiếp)

### Port chưa dùng — phù hợp cho Neon

| Feature | Ứng dụng Neon |
|---|---|
| `struct` (value types) | Vec2/Color/Rect layout math — thay class Yoga |
| Discriminated union (`match`) | NodeData thay cho `data as XxxData` long-tail |
| `Result<T,E>` + `try/catch` | Thay exception trong resource/http/parse |
| `Promise<Result<T,E>>` + `try await` | Async resource fetching (thay core/resource.nim 913 LOC) |
| `actor` | Effect scheduler / owner tree coordination |
| `spawn` (thread pool) | Parallel rendering, image decode |
| Convention dispatch | `getDynamicField` cho dynamic props; `asString` cho style serialization |
| Sized integers (`int32`/`uint8`) | Canvas pixels, byte buffers (zero-overhead) |
| `T[N]` fixed array / `Span<T>` | Style tokens, layout buffers (zero-alloc) |
| `Maybe<struct>` auto-collapse | Nullable owner/computation |
| `@derive(Eq, Hash)` | Style key memoization (PLANNARED — đáng đợi) |
| Pipe `|>`, `match` expr | Reactive runtime dispatch |

### 3 module hưởng lợi nhiều nhất nếu dùng idiom

| Module (Nim) | Hiện port | MetaScript idiom | Lợi ích |
|---|---|---|---|
| **yoga.nim + yoga/** (590 LOC) | — | `struct Vec2` + `Span<float64>` + `extern function` + `@include("yoga.h")` | Zero-copy layout, không refcount trên hot path |
| **resource.nim** (913 LOC, async) | — | `Promise<Result<T, FetchError>>` + `try await` + `AbortController` | Compile-time error-safe, không throw; cancel đúng |
| **style.nim** (572 LOC, CSS-like) | `macros/ui/style.ms` (6 LOC stub) | `interface StyleProps` + `Map<string, StyleValue>` + `@derive(Hash)` + `match (kind: StyleKind)` DU | Static type-check style, memo cache auto |

---

## Cảnh báo trạng thái MetaScript

### JSX (đã hoạt động end-to-end)

`docs/JSX-ROADMAP.md` của recompiler có thông tin mâu thuẫn: phần audit đầu ghi "Phase 3 DONE 2026-06-21 (18 tests)", nhưng task block dưới vẫn ghi TODO. **Port hiện tại chạy được `element.ms` với JSX** → parser thực sự đã xong, doc chưa sync. Có thể yên tâm dùng JSX.

### Macro expansion v1 (hạn chế)

Tham chiếu: `docs/LANG-METAPROGRAMMING.md` L481-485 của recompiler.

- Macro phải trả **object literal khớp Node serialization shape** — không gọi `createNodeAt()` tự do trong macro body (Phase D6 partial).
- `nodeToASTLiteral` chỉ cover 21/68 NodeKind cho macro args phức tạp.

→ Port `element.ms` đã workaround (build literal trực tiếp), nhưng macros phức tạp hơn (component, control flow với generics) sẽ cần đợi Phase E5.

### `@target("c") / @target("js")` (chưa xong)

`docs/LANG-METAPROGRAMMING.md` L368: PARSED nhưng expansion **chưa xong**. Port `platform/browser/dom.ms` hiện chạy vì code không cần nhánh tĩnh. **Khi port iOS/Android cần `@target` để chọn backend → sẽ kẹt** cho đến khi MetaScript implement Phase F.

---

## Lộ trình đề xuất

### Phase A — Kiến trúc cốt lõi đúng idiom

1. Refactor `render/node.ms` → dùng `struct` cho VNode (value type, stack-alloc)
2. Định nghĩa `NodeData` bằng `match (kind: NodeKind)` DU → thay pattern `node.data as X`
3. `macros/state/` → thêm macro `signal/memo/effect` khai báo (compile-time first, đúng `CLAUDE.md`)

### Phase B — Browser MVP

1. Port `component.nim` → function component + JSX (đã có nền)
2. Port `style.nim` → `interface StyleProps` + memo cache (`@derive(Hash)` khi ready)
3. Async resource → `Promise<Result<T,E>>` thay cho throw

### Phase C — Native (cần đợi compiler)

1. Đợi `@target` expansion (Phase F) trước khi port ios/android
2. Yoga → `struct` + `extern function` + `@include`

---

## Tài liệu tham khảo

- **Nim gốc**: `/Users/le/projects/neon/src/`
- **Compiler docs**: `/Users/le/metascript/recompiler/docs/`
  - `LANG.md` — language reference
  - `LANG-METAPROGRAMMING.md` — macro model (Node compile-time only)
  - `LANG-JSX.md` + `JSX-ROADMAP.md` — JSX spec + trạng thái
  - `PROTOCOLS.md` — convention-based dispatch
  - `NIM-REF.md` — Nim mapping
