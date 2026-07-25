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

## 🟢 LATEST (2026-07-25) — R1 inference core FIXED + committed; renderToString HANG attributed to HEAD

**All claims below are EMPIRICALLY VERIFIED this session (A/B binaries, controlled `rm -rf out`).**

### ✅ FIXED + COMMITTED (recompiler main, on top of `cb24df5`)
- `b057320 fix(monomorphize): parenthesize function type literal in annotation substitution`
- `c2a241e test(guard): U[] annotation with U bound to a function type stays an array`

**Root (via /trace-nim, DIVERGE-UNINTENTIONAL → SAME).** The long-hunted "R1 generic erasure"
(`mapArray<number, function>: expected Array, got function`) is an **operator-precedence bug in
STRING-based monomorphization**, not erasure. `substituteTypeStrings`/`substAnnotationAll`
(`checker/instantiate.ms`) substitute type-params **textually** then re-`resolveAnnotation`.
`monoConcreteTypeName` (`monomorphize/clone.ms:321`) emitted a Function as the BARE literal
`() => number`; into a `U[]` annotation that yields `"() => number[]"`, which re-parses as
`() => (number[])` — a FUNCTION, not `(() => number)[]` an Array. Nim never hits this: it
substitutes on PType **nodes** (`semtypinst`), no surface-syntax hazard. Fix = parenthesize the
function literal (`(() => number)`), the precedent already set for anon unions (`clone.ms:285-289`).
**1 line.**

**Empirical localization (6-cell, zero Neon imports):** collapse fires ONLY at
`local-var annotation` × `generic param` × `function type`. Return `U[]` ✅, param `U[]` ✅,
un-annotated local ✅, concrete `(()=>number)[]` ✅, `U[]` with U=number ✅ — only `const x: U[]`
with U=fn ❌. Probes: `probe/ufn_array.ms`, `probe/ufn_disc.ms`, `probe/ufn_base.ms`.

**Verified:** battery **3330 pass / 7 fail = known-flake set exactly, ZERO regression** (the change
touches every generic instantiation). Guard `recompiler src/test/guard/genericFnArrayAnnot.ms`
proven **RED on the pre-fix binary** ("expected Array, got function") → **GREEN** post-fix.
NIM-REF §1 row "Monomorph annotation roundtrip: parenthesize compound type literals" (uncommitted per docs rule).

**Latent siblings (same class, not yet Neon-blocking):** anon `Union` (`A | B`) and `Conditional`
literals are ALSO unparenthesized in `monoConcreteTypeName` → `U[]` with U=union/conditional
collapses identically. Fix when they surface.

### ✅ FIXED 2026-07-25 — `renderToString` HANG (was: try/finally swallowed every exception)

**Not a compiler hang — the COMPILED TEST BINARY spins forever.** Proven by sampling: `msc`'s main
thread sits in `cmdTest → execFile → __wait4` (waiting on its child); the child
`out/debug/_test_*.test` burns 100% CPU in `renderToString → msThrow → msMakeError → msAllocTyped`
— **an infinite re-throw loop**, allocating a fresh error object every iteration.

**Minimal repro (Neon-side, 11 lines): `probe/rts_b.test.ms`** — `try { renderToString(regionNode(…)) } catch (e) {}`.
`probe/rts_a.test.ms` (static tree, no throw) passes in 2s. Emitted C (`out/debug/…renderZnodeOms.c`):

```c
msString renderToString(VNode* n) {
  while (1) {                        // tail-recursion (`return renderToString(producer())`) → loop
    …
    msThrow(MS_STRING_LIT(…)); goto __catch_2;
    __catch_2: {
      msErr = MS_FALSE;              // SWALLOWS the in-flight exception
      msDiscardCurrentException();
      /* unsupported stmt: NullLiteral */   // ← intended handler body never codegen'd
    }
    __finally_2: { …decrefs…; if (msErr) goto BeforeRet_; }   // msErr is FALSE → never taken
  }                                  // falls off the loop body → back to loop head → throw again → ∞
  BeforeRet_: ; return (msString){0};
}
```

