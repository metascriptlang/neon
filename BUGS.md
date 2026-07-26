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

## Toolchain — VERIFIED 2026-07-26 (post-deploy)

| what | value | how verified |
|---|---|---|
| installed compiler | `~/.metascript/bin/msc` **v0.2.27**, built Jul-26 20:32 from `85519a2` (synced binary + std + runtime + vendor) | `msc --version`, `ls -la`, sync log |
| recompiler HEAD | `85519a2` (main) — `src/` + `std/` clean of session work; pre-existing leftovers: `docs/*` + editor-plugin dirty, untracked `src/test/native/run.ms`, `std/process/*`, `ctorExtProtocol*` | `git status --porcelain -- src std` |
| binary ≡ HEAD? | **yes** — built from HEAD post-merge, then `sync-local-binary.sh` | Neon suite 12/3 on `$PATH` msc |
| **battery** | **3338 pass / 0 fail** (162/162 files, self-hosted gen-1 on `85519a2`, ~4.4m). Installed-msc measure pre-merge: 3337/1 (path.ms only) | `cd ~/metascript/recompiler && rm -rf out && msc test src/index.ms` |

**Battery flake reality (2026-07-26):** the old 7-flake set is GONE (suggest ×2 + literals/expressions
fixed by `e7fdf29`/`22805ea`). Current intermittents seen on `a9c0ae6`-lineage: `std/fs/path.ms`
"join Windows absolute b wins" ×1 and the `lifecycle.ms` phase5/6 hover/sig-help block ×9 (LSP
timing — present on one pristine run, absent on the next two). Both hit ZERO in the final gate runs.
Diff any battery failure against these two groups before claiming regression.

- Rebuild compiler: `cd ~/metascript/recompiler && rm -rf out && msc build src/index.ms --gc=drc --danger --cc=clang --output=msc`
- Deploy: `./tools/sync-local-binary.sh` (Neon consumes msc via `$PATH`)
- Recompiler rule: **never commit `docs/*`** (NIM-REF.md rows stay uncommitted).

---

## §1 — CURRENT STATE (measured 2026-07-26, `rm -rf out` PER FILE, all 15 test files)

