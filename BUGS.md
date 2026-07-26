# Neon — Compiler Bug Tracker

TODO + context for the compiler/framework bugs blocking the Neon test suite.
**One bug ≈ one focused session.** Compiler bugs use the `/trace-nim` workflow
(the recompiler is a port of Nim's compiler — trace each divergence to root,
classify DIVERGE-INTENTIONAL vs UNINTENTIONAL against `recompiler/docs/NIM-REF.md`,
fix by returning to Nim's model; never work around).

**Rule for this file:** every number in §1 is a MEASUREMENT with the command that produced it.
If you can't reproduce it, re-measure and rewrite the section — do not layer a new "correction"
on top of a stale claim. History lives in §5 and is append-only.

---

## Toolchain — VERIFIED 2026-07-25 (late)

| what | value | how verified |
|---|---|---|
| installed compiler | `~/.metascript/bin/msc` **v0.2.27**, built Jul-25 21:44 | `msc --version`, `ls -la` |
| recompiler HEAD | `fb50e2b` — `src/` + `std/` **clean** (only `docs/*` + editor-plugin dirty) | `git status --porcelain -- src std` |
| binary ≡ HEAD? | **yes, effectively** — binary predates the 21:56 commits by 12 min but carries their content (they were committed from the tree it was built from). Proof: `renderToString` is green, which ONLY the try/finally fix produces | Neon suite |
| **battery** | **3330 pass / 7 fail** (3337 total; 157 files pass / 5 fail), **6m47s** | `cd ~/metascript/recompiler && rm -rf out && msc test src/index.ms` |

**Battery flake set (the 7 — no-regression means EXACTLY these):** `checker/suggest.ms` ×2
(object properties / enum members, `candidates.length === 3`), `compiler/lsp/handlers/lifecycle.ms`
(`elapsed < 200`, timing), plus `path.ms` / `literals.ms` / `expressions.ms` (Windows-path +
float-precision). 5 files total.

> ⚠ The 2026-07-24 note "true baseline is `3321/16`, don't trust 3330/7" is **REFUTED at this HEAD** —
> re-measured clean above. If you get a different number, diff the `×` lines against this list before
> concluding regression.

- Rebuild compiler: `cd ~/metascript/recompiler && rm -rf out && msc build src/index.ms --gc=drc --danger --cc=clang --output=msc`
- Deploy: `./tools/sync-local-binary.sh` (Neon consumes msc via `$PATH`)
- Recompiler rule: **never commit `docs/*`** (NIM-REF.md rows stay uncommitted).

---

## §1 — CURRENT STATE (measured 2026-07-26, `rm -rf out` PER FILE, all 15 test files)

**Neon suite = 12 pass / 3 fail.** Command: `msc test <file>` per file, clean `out/`.
⚠ Measured with the macro-VM-typing fix **in worktree `/tmp/rc-macrotype` (base `a9c0ae6`), NOT
COMMITTED, NOT DEPLOYED** — verified binary `/tmp/rc-macrotype/msc`. The installed `msc` still
gives 10/5 (it predates both this fix and the 07-25 assert-raise fix, now committed `2a156ff..122949d`).
⚠ Protocol: `rm -rf out` BETWEEN files is load-bearing — sequential `msc test` runs sharing `out/`
produced spurious compile failures (reconcile/reconcileHard flip-flopped until cleaned).

| file | result | file | result |
|---|---|---|---|
| `core/signal` | ✅ | `core/array` | ❌ |
| `core/memo` | ✅ | `render/flow` | ❌ |
| `core/dispose` | ✅ | `render/counter` | ✅ **NEW 2026-07-26** |
| `render/element` | ✅ | `render/voidHost` | ❌ (env) |
| `render/host` | ✅ | | |
| `render/hostOps` | ✅ | | |
| `render/reconcile` | ✅ | | |
| `render/reconcileHard` | ✅ | | |
| `render/renderToString` | ✅ | | |
| `render/region` | ✅ **NEW 2026-07-25** | | |
| `platform/terminal` | ✅ | | |

### Issue count: **3 compiler roots on Neon's path + 2 Neon-side + 6 compiler debts off-path = 11 open**

### The 3 roots blocking the 2 red compiler files (voidHost is §3/env)

| # | root | blocks | exact error (measured) |
|---|---|---|---|
| ~~1~~ | ~~void-callback inference~~ | ~~`region`, `array`~~ | ✅ **CLOSED 2026-07-25 — and the framing was WRONG.** The root was never inference: `genAssertStmt` emitted a bare `return;`, ill-formed C in any non-void function. A concretely-typed **non-generic** arrow failed identically. See §5. |
| **2** | **`Array<function>` method surface** | `array` | `in instantiation of 'indexArray<number, function>': Property 'slice' does not exist on type 'Array'` |
| **3** | **Unresolved-T through generic wrapper** | `flow` | `in instantiation of 'For<number>': Unresolved type 'T' - missing import?` (same for `Index<number>`) |
| **4** | **optional field `fallback?` lowering** | `flow` | `'fallback' does not exist in type ''` · `Property 'fallback' does not exist on type 'object'. Available: when, children, fallback?` · C: `no member named 'fallback' in 'struct msAnon_1bgn5uf'` (flow.ms:71), `member reference base type 'void *' is not a structure or union` (flow.ms:72) |
| ~~5~~ | ~~array-element `void*` erasure~~ | ~~`counter`~~ | ✅ **CLOSED 2026-07-26 — framing WRONG twice over.** Not an array bug, not codegen: the `element` MACRO spliced the literal string `"on"` (the ARGUMENT of `startsWith`) where the `<button>` subtree belonged, because macro bodies compiled with UNTYPED params and every flat Node-field read dispatched blind in the VM. The msString-into-`void*` clang error was where the corpse landed. See §5 2026-07-26. |

**Roots 3 and 4 are both in `flow`** — likely one session, but they are distinct mechanisms
(T substitution vs optional-field struct lowering); do not assume fixing one clears the other.

**Recommended order:** **#3+#4 flow** (2 roots, 1 file, shared session) → **#2**.

### ⚠ On T = unknown → `void*` — real, but NOT a blocker (do not chase it)

`createRoot((d) => {…})` genuinely infers **T = unknown → `void*`** (verified C:
`static void* dollarfn_test1_2_(msClosure d)`, mono instance `run__unknown`). That is a real
inference weakness — but it **blocks nothing**. It only ever surfaced because the assert lowering
emitted an ill-formed `return;` into the resulting non-void function; with §5's fix, `probe/voidcb2`
and `region` are green **while T is still `unknown`**.

A previous session tried to fix the inference (`checkAnonymousFunction`, `checkExprPass.ms:5133`:
block body + `inferredRet == Unknown` → `voidType()`). Battery stayed clean 3330/7 **but it REGRESSED
7 previously-green Neon tests** (host, hostOps, reconcile, reconcileHard, renderToString, terminal,
dispose) — because `inferredReturn === Unknown` conflates "body has NO return statement" with "body
HAS returns whose type didn't resolve". **Reverted; do not retry that way.** If someone does take it
up as a cleanliness task, it needs BOTH (1) a syntactic scan of the block for return statements (not
descending into nested fn bodies) and (2) void-generic instantiation support — `createRoot__void`
emits `const result = fn(dispose)` → C `void result = …`. Nim discards void here. Two features, zero
current payoff.

### #2 — `Array<function>` method surface (`array`)

Post-`b057320` a `U[]` annotation with U=function correctly stays an **Array** (see §5) — but that
array's **method surface** is missing: `indexArray<number, function>` → `Property 'slice' does not
exist on type 'Array'`. Direct sibling of the `b057320` fix, one layer further in.
Repro: `msc test tests/core/array.test.ms`.
(Historical note: the older `.slice(0)` **arity** complaint was NOT a compiler bug — std `slice`
requires `(start,end)`; fixed Neon-side in `src/core/array.ms`. This is a different, real gap.)

### #3/#4 — `flow` (`For<T>` / `Index<T>` / `Show`)

The Neon impl is `src/macros/ui/flow.ms` (uncommitted WIP):
`For<T>` ≈ `regionNode((h) => { const mapped = mapArray<T, HostNode>(props.each, (item, idx) =>
renderNode(props.children(item, idx), host)); … })`. T flows `each: () => T[]` →
`mapArray<T, HostNode>` → region thunk, and does not survive.

- **#3 status:** NOT root-caused. Neighborhood is `recompiler src/checker/instantiate.ms` (Nim
  `seminst` analog), but the mechanism is the opposite of the CompState/bug-E fixes — a type param
  not *substituted* (needs MORE resolution), not one *dropped* (needs preservation). Do not assume
  those fixes cover it.
- **#4 status:** `Show` props declare `fallback?`; the checker reports the field as available yet
  absent from the anon struct (`msAnon_1bgn5uf`), and the sibling access lands on `void*`. That is
  optional-field lowering on an anonymous props object, not T substitution.
- **Repro:** `msc test tests/render/flow.test.ms`.
- **Machinery map (if T-resolution turns out to touch Maybe/nullable):**
  - `!== null` narrowing: `src/checker/flow.ms` → `narrowByLiteralEquality` → `removeNullFromType`
    (peels Maybe via `unwrapMaybeType`, ~line 996); truthiness path ~line 839.
  - Value-Maybe read unwrap (codegen): `src/transform/coercion/maybeReadMaterialize.ms`;
    JS-strip in `src/transform/native/maybeUnwrap.ms`.
  - Assignment-LHS narrowing gate: `checkExprPass.ms` `leftPartOfAsgn>0` suppresses narrowing on the
    assignment target; the index sub-read is exempted (`de158b0`). Reusable for "read-in-lvalue-position".

### ~~#5 — array-element `void*` erasure (`counter`)~~ ✅ CLOSED 2026-07-26

The `msGenericArrayPush(&T6_, MS_STRING_LIT("on"))` C error was downstream wreckage: `"on"` was the
expansion-time value of `a.jsxAttrName.startsWith("on")` — the macro VM evaluated the chain to its
own ARGUMENT because macro bodies compiled untyped. Root-caused + fixed in the macro engine
(§5 2026-07-26); `counter` green. NOTE: the `msGenericArraySlice` ownership question from the 07-25
handoff REMAINS OPEN under #2 (real for `array`'s closure-array `.slice`).

---

## §2 — Open compiler bugs OFF Neon's path (6) — all re-verified 2026-07-25 late

| bug | repro | measured today |
|---|---|---|
| **nullfn bind-order** | `probe/nullfn_bindorder.ms` | ❌ `passing 'msClosure' to parameter of incompatible type` (:78) |
| **nullfn explicit type-arg** | `probe/nullfn_explicit_targ.ms` | ❌ `Argument type mismatch in 'apply' arg 0: got function, expected Maybe_fn_fnnumbernumber17` |
| **union ctor-param proto/def** | `/tmp/mono_union.ms` | ❌ `conflicting types for 'Box__union_number_string_init'` |
| **loop + nested-closure snapshot** | `/tmp/loopesc.ms` | ❌ **builds but MISCOMPILES** — c0 expected 51 → **800**, c1 expected 51 → **0** |
| **`canRaise` missing Nim's `sfGeneratedOp` arm** | `/tmp/craise.ms` | latent (not a live bug) |
| **latent `monoConcreteTypeName` siblings** | — | by inspection: anon `Union` / `Conditional` |

- **nullfn bind-order** — `apply((v:number)=>v+1, 10)` binds T=int32 from arg 1, overriding the arg-0
  arrow. Nim `paramTypesMatchAux` binds progressively IN ARG ORDER → T=number. Do NOT fix by loosening
  the exact-match wrap gate (masks the divergence). Checker unify-order.
- **nullfn explicit type-arg** — `apply<number>((v:number)=>v+1, 10.5)` → arrow checked against the RAW
  pre-substitution formal → degenerates. Needs the INSTANTIATED formal (Nim `implicitConv` /
  `getInstantiatedType`). Checker.
- **union ctor-param proto/def indirection** — generic class ctor with a union param emits
  `_init(…, msUnion* v)` (definition, by-pointer) vs `msUnion v` (forward decl, by-value).
  Pre-existing; unmasked by the `monoTypeKey` split.
- **loop + nested-closure snapshot** — a closure created **inside a loop** that BOTH captures a
  loop-body local AND contains a nested closure. `for i { let c=0; const step=()=>{ const
  inc=()=>{c=c+1}; inc(); return c }; arr.push(step) }` → after 50 calls each counter should read 51.
  **Values have MOVED since the 07-21 note (`c0:4 c1:0`) — now `c0:800 c1:0`, still wrong, now wildly
  so.** Not a bug-D regression (verified against pre-fix `7a936b0`: `c0:4 c1:3`, also wrong). No UAF
  (exit 0). Root (suspected): loop-escape wants a per-iteration SNAPSHOT of `c`, but a loop closure
  containing a nested closure goes through `setupSharedEnv` → up-chain reaches a shared slot instead of
  the per-iteration one. Needs per-iteration env identity. Compare `/tmp/loopsimple.ms` (non-nested,
  correct). **This is a silent wrong-answer bug — highest severity of anything in §2.**
- **`canRaise` missing `sfGeneratedOp`** — every `msStringDecref`/destroy call gets a raise check:
  ```c
  msStringDecref(t_1_);         if (msErr) goto __finally_1;
  msStringDecref(dollartmp_0_); if (msErr) goto __finally_1;
  ```
  Nim `canRaise` (`ast.nim:1562`) has TWO arms: **A** — `sfGeneratedOp in fn.sym.flags → false`
  (a compiler-generated lifecycle op can never raise, decided AT THE CALL SITE); **B** — conservative
  when the effect list is absent. MS has only B (documented at `codegen/c/statements.ms:206`); its
  `suppressRaiseCheck` (`declarations.ms:234` = `isDrcHookFn || isActorDispatch`) fires only while
  emitting the *body of* a hook, never for a *call to* one. Costs: code bloat; forces the
  `__oldErr_<lab>` save/restore Nim skips; and an internal contradiction — those checks are harmless
  only *because their premise is false*; if a decref really could raise, a partially-run cleanup jumps
  to `__finally_1` which decrefs the SAME vars again → double-decref → UAF.
  **Verdict DIVERGE-UNINTENTIONAL, but NOT live today** (decrefs never set `msErr`).
  ⚠ When fixing, do NOT delete the `__oldErr_<lab>` save/restore — Nim keeps both branches.
  **First thing to establish (unverified):** whether `isDrcHookFn` can be applied to a CALLEE at the
  call site (is the callee symbol/decl reachable from `emitCallRaiseCheck`?).
- **latent `monoConcreteTypeName` siblings** — anon `Union` (`A | B`) and `Conditional` literals are
  still emitted unparenthesized, so `U[]` with U=union/conditional collapses exactly like the function
  case did (§5, `b057320`). Fix when they surface.
- **deferred, not counted:** catch-side `e.message` (object-carrying exceptions) — MS's exception
  runtime is string-based by design; `throw` works, `catch (e) { e.message }` does not.

---

## §3 — Neon-side / environment (2)

- **`voidHost`** — TWO independent problems, both Neon-side:
  1. **test-code type error** (fixable now, no compiler needed):
     `Argument type mismatch in 'renderToHost' arg 0: got string, expected VNode` ×2.
  2. **env:** `sokol_gfx.h file not found` at `/Users/le/metascript/void/src/sokol/bridgeEmbed.m:12`.
     Native dependency (Void host + sokol) not present.
- **`terminal`** — ✅ FIXED 2026-07-21, Neon-side, stays green (284/284). Was "two short texts in a row
  render as 1 line". Two fixes in `src/platform/terminal/paint.ms`: tag `"row"` now defaults
  flexDirection to row; `getAttr`/`getAttrNum` guard with `.has(name)`.

---

## §4 — Uncommitted Neon work (do not confuse with bugs)

The render feature WIP is **uncommitted in the Neon repo** and is real, coherent work:
Components + For/Index/Show + list-region reconcile. Modified `src/render/{node,host}.ms`,
`src/macros/ui/flow.ms`, `src/platform/browser/dom.ms` (insertBefore/removeChild/nextSibling),
`src/core/memo.ms` (glitch-free memo + `equals`), `build.ms`; untracked `src/render/reconcile.ms`,
`src/core/array.ms`, `tests/render/{region,flow,reconcile,reconcileHard,…}.test.ms`.
**Preserve it.** It is blocked by roots #1-#5, not broken. Commit once green (needs review).

---

## §5 — Fixed (history + root-cause ledger, append-only)

### 2026-07-26 — `counter` GREEN: macro-VM flat Node reads were untyped ⚠ IN WORKTREE `/tmp/rc-macrotype`, NOT COMMITTED

**§1 #5 "array-element void* erasure" was a mis-framing.** Real chain: `element.ms:20`
`a.jsxAttrName.startsWith("on")` evaluated AT EXPANSION TIME to the literal `"on"` (its own argument)
→ the macro spliced `"on"` where the `<button>` subtree belonged → clang saw `msString` pushed into a
`void*` children array. Six neon probes (`probe/macro_*.test.ms`) isolated it: flat reads alone were
correct, ANY chained call mis-dispatched, and the early "direct param fields work" conclusion was
itself a false-green (`"p".length == 1 ==` attr count; a 2-attr disambiguation probe pinned EVERYTHING
flat as untyped — `.length` chains returned the attr COUNT).

**Root (3 layers, all in the macro-engine path):**
1. `expand.ms getOrCompileMacro` built the `__macroBody` wrapper with `fnParamTypes` all `""`
   (deliberate — "param types are never known"), so `n: Node` was Unknown BY CONSTRUCTION; every flat
   read (the VM wire format flattens NodeData payload fields onto the Node object —
   `nodeToASTLiteral`/`bridge.ms`, no `data` key) dispatched blind in the Raiser lowering.
2. `transformForEngine` DROPPED `checkerCtx.errors` — the engine swallowed every checker error, so
   LANG-METAPROGRAMMING.md's "checker validates Node access before macro ever runs" was unimplemented
   on this path (`a.totallyBogusFieldXyz` compiled silently).
3. Design (weighed Nim `macros.nim` NimNode-opaque accessors, Haxe ExprDef pattern-match, MS's own
   idiom = 3297× `.data as XData` vs exactly 1 flat read in the compiler): the flat wire IS the
   macro-layer representation for now; the checker types it by the **LANG.md:646 DU access rule**
   (field name unique across variants → direct read, no cast; conflicting types → must narrow).
   Long-term S1 roadmap: `NodeData` becomes a real `match (kind: NodeKind)` DU and the VM carries
   nested `data` — probe `macro_narrow.test.ms` N1 (`.data as XData` reads empty inside a macro) is
   the Nhịp-2 marker. Nhịp-2/3 NOT started.

**Fix (worktree `/tmp/rc-macrotype`, base `a9c0ae6`, ~10 files):**
- `macroParamTypesRegistry` + `macroDeclModuleRegistry` threaded collect → `ExportedSymInfo`
  (`macroParamTypes`; `definingModule` reused) → both import stations (incl. re-export hub) →
  `getOrCompileMacro` wrapper `fnParamTypes` (parser already kept `macroDeclParamTypes` — unused).
- Engine seeds now UNION invoker scope + the macro's DECLARING module scope
  (`lookupModuleCtx(declPath)`) — invoker-only seeds broke cross-module macros with
  `Unresolved type 'Node'` whenever the CALLER didn't import Node (Neon's exact shape).
- `setEngineCheckMode` slot spans check + refineTypes + transformForRaiser — restoring it before
  refine re-broke lowering (the last "`.length` still returns attr count" mystery: refine re-inferred
  without engine mode, so the Raiser host-fn dispatch saw Unknown again).
- `checkExprPass`: `resolveEngineNodeVirtualProp` for member READS (universal `line/column/endLine/
  endColumn` → number; payload fields via NodeData variant lookup mirroring `findVariantByFieldName`;
  same-name-different-type → error demanding a kind-narrow or `.data as <Kind>Data`) +
  `engineNodeHasVirtualKey` for object-literal CONSTRUCTION against class Node (existence-only —
  building `{kind, line, column, value}` stays legal; `value` ambiguity applies to reads, not builds).
- Engine errors now SURFACE: `EngineMacroResult.errors` → forwarded as
  `Macro '<name>' body: <msg>` — **Severity.Error only** (the wrapper's unused-sweep hints on seeded
  symbols are synthetic noise; first attempt forwarded a `'Box' is declared but never used` HINT as a
  hard error and broke module-local-type macros).

**Guards (both proven RED on installed pre-fix msc → GREEN on worktree msc):**
- `src/test/handoff/macroNodeFieldTyped.ms` (battery-registered in `handoff/index.ms`): startsWith
  chain classification (`evt;attr;`) + direct read, 2-attr disambiguating values. Pre-fix RED
  signature: `AssertionError: got: on`.
- `src/test/guard/macroNodeBogusField.ms` (GUARD-CHECK-FAIL × 2): bogus flat field must error;
  unnarrowed `n.value` must demand narrowing. Pre-fix RED: compiled clean.

**Gates:** worktree-msc self-hosted battery **3338/3338 (162/162 files, 0 fail)**; installed-msc
battery on the modified tree 3337/1 (path.ms Windows-join only). Pristine-`a9c0ae6` baseline
3328/10 = path ×1 + lifecycle ×9 (the lifecycle phase5/6 hover block is timing-flaky: present
pristine, absent both later runs — NOT this session's doing either way). Neon 11/4 → **12/3**
(`counter` green; array/flow/voidHost = #2/#3/#4/env, untouched by this fix). Neon probes:
startswith/attrloop/fieldstr/chain/direct/evt_attr/narrow-N3 green; `macro_disambig`/`macro_lenval`
keep deliberate RED bracket-tests (they assert the formerly-wrong values — rewrite truth-only or
delete at leisure); `macro_narrow` N1 stays red BY DESIGN (Nhịp-2 marker).

### 2026-07-25 (late) — assert exited via `return;`; test boundary never observed `msErr` ⚠ STAGED, NOT COMMITTED

**Two bugs, one root: the test boundary was not the catch site.** Traced via `/trace-nim`.
Changes are **staged in the recompiler working tree, uncommitted, NOT deployed** — the installed
`msc` is unchanged. Verified binary: `/tmp/rc-testbound/msc` (worktree `/tmp/rc-testbound`).

**Bug A — silent false-green (runtime, `runtime/core/test.h`).** `ms_test_main` called `e->fn()`
and read only `__ms_test_failed`, never `msErr`. **Any uncaught exception escaping a test body was
reported ✓ PASS.** Proof (`probe/esc_throw2.test.ms`): prints `MARK-before`, does NOT print
`MARK-after`, and the following `assert 1 === 2` never runs — yet the file reported ✓ 1 passed.

**Bug B — assert's exit was `return;` (compiler, `codegen/c/statements.ms:927`).** `genAssertStmt`
emitted `msTestCheckFail(...); return;` on the test arm. A bare `return;` is **ill-formed C in a
non-void function**, so an assert inside ANY non-void arrow broke — and where it did compile it
returned from the innermost **lambda**, not the test.
⚠ **This refutes the old "void-callback inference" framing:** `probe/va_num.test.ms` —
`(v: number): number => { assert v > 0, "positive"; return v * 2; }`, **zero generics, fully
concrete** — failed identically. Inference was never the root.

**Nim (`lib/std/assertions.nim`):** `assert` → `assertImpl` → `failedAssertImpl` → `raiseAssert`
`{.noinline, noreturn.}` — it **RAISES**. A raise is return-type agnostic and works at any nesting
depth; and assert's own doc gives the other half: *"This exception is only supposed to be caught by
unit testing frameworks"* — the FRAMEWORK is the catch site. Verdict **DIVERGE-UNINTENTIONAL → SAME**
(NIM-REF had no assert/test-framework row; one was added).

**Fix — 3 sites, +21/−1:**
- `runtime/core/test.h` — boundary consumes the in-flight exception:
  `if (msErr) { __ms_test_failed = 1; msDiscardCurrentException(); }` = NIM-REF row 61's bare-catch
  consume-once (decref+null), so no leak, no double free. Also resets `__ms_last_assert_file/line`
  per test (they were never reset → stale location attribution).
- `src/codegen/c/statements.ms` — assert emits `msErr = MS_TRUE` + new `emitPendingErrorGoto(p)`,
  the conditional twin of `emitErrorGoto`: same `errorTargets`/`BeforeRet_` target `genThrowStmt`
  uses, and it sets `beforeRetNeeded` so the epilogue's zero-value return exists.
  **No exception object is minted** — `msTestCheckFail` already owns the message (`strncpy` into its
  own static buffer), and `msCurrException` is deliberately left untouched so an assert failing
  inside a catch body cannot orphan the exception being handled.
- `src/codegen/c/test.ms` — dispatcher TU must `#include "runtime/core/system.h"`; it included only
  `test.h`, where `msErr` is undeclared.

**Verified:**
| check | result |
|---|---|
| battery (`rm -rf out`) | **3330 / 7** = known-flake set exactly, ZERO regression |
| `uncaught exception escaped` across all 3337 battery tests | **0** — no test was exploiting the hole; the fix cost nothing |
| Neon suite | 10/5 → **11/4**, `region` GREEN (this was its sole blocker) |
| guard `src/test/guard/assertInNonVoidArrow.ms` (6 shapes) | **RED pre-fix = 4 compile errors → GREEN 6/6** |
| guard `src/test/guard/testBoundaryReportsEscape.ms` (+ `fixtures/escapingThrow.test.ms`) | **RED pre-fix → GREEN** (proven against pre-fix codegen **and** pre-fix `test.h` together) |
| `probe/va_num`, `probe/voidcb2` | FAIL → **PASS** |
| `probe/esc_throw2` | PASS *(wrong)* → **FAIL** *(correct)* |
| assert failure reporting (message, power-assert diagram, file:line) | unchanged |

**Bug A guard — how it works.** A guard for bug A must assert a *failing* outcome, which a passing
test file cannot say about itself. Solution: `testBoundaryReportsEscape.ms` **spawns the compiler
under test** (`execFile(cwd() + "/msc", ["test", fixtures/escapingThrow.test.ms])`) and asserts the
child exits **exactly 1** — `ms_test_main`'s "some test failed" code. `0` means the escape was
swallowed (the bug); any other code means `./msc` was missing or unrunnable, which must not read as
a pass. Run it the standard way, from the recompiler root, after building `./msc`.
⚠ Its exit code is polluted by the known `std/fs/path.ms` flake (`std/process` pulls it into the
closure) — **read the guard's own `✓ / ×` line**, not the exit code.

**Mystery solved as a side effect:** the doc's long-running `3330/7` vs `3321/16` contradiction was
never a real baseline disagreement — `3321/16` is what you get in a **git worktree**, where the
untracked `examples/*.ms` are absent and 9 LSP tests fail on `src.length > 0`. Symlink `examples/`
(and `vendor/`, also absent) into any worktree before trusting a battery number.

### 2026-07-25 — try/finally swallowed every exception (`renderToString` HANG) ✅ COMMITTED

**Commits (recompiler main):** `5a3444e feat(ast): mark try statements with an explicit hasCatchClause`
· `1b9be8a fix(codegen): a try without a catch clause propagates instead of swallowing`
· `adff288 fix(codegen): omit the JS catch clause when the try has none`
· `eecb0eb fix(codegen): a raise inside a catch body still runs its finally`
· `fb50e2b test(guard): try/finally propagates and empty catch swallows`.
*(An earlier revision of this file said "uncommitted" — stale, corrected 2026-07-25 late.)*

**Not a compiler hang — the COMPILED TEST BINARY spun forever.** Sampling showed `msc`'s main thread in
`cmdTest → execFile → __wait4` while the child burned 100% CPU in
`renderToString → msThrow → msMakeError → msAllocTyped` — an infinite re-throw loop.

```c
msString renderToString(VNode* n) {
  while (1) {                        // tail-recursion → loop
    msThrow(MS_STRING_LIT(…)); goto __catch_2;
    __catch_2: {
      msErr = MS_FALSE;              // SWALLOWS the in-flight exception
      msDiscardCurrentException();
      /* unsupported stmt: NullLiteral */   // ← intended handler body never codegen'd
    }
    __finally_2: { …decrefs…; if (msErr) goto BeforeRet_; }   // msErr FALSE → never taken
  }                                  // → back to loop head → throw again → ∞
  BeforeRet_: ; return (msString){0};
}
```

**Two compounding defects:** (1) a handler synthesized for a function with NO source-level try/catch
swallowed a propagating exception instead of re-raising; (2) with `msErr` cleared, the tail-call
`while(1)` had no exit on the exception path.

**Fix — STRUCTURAL, no sniffing:** `hasCatchClause: boolean` on `TryCatchStmtData` + the inline
`NodeData` arm (`std/meta/node.ms:364,586`); `makeTryFinally` vs `makeTryCatch` constructors replace
inference at all 6 creation sites; `clone.ms` carries it; **both C and JS backends** read it (the JS
backend had the same swallow bug). Plus the trailing `raiseExit` after the finally, the
`__oldErr_<lab>` save/restore around the finally body (Nim `oldNimErrFin`), and the
parser/`deferLower` absence sentinel unified with the DRC injector's.
Guard `src/test/guard/tryFinallyPropagates.ms` proven RED→GREEN.
NIM-REF §1 "Try/finally handler presence is structural".

**Bisect that found it** (all other files at HEAD): HEAD → HANG; HEAD with the R1 `clone.ms` fix
reverted → HANG (⇒ not the R1 fix); HEAD with 3 throw-codegen `.ms` reverted to `164a58a` → PASS 5s;
Jul-24 backup binary → PASS 3s. Culprit `2974c6c` "bare catch releases the caught exception" (+/or
`f14d2e2`). `ab1d87a` alone was not sufficient.
Repro `probe/rts_b.test.ms` (11 lines); `probe/rts_a.test.ms` is the no-throw control.

### 2026-07-25 — R1 "generic erasure" was an operator-precedence bug ✅ COMMITTED

`b057320 fix(monomorphize): parenthesize function type literal in annotation substitution` ·
`c2a241e test(guard): U[] annotation with U bound to a function type stays an array`

**DIVERGE-UNINTENTIONAL → SAME.** The long-hunted `mapArray<number, function>: expected Array, got
function` was **not erasure** — it is **string-based monomorphization losing operator precedence**.
`substituteTypeStrings`/`substAnnotationAll` (`checker/instantiate.ms`) substitute type-params
**textually**, then re-`resolveAnnotation`. `monoConcreteTypeName` (`monomorphize/clone.ms:321`)
emitted a Function as the BARE literal `() => number`; substituted into `U[]` that yields
`"() => number[]"`, which re-parses as `() => (number[])` — a FUNCTION, not `(() => number)[]`.
Nim never hits this: it substitutes on PType **nodes** (`semtypinst`), no surface-syntax hazard.
Fix = parenthesize (precedent already set for anon unions, `clone.ms:285-289`). **1 line.**

**Localization (6-cell, zero Neon imports):** fires ONLY at `local-var annotation` × `generic param` ×
`function type`. Return `U[]` ✅, param `U[]` ✅, un-annotated local ✅, concrete `(()=>number)[]` ✅,
`U[]` with U=number ✅ — only `const x: U[]` with U=fn ❌.
Probes `probe/ufn_array.ms` / `ufn_disc.ms` / `ufn_base.ms` — **all ✅ as of 2026-07-25 late.**
Guard `recompiler src/test/guard/genericFnArrayAnnot.ms` proven RED→GREEN.
NIM-REF §1 "Monomorph annotation roundtrip: parenthesize compound type literals".

### 2026-07-24 — R1 closure-scope-loss ✅ COMMITTED

`0e4c18a fix(transform): walkExpandBlocks descends into expression-position fn bodies` ·
`164a58a test(guard): destructure lowering reaches expression-position arrows`

**DIVERGE-INCOMPLETE → SAME** (`transf.nim`, NIM-REF row 76). The `undeclared 's'/'g'/'list'/'items'`
family was NOT a `$up`/lambda-lift bug — it was `const [a,b]=f()` **destructuring inside an arrow in
EXPRESSION position** (var-init / capturing / call-arg) never lowering, because
`walkExpandBlocksHooked` (`transform/walker.ms`, shared by 9 desugar passes) had a no-op `_ => {}`
default that skipped expression-position fn bodies. Fix = default → `mapChildren` uniform recurse
(direct sibling of the `eafbc8b` walkLift fix). Independent of lifting.
Guard `recompiler src/test/guard/destructureInArrowLower.ms`.
NIM-REF "Statement-expansion walk: uniform child traversal".
Probes `probe/r1_undeclared_s.ms` + `probe/r1_arity_min.ms` — **both ✅ as of 2026-07-25 late.**

### 2026-07-23 — Map.get → `V | null` flip + value-type Maybe unwrap ✅ COMMITTED + DEPLOYED

*(An earlier revision said "NOT deployed" — stale; HEAD includes these and the installed binary is
built from HEAD.)*

- **Original framing was WRONG.** "`Map.get(missing)` returns zero not null" is **Nim
  `Table.getOrDefault`** semantics — correct by that contract. The emitted C proved the call site typed
  `.get()` as plain `V`, so `x === null` constant-folded to `false` for value types.
- **Decision: flip to JS/TS-Optional `get(): V | null`** (matches TS/Rust/Swift; Nim's `Option[T]` is
  model-compatible). **DIVERGE-INTENTIONAL.** Commits `8c69ffa..dd80ebc` + `42a799c` (HashMap.get),
  `901a849` (boolean arrays → `msUint8Array`), `b8d43fa` (`hash(unknown)` via `msPtrHash` — unblocks
  `Map<unknown,*>` keys, which the render layer needs), `0a3da84` (`maybeUnwrap.ms`),
  `1754f7f`/`6a6ec45` (caller migration).
- **Value-type Maybe unwrap operators shipped:** `as T` (nullableLower rule 1c), `?? d` (checker
  `inferBinaryOp`), postfix `!` (parser + TypeAssertion sentinel `"!"`).
  Guard `src/test/guard/maybeValueUnwrap.ms`.
- **Settled idiom:** `!== null` narrow (ref) / `?? default` (value) / hoist `const e=arr[i]` for
  LHS-index writes — **NEVER `as X`** (unsafe non-null assertion that defeats the flip). `.has()` only
  for pure presence checks.
- **`de158b0` fix(checker): flow-narrow value-Maybe array index on assignment LHS** — real gap:
  `a[i] = v` with `i` a value-Maybe wasn't narrowed (`leftPartOfAsgn>0` suppressed narrowing for the
  whole LHS incl. the index READ).