**Two compounding defects:** (1) a handler synthesized for a function with NO source-level try/catch
**swallows** a propagating exception (`msErr = MS_FALSE` + discard) instead of re-raising — the
`/* unsupported stmt: NullLiteral */` shows its body failed to generate; (2) with `msErr` cleared the
`goto BeforeRet_` guards can't fire, so the tail-call `while(1)` has **no exit on the exception path**
and loops back to the function entry. Either defect alone would break; together they spin.
The exception must reach the CALLER's `catch` (the test asserts `threw === true`).

**Attribution — bisected, decisive (all other files at HEAD, incl. the R1 fix):**
| build | `probe/rts_b.test.ms` |
|---|---|
| HEAD | **HANG** (>200s) |
| HEAD, `clone.ms` R1 fix reverted | **HANG** ⇒ NOT the R1 fix |
| HEAD, 3 throw-codegen `.ms` reverted to `164a58a` | **PASS 5s, 274/274** |
| Jul-24 backup binary (pre-throw-group) | **PASS 3s, 274/274** |

⇒ culprit = **`2974c6c` fix(codegen): bare catch releases the caught exception** (emits exactly the
`msErr = MS_FALSE; msDiscardCurrentException();` arm above, `src/codegen/c/statements.ms`) and/or
**`f14d2e2`** (`asyncBridge.ms`/`generatorLower.ms`). `ab1d87a` (runtime `msDiscardCurrentException`)
is NOT sufficient on its own — patching the `msDecref` out of the runtime did **not** stop the hang
(the swallow + loop-back is the driver, not the decref).
**FIXED** (recompiler, uncommitted) — STRUCTURAL, no sniffing: `hasCatchClause: boolean` added to
`TryCatchStmtData` + the inline `NodeData` arm (`std/meta/node.ms:364,586`); `makeTryFinally` vs
`makeTryCatch` constructors replace inference at all 6 creation sites; `clone.ms` carries it; BOTH C and
JS backends read it (the JS backend had the same swallow bug). Plus the
trailing `raiseExit` after the finally and the `__oldErr_<lab>` save/restore around the finally body
(Nim `oldNimErrFin`), plus the parser/`deferLower` absence sentinel unified with the DRC injector's.
Battery 3330/7, Neon 10 pass, `renderToString` 4s. Guard `src/test/guard/tryFinallyPropagates.ms`
proven RED→GREEN. NIM-REF §1 "Try/finally handler presence is structural".
**Superseded fix direction:** a synthesized cleanup handler must re-raise
(leave `msErr` set / `goto BeforeRet_` after cleanup), never clear it; and the tail-call `while(1)`
needs an unconditional exception exit.

### (superseded framing) — NOT caused by the R1 fix
Deploying HEAD (which this session did) made `renderToString` hang in codegen at
`std/meta/node.ms:500` (recursive `=destroy` of a self-referential owning type).
**A/B proven:** `msc-nofix` (HEAD with clone.ms reverted) and `msc` (HEAD+fix) BOTH hang at 200s;
the Jul-24 23:03 backup binary runs it in **4s exit 0**. ⇒ the hang comes from the commits between
that backup and HEAD — i.e. the parallel **throw/exception goto-codegen** thread, exactly the
`7c78dc0` symptom already documented below. The old note "installed msc does NOT hang on node.ms,
renderToString is green" is now **STALE/FALSE at HEAD**.
**Consequence:** Neon on the current deploy = 9 pass / 5 fail + renderToString HANG (was 10/5).
**Owner:** the throw-codegen thread — needs a bisect over that range. Neon can also pin the Jul-24
backup binary to get 10/5 back at the cost of losing `0e4c18a` + the R1 fix.