**Neon suite = 14 pass / 1 fail — every compiler-blocked file is GREEN; the only red is `voidHost`,
which is an ENVIRONMENT gap (`sokol_gfx.h` absent), not a compiler or framework bug.**
⚠ Measured with the WORKTREE binary `/tmp/rc-flow/msc` (base `85519a2` + this session's five fixes),
`msc test <file>` per file with a clean `out/`. The `$PATH` msc is still the Jul-26 20:32 build and
will reproduce the OLD failures until `./tools/sync-local-binary.sh` runs — **deploy is owed**.
⚠ Protocol: `rm -rf out` BETWEEN files is load-bearing — sequential `msc test` runs sharing `out/`
produced spurious compile failures (reconcile/reconcileHard flip-flopped until cleaned).

| file | result | file | result |
|---|---|---|---|
| `core/signal` | ✅ | `core/array` | ✅ **NEW 2026-07-26 (late)** |
| `core/memo` | ✅ | `render/flow` | ✅ **NEW 2026-07-26 (late)** |
| `core/dispose` | ✅ | `render/counter` | ✅ **NEW 2026-07-26** |
| `render/element` | ✅ | `render/voidHost` | ❌ (env — sokol) |
| `render/host` | ✅ | | |
| `render/hostOps` | ✅ | | |
| `render/reconcile` | ✅ | | |
| `render/reconcileHard` | ✅ | | |
| `render/renderToString` | ✅ | | |
| `render/region` | ✅ **NEW 2026-07-25** | | |
| `platform/terminal` | ✅ | | |

### Issue count: **0 open on Neon's path + 1 env (voidHost) + 7 compiler debts off-path**

Five roots closed on 2026-07-26 (late) in one session: #2 #3 #4 (+ the ref-truthiness layer under #4)
#6 #7. Four were compiler bugs, #7 was Neon's own. Every one had been mis-framed in this file before
it was traced — see §5 for the corrected mechanisms.

### The roots that used to block `array` / `flow` — all closed (voidHost is §3/env)

| # | root | blocks | exact error (measured) |
|---|---|---|---|
| ~~1~~ | ~~void-callback inference~~ | ~~`region`, `array`~~ | ✅ **CLOSED 2026-07-25 — and the framing was WRONG.** The root was never inference: `genAssertStmt` emitted a bare `return;`, ill-formed C in any non-void function. A concretely-typed **non-generic** arrow failed identically. See §5. |
| ~~2~~ | ~~`Array<function>` method surface~~ | ~~`array`, `flow`~~ | ✅ **CLOSED 2026-07-26 (late) — framing wrong AGAIN: nothing to do with generics or instantiation.** The C-backend array prelude (`std/core/array/index.cms`) hand-specialized the full 16-method surface for `number[]` and `string[]` but gave the generic `T[]` block only push/pop/at/setLength/capacity/splice — **`slice` (and indexOf/includes/concat/reverse/sort/fill/join/shift/count) simply did not exist for any other element type.** A bare non-generic `let ds: (() => void)[]` failed identically; `number[]`/`string[]` passed. The JS prelude (`index.jms`) had declared the whole surface generically all along, and std itself carried a workaround (`websocket/frame.ms:203` `sliceBytes`, comment "number[] doesn't have built-in slice"). Fixed `33dca18`. See §5. |
| ~~6~~ | ~~generic ctor instance not emitted~~ | ~~`flow`~~ | ✅ **CLOSED 2026-07-26 (late).** Not a drain/ownership bug: `instantiateClassConstructor` bailed on `classSym.declNode.kind !== ClassDecl`, and an IMPORTED class symbol carries the **ImportDecl** — so EVERY cross-module `new Generic<T>()` was skipped silently, no instance ever queued, while codegen still emitted the call + a forward decl → `undefined symbol` at link. It only ever looked fine when the defining module happened to instantiate the same specialization itself (why `Signal<number>` linked and `Signal<boolean>` did not). See §5. |
| ~~7~~ | ~~compiler internal error~~ | ~~`array`, `flow`~~ | ✅ **CLOSED 2026-07-26 (late) — NOT a compiler bug at all.** `msc build` succeeds; the error comes from the PRODUCED BINARY at runtime. `indexArray`'s `makeRowInto` did `mapped[pos] = …` into an empty array — index-store past the end RAISES in MetaScript (Nim `IndexDefect` semantics), it does not grow the array as JS would. Its sibling `mapArray` in the same file had always pre-sized with `new Array(newLen)`. Neon-side fix: append via `push`, stores passed as parameters (mapArray's shape). See §5. |
| ~~3~~ | ~~Unresolved-T through generic wrapper~~ | ~~`flow`~~ | ✅ **CLOSED 2026-07-26 (late) — and instantiate.ms was the WRONG neighborhood: the root is the PARSER.** Explicit `<T, string>` lives in a single `state.pendingTypeArg` slot consumed by the NEXT CallExpr to FINISH parsing — a nested call in the argument list (`props.each()`) finishes first and steals it, so the outer call's AST `typeArg` stays empty forever. Checker re-checks of instantiated generic bodies then fall back to the location-keyed side channel (`findCallTypeArg` fallback), which still holds the PRE-substitution string → `resolveAnnotation("T")` in a scope with no T. Concrete-arg calls never noticed (the stale side-channel string is already concrete — "accidentally right"). Fix: capture the slot at parseCallExpr ENTRY. See §5. |
| ~~4~~ | ~~optional field `fallback?` lowering~~ | ~~`flow`~~ | ✅ **CLOSED 2026-07-26 (late) — TWO pre-existing roots under one symptom, neither was "Maybe lowering".** (a) The anon-object-type STRING parse (`resolvePass.ms` `{...}` branch) kept the `?` glued to the field name (`"fallback?"`) — member reads missed, literal excess-key check missed, C anon struct had no `fallback`. The interface TOKEN path had discarded the `?` token all along (`?` is cosmetic: no missing-field check exists on ANY path; omitted field = zero-init/NULL). Fix: strip trailing `?`, parity with the token path. (b) LAYER 3, exposed the moment (a) cleared: `wrapTruthiness` (`stringTruthiness.ms`) had NO Ref arm — `if (fb)` on a class/interface value fell into the syntactic string fallback → C `->byteLength` on a non-string struct (`if (!fb)` was never affected: UnaryExpr short-circuits). Pre-existing and fully general (bare `const v: VN; if (v)` failed). Fix: Ref arm → `!== null`. See §5. |
| ~~5~~ | ~~array-element `void*` erasure~~ | ~~`counter`~~ | ✅ **CLOSED 2026-07-26 — framing WRONG twice over.** Not an array bug, not codegen: the `element` MACRO spliced the literal string `"on"` (the ARGUMENT of `startsWith`) where the `<button>` subtree belonged, because macro bodies compiled with UNTYPED params and every flat Node-field read dispatched blind in the VM. The msString-into-`void*` clang error was where the corpse landed. See §5 2026-07-26. |