- **Two `{unknown,null}` fixes, same family** (both `/trace-nim`, Nim `options.nim` SomePointer split):
  1. **codegen borrow** (`statements.ms isUnionNarrowing`, DIVERGE-UNINTENTIONAL): `const a =
     map.get(k) as unknown` emitted `void** a = &(get_call())` → "address of rvalue". A nilable pointer
     collapses to bare `void*` with NO tagged storage to borrow. Fix: return false when
     `unwrapRefNullUnion(srcType) !== null`. Genuine tagged-DU narrowing untouched (emit-C byte-identical).
  2. **checker diagnostic** (`checkExprPass.ms:1389`, DIVERGE-INCOMPLETE): `unknown|null as <fat value>`
     slipped the value-shape diagnostic (inspected only bare `unknown`) → cryptic clang error. Fix: peel
     `unwrapRefNullUnion` first (mirrors `:1951`/`:2858`).
  Guards `nilableUnknownAsCast.ms` + `src/test/handoff/nilableUnknownCastError.ms`.
  Repro `/tmp/unkas.ms` — **✅ as of 2026-07-25 late.**

### 2026-07-22 — `memo` GREEN (bug C + the nullable-fn family) ✅ DEPLOYED

- **bug C — `throw new Error(msg)`** (`7202674` + `3b57979`). Not a Nim divergence — MS's exception
  runtime is string-based by design. Added std `class Error { message }` (checker-only aid) +
  `genThrowStmt` erases `new Error(arg)` → `msThrow(arg)`. Catch-side `e.message` remains a separate
  deferred gap (§2).