### ❌ REJECTED this session — void-callback inference (do NOT retry this way)
`createRoot((d) => { …; d(); })` infers **T = unknown → `void*`**, so the `assert` macro's
bare `return;` (valid only in a void C function) errors "non-void function should return a value"
(blocks `region`, and `array` after its first layer). Verified C: `static void* dollarfn_test1_2_(msClosure d)`;
mono instance `run__unknown`. Minimal repro `probe/voidcb2.test.ms` (12 lines, zero imports).
**Attempted fix** (`checkAnonymousFunction`, `checkExprPass.ms:5133`): block body + `inferredRet == Unknown`
→ return `voidType()` (Nim parity: `returnType == nil` IS void). **Battery stayed clean 3330/7 —
but it REGRESSED 7 previously-green Neon tests** (host, hostOps, reconcile, reconcileHard,
renderToString, terminal, dispose). **Reverted.**
**Why it's wrong:** `inferredReturn === Unknown` conflates "body has NO return statement" with
"body HAS returns whose type didn't resolve"; the latter previously landed on permissive `unknown`
and now got forced to strict `void`. A correct fix must **syntactically scan the block for return
statements** (not descending into nested fn bodies) and only then infer void. **Also note** T=void
then requires void-generic instantiation support — `createRoot__void` emits
`const result = fn(dispose)` → C `void result = …` invalid ("assigning to void* from incompatible
type void"). That's a second, larger feature (Nim discards void). Budget both before retrying.

### Current per-red blockers (measured on HEAD+fix, post-R1-fix)
| red | blocker now | root |
|---|---|---|
| `array` | `Property 'slice' does not exist on type 'Array'` for `Array<function>` (+ void-callback) | closure-array method surface |
| `region` | `createRoot((d)=>{…})` "should return a value" | void-callback (see REJECTED above) |
| `flow` | `Unresolved type 'T'` + `'fallback' does not exist in type ''` | generic T substitution + Show props |
| `counter` | `void* ← msString` at `counter.test.ms:33` | array-element erasure |
| `voidHost` | `sokol_gfx.h not found` | Neon-side env, not compiler |

**The "one root behind all 4 reds" framing below is REFUTED** — these are 3 distinct compiler roots
plus one env issue.

---

## 🟢 LATEST (2026-07-24 late) — R1 closure-scope-loss FIXED + committed

**Done this session (recompiler `main`, 2 commits on top of `276308a`):**
- `0e4c18a fix(transform): walkExpandBlocks descends into expression-position fn bodies`
- `164a58a test(guard): destructure lowering reaches expression-position arrows`

**Root (via /trace-nim, verdict DIVERGE-INCOMPLETE → SAME, grounded in `transf.nim` + NIM-REF row 76):**
the R1 **closure-scope-loss** (`undeclared 's'/'g'/'list'/'items'`) was NOT a `$up`/lambda-lift bug — it
was `const [a,b]=f()` **destructuring inside an arrow in EXPRESSION position** (var-init / capturing /
call-arg) never lowered, because `walkExpandBlocksHooked` (`transform/walker.ms`, shared by 9 desugar
passes) had a no-op `_ => {}` default that skipped expression-position fn bodies. Fix = default →
`mapChildren` uniform recurse (direct sibling of the `eafbc8b` walkLift fix). Independent of lifting.
Guard `recompiler src/test/guard/destructureInArrowLower.ms` (RED pre-fix = undeclared a/b in all 3 arrow
positions, GREEN drc+orc). NIM-REF row "Statement-expansion walk: uniform child traversal" (uncommitted).

**⚠ CORRECTIONS to the stale notes below:**
- **True battery baseline on this machine = `3321 / 16`, NOT 3330/7.** Verified: installed msc (clean)
  and msc-local (fix) give the BYTE-IDENTICAL 16-fail set (5 flake files: path/literals/expressions/
  suggest/lifecycle). No-regression = diff the `×` fail lines vs a clean run, don't trust 3330/7.
- The R1 **"closure-local scope loss (undeclared list/g)"** open sub-bug below is now **FIXED** (this fix).
- **slice-arity** (array/region `.slice(0)`) was NOT a compiler bug — std builtin `slice` requires
  `(start,end)`. Fixed **Neon-side** in `src/core/array.ms` (`.slice(0)`→`.slice(0,len)`), UNCOMMITTED
  (lives with the held render WIP).
- The "2 async blockers (7c78dc0/a8dabb9)" READ-FIRST framing below is STALE — the throw session committed
  well past them (main now `276308a`+); installed msc (built today) does NOT hang on `node.ms`,
  `renderToString` is green.

**✅ DEPLOYED 2026-07-25** — rebuilt recompiler HEAD `164a58a` (283 modules, 22s) +
`./tools/sync-local-binary.sh`. Installed `msc` now carries the closure-scope-loss +
walkExpandBlocks fix. Verified: suite = **10 pass / 5 fail** on the deployed binary (the fix
landed but greened 0 Neon files — each red hits a DEEPER root underneath, captured below).

**NEXT — precise current errors per red (2026-07-25, on the DEPLOYED post-fix `msc`). The
"one root behind all 4" hope is REFUTED — 3 distinct compiler roots + 1 env:**

| red | exact error | root (distinct) |
|---|---|---|
| `array` | `instantiation of 'mapArray<number, function>': Return type mismatch in '<arrow>': expected Array, got function` + C `msClosure ← msRefArray`/`msClosureArray ← msClosure` (array.ms:66/67/72/80) | **U bound to a function type; `U[]` erases to bare `function`** (array-of-function loses its array wrapper during instantiation) |
| `flow` | `instantiation of 'For<number>': Unresolved type 'T'` + `'fallback' does not exist in type ''` (flow.ms:71/72, `msAnon_*` / `void*` member) | **Unresolved-T** (T not substituted through `For<T>`→`mapArray<T,HostNode>`) + Show-props `fallback?` optional-field lowering |
| `region` | `non-void function 'dollarlifted_test1_7_' should return a value` ×5 (region.test:30-38) | **lifted `createRoot((d)=>{… return …})` loses its return** — lambda-lifting emits the lifted arrow `void` but body returns U |
| `counter` | `assigning to 'void *' from incompatible type 'msString'` (counter.test:33) | **array-element `void*` erasure** (`msGenericArrayPush`) |
| `voidHost` | `sokol_gfx.h file not found` | Neon-side env/sokol — NOT a compiler bug |

`array` and `flow` share the `mapArray<T,U>` generic path (highest leverage — fix both together).
Each remaining root = one focused `/trace-nim` session on checker `instantiate`/inference +
lambda-lifting. Recommended order: **mapArray U-erasure (array+flow)** → region lifted-return →
counter element-erasure. `voidHost` is Neon-side.

---

## 🔴 CURRENT STATE — READ FIRST (2026-07-24, end of session) — ⚠ SUPERSEDED, see 🟢 LATEST above

**One-line:** Map.get **and** HashMap.get are fully flipped to `V | null` and committed to
recompiler main. Deploying the new `msc` to Neon is **BLOCKED by 2 async-session compiler
bugs** — fix those first (in recompiler). Neon is pinned to the OLD Jul-22 baseline = **10 pass / 5 fail**.

### ✅ Committed to recompiler main (this session) — Map.get/HashMap.get migration DONE
- `901a849` boolean arrays → `msUint8Array`
- `b8d43fa` `hash(unknown)` via `msPtrHash` — unblocks `Map<unknown,*>` keys (render layer needs it)
- `0a3da84` add missing `maybeUnwrap.ms` (healed a broken HEAD: imported by tracked `transform/index.ms` but untracked)
- `42a799c` **`HashMap.get` returns `V | null`** (`Map.get` already flipped at `8c69ffa`)
- `de158b0` **fix(checker): flow-narrow value-Maybe array index on assignment LHS** — a real compiler gap: `a[i] = v` where `i` is a value-Maybe wasn't narrowed (`leftPartOfAsgn>0` suppressed narrowing for the whole LHS incl. the index READ). Fix resets `leftPartOfAsgn=0` around the ArrayAccess index check (`checkExprPass`).
- `1754f7f` migrate ~14 bare `HashMap.get` callers to `!== null` / `??`
- `6a6ec45` migrate 8 `as X` `HashMap.get` callers (symbol.ms lookup×3, cparse typedefs/tags/macros×5)

Idiom (settled): **`!== null` narrow (ref) / `?? default` (value) / hoist `const e=arr[i]` for LHS-index writes — NEVER `as X`** (unsafe non-null assertion that defeats the whole flip). `.has()` kept only for pure presence checks; every migrated site was a `.has()`+`.get()` double-lookup collapsed to one. Battery **3330/7** clean (verified on a base WITHOUT the 2 async bugs below).

### 🚨 BLOCKER — 2 async-session compiler bugs on main (fix FIRST, in recompiler)
Full brief + repros + fix plan: **`~/metascript/recompiler/HANDOFF-throw-codegen.md`** (untracked).
Both from the goto-based throw/exception codegen work (all "Son Le" author — same machine, different work-thread):
1. **`7c78dc0` "goto-based throw propagation to enclosing catch" → COMPILER HANG** when generating the recursive `=destroy` of a self-referential owning type (`std/meta/node.ms:500`). **BISECTED:** `c15b7da` (=`7c78dc0~1`) GOOD (0.6s), `7c78dc0` HANG, `ca911c0` HANG. **This is what blocks `renderToString`** and Neon deploy — NOT the Map.get flip.
2. **`a8dabb9` "propagate unhandled raises to BeforeRet_ epilogue"** → `use of undeclared label 'BeforeRet_'` breaks std `serialize/json/{stringify,builder,parser}.ms` + `core/websocket/*`. Emits `goto BeforeRet_` in more sites than it declares the label.

### ⚠ Shared install `~/.metascript` is CONTENDED
The compiler session actively `sync`-deploys to it — **don't trust the current install**. First thing a fresh session must do: re-establish a coherent `msc` (ideally the compiler-session's fixed build once the 2 bugs above land).
- Neon **10/5 baseline** = binary `~/.metascript/bin/msc.bak-1784792656` (Jul-22) + **struct-D**
  = `git show d8f3028:std/core/struct.ms` (in recompiler) with the 2 `msPtrHash`/`hash(unknown)` lines inserted after `hash(this i: int32)`. Copy binary + std to `~/.metascript/`, restore `vendor/{argon2,mbedtls,miniz,monocypher}` from the recompiler tree. Verify `msc test tests/render/host.test.ms`.