**⚠ The #3/#4/truthiness fixes are COMMITTED on recompiler `main` (`bbc2e3c`, `c41f1a3`, `6422400` — one
root + its guard each, ff-merged from worktree `/tmp/rc-flow`) but NOT YET DEPLOYED** — the installed
`$PATH` msc is still the Jul-26 20:32 build of `85519a2` and still shows the old #3/#4 signatures.
Until `./tools/sync-local-binary.sh` runs, reproduce with the worktree binary `/tmp/rc-flow/msc`.
Measurements below are all worktree-msc with `rm -rf out` per file: guards 3× proven RED on installed → GREEN on worktree;
battery `msc test src/index.ms` = **3338/3338 (162/162, 0 fail)**; Neon suite = **12/3** with `flow`'s
error moved to #2 exactly. (`msc test src/test/index.ms` fails 74 type errors on BOTH installed-pristine
and worktree — stale aggregator, pre-existing, not a session regression; handoff guards gate standalone.)

**Nothing left on Neon's path.** Next actions are (1) DEPLOY the five fixes (`./tools/sync-local-binary.sh`
after rebuilding msc from main) and re-measure the suite on the `$PATH` binary, (2) the `voidHost`
environment (§3), (3) the off-path compiler debts in §2 — which gained one sibling this session:
**ctor-param proto/def indirection for struct/array type args** (`new GcCell<CmgTag>({…})` emits
`_init(…, CmgTag*)` but passes the literal by value; same family as the known union-param mismatch,
pre-existing, only reachable now that cross-module ctors instantiate at all).

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

### ~~#2 — `Array<function>` method surface (`array`)~~ ✅ CLOSED 2026-07-26 (late), `33dca18` — see §5

Historical framing below is superseded; the root was a std C-backend surface gap, not a generic-instantiation
or method-resolution bug. Kept for the `b057320` lineage note only.