- **Root B — `substituteStruct` dropped Maybe identity** (`ba6b365`). Rebuilding a substituted Maybe via
  generic `createStruct` lost `IsMaybe` + kept the stale `T` name → `isMaybeType` false → guard
  `f !== null` folded constant-true + `f(x)` called a struct. Fix: route Maybe rebuilds through
  `createMaybeType`. **DIVERGE-UNINTENTIONAL → SAME** (Union was already canonicalized; Struct was the
  outlier). Guard `maybeIdentitySubst.ms` (`2f039bd`).
- **gap-1/gap-2 — call-site Maybe-coercion for Function args** (`f1061e0` + `b5977f8`). The coercion loop
  skipped Function args; the generic call-site wrap stamped the RAW formal. Nim `implicitConv`
  (sigmatch.nim:2179) always uses the INSTANTIATED formal. **DIVERGE-INCOMPLETE → SAME.**
  ⚠ **SCOPE:** proven for memo's shape only (optional `equals = null`, T bound from `fn: () => T`,
  untyped arrow params). The GENERAL "pass an arrow to a generic `Maybe<fn>` param" is NOT solved —
  the two `nullfn_*` probes in §2 are what's left.
- **inline arrow not lifted in wrapper positions** (`eafbc8b` + guard `4e6733d`). `walkLift` had an
  ad-hoc arm list + a no-op `_ => {}` default, so an inline arrow inside a call held by ANY wrapper
  (MemberExpr method chain, ternary, index, `as`-cast, **NewExpr**) was never walked → codegen
  `0 /* unlowered ArrowFunction */` → C `msClosure ← int`. Fix: default → `mapChildren(node, walkOrLift)`,
  the analog of Nim `liftCapturedVars` (lambdalifting.nim:511). **DIVERGE-UNINTENTIONAL → SAME.**
  → **This also fixed the "arrow-in-`new`-arg not lowered" sub-bug: `/tmp/mono_fn.ms` now BUILDS
  (verified 2026-07-25 late).** Probe `probe/nullfn_generic_arg_notlowered.ms` ✅.