### 🧩 Neon render feature WIP (uncommitted in the NEON repo) — SEPARATE, don't confuse
7 modified + several untracked files implement **Components + For/Index/Show + list-region reconcile**:
`src/render/{node,host}.ms`, `src/macros/ui/flow.ms` (For/Index/Show), `src/platform/browser/dom.ms`
(insertBefore/removeChild/nextSibling), `src/core/memo.ms` (glitch-free memo + `equals`), `build.ms`
(std/build API) + untracked `src/render/reconcile.ms`, `src/core/array.ms`, `tests/render/{region,flow,reconcile,reconcileHard,...}.test.ms`. **Real, coherent, valuable feature** — blocked by the R1 + flow compiler bugs below (code is written, `msc` can't compile it yet). **Preserve it; finish in a fresh Neon session AFTER the compiler is stable.** Not committed yet (needs review + green).

### Neon suite: still **10 pass / 5 fail** on the Jul-22 baseline
RED = `array`, `region`, `counter` (**R1** generic-erasure family), `flow` (**Unresolved-T**), `voidHost` (env/sokol). These are the remaining COMPILER bugs for Neon green — see R1 + flow sections below. Map.get/HashMap.get is DONE and does **not** green these (never was their blocker).

### Suggested order for the next sessions
1. **recompiler session** (already active on `main`, HEAD past mine): fix `7c78dc0` + `a8dabb9` per HANDOFF → coherent deployable `msc`.
2. Then a recompiler session on **R1** (array/region/counter) + **flow Unresolved-T** — the actual Neon-green blockers.
3. Then a **fresh Neon session**: deploy the coherent `msc`, finish the Component/For/Show WIP, drive `region`/`flow` green, commit the render feature.

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
- **⚠ STILL NOT DEPLOYED** (as of 2026-07-22) — the actor self-build blocker is now CLEARED (recompiler
  HEAD self-builds clean in ~22s; the actor spawn-rule commits landed on top of `eafbc8b`). But the
  recompiler WORKING TREE still holds a parallel session's uncommitted WIP (boolean-arrays → `msUint8Array`
  across `codegen/c/types.ms` + `transform/native/{builtinLower,hcrLift}.ms` + `std/core/struct.ms`
  `hash(unknown)`/`msPtrHash`). Deferred deploy so as not to ship their unfinished work. All layer-2 work
  below was developed + verified against a local `./msc-local` build, NOT the installed msc.