Post-`b057320` a `U[]` annotation with U=function correctly stays an **Array** (see §5) — but that
array's **method surface** is missing: `indexArray<number, function>` → `Property 'slice' does not
exist on type 'Array'`. Direct sibling of the `b057320` fix, one layer further in.
Repro: `msc test tests/core/array.test.ms`.
(Historical note: the older `.slice(0)` **arity** complaint was NOT a compiler bug — std `slice`
requires `(start,end)`; fixed Neon-side in `src/core/array.ms`. This is a different, real gap.)

### ~~#3/#4 — `flow` (`For<T>` / `Index<T>` / `Show`)~~ ✅ CLOSED 2026-07-26 (late) — see §5; `flow` now blocked by #2 only

Three compiler roots fell in one session (parser typeArg steal, anon `?` parse, ref truthiness —
details in the roots table above + §5). `flow`'s sole remaining error is #2's `.slice` surface via
`indexArray<number, unknown>`. Repro unchanged: `msc test tests/render/flow.test.ms`.
The old "instantiate.ms neighborhood" guess was wrong — nothing in instantiation needed fixing;
`replaceTypeVars` had ALWAYS substituted AST-resident `typeArg` correctly (instantiate.ms:369) —
the parser simply never put the string on the right node when args contained a nested call.

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
| **struct/array ctor-param indirection** (NEW 2026-07-26 late) | `new GcCell<CmgTag>({ label: "x" })` / `new GcCell<number[]>([1,2,3])` from an importing module | ❌ `passing '__anon1__label' to parameter of incompatible type 'CmgTag *'` — the ctor's declaration takes the type arg BY POINTER while the call site passes it by value. Same family as the union row above; pre-existing, but only reachable since #6 made cross-module ctors instantiate at all. Excluded from the #6 guard on purpose (documented inline there). |
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

**2026-07-26: the green render layer LANDED** (`cd4b535..4731735` — array/memo/reconcile/
host+node+dom/render-tests/docs/build, 7 commits split by concern). Still uncommitted, ON PURPOSE:

- `src/macros/ui/flow.ms` (M) + `tests/render/flow.test.ms` — bug #3/#4 WIP, next session's subject.
- `src/platform/void/` + `tests/render/voidHost.test.ms` — void-host WIP, env-blocked (§3).
- `probe/` — scratch probes (referenced by §5 entries; `macro_disambig`/`macro_lenval` keep
  deliberate RED bracket-tests, `macro_narrow` N1 = Nhịp-2 marker).
- `deps/` (vendored yoga clone — vendoring is its own task), `docs/EDITOR*.md` (design scratch).

**Preserve these.** flow/void are blocked by open roots, not broken.

---

## §5 — Fixed (history + root-cause ledger, append-only)

### 2026-07-26 (late) — #6 closed: cross-module `new Generic<T>()` never instantiated its constructor ⚠ NOT YET DEPLOYED

**The symptom was a linker error; the cause was a silent `return` in the checker.** Probe ladder
(`/tmp/p6*`): same-module `new Sig<T>()` GREEN; cross-module RED for **every** type argument
(number/string/boolean/array/interface — so not a type-repr issue); cross-module generic **function**
GREEN (so not the drain, not DCE, not the `HasConstructor` flag); and the decisive pair — cross-module
RED **unless the defining module itself instantiates the same specialization**, in which case the
importer links against the definer's copy. Instrumenting the compiler printed the mechanism directly:
`[CTOR] Sig__boolean_new existingSym=N declNode=kindImportDecl` — `instantiateClassConstructor`
(`instantiate.ms`) bails on `classSym.declNode.kind !== NodeKind.ClassDecl`, and an imported class
symbol's `declNode` is the **ImportDecl**. No instance was ever queued (confirmed: the pending-instance
drain printed nothing for the ctor while it printed the generic function), yet codegen still emitted
the call plus a forward declaration — so the build "succeeded" and the linker took the blame.

**Verdict: two divergences, one intentional and one not.** Dropping ClassDecl at the export boundary is
DELIBERATE and documented (`checker/context.ms`: shipping class decls makes the importer re-resolve
member types in its own scope and pollute the type registry). Nim has no such problem because
`generateInstance` copies the AST straight off the generic symbol (`seminst.nim` `copyTree(fn.ast)`) and
adds the producer as a friend module — the instantiator can always reach the source. MS kept the
restriction but never wired the ctor path to the alternative route: **DIVERGE-UNINTENTIONAL**, fix
inside the intentional constraint.

**Fix (1 file, +14/−2):** ask the class's DEFINING module for the real declaration via
`pickBodyCtx(classSym.modulePath, ctx)` — the `_moduleCtxMap` registry whose own comment cites Nim's
`graph.ifaces[module]` lookup, and which **this same function already used 73 lines below** to re-check
the constructor body. Renamed imports resolve through `originalName`. When the registry has no ctx
(fallback returns the caller's), behaviour is exactly as before — no regression path.

**Empirical confirmation in the emitted C:** the defining module's TU went from *nothing* to
`void GcCell__boolean_init(GcCell__boolean* this, MS_BOOL v) { … }` (so the instance also survives that
module's DCE — the one downstream risk worth checking), and the importer's forward declaration now
carries `MS_BOOL` instead of `void*`.

**Guard:** `src/test/handoff/crossModuleGenericCtor.ms` + `fixtures/genericCtorLib.ms` — a specialization
only the importer asks for (boolean, string) plus the definer's own (number). RED pre-fix → GREEN.
Two shapes are deliberately excluded with a comment (struct and array type args): they fail on the
ctor-param proto/def indirection, a pre-existing sibling now reachable, tracked in §2.
**Gates:** battery **3338/3338**; Neon 12/3 with `flow`'s link error gone.

### 2026-07-26 (late) — #7 closed: NOT a compiler bug — `indexArray` index-stored past the end (Neon-side)

`Error: index 0 out of bounds (length 0)` looked like an msc internal crash. It is not: `msc build`
prints `Built 37 module(s)` and the message comes from the **produced binary**. `indexArray`'s
`makeRowInto` did `mapped[pos] = createRoot(…)` / `disposers[pos] = d` with the stores still empty.
**MetaScript follows Nim here: an index-store past the end raises (`IndexDefect`), it does not grow the
array the way JS does.** The sibling engine `mapArray`, in the same file, had always pre-sized with
`new Array(newLen)` before index-assigning — so the file itself contained the correct pattern.
This is Neon's bug, not a compiler limitation, and it was only reachable once #2 gave `.slice` to
closure arrays and the file got past the checker for the first time.

**Fix (Neon `src/core/array.ms`):** rows are only ever created at the tail, so `makeRowInto` appends
with `push` and takes the stores as parameters instead of capturing them — mirroring `mapArray`'s
`makeRowInto(item, pos, mapStore, dispStore, idxStore)` signature.
**Result:** `core/array` GREEN (280/280) and `render/flow` GREEN (278/278) — **Neon 14 pass / 1 fail**,
the remaining red being `voidHost`'s missing `sokol_gfx.h` (§3, environment).

### 2026-07-26 (late) — #2 closed: the C array prelude never had a generic `slice` ✅ COMMITTED `33dca18` (main) — ⚠ NOT YET DEPLOYED

**Not a generics bug, not a method-resolution bug — a std surface gap.** Probe matrix
(`/tmp/p2e`): `.slice` GREEN for `number[]` and `string[]`, RED for boolean/unknown/function/
interface/class/nested-array; `push`/`pop`/`splice` GREEN everywhere; a **non-generic** bare
`let ds: (() => void)[]` failed exactly like the generic case, killing the "instantiated
`Array<function>`" framing. Cause: `std/core/array/index.cms` hand-specializes 16 methods for
`number[]` and 16 for `string[]`, but its generic `T[]` block declares only push/pop/at/setLength/
capacity/splice — `slice`, `indexOf`, `includes`, `concat`, `reverse`, `sort`, `fill`, `join`,
`shift`, `count` exist for NO other element type. `index.jms` (JS backend) declares the full
surface generically, and std itself had already worked around the hole
(`std/core/websocket/frame.ms:203` `sliceBytes`, "number[] doesn't have built-in slice").

**Verdict DIVERGE-INCOMPLETE → follow Nim.** Nim's slice is a **generic proc, monomorphized per T,
copying element-wise via `=copy`** (`lib/system/indices.nim` HSlice family) — NOT hand-written
per-element-type C. MS already had that exact pattern one function below the gap:
`sortBy<T>(this arr: T[], cmp)` is an MS-bodied generic array extension in the same `.cms`.
Fix mirrors it — `slice<T>` with an MS body (clamp semantics copied from `msNumberArraySlice`:
negative counts from the end, `end` clamped to `len`, empty when `start >= end`), so **no new
runtime C function is needed** and the number/string externs still bind first (proven by a guard
assertion). **Runtime prerequisite confirmed empirically in the emitted C** — DRC injects Nim's
`=copy` on the element read:
`dollarborrow_0_ = msRefArrayAccess((*arr), i); msIncref(dollarborrow_0_); msGenericArrayPush(out_1_, dollarborrow_0_);`
so the source array keeps its reference and nothing double-frees.

**Guard:** `src/test/handoff/genericArraySlice.ms` — closure / interface / class / unknown /
boolean / nested-array slices, out-of-range clamping, source-array survival, plus a
number+string case pinning that the specialized externs still resolve. RED pre-fix (checker:
`Property 'slice' does not exist on type 'Array'`) → GREEN 6/6.

**Gates:** battery **3338/3338** (162/162); Neon suite **12/3** — `array` and `flow` now have
**zero checker errors**, which uncovered two masked roots recorded as #6 (flow: `undefined symbol
_Signal__boolean_init` at link) and #7 (array: msc internal `index 0 out of bounds`). An isolated
`indexArray`-shaped probe (generic + `.slice` on a closure array) builds and runs clean, so
neither new failure is caused by this fix. Changed: `std/core/array/index.cms` (+22),
`src/test/handoff/genericArraySlice.ms`, one index import.

### 2026-07-26 (late) — flow #3+#4 closed: THREE compiler roots, none where BUGS.md pointed ✅ COMMITTED `bbc2e3c`+`c41f1a3`+`6422400` (main) — ⚠ NOT YET DEPLOYED

**#3 "Unresolved-T" was a PARSER bug, not instantiation.** Probe chain (`/tmp/flowprobe/p3a-f`):
explicit-args + nested-call args RED; inferred GREEN; explicit CONCRETE args GREEN; no-call-site
GREEN (generic bodies only check at instantiation); explicit-args + bare-identifier args **GREEN —
the discriminator**. Mechanism: `state.pendingTypeArg` is a SINGLE parser slot consumed by the next
CallExpr to FINISH parsing (`call.ms` consumed it AFTER `parseExprList`), so any nested call inside
the argument list stole the outer call's `<T, string>`. The outer node's `typeArg` stayed empty; at
plain check time `findCallTypeArg`'s location-keyed side-channel fallback returned the same string
so concrete code was accidentally right; inside an INSTANTIATED generic body the side channel still
holds the pre-substitution text (`replaceTypeVars` substitutes only AST-resident `typeArg`,
instantiate.ms:369) → `resolveAnnotation("T")`, no T in scope (params are TEXT-substituted, not
scope-injected) → the 3× duplicate errors = 3 checker sites resolving the same stale string
(checkExprPass 2788/3013/3351). **Fix: capture the slot at `parseCallExpr` ENTRY** (before args) —
nested calls with their own explicit args still bind correctly (slot is set immediately before each
call's `(`). `f<T>(g<U>(x))` was double-broken pre-fix (inner overwrote, then consumed).

**#4 was TWO pre-existing gaps; "Maybe lowering" fears dissolved on probing.** (a) The anon-object
STRING parse (`resolvePass.ms` `{...}` branch) glued `?` to the field name → all three §1 error
shapes from one line. The interface TOKEN path (`parseInterfaceLikeDecl`) has always discarded the
`?` token — and probes proved the SEMANTICS already work end-to-end everywhere (literal may omit ANY
field on ANY path — no missing-key check exists; omitted = zero-init: ref → NULL, Maybe carrier →
present=false; `if (fb)` narrowing fine). Neon-Nim's own `fallback*: Option[string]` (types.nim:414)
confirms the intended semantics. **Fix: strip trailing `?` in the anon parse** — string path ==
token path. `?` remains cosmetic on both (de-facto spec; LANG.md silent — a docs line is owed).
(b) **Ref-truthiness root exposed the instant (a) cleared** (guard's class-field case went
`->byteLength` at C level): `wrapTruthiness` (`transform/coercion/stringTruthiness.ms`) had
type-aware arms for boolean/Maybe/value-struct/array but **no Ref arm** — a bare ref-typed
Identifier/MemberExpr condition fell into the legacy syntactic STRING fallback (`x.byteLength > 0`).
Fully general pre-existing bug (`const v: VN = mk(); if (v)` failed on installed msc, no `?`, no
anon type, no generics — probes p4g-j) that had simply never been written in compiler/battery code
(`!x` was immune: UnaryExpr is isAlreadyBoolean, C `!ptr` valid — only the POSITIVE bare form died;
Show's `if (fb)` on VNode is exactly that form). **Fix: Ref arm → `cond !== null`** before the
fallback (null-sentinel refs, NIM-REF §57 pointer model).

**Guards (all three proven RED on installed pre-fix msc → GREEN on worktree msc), registered in
`src/test/handoff/index.ms`:** `explicitTargGenericBody.ms` (RED = 6× Unresolved-T; covers the
nested-explicit steal too), `anonOptionalField.ms` (RED = 4 checker errors, value + ref-class
shapes), `refTruthiness.ms` (RED = C `byteLength` on struct VN/RtBox; iface local + class param +
anon-field read).

**Gates (worktree msc `/tmp/rc-flow`, base `85519a2`, 3 files changed):** battery
`rm -rf out && msc test src/index.ms` = **3338/3338, 162/162, 0 fail** (flakes absent); 14/14
probes GREEN (all prior-green stay green); Neon full suite (`rm -rf out` per file) = **12/3**:
same count as baseline but `flow`'s error MOVED to #2 (`indexArray<number, unknown>` `.slice`) —
#2 is now the single root behind both remaining compiler-red files. `msc test src/test/index.ms`
= 74 type errors on BOTH pristine-installed and worktree (stale aggregator, pre-existing).
Changed: `src/parser/expressions/call.ms`, `src/checker/resolvePass.ms`,
`src/transform/coercion/stringTruthiness.ms` (+3 guard files, +3 index imports).
Committed one-root-per-commit: `bbc2e3c` (parser), `c41f1a3` (checker), `6422400` (transform + the
three index registrations). **Deploy still owed** — run `./tools/sync-local-binary.sh` after a
`rm -rf out && msc build src/index.ms --gc=drc --danger --cc=clang --output=msc` from main, then
re-measure the Neon suite on the `$PATH` msc.
Landed as one commit per root: `bbc2e3c` (parser typeArg), `c41f1a3` (anon `?`), `6422400` (ref
truthiness + guard registrations). Deploy still pending — see the ⚠ note in §1.

### 2026-07-26 — `counter` GREEN: macro-VM flat Node reads were untyped ✅ COMMITTED `7158d9a`+`ed799b6`+`85519a2`, DEPLOYED same day

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

### 2026-07-25 (late) — assert exited via `return;`; test boundary never observed `msErr` ✅ (later committed `2a156ff`+`0d867fd`, deployed with the 2026-07-26 build)

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
`dispose`, `memo`, `region`, `counter` — **12 files green on the installed `msc`** (deployed
2026-07-26, verified post-deploy sweep). The reactive core + render layer are solid;
re-run them on every compiler deploy. Two of the last three compiler fix attempts were caught by
exactly this suite and not by the battery (the rejected void-callback inference fix regressed 7 of
these while the battery stayed clean at 3330/7) — **the Neon suite is a stronger gate than the
battery for closure/inference work.**
