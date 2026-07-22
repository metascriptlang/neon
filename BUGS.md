# Neon — Compiler Bug Tracker

TODO + context for the compiler/framework bugs blocking the Neon test suite.
**One bug ≈ one focused session.** Compiler bugs use the `/trace-nim` workflow
(the recompiler is a port of Nim's compiler — trace each divergence to root,
classify DIVERGE-INTENTIONAL vs UNINTENTIONAL against `recompiler/docs/NIM-REF.md`,
fix by returning to Nim's model; never work around).

**Toolchain:** self-hosted `msc` in `$PATH` (currently **v0.2.27**).
- Rebuild compiler: `cd ~/metascript/recompiler && rm -rf out && msc build src/index.ms --gc=drc --danger --cc=clang --output=msc`
- Deploy: `./tools/sync-local-binary.sh`  (Neon consumes msc via `$PATH`)
- Battery (regression gate): `rm -rf out && msc test src/index.ms` — baseline **3330 pass / 7 fail**; the 7 are known float-precision / Windows-path / LSP-timing flakes (path.ms, literals.ms, expressions.ms, suggest.ms, lifecycle.ms). No-regression = exactly these 7.
- Recompiler rule: **never commit `docs/*`** (NIM-REF.md rows stay uncommitted).

---

## ✅ Fixed (2026-07-21 — committed + deployed, msc v0.2.27)

Two cross-module generic-instantiation blockers. Each was traced to root via
`/trace-nim`, verdict DIVERGE-UNINTENTIONAL, battery 3330/7 no-regression.

- **CompState_Clean** — enum member lost across cross-module generic instantiation.
  `recompiler` commit `8e41629`. Root: checker rewrites `E.M` → mangled Identifier
  `E_M` whose name is deliberately never in scope, so `resolvedSym` is its ONLY
  resolution path; generic instantiation dropped it at 2 sites (Mono-clone branch +
  `clearCheckerState`). Fix: preserve `EnumMember` resolvedSym in `clone.ms`
  `copyNodeMeta` (DRY-hoisted to apply in BOTH Mono+Check) + `instantiate.ms`
  `clearCheckerState` guard. Nim parity = `freshGenSyms` (seminst.nim:100-118) carries
  non-gensym syms by reference. NIM-REF.md §1 "Enum member repr & generic-instantiation survival".

- **Generic instance-method void\* erasure (bug E)** — instance method of a generic
  class used cross-module → struct `Cell__int32` emitted but `c.set()`/`c.get()` bound
  to erased `Cell_set(Cell__unknown*, void*)` → C `void*` vs `int32` mismatch
  (`counter.test` `assigning to void*`). `recompiler` commit `f3751dd`. Root:
  `context.ms buildExportInfo` gated method `declNode` carriage on
  `methodIsStatic && isGenericFn(method-own-flags)`, but an instance method's
  genericity comes from the class `<T>` via `this`, not its own flags. Fix: DRY helper
  `methodCarriesMonoBody(symType) = hasGenericParams(symType)` at both primary+overload
  gates (single export chokepoint; import side copies gate-free).
  NIM-REF.md §1 "Generic method cross-module monomorphization".

- **bug D — nested-closure write-loss** (blocked `dispose`). Outer closure that both
  captures a parent-scope local AND contains a nested closure snapshotted that var BY
  VALUE into each intermediate env (copy-cascade) → inner-closure writes hit the copy,
  lost. **DIVERGE-UNINTENTIONAL** (Nim never copies: one storage slot, `up`-chain walk,
  `accessViaEnvParam` lambdalifting.nim:529). Fix = up-chain, `lambdaLifting.ms` only.
  Commits `1d1f710` (skip ancestor field+copy; wire `$up`; compile-time ancestor chain;
  `rewriteNode`/`chainWalkAccess` walk N `$up` hops) + `584b2da` (`rewriteOuterRef` also
  chain-walks — `return c` at the closure's own scope was miscompiling; `$up` typed
  owning `Ref<parentEnv>` so escaping closures don't dangle). Rejected the Ptr-promotion
  band-aid (`EnvPromotedPtr` — 2nd mechanism duplicating `chainWalkAccess`; not Nim).
  Verified: repro `c=1`, `dispose.test` 4/4, 2-level escaping stress bad=0 (SIGTRAP before
  owning `$up`), battery 3323/14 = known-flake only, 0 closure-area regress. Deployed.
  NIM-REF.md §1 "Lambda lifting: ancestor captures".

---

## ✅ Suite runs again — assert syntax migrated (2026-07-21, session 4)

Earlier this file said `assert expr : "msg"` blocked the whole suite. **RESOLVED, and it
was never a missing feature:** the assert syntax *changed* to `assert cond, "msg"` (comma;
recompiler parser `743f446`/`2eb19c8`). The colon form was the STALE one. Neon's 14 test
files were migrated (147 asserts colon→comma) + committed (`f61a059` — 4 tracked files;
10 untracked new tests held back until green). **Suite ran 7 PASS / 8 FAIL** on msc v0.2.27
when this was written; `terminal` (Neon-side) + `dispose` (bug D) + **`memo`** have since been
FIXED → **now 10 PASS / 5 FAIL** (memo GREEN 2026-07-22 via bug C + the nullable-fn-in-generic
family — see the two ✅ sections directly below).

**Verified (clean rebuild, no cache):** installed msc ≡ `rm -rf out` rebuild from HEAD —
both 7/8, `/tmp/mrepro.ms` fails both, 8-byte size delta = build nondeterminism only.
Compiler self-build ≈ **23s** (282 modules). ⇒ every FAIL below is on the LATEST compiler.

**⚠ bug E (`f3751dd`) is committed but clears 0/8 Neon — the "Fixed" claim above is
unverified.** It was committed while the parse wall hid the suite. With the wall gone,
re-run shows it fixes NONE of the Neon fails: `counter` still fails `void* ← msString`,
but via `msGenericArrayPush` (array-element erasure) — a DIFFERENT path than the
instance-method dispatch f3751dd fixed. So **counter is OPEN** (folded into the R1 /
generic-erasure family below), not fixed. f3751dd may still be correct for its own
`Cell<T>.set()` cross-module case — it just isn't on Neon's blocking path.

---

## ✅ Fixed 2026-07-22 — `memo` GREEN (bug C + nullable-fn-in-generic family)

All traced via `/trace-nim`, battery **3330/7** no-regression. The recompiler checker/codegen
fixes are **committed AND deployed** (msc v0.2.27 — `memo.test` 275/275 GREEN on the installed msc).
NIM-REF.md §1 rows written (uncommitted per docs rule).

- **bug C — `throw new Error(msg)`** (recompiler `7202674` feat + `3b57979` test). Not a Nim
  divergence — MS's exception runtime is string-based by design. Added std `class Error { message }`
  (checker-only aid) + `genThrowStmt` erases `new Error(arg)` → `msThrow(arg)`. Catch-side `e.message`
  is a SEPARATE deferred gap (object-carrying exceptions); memo only throws, never catches.
- **Root B — `substituteStruct` dropped Maybe identity** (recompiler `ba6b365`). Rebuilding a
  substituted Maybe via generic `createStruct` lost `IsMaybe` + kept the stale `T` name → `isMaybeType`
  false → guard `f !== null` folded constant-true + `f(x)` called a struct. Fix: route Maybe rebuilds
  through `createMaybeType`. **DIVERGE-UNINTENTIONAL → SAME** (Union case already canonicalized; Struct
  was the outlier). Guard `recompiler src/test/guard/maybeIdentitySubst.ms` (`2f039bd`).
- **gap-1/gap-2 — call-site Maybe-coercion for Function args** (recompiler `f1061e0` + `b5977f8`
  default-arg fix). Coercion loop skipped Function args; generic call-site wrap stamped the RAW formal.
  Nim `implicitConv` (sigmatch.nim:2179) always uses the INSTANTIATED formal. Fix: defer generic Maybe
  formals in the loop; reconciliation re-coerces with the substituted formal. **DIVERGE-INCOMPLETE → SAME.**
  This closed R1's old `Maybe_fn… is not a function` nullable-call blocker (crossed out below).

**⚠ SCOPE:** gap-2 proven for **memo's shape only** (optional `equals = null`, T bound from
`fn: () => T`'s return, untyped arrow params). The GENERAL "pass an arrow to a generic `Maybe<fn>`
param" is NOT solved — see the two open siblings under R1 (`nullfn_*` probes).

## ✅ Fixed 2026-07-22 — inline arrow not lifted in wrapper positions (was mis-filed as `nullfn_generic_arg_notlowered`)

**Reframe:** `probe/nullfn_generic_arg_notlowered.ms` was NOT a Maybe/generic bug. A bare
non-nullable non-generic `g(x => …).toString()` fails identically. Root: lambda-lifting's `walkLift`
had an ad-hoc arm list (Call/Binary/Unary/Object/Array) + a **no-op `_ => {}` default**, so an inline
arrow inside a call held by ANY wrapper — MemberExpr (method chain), ternary, index, `as`-cast — was
never walked → codegen `0 /* unlowered ArrowFunction */` → C `msClosure ← int`. (A variable-bound
arrow escaped — VariableDecl WAS handled.)

- **Fix** (recompiler `eafbc8b`): `walkLift` default now `mapChildren(node, walkOrLift)` — uniform
  child traversal, the analog of Nim `liftCapturedVars` else `for i in 0..<n.len` (lambdalifting.nim:511).
  Restores symmetry with MS's DETECTION pass, which was already uniform. **DIVERGE-UNINTENTIONAL → SAME.**
  Guard `recompiler src/test/guard/inlineArrowMemberLift.ms` (`4e6733d`, proven RED on the deployed
  pre-fix binary → build error). Battery 3323/14 = known-flake only. NIM-REF §1 "Lambda lifting:
  uniform child traversal".
- **⚠ NOT DEPLOYED YET** — recompiler HEAD is currently **broken to self-build** (parallel session's
  actor I18/I19: `runtime/actor/actor.c` uses undefined `msPidSlot`/`msHazardRec`). `eafbc8b` is gated
  green on base `2f039bd` (independent of actor) but can't be rebuilt/deployed until actor is fixed.
- **Likely also fixes** the R1 "arrow-in-`new`-arg not lowered" sub-bug (same walk gap, NewExpr fell to
  the no-op default) — verify after deploy.
- **⚠ LAYER 2 revealed (NEW, open — next session, R1 family):** for the GENERIC probe, the arrow now
  lifts but its `(a,b): T` params erase to `void*` → `dollarfn_main_1_(void* a, void* b)` → `void* != 0.0`
  C error. This is generic arrow-arg param-type non-substitution (R1 erasure). `probe/nullfn_generic_arg_notlowered.ms`
  still RED at this layer. Repro also: capturing-arrow variant.

## TODO — per-file compiler bugs (independent; take one per session)

### open siblings of the nullfn family (checker; NOT on any Neon test's path; probes in `probe/`)
- **`probe/nullfn_bindorder.ms`** — `apply((v:number)=>v+1, 10)` binds T=int32 from arg 1, overriding
  the arg-0 arrow. Nim `paramTypesMatchAux` binds progressively IN ARG ORDER → T=number. Do NOT fix by
  loosening the exact-match wrap gate (masks the divergence). Checker unify-order bug.
- **`probe/nullfn_explicit_targ.ms`** — `apply<number>((v:number)=>v+1, 10.5)` → arrow checked against
  the RAW pre-substitution formal → type degenerates. Needs check against the INSTANTIATED formal
  (Nim `implicitConv`/`getInstantiatedType`). Checker.
- **layer-2 void\* erasure** (above) — generic arrow-arg param-type not monomorphized. R1 family.

### ~~bug C — `throw new Error(...)` / no `Error` type → blocks `memo`~~ ✅ FIXED 2026-07-22 (`7202674`+`3b57979`, deployed) — see ✅ section above. Historical detail kept below.
- **Symptom:** `in instantiation of 'createMemo<int32>': Undefined variable 'Error'`;
  earlier surface `memo.ms:27 passing 'Error*' to param of incompatible type 'msString'`.
- **Root:** MetaScript has no `Error` type. `genThrowStmt` (recompiler
  `src/codegen/c/statements.ms:596`) emits `msThrow(<arg>)` assuming a string;
  `new Error(msg)` fabricates an incomplete `Error*`. `new Error` being undefined is
  non-fatal during imported-generic instantiation → garbage C reaches clang.
- **Fix (HIGH):** in `genThrowStmt`, when the arg is `new Error(...)`, emit
  `msThrow(<first string arg>)`; add a minimal std `class Error { message: string }` so
  the checker resolves it (closes the non-fatal downgrade). Option 2 (later) = Nim-parity
  object-carrying catchable exceptions.
- **Note:** `memo` needs C **AND R1** — besides `throw new Error`, it hits `Maybe_fn… is not a
  function` on the nullable `equals()` call (R1 nullable-Maybe-call family below; the OLD
  `Maybe_p22` name in earlier notes is FIXED — that was the type-identity collision, this is a
  DISTINCT nullable-call unwrapping gap). bug E (`f3751dd`) does NOT help it (clears 0/8). So memo
  stays red until both C and R1-nullable-call land.
- **Repro:** isolated `function main(): void { throw new Error("x"); }` — or
  `msc test tests/core/memo.test.ms` once assert:msg lands.

### R1 — generic instantiation erases function/closure type-info → blocks `array`, `region`, `counter` (~~+ memo's 2nd error~~ — memo GREEN 2026-07-22)
**STATUS: PARTIAL — 2 of ~6 sub-bugs closed this session (2026-07-22). Type-identity root done; 5 open sub-bugs below + 2 new found.**

- **✅ SUB-BUG FIXED 2026-07-21 (structural type-dedup keys):** the `probe/r1_arity_min.ms`
  "expected at most 0, got 1" was a **type-identity collision**, NOT a lambda-lifting bug — the
  KEY-CORRECTION note below was WRONG. `X | null` lowers to `Maybe<X>`; the cache key collapsed
  EVERY function to `"p"+kindOrdinal`, so `(()=>number)|null` and `((v:number)=>void)|null` both
  became `Maybe_p22` → `setter` inherited `getter`'s arity-0. Empirical proof: **single** nullable-fn
  field PASSES, **non-nullable** PASSES, **two different-arity** nullable fields COLLIDE. Fixed in the
  recompiler (structural fn key `params+return` in `maybeCacheKey` + checker `typeKey` + codegen
  `anonFieldKey`; NIM-REF §1 "Structural type-dedup keys"). Verdict DIVERGE-UNINTENTIONAL (our own
  codegen `typeKey` already keyed functions structurally). Battery 3323/14 = known-flake only.
  ⚠ **Landed in the recompiler tree, NOT yet deployed** (live tree holds a parallel session's WIP;
  rebuild/deploy deferred to avoid bundling it). The Neon R1 files stay RED on the OTHER sub-bugs
  the fix exposed underneath (closure-local scope `undeclared 'list'/'g'`, `as`-cast malformed C,
  array-element `void*` erasure, `Maybe_fn… is not a function` nullable-call).
- **✅ SIBLING FIXED 2026-07-21 (`monoTypeKey`, recompiler `e771cb9`):** the same collapse at the
  generic-monomorph dedup level — `Function => "function"` + anon `Union => "union"` fused distinct
  instantiations to one mangled symbol. Proven via repro: fn-collapse (`Holder<()=>number>` vs
  `Holder<(x)=>void>`) was BENIGN (ran correct — `msClosure` uniform, arity applied at call site),
  but union-collapse (`Box<number|string>` vs `Box<boolean|number>`) was a REAL miscompile
  (incompatible `msUnion` payloads fused). Structural key fixes both; battery 3323/14 clean. Path
  back to Nim (`sameInstantiation`) confirmed SAFE. See NIM-REF §1 "Structural type-dedup keys".
- **NEW sibling bugs found during the repro (independent, still open):**
  - **union ctor-param proto/def indirection:** a generic class ctor with a union param emits
    `_init(…, msUnion* v)` (definition, by-pointer) vs `msUnion v` (forward decl, by-value) →
    `conflicting types`. Present pre-fix; unmasked by the monoTypeKey split. Repro `/tmp/mono_union.ms`.
  - **arrow-in-`new`-arg not lowered:** `new Holder<…>(() => 42)` emits
    `Holder__…_init(_new_, 0 /* unlowered ArrowFunction */)` → `passing 'int' to msClosure`. The
    arrow literal in a constructor arg skips closure lowering. Repro `/tmp/mono_fn.ms`
    (function-typed *var* args work — `/tmp/mono_fn2.ms`).
    **→ LIKELY FIXED by `eafbc8b`** (uniform `walkLift` child traversal — NewExpr was another kind
    falling to the old no-op default; same root as the inline-arrow-lift ✅ section above). VERIFY
    after deploy; the generic case may still hit layer-2 void\* param erasure.
- **Symptom:** array → `mapArray<number, number>: Too many arguments: expected at most 0, got 1`;
  region → `mapArray<number, unknown>: Argument 0: cannot pass value type number as unknown`;
  counter → `void* ← msString` via `msGenericArrayPush` (array-element erasure);
  memo → `Maybe_p22 is not a function` on the nullable `equals()` call.
- **ISOLATED (2026-07-21) — durable minimal repros in `probe/` (0 Neon imports):**
  - `probe/r1_arity_min.ms` (13 lines, **NON-generic**) → `Too many arguments: expected at
    most 0, got 1` at `cell.setter(n)`, where `setter: ((v:number)=>void)|null` is assigned
    from a generic-tuple destructure (`const [g,s]=createSignal(0)`) inside one sibling
    closure and CALLED after `!== null` narrowing in another. Also emits broken C (`expected ')'`).
  - `probe/r1_undeclared_s.ms` (10 lines) → a NEARBY-but-DISTINCT bug: same shape, destructure
    guarded differently → C references the closure-local `s` out of scope (`use of undeclared
    identifier 's'`).
  - **~~KEY CORRECTION (WRONG — superseded by the ✅ SUB-BUG FIXED note above):~~**
    ~~genericity of the enclosing fn is **NOT** required (non-generic repro fails identically).~~
    ~~So this is a **closure / lambda-lifting lowering bug** — a function value from a~~
    ~~destructured generic-tuple, stored in a nullable-fn field, shared across SIBLING~~
    ~~closures, loses its signature — NOT a generic-monomorph erasure. Closer to **bug D**'s~~
    ~~neighborhood than to CompState/bug-E.~~ `createSignal` source is necessary: a plain-arrow
    setter (probe `m5`) PASSES; single-closure variants (q1-q3, r1, r3) PASS.
- **~~Related but likely DISTINCT sub-bugs (STALE label — f3751dd note still valid):~~**
  ~~counter `void*` via `msGenericArrayPush` (array-element erasure), memo `Maybe not a function`~~
  ~~(nullable call), flow `Unresolved T`. ≥2-3 roots, not one.~~ **f3751dd (method dispatch) clears
  NONE — verified 0/8.** Old B1 (nested named fn) / B2 (`.slice` arity) labels are STALE.
- **OPEN sub-bugs remaining (after this session's 2 fixes):**
  - **closure-local scope loss** — `undeclared 'list'` (array), `undeclared 'g'` (region). The
    nullable-fn fix exposed this underneath; likely a lambda-lifting/`$up` issue (bug-D neighborhood).
  - **`as`-cast malformed C** — `(cell.getter as () => number)()` emits
    `double (*(msClosure*)&(…getter))(void);` (expected `)`). Distinct codegen bug, pre-existing.
  - **array-element `void*` erasure** — counter `void* ← msString` via `msGenericArrayPush`.
  - ~~**`Maybe_fn… is not a function` nullable-call** — memo's 2nd blocker.~~ ✅ FIXED 2026-07-22
    (Root B `substituteStruct` + gap-2 reconciliation — `ba6b365`/`f1061e0`; see ✅ section above).
  - **`Unresolved T`** — flow (separate section below).
- **Repro:** `/tmp/mrepro.ms` (isolated, reconstruct from shape above);
  `msc test tests/core/array.test.ms` · `tests/render/region.test.ms` · `tests/render/counter.test.ms`.

### Unresolved type `T` → blocks `flow`
- **Symptom:** `in instantiation of 'For<number>': Unresolved type 'T' - missing ...`.
- **Status:** NOT root-caused this session. Same neighborhood as CompState/bug E
  (generic-instantiation scope loss) but a DIFFERENT mechanism — a generic type param
  not substituted during instantiation (needs MORE resolution, not preservation). Do not
  assume the CompState/bug-E fixes cover it.
- **Repro:** `msc test tests/render/flow.test.ms`.

### Map value-type `.get(missing)` returns zero, not `null` (surfaced 2026-07-21 via terminal)
- **Symptom:** `Map<string,string>.get(absentKey)` returns `""` (string zero-value), NOT
  `null`, though the static type is `string | null`. `.has(absentKey)` is correct (false).
- **Impact:** any `if (m.get(k) === null)` presence check silently fails → wrong fallback.
  Hit Neon's terminal `getAttr` (Neon-side worked around with `.has()`). Likely affects all
  value-type V (number/bool) — container returns the zeroed slot instead of the Maybe null.
- **Repro:** `probe/mapget_missing_returns_empty.ms` (`m.get("nope") === null` → false, value `""`).
- **Fix (compiler):** `get` on a missing key must yield the Maybe null, not the value-type
  zero. Same "value-type in generic container" family as the R1 notes.

### loop + nested-closure snapshot broken (PRE-EXISTING — found during bug-D audit)
- **Symptom:** a closure created **inside a loop** that BOTH captures a loop-body local
  AND contains a nested closure returns wrong counts. Repro `/tmp/loopesc.ms`
  (`for i { let c=0; const step=()=>{ const inc=()=>{c=c+1}; inc(); return c }; arr.push(step) }`):
  after 50 calls each expects 51, gets ~4; independent counters cross-contaminate.
- **NOT a bug-D regression:** verified against `7a936b0` (pre-fix) — old gives `c0:4 c1:3`,
  new `c0:4 c1:0`; BOTH wrong. Non-nested loop closures are correct in both. No UAF (exit 0).
- **Root (suspected):** loop-escape wants a per-iteration SNAPSHOT of `c`, but a loop
  closure containing a nested closure still goes through `setupSharedEnv`; the up-chain
  reaches a shared slot instead of the per-iteration one. Old copy-cascade snapshotted the
  value (but lost writes = bug D); up-chain shares (but breaks per-iteration independence).
  Separate from bug D — needs per-iteration env identity for loop + nested closures.
- **Repro:** `/tmp/loopesc.ms` vs `/tmp/loopsimple.ms` (non-nested, correct).

---

## Non-compiler (Neon-side / environment)

- **terminal** — ✅ **FIXED 2026-07-21 (Neon-side).** Was `two short text in row = 1 line`.
  Two fixes in `src/platform/terminal/paint.ms`: (1) tag `"row"` now defaults flexDirection to
  row (previously only the explicit attr did); (2) `getAttr`/`getAttrNum` guard with `.has(name)`
  because of the Map `.get`-missing bug above (old `v === null` fallback never fired). Now 284/284.
- **voidHost** — `sokol_gfx.h file not found`. Native dependency / build environment
  (Void host + sokol). Not a compiler issue.

---

## ✅ Passing — don't touch
`signal`, `element`, `host`, `hostOps`, `reconcile`, `reconcileHard`, `renderToString`,
`terminal`, `dispose`, `memo` (10 files green). The reactive core + render layer are solid; guard them on every change.

Remaining RED (5): `array`, `region`, `counter` (R1 generic-erasure family), `flow` (Unresolved T), `voidHost` (env/sokol).