- **Likely also fixes** the R1 "arrow-in-`new`-arg not lowered" sub-bug (same walk gap, NewExpr fell to
  the no-op default) — verify after deploy.

## ✅ Fixed 2026-07-22 — LAYER 2: contextual arrow param typing peels Maybe (was mis-filed as R1 generic erasure)

**REFRAME (the earlier "layer-2 = generic arrow-arg param-type non-substitution / R1 erasure" was WRONG).**
Four-cell localization with body-forcing arrows (`(a,b) => (a!==0.0)===(b!==0.0)`, which forces `a` to a
concrete type) proved it is NOT generic-specific and NOT R1 erasure:

| formal shape | arrow params | result |
|---|---|---|
| bare `fn` (non-generic) `pA2` | typed `double` | ✅ builds |
| bare `fn` (generic `T`) `pC2` | typed `double` (T substituted) | ✅ builds |
| `fn \| null` (non-generic) `pB2` | **`void*`** | ❌ `void* != double` |
| `fn \| null` (generic `T`) `pD2` / the probe | **`void*`** | ❌ `void* != double` |

So the trigger is the **Maybe/nullable wrapper**, orthogonal to generics. Root: `checkAnonymousFunction`
(`checker/checkExprPass.ms`) gated BOTH the contextual param-type source AND the Bug-G contextual
return-type fallback on `expectedType.kind === TypeKind.Function`. A `fn | null` formal is a Maybe struct
(`IsMaybe`, inner in `typeReturn`), not `Function`, so untyped arrow params fell to `unknown` → `void*`.
- **Fix** (recompiler, checker-only, `checkAnonymousFunction`): peel a Maybe (`isMaybeType` → `typeReturn`)
  into `fnExpected` before both gates. **DIVERGE-INCOMPLETE → SAME** (parity with MS's own bare-`fn` path).
  Guard `recompiler src/test/guard/maybeArrowParamContext.ms` (RED pre-fix = `void*/double` on non-generic
  + generic nullable-fn arrows, GREEN post-fix). Battery **3330/7** = known-flake set exactly.
  NIM-REF §1 "Contextual arrow param/return typing peels Maybe". Sibling of the memo/gap-2 SCOPE note.
- **Effect:** `probe/nullfn_generic_arg_notlowered.ms` now BUILDS + RUNS `true` (both the lift layer from
  `eafbc8b` and this param-type layer are closed). Does NOT green `array`/`region`/`counter` alone — those
  fail earlier on their own sub-bugs (slice-arity, `Return type mismatch expected Array got function`,
  `void*←msString`). **⚠ NOT committed/deployed yet** — see the deploy note above.

## TODO — per-file compiler bugs (independent; take one per session)

### open siblings of the nullfn family (checker; NOT on any Neon test's path; probes in `probe/`)
- **`probe/nullfn_bindorder.ms`** — `apply((v:number)=>v+1, 10)` binds T=int32 from arg 1, overriding
  the arg-0 arrow. Nim `paramTypesMatchAux` binds progressively IN ARG ORDER → T=number. Do NOT fix by
  loosening the exact-match wrap gate (masks the divergence). Checker unify-order bug.
- **`probe/nullfn_explicit_targ.ms`** — `apply<number>((v:number)=>v+1, 10.5)` → arrow checked against
  the RAW pre-substitution formal → type degenerates. Needs check against the INSTANTIATED formal
  (Nim `implicitConv`/`getInstantiatedType`). Checker.
- ~~**layer-2 void\* erasure** — generic arrow-arg param-type not monomorphized. R1 family.~~ ✅ FIXED
  2026-07-22 (was NOT generic/R1 — the Maybe wrapper stripping contextual param typing; see ✅ section above).

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
- **⭐ Context 2026-07-24:** `mapArray`/`indexArray` (the arity + array-element `void*` erasure source)
  are now CONSUMED by the Neon render WIP `src/macros/ui/flow.ms` (`For<T>`/`Index<T>`) — impl in the
  untracked `src/core/array.ms`. `array`/`region` test `mapArray` directly; `flow` hits it through the
  generic `For<T>` wrapper (→ **same code path as the flow `Unresolved-T` bug**; see the flow section).
  Fix R1 + flow together — one is the direct call, the other the generic-wrapped call of the same
  `mapArray<T, HostNode>`.

### Unresolved type `T` → blocks `flow`  ← likely the cleanest NEXT Neon-green target (after 7c78dc0/a8dabb9)
- **Symptom:** `in instantiation of 'For<number>': Unresolved type 'T' - missing ...`.
- **Status:** NOT root-caused. Same neighborhood as CompState/bug E
  (generic-instantiation scope loss) but a DIFFERENT mechanism — a generic type param
  not substituted during instantiation (needs MORE resolution, not preservation). Do not
  assume the CompState/bug-E fixes cover it.
- **Repro:** `msc test tests/render/flow.test.ms`.
- **⭐ Context from the 2026-07-24 (Map.get) session — the actual code `For<number>` instantiates:**
  The `For<T>`/`Index<T>`/`Show` impl now EXISTS (Neon WIP, uncommitted, `src/macros/ui/flow.ms`).
  `For<T>` ≈ `regionNode((h) => { const mapped = mapArray<T, HostNode>(props.each, (item, idx) =>
  renderNode(props.children(item, idx), host)); ... })`. So T flows: `each: () => T[]` →
  `mapArray<T, HostNode>` → the region thunk. **This means `flow` (Unresolved-T) and R1's
  `mapArray<…>` arity/erasure bugs are the SAME code path** — `flow.ms For` → `mapArray` (impl in
  untracked `src/core/array.ms`). Fix them together; `region.test`/`array.test` exercise `mapArray`
  directly, `flow.test` exercises it through the generic `For<T>` wrapper.
- **⭐ Narrowing / value-Maybe machinery map (learned this session — if T-resolution touches Maybe/nullable):**
  - Generic instantiation / T substitution: `recompiler src/checker/instantiate.ms` (Nim `seminst`
    analog); CompState/bug-E fixes were `clone.ms copyNodeMeta` + `context.ms buildExportInfo` gates.
  - `!== null` narrowing: `src/checker/flow.ms` → `narrowByLiteralEquality` → `removeNullFromType`
    (ALREADY peels Maybe via `unwrapMaybeType`, line ~996). Truthiness path at line ~839.
  - Value-Maybe read unwrap (codegen side): `src/transform/coercion/maybeReadMaterialize.ms` (retypes
    a narrowed read to its carrier + wraps `.value`); JS-strip in `src/transform/native/maybeUnwrap.ms`.
  - Assignment-LHS narrowing gate: `checkExprPass.ms` uses `leftPartOfAsgn>0` to suppress narrowing on
    the assignment target; the index sub-read is exempted (commit `de158b0`, reset around the
    ArrayAccess index check). Reusable pattern for "read-in-lvalue-position" narrowing bugs.

### Map `.get` → `V | null` (TS-Optional flip) + value-type Maybe unwrap — ✅ COMMITTED to recompiler main, NOT deployed (2026-07-23)
- **Original framing (WRONG):** "`Map.get(missing)` returns zero not null — compiler bug."
  Traced via `/trace-nim`: the OLD `get<K,V>(): V` returning `null as unknown as V` is
  **Nim `Table.getOrDefault`** (zero on miss, presence via `.has()`) — correct by that contract,
  and the emitted C proves the call site typed `.get()` as plain `V` (not `V|null`), so
  `x === null` constant-folds to `false` for value types. The static-type claim was empirically
  false. Neon's terminal already uses `.has()` (right for getOrDefault).
- **Decision:** flip to **JS/TS-Optional** `get(): V | null` (matches TS/Rust/Swift; Nim's own
  `Option[T]` is model-compatible — NIM-REF §1 pointer-model row). DIVERGE-INTENTIONAL.
- **Done + proven (committed to recompiler main `8c69ffa..dd80ebc`):**
  - std `Map.get: V → V|null` (return real `null`); compiler self-build needs only **4 fixes**
    in `symbol.ms` (`as Symbol` at `has()`-guarded returns). Battery 3330/7. Perf: self-build
    19.9s vs ~22s baseline (box `{value,present}` is a fixed constant, no atomics).
  - **Value-type Maybe unwrap operators shipped in the compiler** (needed to *use* the result):
    `as T` (nullableLower rule 1c), `?? d` (checker inferBinaryOp), postfix `!` (parser +
    TypeAssertion sentinel `"!"`). Guard `recompiler src/test/guard/maybeValueUnwrap.ms`
    (RED pre-fix, GREEN post-fix). NIM-REF §1 "Value-type Maybe unwrap operators".
  - Repro `probe/mapget_missing_returns_empty.ms` now prints `missing === null : true`.
- **Neon effect:** flip + unwraps → suite stays **10/5 → 9/6** only because of the OPEN gap below
  (reconcile.test); framework code (`reconcile.ms` uses `as number`) is fixed by rule 1c.
- **✅ FIXED 2026-07-23 (committed to recompiler main) — reconcile.test unknown-borrow + checker fat-value diagnostic.**
  Two fixes, SAME family ("nilable-union `{unknown,null}` slips past a check that only inspects bare
  `unknown`"), both traced via `/trace-nim` (read Nim `options.nim` SomePointer split this session).
  - **(1) codegen borrow** (`statements.ms isUnionNarrowing`, DIVERGE-UNINTENTIONAL): `const a =
    map.get(k) as unknown` emitted `void** a = &(get_call())` → clang "address of rvalue". Root:
    `isUnionNarrowing` gated the VarDecl storage-borrow arm (`${cType}* v; v=&(init)`) on
    `srcType.kind === Union` — TRUE for a pointer-collapsed `unknown|null` too, but a nilable pointer
    collapses to bare `void*` (row 57) with NO tagged storage to borrow. Fix: `isUnionNarrowing`
    returns false when `unwrapRefNullUnion(srcType) !== null`. Now `void* a = get_call()` (value).
    Genuine tagged-DU narrowing untouched (emit-C `msc-b ≡ baseline` byte-identical). The earlier
    "value-copy void* var inits from rvalues" hypothesis was directionally right; this is the precise
    site.
  - **(2) checker diagnostic** (`checkExprPass.ms:1389`, DIVERGE-INCOMPLETE, found while proving
    fail-loud): `unknown|null as <fat value>` slipped the value-shape diagnostic (which inspected only
    bare `unknown`) → cryptic clang error instead of the clean "cannot cast unknown to value type".
    Fix: peel `unwrapRefNullUnion` before the check (mirrors the peel already at call-arg sites
    `:1951`/`:2858`; the cast site was the only one missed). Now diagnosed at checker; bare-unknown
    still diagnosed; `unknown|null as Ref` no over-fire.
  - **Verified:** `unkas` repro build+run prints `ok`; battery **3332/5** (flake-only, 0 regression);
    guards proven RED→GREEN — `recompiler src/test/guard/nilableUnknownAsCast.ms` (runtime) +
    `src/test/handoff/nilableUnknownCastError.ms` (3/3, checker negative). NIM-REF §Value-type-Maybe
    row + §57 updated FIXED (uncommitted per docs rule). Repro `/tmp/unkas.ms`; was hitting only
    `reconcile.test.ms:57-59` pool (`Map<string, HostNode=unknown>`).
- **Deferred follow-up:** flip `HashMap.get` too (+~24 internal callers: `nameIndex`/`seen`/caches/
  macros — mostly ref-type `as X`, one value-type `seen.get() as number` needs narrow under the
  bootstrap compiler). Internal-only, off Neon's path.
- **✅ COMMITTED to recompiler main 2026-07-23, ⚠ NOT deployed** — 5 commits `8c69ffa..dd80ebc`:
  Map.get flip / value-type Maybe unwrap operators ①②③ / codegen borrow guard / checker fat-value
  diagnostic / guards. Installed `msc` is still the OLD v0.2.27 (no fixes). To deploy: rebuild from
  HEAD (`cd ~/metascript/recompiler && rm -rf out && msc build src/index.ms --gc=drc --danger
  --cc=clang --output=msc`) + `./tools/sync-local-binary.sh` — OR the already-proven binary is at
  `/tmp/recompiler-b/msc-b`. ⚠ HEAD `dd80ebc` NOT build-verified in-place (live recompiler tree holds
  a parallel session's WIP that would contaminate/hang a build); the identical logic was fully
  verified in the isolated `/tmp/recompiler-b` copy (283-module build + battery 3332/5 + guards).
  **Neon effect after deploy:** `reconcile.test` framework-pool pattern (`Map<string, HostNode>`)
  now compiles → suite should recover to **10/5** (verify).

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
