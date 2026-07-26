# Neon Port Status — Nim → MetaScript

**Last Updated**: 2026-07-06
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