- **LAYER 2 — contextual arrow param typing peels Maybe** (checker-only, `checkAnonymousFunction`).
  Earlier mis-filed as "R1 generic erasure"; a four-cell localization proved it is the **Maybe wrapper**,
  orthogonal to generics:

  | formal shape | arrow params | result |
  |---|---|---|
  | bare `fn` (non-generic) | typed `double` | ✅ |
  | bare `fn` (generic `T`) | typed `double` | ✅ |
  | `fn \| null` (non-generic) | **`void*`** | ❌ |
  | `fn \| null` (generic `T`) | **`void*`** | ❌ |

  Root: the gate `expectedType.kind === TypeKind.Function` on BOTH the contextual param-type source and
  the contextual return-type fallback. A `fn | null` formal is a Maybe struct (`IsMaybe`, inner in
  `typeReturn`), not `Function` → untyped arrow params fell to `unknown` → `void*`. Fix: peel the Maybe
  before both gates. **DIVERGE-INCOMPLETE → SAME.** Guard `maybeArrowParamContext.ms`.
  NIM-REF §1 "Contextual arrow param/return typing peels Maybe".

### 2026-07-21 — type-identity, cross-module generics, closures ✅ DEPLOYED

- **Structural type-dedup keys.** `X | null` lowers to `Maybe<X>`; the cache key collapsed EVERY
  function to `"p"+kindOrdinal`, so `(()=>number)|null` and `((v:number)=>void)|null` both became
  `Maybe_p22` → `setter` inherited `getter`'s arity-0. Proof: single nullable-fn field PASSES,
  non-nullable PASSES, two different-arity nullable fields COLLIDE. Fix: structural fn key
  (`params+return`) in `maybeCacheKey` + checker `typeKey` + codegen `anonFieldKey`.
  **DIVERGE-UNINTENTIONAL** (our own codegen `typeKey` already keyed functions structurally).
- **`monoTypeKey` sibling** (`e771cb9`) — same collapse at the generic-monomorph dedup level:
  `Function => "function"` + anon `Union => "union"` fused distinct instantiations to one mangled
  symbol. fn-collapse was BENIGN (`msClosure` uniform, arity applied at call site) but union-collapse
  was a REAL miscompile (incompatible `msUnion` payloads fused). Nim parity `sameInstantiation`.
  NIM-REF §1 "Structural type-dedup keys".
- **CompState_Clean** (`8e41629`) — enum member lost across cross-module generic instantiation. The
  checker rewrites `E.M` → mangled Identifier `E_M` whose name is deliberately never in scope, so
  `resolvedSym` is its ONLY resolution path; instantiation dropped it at 2 sites. Fix: preserve
  `EnumMember` resolvedSym in `clone.ms copyNodeMeta` (DRY-hoisted to apply in BOTH Mono+Check) +
  `instantiate.ms clearCheckerState` guard. Nim parity `freshGenSyms` (seminst.nim:100-118).
- **bug E — generic instance-method `void*` erasure** (`f3751dd`). `context.ms buildExportInfo` gated
  method `declNode` carriage on `methodIsStatic && isGenericFn(method-own-flags)`, but an instance
  method's genericity comes from the class `<T>` via `this`. Fix: `methodCarriesMonoBody(symType) =
  hasGenericParams(symType)` at both primary+overload gates.
  ⚠ **Correct for its own case but clears 0 Neon files** — `counter` fails on the array-ELEMENT path
  (§1 #5), not method dispatch.
- **bug D — nested-closure write-loss** (`1d1f710` + `584b2da`; unblocked `dispose`). An outer closure
  that both captures a parent-scope local AND contains a nested closure snapshotted that var BY VALUE
  into each intermediate env (copy-cascade) → inner-closure writes hit the copy and were lost.
  **DIVERGE-UNINTENTIONAL** (Nim never copies: one storage slot, `up`-chain walk, `accessViaEnvParam`,
  lambdalifting.nim:529). Fix = up-chain in `lambdaLifting.ms`: skip ancestor field+copy, wire `$up`,
  compile-time ancestor chain, `rewriteNode`/`chainWalkAccess`/`rewriteOuterRef` walk N `$up` hops;
  `$up` typed owning `Ref<parentEnv>` so escaping closures don't dangle. Rejected the Ptr-promotion
  band-aid (`EnvPromotedPtr` — a 2nd mechanism duplicating `chainWalkAccess`; not Nim).
  NIM-REF §1 "Lambda lifting: ancestor captures".
- **assert syntax** — `assert cond, "msg"` (comma) is current; the `assert expr : "msg"` colon form was
  STALE, never a missing feature. Neon's 14 test files migrated (147 asserts) + committed (`f61a059`).

---

## §6 — Passing, don't break

`signal`, `element`, `host`, `hostOps`, `reconcile`, `reconcileHard`, `renderToString`, `terminal`,
`dispose`, `memo`, `region`, `counter` — **12 files green** (`region` 2026-07-25, `counter`
2026-07-26 — both on not-yet-deployed compiler fixes; the installed `msc` still shows 10). The reactive core + render layer are solid;
re-run them on every compiler deploy. Two of the last three compiler fix attempts were caught by
exactly this suite and not by the battery (the rejected void-callback inference fix regressed 7 of
these while the battery stayed clean at 3330/7) — **the Neon suite is a stronger gate than the
battery for closure/inference work.**
