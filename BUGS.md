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

## Toolchain — VERIFIED 2026-07-27 (late, post-voidHost)

| what | value | how verified |
|---|---|---|
| installed compiler | `~/.metascript/bin/msc` **v0.2.27**, built **Jul-27 (late)** from `1e1db2a` **+ 2 uncommitted fixes** (passC module-relative, charAt/slice host bridges) | `msc --version`, `ls -la ~/.metascript/bin/msc`, sync log |
| recompiler HEAD | `1e1db2a` (main). **This session's compiler work is UNCOMMITTED in the working tree**: `src/checker/checkPass.ms`, `src/codegen/raiser/expressions.ms`, `src/raiser/{bytecode,disasm,vm}.ms`, `runtime/core/system.h`, `std/core/struct.ms`, `src/test/lang/comptime.ms`, `src/test/handoff/{index.ms,passCModuleRelativeInclude.ms,fixtures/passCRel*}`. Pre-existing leftovers untouched: `docs/*` + editor-plugin dirty, `src/test/{CLAUDE.md,native/README.md}`, untracked `src/test/native/run.ms`, `std/process/*`, `ctorExtProtocol*` | `git log --oneline`, `git status --porcelain -- src std` |
| binary ≡ working tree? | **yes** — `rm -rf out && msc build src/index.ms …`, then `./tools/sync-local-binary.sh` | post-deploy sweep below |
| **battery (post-deploy, `./msc`)** | **3340 pass / 0 fail** (163/163 files, ~4.5m) | `cd ~/metascript/recompiler && rm -rf out && ./msc test src/index.ms` |
| **Neon suite (post-deploy, installed msc)** | **16 pass / 0 fail** — includes NEW `render/style` (S1) | `msc test <file>` per file, `rm -rf out` between |

⚠ 2026-07-29 (late evening): installed msc is **gen-21** — JS backend now completes omitted
struct-literal fields with their zero value (C zero-fill parity; Nim model: objects are always
fully initialized). Found by the FIRST real-browser run of counterDom: `{ padding: 16, … }: Style`
left `width` undefined, `v === null` strict-miss → `undefined.toString` crash in applyCss. New
transform pass `src/transform/coercion/objectLiteralComplete.ms` (jsBackend-gated; skips extern
types, function-typed fields, spread-desynced literals); guard in `src/test/js/basic.ms` proven
red by toggling the pass off (exactly 1 fail in 2768). Gates: battery 3356/3356 (js/ not in that
closure — it lives in `src/test/index.ms`), js/basic closure 2768/2768, Neon 16/16, browser E2E
green (§1). ⚠ Side-find: unified `src/test/index.ms` has 4 PRE-EXISTING standalone-red files
(syntax, bug006, classMemberElseIf, deepNesting) — fail identically under a no-fix binary.

⚠ 2026-07-29 (evening): installed msc is **gen-20** — the JS backend now expands macros (two-phase
cmdBuildJS/cmdRunJS + loud post-expansion errors on every backend; §5 entry below). Neon's browser
path compiles end-to-end for the FIRST time: `element(<JSX/>)` expands into `el/withStyle` calls in
the bundle, `examples/counterDom.ms` bundles 21 modules with 0 `unsupported`, and
`probe/lspJsxStyleFixture.ms` node-runs printing `true`. Also in gen-20's std: `struct.jms` Map/Set
gained the missing `export`, string jms renamed `toLower/toUpper` → `toLowerCase/toUpperCase` (cms
parity), `toJSStr` passes non-arrays through. Battery **3356/3356** + Neon **16/16** re-verified
under the INSTALLED binary (not a sibling build — see the corrupt-binary incident in §5).

⚠ 2026-07-29: installed msc is **gen-19** — LSP macro expansion actually works now, closing the two
Neon MISS shapes from the object-completion table (`createStyles({ box: { | } })` and
`<div style={{ | }}>` both return the full 45-field Style set, measured over a REAL `msc lsp` stdio
session). THREE stacked causes, all fixed in the recompiler (§5 2026-07-29): transam never imported
`meta/expand` (subset builds silently no-op every macro — checkerCallbacks default returns the node
unchanged), TransAm never full-checked macro-declaring deps (engine body compile missing the
declaring module's imports → `body: Unresolved type 'Node'` → `_failedMacros`), and the macro-emitted
callee stamped at the entry literal's position shadowed the contextual-type record
(`sgQueryContextualTypeAt` now tried first). Hardening the guards then caught a FOURTH, pre-existing
SHIPPING CRASH: `removeExportEntry` never updated `moduleIndex`, so ANY didChange that invalidated
exports left stale indexes — edit a macro module, complete in a dependent → `index N out of bounds`
kills the request (measured on gen-18), or silently serves ANOTHER module's exports when sizes line
up. Fixed + guarded by the lifecycle-parity edit test. Guards: +5 in `completion.ms` (2 proven red
for the roots, +3: JSX shape, edit-refresh via didOpen/didChange, macro-module import cycle
termination). Gates: battery **3356/3356** (165 files) built+run in an isolated `/tmp/lsp-verify`
snapshot (live repo `out/` was contended by a parallel native-suite session), Neon **16/16**, E2E
LSP probes incl. didChange refresh (padX appears post-edit).
New uncommitted on top: recompiler `src/compiler/transam/index.ms`, `src/checker/suggest.ms`,
`src/compiler/lsp/handlers/completion.ms`; neon `probe/{lspStyleFixture,lspJsxStyleFixture,macmodMin,macuseMin}.ms`.
Side find: same-scope redeclaration miscompiles (new §2 row).

⚠ 2026-07-27 (night): installed msc is **gen-4 of this session** — adds the §5 2026-07-27-night checker
fixes (Maybe payload identity, struct-field repr gate, as<X> at assignment/nullable). Uncommitted on
top of the earlier uncommitted set: recompiler `src/checker/{types,compat,checkExprPass}.ms` + guards.

⚠ 2026-07-27 (late night, S1b): installed msc is now **gen-5** — adds the bug051 fixes (§5
2026-07-27-late-night): ObjectLiteral `keyLocations` survive the macro round-trip
(`src/compiler/meta/bridge.ms` setLocs/readLocs) and excess-property/duplicate-key diagnostics fall
back to the literal's location instead of being swallowed (`src/checker/checkExprPass.ms`). Gates on
gen-5: battery **3341/3341 (163 files)** — +1 is the new in-battery bridge round-trip guard — and
Neon **16/16** re-run file-by-file. New uncommitted on top: recompiler `src/compiler/meta/bridge.ms`,
`src/checker/checkExprPass.ms`, `src/test/fixedbugs/{bug051.ms,index.ms}`; neon
`src/macros/ui/style.ms` (real macro), `src/macros/ui/element.ms` (static-style guard, sacred),
`tests/render/style.test.ms` (no more hand-written Sheet; 4 tests), `probe/style_*.ms`, `docs/STYLE.md`.

⚠ 2026-07-28 (row 9, same day): installed msc is **gen-15** — the on-demand macro-helper diagnostic
queue PLUS the refusal to execute a macro whose body/helpers failed to check (§2 row 9 → §5; gen-14
was the report-only half, superseded within the hour). Built from an rsync'd snapshot again
(`/tmp/row9-verify`), so gen-15 = gen-13 + the parallel session's now-committed
`e628ea9`/`76a7222` + this fix. Gates:
battery **3342/3342** (163 files), `bug056` closure **2769**, `json.ms` closure **2776**, Neon
**16/16** run with the pre-install binary. ⚠ `src/test/fixedbugs/index.ms` cannot compile
bug006/008/010/047 when aggregated — **pre-existing**, identical set fails on `msc.bak-1785244527`
(the gen-13 backup the sync script wrote), and all four pass standalone.

⚠ 2026-07-28 (bindSym V2, same day): installed msc is **gen-13** — closes the remaining bindSym
gaps: **bound MACROS** (`bindSym("cborValueOf")` — `expandMacroInvocation` fetches body/params from
the DECLARING module's registries via a regCtx from `lookupModuleCtx(sym.modulePath)`; modulePath
stamped at bake since `collectMacro` never sets it; compiled-macro cache key now carries the
declaring module, closing a latent same-name collision) and **symHandle through nested expansion**
(all THREE serializers — nodeToValue, readNodeFromObject, nodeToASTLiteral — carry it, so a bound
identifier survives being passed as an ARG through a second macro). `encode` moved from cbor's index
hub into encoder.ms (bindable without an encode↔index cycle). Net: `json.ms` CBOR user imports
**7 → 1** (`cborEncode` only) — this differential IS the red/green proof: under gen-12 semantics a
bound macro expansion finds no registry and fails. Guards: bug056 now **7 tests** (+ bound macro
cross-module, user-scope same-name cannot hijack a bound macro, bound identifier through a second
macro). ⚠ Root-caused a self-inflicted crash: stamping `node.resolvedSym` by reading `d.callee`
AFTER `node.data = {...}` replacement — DRC destroys the old CallExprData, `d.callee` dangles
(misaligned 0x5 panic). Rule: **read everything you need from old node.data into locals BEFORE
mutating it.** ⚠ Session collision diagnosis: the "NIM-GUARD LEDGER" stray line + every link flake
(TBD parse / dedup-literals / FileNotFound) came from a PARALLEL session running guard builds
(`-DMS_DRC_LEDGER`) and `rm -rf out` in the SAME repo + shared `~/.metascript/cache` — verification
moved to an rsync'd snapshot (`/tmp/bindsym-verify`) with its own `out/`. ⚠ gen-13 was built FROM
that snapshot because the parallel session left in-flight edits to `src/checker/{compat,flow}.ms`
in the main tree — those edits are NOT in the gen-13 binary; whoever rebuilds next inherits both
change sets. Gates on gen-13: battery **3342/3342**, `json.ms` **14/14** (closure 2776), bug056
**7/7** (closure 2769), Neon **16/16** file-by-file.

⚠ 2026-07-28 (bindSym): installed msc is **gen-12** — adds `bindSym("name")` (Nim's static
semBindSym model, traced in Nim source first: `opcNBindSym` is a copyTree from VM constants — bake,
not runtime lookup; the scope-swapping dynamic variant is feature-gated experimental there and NOT
built here). Macro bodies splice Identifiers PRE-BOUND in the macro's declaring module: checker sees
`NodeFlag.BoundSym` (16384) + `Node.resolvedSym` and skips the user-scope lookup — call sites need
no imports for macro-emitted helpers, user-local same-names cannot hijack them, private helpers
bind. Pieces: bake branch in `bakeTypeIntrinsics` (expand.ms, resolves via `macroDeclModuleRegistry`
→ `lookupModuleCtx(...).table`, `ensureShaped` at bake, generics rejected V1); append-only
bound-symbol registry + `symHandle` read-back in bridge.ms (Symbol OBJECT IDENTITY preserved —
flow.ms compares by reference, codegen mangles through it); BoundSym honored at checkExprPass
Identifier branch AND checkCallExpr callee lookup (bound OVERRIDES lookup — the anti-hijack), then
normal semantics continue (Nim re-runs semSym on nkSym — NOT the EnumMember early-return); survival
exemptions in instantiate.ms `clearCheckerState` + clone.ms `copyNodeMeta`; `symHandle` accepted as
engine-mode virtual key (the A4 `engineNodeHasVirtualKey` door — a typed `const x: Node = bindSym(…)`
otherwise trips the bug051 excess-property check). Dogfood: `std/serialize/cbor/encode.ms` binds its
builders — the dynamic `builderName` dispatch was restructured into static branches (bindSym is
bake-time; dynamic names cannot bind) — `json.ms` CBOR user imports **7 names → 3** (`cborEncode,
cborValueOf, encode`; still unqualified: emitted MACRO calls — bindSym V1 binds functions, not
macros — and `encode`, hub index.ms, binding would cycle). Guard `src/test/fixedbugs/bug056.ms`
(4: cross-module no-import, incompatible user-scope same-name no-hijack, function-local shadow,
unresolvable name errors clearly) — proven RED by toggling the bake branch off (exactly 4 fail).
New `compileProjectToCWithStd` in `src/test/helpers.ms` (project + std; expandMacros in BOTH
alive-set and codegen loops so bound callees survive DCE). Gates on gen-12: battery **3342/3342**,
`json.ms` **14/14**, bug056 closure **2766/2766**, Neon **16/16** re-run file-by-file, `rm -rf out`.
⚠ Rule learned: a synced std that EMITS bindSym requires the gen-12+ binary — gen-11 cannot bake it;
never leave `~/.metascript/std` ahead of `~/.metascript/bin/msc` (this rebuild restored binary ≡
tree). ⚠ `msc run` and `msc test` corrupt each other's `out/debug/.cache` (link flakes: "failed to
parse TBD file", "failed to deduplicate literals: InputOutput") — `rm -rf out` when switching modes.
⚠ Seen ONCE on gen-11 during a cold `msc run`: a stray "NIM-GUARD LEDGER: DOUBLE-DESTROY of Node"
line; `strings` shows NEITHER the installed msc nor the built probe contains that string (ledger is
`-DMS_DRC_LEDGER`, off by default), 5+ re-runs + all gates clean — classified output contamination.

⚠ 2026-07-27 (A4, cont. 2): installed msc is **gen-11** — adds `getTypeArg()`: the explicit `<T>`
at a macro CALL SITE (`decode<User>(s)`) now reaches the macro body. **The gen-10 note below claiming
type args are unreachable was WRONG** — the parser stores the type arg on the Node itself
(`callNode.typeArg`, `parser/expressions/call.ms`) and the CallExpr→MacroInvocation rewrite replaces
only `node.data`, so it already survived to `expandMacroInvocation`; `MacroInvocationData` never
needed a slot. Implementation is small: resolve the name in the CALL SITE scope, peel Ref, splice the
type-AST; bake into a CLONE of the body and key the compiled-macro cache by (macro name, type arg) —
a name-only key lets the first instantiation poison the rest. Guard `src/test/fixedbugs/bug055.ms`
(3: reads the type arg, TWO instantiations stay independent — proven RED under a name-only key,
missing `<T>` is a clear compile error). V1 limits: exactly one type arg; a macro DECLARATION still
cannot carry type params (`macro m<T>(x)` does not parse) — not needed, since `getTypeArg()` reads
the call site. Gates on gen-11: battery **3342/3342**, `src/test/c/json.ms` **14/14**, Neon **16/16**
re-run file-by-file.

⚠ 2026-07-27 (A4, cont.): installed msc was **gen-10** — adds `getTypeImpl(TypeName)` for macro
bodies (`src/compiler/meta/expand.ms` `bakeTypeIntrinsics`): resolves a type BY NAME in the macro's
declaring module, peels Ref, splices the type-AST as a `Node`-asserted literal. This is what
`createStyles({...})` needs — a bare object-literal argument has no contextual type at expand time,
so `arg.nodeType` gives nothing and validating it against `Style` previously required a witness
param. Guard `src/test/fixedbugs/bug054.ms` (3: unknown key rejected with the macro's own message +
available list, valid sheet passes, unresolvable name is a compile error). Gates on gen-10: battery
**3342/3342**, guards standalone green, `src/test/c/json.ms` **14/14**, Neon **16/16** re-run
file-by-file. ⚠ (superseded by the gen-11 note above: `typeArg` DOES reach macros — `getTypeArg()`.)
⚠ Test-cost model measured and documented in `recompiler/src/test/CLAUDE.md` §5.1: `msc test <file>`
runs every inline test in the file's dependency CLOSURE, so one `src/test/**` guard (~240s) costs
about the same as the whole battery (~280s), while a compiler-module test is ~11-13s. `out/` does
NOT cache test runs (cold 240s vs warm 237s). `msc check` is unusable as a gate (fails to resolve
relative imports, missed a planted type error). Both aggregators are RED: `src/test/index.ms`
(74 type errors, pre-existing) and `src/test/fixedbugs/index.ms` (bug006/008/010/047 fail C codegen
when bundled, each green standalone) — so guards must be run one at a time.

⚠ 2026-07-27 (A4 session): installed msc was **gen-9** — SERIALIZE A4 read path: macro bodies
typecheck `node.nodeType` as the type-AST **Node** (engine-mode view at exactly TWO sites in
`src/checker/checkExprPass.ms` — member read + emitted-literal write, both handing back the Ref<Node>
VALUE representation; class decl stays `nodeType: Type` — compiler truth), and TWO swallowed-error
roots closed in `src/codegen/raiser/eval.ms` (§5). **No workarounds left in the tree**: the gen-7
same-NAME call-arg exemption was removed once the real root (peeled-Struct vs Ref<Node>) was found.
Gates on gen-9: battery **3342/3342 (163 files)** — +1 is the in-battery eval.ms slot-restore guard
(proven RED by toggling the fix off) — Neon **16/16** re-run file-by-file, `bug052.ms` (4: fields,
union, demo-B key validation, Ref-representation guard) + `bug053.ms` (1) green, all proven RED
pre-fix, and `src/test/c/json.ms` **14/14** (no KNOWN-RED). New uncommitted on top: recompiler
`src/checker/checkExprPass.ms`, `src/codegen/raiser/eval.ms`, `std/meta/node.ms` (comments only),
`std/serialize/{json,cbor}/decode.ms` (push literal type-AST node directly — kills the `value`
DU-conflict read), `src/test/helpers.ms` (`compileToCWithStd`), `src/test/fixedbugs/{bug052,bug053,
index}.ms`, `src/test/c/json.ms` (4 stale tests modernized).

⚠ **The battery does NOT run the guards.** Its 162 files are compiler/std sources with *inline* tests;
`src/test/**` is reached only through the broken `src/test/index.ms` aggregator (§7). Measured this
session: adding a test to `src/test/lang/comptime.ms` left the battery count at 3338 unchanged, and
neither `src/test/handoff/*` nor `src/compiler/meta/hostTable.ms` (18 inline tests) appears in the
162. **Every guard must be run standalone** — a green battery says nothing about them.

**Battery flake reality (2026-07-26):** the old 7-flake set is GONE (suggest ×2 + literals/expressions
fixed by `e7fdf29`/`22805ea`). Current intermittents seen on `a9c0ae6`-lineage: `std/fs/path.ms`
"join Windows absolute b wins" ×1 and the `lifecycle.ms` phase5/6 hover/sig-help block ×9 (LSP
timing — present on one pristine run, absent on the next two). Both hit ZERO in the final gate runs.
Diff any battery failure against these two groups before claiming regression.

- Rebuild compiler: `cd ~/metascript/recompiler && rm -rf out && msc build src/index.ms --gc=drc --danger --cc=clang --output=msc`
- Deploy: `./tools/sync-local-binary.sh` (Neon consumes msc via `$PATH`)
- Recompiler rule: **never commit `docs/*`** (NIM-REF.md rows stay uncommitted).

---

## §1 — CURRENT STATE (measured 2026-07-27 night, `rm -rf out` PER FILE, all 16 test files)

**Neon suite = 16 pass / 0 fail** (15 + `render/style` NEW — S1 of `docs/STYLE.md` landed and green).
✅ Measured on the INSTALLED `$PATH` msc (Jul-27 night build, gen-4 of this session — §5 2026-07-27-night).
✅ **The long-standing `reconcile`/`reconcileHard` intermittent is SOLVED and was never a "flake"** —
it was a signed-overflow UB trap in `msPtrHash`, firing only when the ASLR'd pointer folded high
enough (§5 B). Measured `reconcileHard` 2-fail-in-6 before, 0-in-8 after; then 30 consecutive
Neon file-runs clean. The old note blaming a shared `out/` was wrong: every measurement here used
`rm -rf out`. **Chase intermittents — this one hid a real memory-model bug for weeks.**
⚠ Protocol: `rm -rf out` BETWEEN files is load-bearing — sequential `msc test` runs sharing `out/`
produced spurious compile failures (reconcile/reconcileHard flip-flopped until cleaned).
✅ 2026-07-29 (late evening, gen-21): **browser E2E VERIFIED in real Chrome (headless Blink+V8)** —
`examples/counterDom.ms` + `examples/counterDom.html` host: 2 clicks → `Count: 2`, and
`<div style={{…}}>` lands as inline CSS via `applyCss` (`padding: 16px; color: rgb(205, 214, 244);
background-color: rgb(30, 30, 46); border-radius: 8px`). S2 browser projection CLOSED. Needed the
gen-21 compiler fix (§5): omitted Style fields were `undefined` in JS, crashing `len()`. Suite
re-measured 16/16 under installed gen-21, same file-by-file protocol.

| file | result | file | result |
|---|---|---|---|
| `core/signal` | ✅ | `core/array` | ✅ **NEW 2026-07-26 (late)** |
| `core/memo` | ✅ | `render/flow` | ✅ **NEW 2026-07-26 (late)** |
| `core/dispose` | ✅ | `render/counter` | ✅ **NEW 2026-07-26** |
| `render/element` | ✅ | `render/voidHost` | ✅ **NEW 2026-07-27 (late)** |
| `render/style` | ✅ **NEW 2026-07-27 (night)** | | |
| `render/host` | ✅ | | |
| `render/hostOps` | ✅ | | |
| `render/reconcile` | ✅ | | |
| `render/reconcileHard` | ✅ | | |
| `render/renderToString` | ✅ | | |
| `render/region` | ✅ **NEW 2026-07-25** | | |
| `platform/terminal` | ✅ | | |

### Issue count: **0 open on Neon's path + 7 compiler debts off-path**

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

**✅ All five compiler fixes are COMMITTED on recompiler `main` and DEPLOYED (Jul-27 00:10):**
`bbc2e3c` parser typeArg · `c41f1a3` anon `?` · `6422400` ref truthiness · `33dca18` generic
`slice<T>` · `1e1db2a` cross-module generic ctor. One root + its guard per commit. Neon-side:
`f5824b7` (indexArray append) + `454eec7`/`df9a4d5` (flow feature + its test).
Every guard was proven RED on the pre-fix binary before the fix landed.
(⚠ `msc test src/test/index.ms` fails 74 type errors on a pristine tree too — stale aggregator,
pre-existing, NOT a gate. The handoff guards are run standalone.)

**Nothing left on Neon's path.** Remaining work, in the order it is worth doing: (1) the `voidHost`
pair in §3 — a two-line Neon test-code type error plus the missing sokol dependency, (2) the
off-path compiler debts in §2, where **loop + nested-closure snapshot is the only silent
wrong-answer bug and therefore the highest severity item in this file**, (3) the small debts
listed in §7.

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

### Lineage note (kept from the closed rows)

The `.slice(0)` **arity** complaint that predates #2 was never a compiler bug — std `slice` takes
`(start, end)`; it was fixed Neon-side long before the real surface gap was found. The
`msGenericArraySlice` ownership question from the 07-25 handoff is **answered**: no such runtime
function was needed, and the emitted C shows DRC injecting `msIncref` per copied element (§5 #2).

---

## §2 — Open compiler bugs (15) — rows 1-3 + 5-7 re-verified 2026-07-25 late; row 4 added 2026-07-26 late; row 8 added 2026-07-27 late; row 9 CLOSED 2026-07-28 (kept struck-through, its severity note is a lesson) and two rows were added the same day by the probes that closed it; same-scope redeclaration row added 2026-07-29; asBytes-on-C row added 2026-07-29 night and CLOSED 2026-07-29 late night (kernel pair landed, see §5) — the probes that closed it added two rows (uint8[] method widening, bug006 standalone divergence) and the /trace-nim audit added a third (bridge ownership, 3 holes); the A4 "dual-Node" row was WITHDRAWN — misdiagnosis, see §5

| bug | repro | measured today |
|---|---|---|
| **nullfn bind-order** | `probe/nullfn_bindorder.ms` | ❌ `passing 'msClosure' to parameter of incompatible type` (:78) |
| **nullfn explicit type-arg** | `probe/nullfn_explicit_targ.ms` | ❌ `Argument type mismatch in 'apply' arg 0: got function, expected Maybe_fn_fnnumbernumber17` |
| **union ctor-param proto/def** | `/tmp/mono_union.ms` | ❌ `conflicting types for 'Box__union_number_string_init'` |
| **struct/array ctor-param indirection** (NEW 2026-07-26 late) | `new GcCell<CmgTag>({ label: "x" })` / `new GcCell<number[]>([1,2,3])` from an importing module | ❌ `passing '__anon1__label' to parameter of incompatible type 'CmgTag *'` — the ctor's declaration takes the type arg BY POINTER while the call site passes it by value. Same family as the union row above; pre-existing, but only reachable since #6 made cross-module ctors instantiate at all. Excluded from the #6 guard on purpose (documented inline there). |
| **loop + nested-closure snapshot** | `/tmp/loopesc.ms` | ❌ **builds but MISCOMPILES** — c0 expected 51 → **800**, c1 expected 51 → **0** |
| **`canRaise` missing Nim's `sfGeneratedOp` arm** | `/tmp/craise.ms` | latent (not a live bug) |
| **latent `monoConcreteTypeName` siblings** | — | by inspection: anon `Union` / `Conditional` |
| **object spread in object literal** (NEW 2026-07-27 late) | `/tmp/ns_spread/main.ms` (6 lines, `docs/STYLE.md` §7) | ❌ checker PASSES, C fails: `no member named 'dotdotdot_' in 'struct Style'`, emitted as `_lit4_->dotdotdot_ = /* spread */ base_1_;` |
| ~~on-demand helper compile errors unreported~~ | `src/test/fixedbugs/bug057.ms` | ✅ **CLOSED 2026-07-28** — helper errors now queue in `eval.ms` and merge into the macro's result (`Macro 'X' body: helper 'y': …`). See §5 for the measured severity correction |
| **`string = number` is not a checker error** (NEW 2026-07-28, found probing row 9) | `function f(n: number): number { const s: string = n; return n; }` | ❌ checker PASSES, C fails: `used type 'msString' where arithmetic or pointer type is required`, emitted as `s_1_ = ((msString)(n));`. Same shape as the object-spread row: a check the checker should own, deferred to the C compiler. NOT metaprogramming — plain assignment |
| **an all-nullable interface accepts ANY object** (NEW 2026-07-28, found in S2) | `n.layoutStyle = style` in `src/platform/void/host.ms` — `layoutStyle: FlexStyle \| null`, `style: Style` (a DIFFERENT interface) | ❌ type-checks silently. Every `FlexStyle` field is nullable, and with no missing-field rule (Nim default-init, NIM-REF §1) an all-nullable interface is structurally satisfied by anything — so assignability stops discriminating. S1 shipped this: the void host stored a Neon `Style` where yoga expected a `FlexStyle`, and layout silently read garbage. Fixed Neon-side (`asFlexStyle(style)`), but the CHECKER hole is open. The bug058 rule does not cover it: no field is function-typed. |
| **`async` helper called from a macro body** (NEW 2026-07-28, found probing row 9) | macro body does `value: bad(2)` where `async function bad(n: number): Promise<number>` | ❌ compiles clean — no diagnostic from the module check OR the engine check. The macro VM cannot run async, so the spliced value cannot be the awaited number. ⚠ **only the SILENCE is measured**; the emitted value was not inspected. Verify before assuming it is a wrong-answer bug |
| **same-scope redeclaration is not a checker error → miscompile** (NEW 2026-07-29, found writing the LSP probe) | `let ei = 0; … const ei = findExportedSymbol(…);` in ONE scope | ❌ checker PASSES, C fails (when lucky): the second decl reuses the first's C slot with the FIRST type — `incompatible pointer to integer conversion assigning to 'int32_t' from 'ExportedSymInfo *'`. TS/Nim both reject redeclaration in the same scope. If the two types happen to be ABI-compatible the C compiles and reads garbage silently — same family as the `string = number` row |
| ~~`asBytes` miscompiles on the C backend in every form~~ | `src/test/fixedbugs/bug063_asbytes_zero_copy_bridge.ms` | ✅ **CLOSED 2026-07-29 late night** — HiddenStdConv Cursor branch now picks the cast shape per direction (string = fat value, array = pointer). ⚠ the row's "asString does not exist on cms" claim was WRONG — `@builtin("AsString")` was in index.cms all along, same broken emission, fixed by the same patch. See §5 |
| **uint8[] widens onto the 15 remaining number[] extern methods → silent byte corruption on C** (NEW 2026-07-29 late night, found by the probe that closed the asBytes row) | `const b: uint8[] = []; b.push(104); b[0]` was the proven case — `msNumberArrayPush(b, 104.0)` stores an 8-byte double in a 1-byte payload, reads give the double's LOW BYTE (104 → 0). push is FIXED (bug064: uint8[] overload in index.cms + exact-receiver tiebreak in checker), but at/pop/shift/indexOf/includes/slice/concat/reverse/sort/fill/count/join/setLength/capacity/splice still have NO uint8[] overloads and still bind number[] | ❌ silent wrong answers on C for every listed method on a uint8[] receiver; std's own `serialize/json/accessors.ms:168` pushed uint8 through the broken path before the fix. **Must close before shared.ms algorithms use anything beyond push + indexing.** Runtime only ships Push/At/Destroy/New for uint8 — the other 13 need C runtime fns too. **NEW facet (2026-07-30, found red-proving bug065):** even push still mis-dispatches when the arg is a NON-LITERAL number — `let x = 65; b.push(x)` reads back 0 silently (bug064's tiebreak fires only when the uint8 overload is a candidate; a number-typed arg disqualifies it). Byte-loop code must cast (`as uint8` — Nim-faithful, Nim requires `byte(x)` too), but the silent number[] fallback stays a trap until this row closes |
| **bug006 fails standalone but battery is green — harness/mono path divergence** (NEW 2026-07-29 late night, pre-existing at gen-21) | `msc test src/test/fixedbugs/bug006.ms` under INSTALLED gen-21, zero local changes | ❌ C fails: `msArrayAccess((*(*arr)), 0)` — double deref of a generic indirect param after macro round-trip. Same file passes inside the full battery graph. Standalone-vs-graph compile takes a different mono/indirection path. Also true of bug062 in a worktree (needs its uncommitted checker half — that one is expected). Filed so the next person who runs fixedbugs standalone doesn't chase it as THEIR regression (this session lost ~30 min to exactly that) |
| ~~zero-copy bridge ownership model incomplete — 3 measured holes~~ | guards `src/test/fixedbugs/{bug065_asstring_exit_uaf,bug066_asbytes_rvalue_receiver,bug067_literal_view_push_static_clobber}.ms` — each proven RED against the exact hole | ✅ **CLOSED 2026-07-30** (see §5): (a) rvalue receiver → `lowerRvalueBridge` (AsBytes-gated receiver→temp hoist, flat splice) wired into the pipeline — discovery: `lowerRvalue` was NEVER wired despite the index.ms header listing it as pass #21; (b) asString exit UAF → interception removed, call falls to plain extern `msAsString` = COPYING kernel (cstrToNimstr shape) in `runtime/core/array.c`; zero-copy MOVE at analyzer last-use stays a later arc; (c) WORSE than filed — cap flag bits (STRLIT bit 62 + ASCII-cache bits 61/60) read RAW made push's room check see "infinite cap" → in-place writes to static memory that never even reached `msArrayPrepareAdd`; fix = masked compare + flag divert in `msUint8ArrayPush`, copy-on-flag in both `msArrayPrepareAdd/Uninit` (Nim `prepareSeqAddUninit` parity). STILL OPEN by design: heap-source view mutation writes through (Nim-faithful reinterpret semantics), and a mutated literal-view's copied payload may leak if the analyzer skips destroy on literal-init locals (bounded, noted) |
| ~~shared-std string byte-loops miscompile in the SELF-HOST build — "export" lexes as ex\|port~~ ✅ **CLOSED 2026-07-30 — root-caused, NOT a compiler bug: index-space divergence (extern = UTF-16 code units, shared.ms = bytes). See §5 and the index-space row below** | apply `/tmp/string-migration.patch` (re-derivable: `shared.ms` parked UNTRACKED at `std/core/string/shared.ms`; remove the 22 algorithm externs from index.cms + the bodies from index.jms, append the export-list re-export to both), rebuild msc with a GOOD compiler, then `msc run` ANY file | ❌ the produced compiler is broken: std loading dies with `Undefined variable 'ex' / 'port' / 'expo' / 'rt'` (identifier boundaries cut mid-word), `@include` paths garble to `*.h`, phantom "Parse: Unexpected token" errors. EVIDENCE CHAIN: (1) the SAME shared.ms compiled into small programs is byte-perfect — 36/36 dual-backend diff incl. UTF-8 + empty string; (2) still broken with CLEAN std + known-good builder → the orphan-JSDoc accident of attempt 1 is exonerated; (3) breakage exists only in the 287-module whole-compiler context → context-dependent miscompile (suspects: int64 params / default args / extension dispatch under mono+DCE at scale). Bisect recipe: wire ONE function's cms extern → shared re-export at a time (start byteSlice/byteAt — lexer-critical), rebuild with the good wt msc, probe `msc run` on a 1-line file |
| **string API has no single index space — C runtime = UTF-16 code units, jms = bytes, spec = TS** (NEW 2026-07-30, the root behind the self-host row) | `probe/stringSpecOracle.ms` — ONE file, 3 runners: `node` (= TS oracle; strip annotations via `sed 's/: string//g; s/: void//g'`), `msc run`, `msc build --target=js` + `node out/stringSpecOracle.js`; expected baked in `probe/stringSpecOracle.expected.txt` | ❌ 40-row matrix: **JS 18 red** (`length`/`indexOf`/`lastIndexOf`/`padStart` in byte space; astral `charAt(1)` = garbage glyph `𣐀`), **C 6 red** (`padStart` target counted in BYTES; astral `charAt(1)` returns whole `👍` instead of the low surrogate half; astral `slice(1,3)` empty), ascii 16/16 green on BOTH. CONTRACT DECIDED (user 2026-07-30, normative section added to LANG.md §"Index-Space Contract"): TS tier = code-unit TS-exact incl. `s[i]` ≡ `charAt(i)` returning `string`; byte tier = explicit `byte*` names (Nim surface); representation stays UTF-8 bytes + zero-copy asBytes. **JS HALF FIXED 2026-07-30 late (uncommitted): 40/40 vs oracle** — `fromJSStr` lone-surrogate WTF-8 fallback (root of astral garbage: charAt of an astral half fed a lone surrogate back through the pair branch → NaN bytes), `indexOf`/`lastIndexOf`/`padStart`/`padEnd` → native delegation via toJSStr, new `msStringLength` (code-unit byte-walk) + new jsBackend-gated pass `src/transform/coercion/stringLengthJS.ms` (`.length` on String → `msStringLength()`; JS path never ran nativeLower's rewrite — C-only call sites compile.ms:1088/:1479). Gates: battery 3364/3364, js/basic 2778/2778, C harness byte-identical pre/post. **`s[i]` JS also fixed same session** (same pass, `charAt(s,i)` rewrite; harness grew to 45 rows incl. `s[i]` — JS 45/45). **C HALF FIXED same session (uncommitted): 45/45 — BOTH BACKENDS NOW MATCH THE NODE ORACLE 45/45.** `runtime/core/string.c`: new `msWtf8EncodeSurrogate` helper; `msStringCharAt` returns the exact half for astral (was: whole 4-byte glyph for either unit index); `msStringSlice` non-ASCII walk rewritten in unit space with half-inclusion at boundaries (was: `charPos == start` never matches mid-pair → byteStart -1 → EMPTY); `msStringPadStart/PadEnd` target + pad now counted in UTF-16 units via `msStringLength` + `msPadEmitUnits` (was: bytes; astral pad truncation keeps the high half, TS parity — in-code, not fixture-covered). Astral harness rows refitted to `charCodeAt`-based numeric compare (printed-lone-surrogate trap: node writes U+FFFD, C writes raw WTF-8). Gates after C fix: battery 3364/3364, js/basic 2778/2778, stage-2 self-host rebuild green. **Guard bug068 BAKED same session** (`src/test/fixedbugs/bug068_string_index_space.ms`, 5 tests, imported in fixedbugs/index.ms, ported to live): green under fixed runtime (280/280 in the 14-file glob), **proven RED against pre-fix string.c** (3/5 fail: padStart/astral-half/slice — the length/indexOf tests guard the JS half, which fixedbugs cannot run; the neon `probe/stringSpecOracle.ms` 3-runner harness stays the JS-side gate). ⚠ TWO harness facts measured while baking: the BATTERY (`msc test src/index.ms`) contains ZERO fixedbugs tests — guards run ONLY via the per-file glob; and `src/test/fixedbugs/index.ms` as an ENTRY is unbuildable in a worktree without the parallel session's untracked bug062 file. REMAINING for this row: commit; documented deviations (charAt/s[i] out-of-range `""` not `undefined`; C stdout writes lone halves as raw WTF-8) |
| **`s[i]` on JS backend read raw bytes — checker+C were ALWAYS coherent** (2026-07-30; the original "checker type lie" filing was a MISDIAGNOSIS — `checkExprPass.ms:866` `charType()` is the RANGE branch `s[a..b]` → `Span<char>` (byte tier, correct by design); plain `s[i]` was `stringType()` all along at :873, and C emits `msStringArrayAccess` returning a code-unit string) | `const c = "a—b"[1]; console.log(c)` — C prints `—` ✓, JS printed `226` | ✅ **JS HALF FIXED 2026-07-30 late (uncommitted)**: `stringLengthJS` pass also rewrites non-range `s[i]` on String → `charAt(s, i)`; harness `s[i]` rows 5/5 green on JS (45/45 total), js/basic 2778/2778 (no `s[i]=` assignment broke — none exists on the JS path). STILL REAL from the original filing: `char` maps to C `char` = **signed on arm64** (Nim char is unsigned; `> 127` latently broken) and `'é' as unknown as char` emits `(char)MS_STRING_LIT(...)` → clang error. Those two stay open |
| **`number[].indexOf` returns -1 for present elements** (NEW 2026-07-30, found by the bisect control run) | `[10,20,30].indexOf(20)` — clean std, wt debug build | ❌ `-1` on C. `string[].indexOf` works. Same extern-dispatch family as the uint8[] widening row above |
| **C literal emission: `\xNN` escapes merge with following hex chars** (NEW 2026-07-30) | `const s = "\xC3\xA9abc";` | ❌ clang: `hex escape sequence out of range` — emitted verbatim, C parses `\xC3A` greedily. Needs escape-safe emission (`"\xC3" "\xA9" "abc"` or octal) |

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
- **object spread in object literal** — `const merged: Style = { ...base, height: 20.0 as float32 };`
  type-checks, then C codegen emits a literal field literally named `dotdotdot_` instead of copying the
  spread operand's fields. **Blocks style composition at runtime (S3 in `docs/STYLE.md` §9)** — not
  S1/S2. The style design picked array layering over spread for provenance reasons *independent* of
  this bug, so it blocks a runtime-merge path, not the design.
- ~~**on-demand helper compile errors unreported**~~ — CLOSED 2026-07-28, see §5. The plumbing gap was
  real; the *severity* filed here was overstated, and the correction is recorded in the ledger.
- **deferred, not counted:** catch-side `e.message` (object-carrying exceptions) — MS's exception
  runtime is string-based by design; `throw` works, `catch (e) { e.message }` does not.

---

## §3 — Neon-side / environment — EMPTY, `voidHost` CLOSED 2026-07-27 (late)

- **`voidHost`** — ✅ **GREEN (3/3).** Both problems recorded here were MIS-DIAGNOSED; see §5 for the
  four real roots. Corrections worth carrying forward:
  - **"env: sokol_gfx.h not present" was WRONG.** `sokol_gfx.h` was on disk the whole time at
    `void/deps/sokol/`. The header was unreachable because `@passC("-Ideps/sokol")` is resolved
    against the **process CWD**, and Neon builds from its own root — a compiler bug, not a missing
    dependency. **Nothing was ever installed to fix this.**
  - **The `renderToHost arg 0: got string` type error no longer existed** when re-measured; it had
    been fixed by an earlier session's compiler work and the row was never re-measured. Per this
    file's own rule: re-measure before repeating a claim.
- **`terminal`** — ✅ FIXED 2026-07-21, Neon-side, stays green (284/284). Was "two short texts in a row
  render as 1 line". Two fixes in `src/platform/terminal/paint.ms`: tag `"row"` now defaults
  flexDirection to row; `getAttr`/`getAttrNum` guard with `.has(name)`.

---

## §4 — Uncommitted Neon work (do not confuse with bugs)

**2026-07-26: the green render layer LANDED** (`cd4b535..4731735` — array/memo/reconcile/
host+node+dom/render-tests/docs/build, 7 commits split by concern). Still uncommitted, ON PURPOSE:

**2026-07-27: the backlog is now EMPTY** — everything above was committed once it was either green
or provably env-blocked:

- `src/macros/ui/flow.ms` + `tests/render/flow.test.ms` → `454eec7` + `df9a4d5` (green).
- `src/platform/void/host.ms` → `54cb9c8`, `tests/render/voidHost.test.ms` → `167493d`.
  ⚠ Committed while still RED — the blocker is the §3 environment gap, not the code.
- `probe/` → `307ba0a`. These are the probes the §5 entries cite. Three assert deliberately WRONG
  values (`macro_disambig`, `macro_lenval`, `macro_narrow` N1) — see §7 before reading them as
  failures.

**2026-07-27 (late), uncommitted and deliberate:** `src/macros/ui/element.ms` (JSX whitespace) +
`tests/render/voidHost.test.ms` (corrected expectations) — both green, awaiting review because
`element.ms` is a sacred file. The matching compiler fixes are uncommitted too (see toolchain table);
**they must land together — Neon's `element.ms` is green only on a compiler carrying the charAt/slice
bridges.**

Still untracked: `docs/EDITOR*.md` (design scratch).
⚠ **`deps/` is NOT empty** — the long-repeated "yoga vendoring never landed" claim is false:
`deps/yoga -> ../../yoga/deps/yoga` exists and resolves to a real checkout (this is what
`voidHost` links against). What is missing is only a *vendored copy*, not the dependency.

---

## §5 — Fixed (history + root-cause ledger, append-only)

### 2026-07-30 (late) — shared-std self-host "miscompile" root-caused: never a miscompile, an index-space divergence

**Bisect** (subset-module harness `/tmp/bisect/gen.py` + `step.sh`, ~27s/step — you CANNOT bisect by
re-exporting one name from the full shared.ms: extension methods register when the module enters the
graph, all 22 collide with the remaining externs → 637 ambiguity errors): byteAt/byteSlice/startsWith/
endsWith/contains/lastIndexOf all GREEN individually; **`indexOf` ALONE reproduces**. A DEBUG stage-2
build (bounds checks ON) reproduces identically with zero memory errors, and `dump-tokens` on the
broken file is byte-identical good-vs-bad binary → pure logic divergence, not corruption.
**Mechanism**: `src/module/loader.ms:106` (`inlineHeaderImports`) rewrites module source mixing
`indexOf`+`lastIndexOf`+`slice`+`.length`. Measured on `std/core/date/index.cms` (685 bytes / 679
code units): extern `indexOf("export")` = **399 = code-unit index** (byte truth 403) and
`slice(399,405)` = `export` ✓ — the C string API is coherently CODE-UNIT indexed; shared.ms indexOf
returns 403 (bytes) → every downstream offset shifts by the UTF-8 surplus, cutting identifiers at
2×(N−1) for N preceding multi-byte chars (matches date N=2 → `ex|port`, performance N=3 → `expo|rt`;
a 1-em-dash file survives). **Two probe traps burned**: differential probes run with the WIRED std
compare shared against itself (its "extern" IS shared) — false-matched twice; always clean std + a
locally-declared copy. And the old "36-value dual C/JS byte-perfect" gate compared shared-C vs
shared-JS (both byte-based) — never shared vs the extern it replaces: false gate, retired.
**Design decided** (user): two-tier index-space contract, normative in LANG.md — TS tier (default
names) = UTF-16 code-unit TS-exact incl. `s[i]` ≡ `charAt(i)` returning `string` (user override:
s[i] must NOT be a byte); byte tier (`byte*` names) = Nim string surface; representation stays UTF-8
bytes both backends; asBytes Cursor-borrow zero-copy PRESERVED (verified `builtinLower.ms:177`
`rewriteZeroCopyBridge` + `msAsString` copying kernel untouched by the design — user hard
requirement). New gate: `probe/stringSpecOracle.ms`, one file, 3 runners (node = TS oracle); first
matrix C 34/40, JS 22/40, ascii 16/16 both. **Side finds**: shared.indexOf lacked negative-start
clamp → OOB read under `--danger` (fixed to the measured extern contract — neg start clamps to 0,
empty needle returns `start` verbatim even negative, `start > len` → -1 — ⚠ fix lives ONLY in the
`/tmp/wt-asbytes` working copy of shared.ms; the COMMITTED `079a3c2` copy is still unclamped, port
it during the two-tier restructure); `number[].indexOf` broken (new §2 row); `\xNN` literal
emission (new §2 row); untyped fn params emit `void*` on C — annotate probe files.

### 2026-07-30 — zero-copy bridge ownership: all 3 audit holes closed ✅ COMMITTED `83832b9`+`292618c`+`d772074`+`2b7f0d5`+`0727619` (neon `c7f4900`)

The §2 "zero-copy bridge ownership" row is CLOSED — guards bug065/066/067, each proven RED against
its exact hole. Gates in the worktree (live HEAD `9a3dc38` + only these patches): battery
**3364/3364** (166 files; 3356 + 7 new guard tests + 1 from the parallel session's corpus commits),
Neon sweep clean (core/render/platform globs, 0 fail), dual-backend probe **16/16 identical** C vs
JS. ⚠ Installed msc still gen-21 — NONE of gen-22-to-be is in the installed binary.

**Hole (b), asString exit UAF — root & fix**: `@builtin("AsString")` lowered to HiddenStdConv +
Cursor = zero-copy BORROW of the array payload; the owned array dies at scope end → returned
string dangles. Fix per plan: interception deleted in `builtinLower.ms` (AsBytes keeps the borrow —
read path measured-correct), so the call falls through to the plain extern and a new copying
kernel `msAsString(msUint8Array*)` (`runtime/core/array.c`, `msStringNew` = cstrToNimstr shape)
returns a fresh OWNED string. Zero-copy MOVE via analyzer last-use = later arc. JS untouched (jms
has its own real asString).

**Hole (a), rvalue receiver — root & fix**: `const rv = (a+b).asBytes()` emitted
`(msUint8Array*)&(msStringConcat(...))` — `&` of a call result. DISCOVERY: `rvalueLower.ms` exists
with green inline tests and a pipeline-header listing (#21) but was **never imported nor called**
— the §2 row's "just isn't routed through it" understated it. Fix: new `lowerRvalueBridge` in
`rvalueLower.ms` — AsBytes-gated (`resolvedSym.builtinKind === "AsBytes"`), hoists an rvalue
receiver to a peer temp at VariableDecl-init and ExprStmt positions via `walkExpandBlocks` flat
splice (callHoist shape — a BlockStmt wrap would scope the binding away). Wired `!jsBackend`
before `lowerExtensionMethod`. The GENERAL all-methods hoist stays unwired (own battery-soak arc).

**Hole (c), borrowed-view push — root WORSE than filed**: the filed row said `msArrayPrepareAdd`
lacks a STRLIT guard; measured reality: prepareAdd was never even reached. String payload caps
carry flag bits (STRLIT 62, ASCII_CHECKED 61, ASCII 60 — the last two set lazily by
`msStringIsAscii` on HEAP strings too) and every push site compares cap RAW → flagged cap reads as
astronomically large → "room available" → in-place write. A 40-push through `"abc".asBytes()`
silently overwrote the NEXT static literal (macOS links the payload writable — no SIGBUS, probe
printed the neighbor as `XXXXXXXXXXXXXX`). Fix (Nim `prepareSeqAddUninit` parity):
`msUint8ArrayPush` masks the cap for its room check and diverts any flagged payload;
`msArrayPrepareAdd/Uninit` copy a flagged payload to a fresh owned one (never realloc, never free
the source; stale ASCII bits dropped with the copy — cache-coherence fix included).

**Guard traps burned this session**: (1) the first bug065 red-proof was POLLUTED — audit3's
measured garbage was TWO stacked bugs (push-arg mis-dispatch writing doubles + the UAF), and with
the dispatch noise removed (`as uint8`) the original asserts went green under the OLD compiler
(72-byte freed block simply not reused). Re-proved RED with a deterministic shape: grow-past-cap
realloc frees the borrowed payload, then a same-size-class allocation reuses it (LIFO). (2) In
bug067, `neighbor === "hello-neighbor"` stays TRUE under the bug — both sides read the same
clobbered payload; assert via `charCodeAt`. (3) `msc run --target=js` doesn't build the bundle —
use `msc build --target=js` + `node out/x.js` for dual-backend probes.

Files: `src/transform/native/builtinLower.ms`, `src/transform/lowering/rvalueLower.ms`,
`src/transform/index.ms`, `runtime/core/array.{c,h}`,
`src/test/fixedbugs/{bug065,bug066,bug067,index}.ms`. New §2 facet filed: uint8[].push with a
non-literal number arg still mis-dispatches (silent 0) — see the 15-methods row.

**Same session, later — shared.ms migration attempted and BLOCKED.** `shared.ms` written (22
algorithm-tier byte-loop fns + 3 private helpers, `as uint8` on every computed push), wired into
BOTH index.cms (externs removed) and index.jms (bodies removed) via one export-list re-export.
Small-program gate PASSED: 36-value dual-backend diff identical (trim/index/split/case/pad/UTF-8/
empty-string). Self-host gate FAILED: the compiler rebuilt on the migrated std is BROKEN — filed
as the new §2 row "shared-std self-host miscompile" (specimen evidence + bisect recipe there). wt
restored to green (battery 3364/3364 re-verified); `shared.ms` parked UNTRACKED at
`std/core/string/shared.ms`; index-wiring patch at `/tmp/string-migration.patch`. Trap for the
record: the first failed build had TWO variables (a script accident left orphaned JSDoc blocks in
cms AND the migration wiring) — and the "clean retry" was accidentally run under the BROKEN binary
as builder, which proved nothing. Only a third cycle (clean std + known-good builder) isolated the
root: the migration wiring itself. Always re-verify a suspect state under a KNOWN-GOOD builder.

### 2026-07-29 (late night) — asBytes/asString C kernels + uint8[].push wrote doubles ✅ COMMITTED `234f75b`+`446148e`+`d835512`+`9a3dc38`

The §2 asBytes row is CLOSED; the probe that closed it found a second, worse bug. Verified in
`/tmp/wt-asbytes` worktree (HEAD + only these patches): battery **3356/3356**, Neon sweep clean,
dual-backend probe **16/16 identical** C vs JS, bug063 + bug064 both proven RED under installed
gen-21.

**Root 1 — one cast shape for two representations** (`src/codegen/c/expressions.ms` HiddenStdConv
Cursor branch). Both bridge directions emitted `*((T*)&(inner))` — correct only for value→value.
But string is a fat VALUE (`msString {len,p}`) while array locals are POINTERS (`msUint8Array*`):
string→bytes needs `((msUint8Array*)&(inner))`, bytes→string needs `*((msString*)(inner))`. The
branch now picks by `convType.kind`. ⚠ The filed row claimed "asString does not exist on cms" —
WRONG: `@builtin("AsString")` sat in `std/core/array/index.cms:261` all along, broken the same way,
fixed by the same patch. Guard: `bug063_asbytes_zero_copy_bridge.ms` (7 tests incl. the
buildString exit path `[] → push → asString`).

**Root 2 — uint8[].push dispatched to msNumberArrayPush** (std + checker). std declared push only
for `number[]`/`string[]`/`T[]`; a uint8[] receiver WIDENED onto number[] → 8-byte doubles stored
into a 1-byte payload → reads return the double's low byte (`104` → `0`). len right, data garbage,
zero diagnostics — and std's own `serialize/json/accessors.ms:168` shipped through it on C. Fix in
two halves: `push(this arr: uint8[], value: uint8) from "&msUint8ArrayPush"` in index.cms (runtime
fn existed, was NEVER referenced anywhere in src/), plus an exact-receiver TIEBREAKER in
`resolveExtensionOverloadCall` — adding the overload alone turned every uint8 push into "Ambiguous
call" because scoring strips receivers, so `this uint8[]` vs `this number[]` tied. Guard:
`bug064_uint8_push_number_dispatch.ms` (4 tests incl. 100-push growth).

**Design lesson**: the first fix attempt PRE-FILTERED candidates to exact-receiver matches before
scoring — rejected in favor of a tiebreak at `idx === -2` only. A tiebreak cannot change any call
that already resolves; a pre-filter can. (bug006 going red mid-session looked like the pre-filter's
fault and was actually the pre-existing standalone divergence now filed in §2 — but the tiebreak
design is still the right one.)

**Method note**: the dual-backend diff probe (one source, `msc run` + `node out/x.js`, diff) is
what proved parity — same recipe as the jms parity session, now also covering the C kernels.

**/trace-nim audit (same night, user-requested)** — verdicts per fix, Nim source read this session:
(1) cast-shape emission = **SAME** (Nim `NimStringV2`/`NimSeqV2` are BOTH fat values — one cast
shape suffices there; our two shapes are the correct adaptation to the documented
DIVERGE-INTENTIONAL "MS arrays are reference types") **but INCOMPLETE at 3 edges** — now the §2
"zero-copy bridge ownership" row (rvalue receiver, asString exit UAF, borrowed-view mutation; all
three MEASURED, probes audit1-3). The bug063 "buildString exit path" test only proves the IN-SCOPE
case — header comment amended. (2) uint8 push overload = SAME-in-spirit within the per-elem-type
runtime repr divergence. (3) exact-receiver tiebreak = **DIVERGE-INCOMPLETE toward Nim**: Nim
sigmatch scores the receiver as arg 0 (never strips it), so this bug class can't exist there; the
tiebreak is a staged step using `sameType` as identity — exactly what NIM-REF row 76 prescribes
("do NOT reuse typeRelation's Exact as identity") — and its lesson (a scoring-relation change
broke overload selection) is why tiebreak-not-prefilter was right: the pre-filter variant was
tried first and withdrawn. Full alignment (receiver participates in scoring) is a separate arc.

Files: `src/codegen/c/expressions.ms`, `src/checker/checkExprPass.ms` (+`sameType` import),
`std/core/array/index.cms`, `src/test/fixedbugs/{bug063,bug064,index}.ms`.

### 2026-07-29 (night) — jms string parity + four cross-backend divergences ✅ COMMITTED `5d7b0dc`+`80d12da`

Closed the §7 "~19 exports behind cms" debt: 18 functions ported as pure-MS byte loops with
semantics read from `runtime/core/string.c` (not guessed), + `lastIndexOf` silent drift
(missing `startIdx`, int32 return). **Root of the divergence class**: the old jms borrowed native
JS behaviour via `@emit(toJSStr→native→fromJSStr)` round-trips where the C runtime is byte-based —
so `toLowerCase` (Unicode vs ASCII `tolower`), `replace` (`$`-patterns vs literal), `split("")`
(UTF-16 chars vs bytes) returned DIFFERENT answers per backend from the same source. Nim's rule
(traced in `strutils.nim`, 3 `defined(js)` sites total): algorithms are pure byte loops shared by
every backend; native emit ONLY at the C-library boundary (`c_snprintf` class) — so `parseFloat`/
`parseInt` keep `Number.*`, everything else became byte loops. `slice`/`charAt`/`charCodeAt` also
round-trip but were MEASURED equal to C (C's slice is UTF-16-char-indexed TS semantics by design) —
left alone, perf-only. Two shipping bugs the surface guard could not see: `.jms` exports SHADOW JS
globals (`parseFloat` called itself — stack overflow), and the with-std harness validates export
signatures, NOT bodies (three int64/int32 mismatches passed a green suite; caught by probe build).
Gates: battery 3356/3356, js/basic 2770/2770 (red-proven guard), js/result 2766/2766, Neon 16/16,
dual-backend probe 59/59 identical. Feasibility probes for single-source std opened the §2 asBytes
row (C codegen broken in every form; `asString` absent from cms) — that row is now the only blocker
to writing std string once in MS for all backends.

### 2026-07-29 (late evening, gen-21) — JS backend: omitted struct-literal fields are `undefined`, not `null` ⚠ UNCOMMITTED

**Symptom**: first real-browser run of `counterDom` (headless Chrome) died in
`applyCss → len → msNumberToStringRadix: Cannot read properties of undefined` — misread twice
before the stack trace corrected it (first guess "signal broken", then "closure capture"; both
refuted by node probes `probe/jsSignalMin.ms` + `probe/jsClosureSignal.ms`, both green). Real root:
`<div style={{ padding: 16, … }}>` emits a JS object with ONLY the written keys, so `s.width` is
`undefined`; MS `v === null` compiles to strict `===` which misses it, falls into the number branch.
C never sees this — struct literals zero-fill. 7-line repro: interface with `w: number | null`,
literal omitting `w` → C `null-ok`, JS `NOT-NULL-BUG`.

**Fix (Nim model: object construction always fully initializes)**: new transform pass
`src/transform/coercion/objectLiteralComplete.ms`, registered jsBackend-only after constFold —
ObjectLiteral whose nodeType unwraps (unwrapRef → typeReturn, NOT typeChildren; then peelThrough)
to a Struct gets every missing field appended with `makeDefaultValue(fieldType)`. Skips: extern
types (`SymbolFlag.ImportC` — real JS APIs distinguish absent vs null), function-typed fields
(bug058 requires them explicitly), literals with keys/properties out of sync (spread — §2 row 8).

**Guard**: `src/test/js/basic.ms` "object literal completes omitted fields" — proven RED by
toggling the pass off: exactly 1 fail in the 2768-test closure. ⚠ `src/test/js/*` is NOT in the
`src/index.ms` battery closure (3356 unchanged is correct); it lives in `src/test/index.ms`.

**Traps re-confirmed**: (1) debug prints inside a transform pass that touch `.sym`/`.typeExtra` of
arbitrary std literals can SEGFAULT the compiler silently — msc exits 0-output, looks like a no-op
build; (2) `msc build --target=js` caches the bundle — `rm out/<name>.js && touch` the source or
the transform never re-runs; (3) installed-msc `msc test` in the recompiler tree hit missing
`_msUnregisterCycle` — repo std/runtime is AHEAD of the installed binary (parallel-session
nullable-carrier stack); all recompiler gates must run under `./msc`, not `$PATH` msc.

**Side-find (pre-existing, NOT this fix)**: unified `src/test/index.ms` has 4 files that fail
STANDALONE under a no-fix binary built from the same tree (lang/syntax, fixedbugs/bug006,
handoff/classMemberElseIf, checker3pass/stress/deepNesting — C-level `void*` member errors in
closure env code). Inherited from the uncommitted parallel-session stack; needs its own session.

**Verify**: battery 3356/3356 under `./msc`; js/basic closure 2768/2768; probe `null-ok` under the
INSTALLED gen-21 (`tools/sync-local-binary.sh`, `msc version` OK — no codesign kill this time);
Neon 16/16 file-by-file; browser E2E green (§1). **Files**: recompiler
`src/transform/coercion/objectLiteralComplete.ms` (new), `src/transform/index.ms` (registration),
`src/test/js/basic.ms` (guard); neon `examples/counterDom.ms` (style added),
`examples/counterDom.html` (browser host, NEW).

**Addendum (same session)** — §7 guard debt closed: `compileProjectToJS` → two-phase
(`emitJSTwoPhase`), new `compileProjectToJSWithStd`, jsxmac guard baked into `src/test/js/basic.ms`.
Red-proof finding worth keeping: skipping `expandMacros` alone stays GREEN — since gen-19 the
checker expands macros at check time, so the two-phase ordering (all checks before any transform)
is the load-bearing half; the explicit `expandMacros` + `hasErrors` after it is the loud-failure
half (gen-20 root 2 parity). The red toggle is an interleaved `transformProgram` inside the check
loop → `ERROR: expand` fires, exactly 1 fail in 2769. Extra helper files: recompiler
`src/test/helpers.ms`.

### 2026-07-29 (evening, gen-20) — JS backend: any macro calling a module-level helper silently no-ops ⚠ UNCOMMITTED

**Symptom**: `msc build x.ms --target=js` prints a GREEN bundle line while the output contains
`const app = /* unsupported: MacroInvocation */;` — Neon's `element(<div/>)` never expanded, so the
whole browser path was dead (this, not `Unresolved type 'Map'`, is why S2's `applyCss` had never
run; the Map error was a separate std bug hiding in front of it). Bisect matrix: object-arg +
cross-module ✅, JSX + same-module ✅, JSX + cross-module ❌ → misleading; the REAL trigger is a
**module-level helper called from the macro body** (`probe/jsxmacMod.ms` + `probe/jsxmacUse.ms`,
2-file repro — must print `expanded-x!`).

**Root 1 (ordering)**: cmdBuildJS/cmdRunJS ran check→expand→**transform** per module in load order.
`transformProgram` mutates the checked AST in place, and the per-module re-check re-registers that
same AST as the module's ctx (`registerModuleCtx`, checkPass.ms:2139). By the time a LATER module
expands the macro, the engine's on-demand helper compile clones a body that is already
native-lowered — `s + "!"` → `msStringConcat(s, "!")` (stringOpLower) — and the raiser check rejects
it: `helper 'shout': Undefined variable 'msStringConcat'`. Fix: **two-phase** build (check + expand +
comptime for EVERY module first, then transform + codegen) in both cmdBuildJS and cmdRunJS.

**Root 2 (silence)**: every macro-machinery diagnostic (`Macro 'x' body: …`, `evaluator
unavailable`) is severity-Error but **non-fatal**, and the build loops only called
`exitOnFatalCheckerErrors` — the errors sat in `ctx.errors` unread. Fix: new `exitOnCheckerErrors`
(non-fatal inclusive) after ALL FIVE `expandMacros` call sites (JS bundle, JS run, C ×2, raiser).
Instrumentation ladder that found both: entry/exit prints in `expandMacroInvocation` +
`getOrCompileMacro` narrowed it to `gocm-broken` in two rebuilds; the message itself was the root.

**Std fixes riding along**: `struct.jms` declared `extern class Map/Set` WITHOUT `export` →
`Unresolved type 'Map'` killed every JS build touching reconcile.ms; string jms exported Nim-style
`toLower/toUpper` where cms exports `toLowerCase/toUpperCase` → renamed to the TS names
(neon `dom.ms:67` updated); `toJSStr` now passes non-arrays through (console.log of a boolean
emitted nothing).

**Incident, recorded so nobody re-lives it**: the first gen-20 candidate (`/tmp` build, made while
the parallel session held the machine at load 36) behaved DIFFERENTLY from the repo build of
IDENTICAL source — probe red, battery green (battery has no cross-module JS-macro test). A 7-build
flag bisect **refuted** the "drc+danger+clang miscompile" theory: singles green, pairs green, triple
REBUILT green. The original binary was simply a corrupt build — the known parallel-session cache
collision extends to produced BINARIES. Lesson: re-verify the fixed behavior under the EXACT binary
you install; "same source, same flags" is not "same binary".

**Verify**: battery 3356/3356 (165 files) under the shipped binary (`/tmp/msc-jsfix`, worktree
recipe); Neon 16/16 under installed gen-20; `probe/jsxmacUse.ms` runs `expanded-x!`,
`probe/lspJsxStyleFixture.ms` runs `true`, `examples/counterDom.ms` bundles 0-unsupported (node run
stops at `document.body` — browser API, environmental).

**Files**: recompiler `src/compiler/compile.ms` (two-phase ×2, `exitOnCheckerErrors` + 5 call
sites), `std/core/string/index.jms`, `std/core/struct.jms`; neon `src/platform/browser/dom.ms`.

### 2026-07-29 — LSP object completion inside macro args: THREE stacked roots, none was the filed hypothesis ⚠ UNCOMMITTED

**Symptom** (from the gen-17 session's table): `createStyles({ box: { | } })` and `<div style={{ | }}>`
returned empty completion; hypothesis on file was "post-expansion records don't map back to source
positions." **Wrong** — locations DO survive the VM round-trip (bridge.ms preserves them exactly);
the expansion never RAN in the LSP at all, and once it ran, a same-position record shadowed the
result. Three roots, outermost first:

1. **Subset builds silently disable all macros.** `expandMacroInvocation` reaches the checker through
   `checkerCallbacks.ms`, whose DEFAULT callback returns the node unchanged — no error, no
   "evaluator unavailable", nothing. Registration happens as a module-load side effect of
   `meta/expand.ms:2113`, and NO LSP/transam module imported it — any binary that didn't happen to
   link `compile.ms` (raw probes, per-file `msc test` subsets) had macros silently off. Fix: transam
   side-effect-imports `meta/expand`, same as it already did for `codegen/raiser/eval`. The full
   `msc` binary was immune (compile.ms pulls expand.ms in), which is why batch builds never showed it.
2. **TransAm never registered macro-declaring modules' ctx.** The engine compiles a macro body with
   seeds from the IMPORTER's scope + `lookupModuleCtx(declPath)` (`eval.ms:160-166`). Batch compile
   registers every module ctx in dep order (`checkPass.ms:2139`); the db only tmp-collected dep
   EXPORTS, so `lookupModuleCtx` missed and the body compiled without the declaring module's imports:
   `Macro 'createStyles' body: Unresolved type 'Node'` ×2 → `_failedMacros` → "evaluator unavailable"
   → silent `unknown`. Fix: `dbTypeCheck` pre-checks any direct dep whose exports contain a macro
   (`checkInProgress` set breaks cycles). This is Haxe display-mode parity — macro modules get
   `dms_full_typing` there for exactly this reason.
3. **The macro-emitted callee shadows the literal's contextual record.** Neon-style macros stamp the
   generated `styleOf` callee at the ENTRY LITERAL's position (`style.ms:41`), so re-checking the
   expansion pushes a function record `[col,col+8)` before the literal's contextual record
   `[col,col+1)` — and `sgQueryAtPosition` returns the FIRST record containing the column. Fix:
   `sgQueryContextualTypeAt` (contextual records only: `sym === null`, `kind === Interface`) tried
   first in the ObjectField branch, generic query as fallback.

**Guards**: 2 tests in `completion.ms` — "cross-module macro body compiles in LSP db" (kills root 2;
red form: `Unresolved type 'Node'` + `evaluator unavailable`) and "macro argument literal (Neon
createStyles shape)" (kills roots 1+3; red form: empty items). Both proven red in sequence during
the fix. ⚠ Probe lesson, twice burned: a raw `createTransAmDb` probe is NOT the real LSP — it needs
`dbEnsureModuleExports` preloaded (didOpen parity) AND `meta/expand` linked, or it fails/greens for
the WRONG reason. The decisive measurements came from driving the INSTALLED `msc lsp` over stdio.

**Gates**: battery **3353/3353** (165 files, +2 guards) under both the building and the built binary;
Neon **16/16**; E2E `msc lsp`: both Neon shapes return the full 45-field `Style` set with clean
diagnostics. JSX needed NO extra fix — `element`'s expansion preserves the literal position and its
callee lands elsewhere. Deployed as **gen-18** via `tools/sync-local-binary.sh`.

**Side find**: same-scope redeclaration miscompile (new §2 row) — the probe itself was the repro.

**Follow-up same day (gen-19)** — hardening the guards surfaced a FOURTH root, a pre-existing
shipping crash: `removeExportEntry` (`transam/index.ms`) shifted `registry.entries` and popped but
NEVER touched `registry.moduleIndex` — the removed path kept its mapping and every later entry's
index went stale. `findModuleExports` then reads `entries[staleIdx]`: out of bounds (loud — measured
`index 3 out of bounds (length 3)` killing a real `msc lsp` completion request on gen-18 after a
didChange) or the WRONG module's exports (silent, when sizes line up). Reachable by ANY edit that
invalidates exports, macros or not. Fix: drop the removed path from `moduleIndex` and re-point the
shifted tail. Second lesson, measured three times this session: **raw-db probes lie** — a test
driving `dbSetFileText` directly never records the dependent's import edges, so didChange
invalidation can't reach it and the dependent stays green-stale; the guard test now drives
`handleDidOpen`/`handleDidChange` (lifecycle parity) and the refresh works. Gates: battery
**3356/3356**, E2E didChange probe (padX appears in completion after editing the macro module).

### 2026-07-28 — a missing function-typed field was a silent SIGSEGV (found starting S2) ⚠ UNCOMMITTED

**Symptom.** `terminalHost()` never implemented `Host.setStyle`, which S1 had added to the `Host`
interface. It type-checked, and `host.setStyle(node, st)` on a terminal node **segfaulted** (exit 139,
"before setStyle" printed, nothing after). `domHost()` had the same hole. The Neon suite was 16/16
green throughout because no test put a typed style on a terminal node.

**Root — compiler, not Neon.** MS had no interface-conformance check of any kind. Measured, 8 lines:

```
interface I { a: number; b: number }
const x: I = { a: 1 };              // compiles
class C implements I { a = 1 }      // compiles — `implements` is decoration
return { f: … } as H (no g)         // compiles → h.g(1) → SIGSEGV
```

**Fix — Nim parity, not a TS tightening** (`/trace-nim`). Nim `collectMissingFields`
(semobjconstr.nim:160-173) default-initializes a missing field and errors ONLY when the field type
`requiresInit`. MS's `requiresInit` set is exactly **function-typed fields**: their zero is NULL and
calling NULL is a segfault, so there is no valid default. Value/nullable/array fields keep Nim's
default-init. Opt out with `((…) => T) | null`. Implemented next to the excess-property check in
`src/checker/checkExprPass.ms`; guard `src/test/fixedbugs/bug058.ms` (3 tests, two of which pin
default-init so the rule cannot silently widen). NIM-REF.md §1 has the row, verdict **SAME**.

**Blast radius, measured BEFORE enabling** (throwaway "every field required" build, then classify):
167 missing-field sites in the recompiler + Neon — `Type.sym`, `Node.nodeType`, `FlexStyle.*`,
`FetchOptions.timeout` … **none function-typed**. So the shipped rule broke exactly ONE thing: the
terminal host, i.e. the bomb itself. Post-fix: battery **3346/3346**, Neon **16/16**.

⚠ The full TypeScript rule (every non-`?` field required) was NOT adopted, and the reason is on the
record: `?` is parsed and **discarded** (`parser/statements/declaration.ms:782`), so today it is a
lie in the grammar. Turning it on means plumbing the flag through `InterfaceDeclData` → field symbols
and fixing all 167 sites. That is a deliberate divergence to decide later, not a bug.

⚠ Separately: **`msc build examples/counterDom.ms --target=js` is broken** — `Unresolved type 'Map'`
×3 + `Undefined variable 'Map'`. **Pre-existing**, reproduced on the pre-fix binary. The browser
host's new `setStyle`/`applyCss` therefore compiles under the C checker but has **never been run**.

### 2026-07-28 — §2 row 9 closed: on-demand macro helper errors reach the user ⚠ UNCOMMITTED

**Root.** `ensureCompiledIntoEngine` (`src/codegen/raiser/eval.ms`) compiles a helper a macro body
calls, into the shared comptime engine. It ran a full check pass and returned only `funcIdx`;
`_lastEngineCheckErrors` was deliberately restored to the wrapper's own list by
`compileProgramIntoEngine` (bug053), so the helper's diagnostics were dropped on the floor.

**Fix, part 1 — report.** A `_pendingHelperErrors` queue in `eval.ms`: `ensureCompiledIntoEngine`
pushes its Error-severity diagnostics re-messaged as `helper '<name>': <msg>`, and
`compileMacroIntoEngine` merges the queue into `EngineMacroResult.errors`, which `getOrCompileMacro`
already reports as `Macro '<name>' body: …`.

**Fix, part 2 — refuse.** Reporting alone was still wrong: `getOrCompileMacro` reported the errors
and then **cached and executed the macro anyway**, so known-garbage bytecode ran in the VM. It now
marks the macro in a `_failedMacros` set and returns null, which `expandMacroInvocation` already
handles gracefully (`Macro 'X' evaluator unavailable`, node left unexpanded). The set means the
diagnostic is emitted once, not once per call site. This turns a VM panic / silently-wrong AST into
one precise error — the reason to prefer failing loud here is that the macro's output feeds the rest
of the check, so a bad expansion is laundered into confusing downstream errors.

Guard `src/test/fixedbugs/bug057.ms` (2 tests): a broken helper names itself AND the evaluator is
refused; a healthy helper adds nothing and still folds (`good(21)` → `42` in the C output).
**Proven RED** by commenting out the merge — exactly the diagnostic test fails, the healthy one stays
green.

**⚠ Severity correction — the filed claim was overstated.** The row said "a type-broken helper
compiles to garbage bytecode silently". Measured, that shape could not be constructed: a helper is an
ordinary module function, so every checker error it has is ALSO reported by the normal module check.
Three probes:

| probe | result |
|---|---|
| `const s: string = n` in the helper | **not a checker error at all** — it survives to C and dies there (`used type 'msString' where arithmetic or pointer type is required`). A separate, unfiled gap |
| `noSuchFn(n)` in the helper | module check reports it; the engine ALSO reports it — post-fix the message carries both, which is what the guard asserts |
| `async` helper called from a macro body | **compiles clean, no error from either path** — the fix does not catch it. Still an open silent-wrong-value shape, and NOT the one this row described |

So the value delivered is defense-in-depth for engine-mode-only failures (a helper that checks fine
normally but cannot compile into the VM), not a live wrong-answer fix. Do not re-file this as
high-severity; if the `async`-in-macro-body shape matters, file THAT, with its own repro.

**Gates (re-run after part 2 — refusing to expand is the riskier half).** Battery **3342/3342**
(163 files); `bug056` **2769**; `src/test/c/json.ms` **2776**; Neon **16/16**. Nothing in either
corpus was relying on a macro that expands despite reported errors, and no false-positive flood
appeared — the point of risk, since the engine seeds a stripped context and could invent errors.

⚠ `src/test/fixedbugs/index.ms` fails to compile 4 members (bug006/008/010/047) when aggregated.
**Pre-existing** — the identical set fails on the pre-fix binary (`msc.bak-1785244527`), and each of
them passes standalone. Same class as the §7 "stale aggregator" debt; not caused by this work.

### 2026-07-28 — bindSym: macros emit pre-bound identifiers (Nim semBindSym) ⚠ UNCOMMITTED

The gap bindSym closes is the last SERIALIZE §11 ergonomics row: macros emitted bare Identifiers
resolved in the USER's scope — 7-name import lists, and a user-local `encode` could silently hijack
a codec's callee. Traced Nim FIRST (semmagic.nim `semBindSym`/`opBindSym`, vm.nim `opcNBindSym`):
Nim's shipped bindSym is STATIC — resolved during macro-body sem, stored in VM constants, replayed
by copyTree; sem accepts the returned `nkSym` without re-binding but still re-checks semantics.
MS already owned 90% of that machine from A4: the bake pass (`bakeTypeIntrinsics`), the
declaring-module registry (`macroDeclModuleRegistry`), a real swappable scope
(`lookupModuleCtx(path).table` with ORIGINAL Symbol objects), the EnumMember resolvedSym
short-circuit precedent (checkExprPass:384), and the engine-mode virtual-key door. The ONE missing
link was the bridge: `valueToNode` drops `resolvedSym` (forward-only by design, pinned by test) and
`symbolToValue` is a lossy `{name, kind}` with no handle. Fix = append-only `_boundSyms: Symbol[]`
registry (bridge.ms) + `symHandle` on the baked literal + rebind-on-read with `NodeFlag.BoundSym`.
Checker honors the bound sym as a REPLACEMENT for lookup (flows into normal semantics; bound
overrides at the callee site too — anti-hijack). Survival exemptions: `clearCheckerState`
(instantiate.ms) and `copyNodeMeta` (clone.ms), both beside the existing EnumMember carve-out.
Limits V1 (documented, not hidden): string-literal names only (dynamic dispatch → static branches),
functions/values only (macro names still resolve via the caller's registry), generics rejected.
V2 (same day, gen-13) removed the macro limit: MacroInvocation nodes carry the bound symbol
(read into a LOCAL before `node.data` replacement — the old data's callee is destroyed by the
assignment; violating this was a misaligned-0x5 panic), expansion resolves registries in the
declaring module, and symHandle rides all three serializers so bound identifiers survive nested
macro passage. Remaining, deliberately deferred: dynamic names (static branches; Nim parity),
generics, gensym hygiene (no consumer emits locals yet).
Files: `src/compiler/meta/{expand,bridge}.ms`, `src/checker/{checkExprPass,instantiate}.ms`,
`src/monomorphize/clone.ms`, `std/meta/node.ms` (+1 enum bit), `std/serialize/cbor/encode.ms`
(dogfood), `src/test/helpers.ms` (+`compileProjectToCWithStd`), `src/test/fixedbugs/bug056.ms`,
`src/test/c/json.ms` (imports 7→3), docs `LANG-METAPROGRAMMING.md` ("Binding symbols" section) +
`SERIALIZE.md` §11 row. All guards proven RED by toggling the bake branch off.

### 2026-07-27 (A4) — nodeType readable from macro bodies + two swallowed-error roots ⚠ UNCOMMITTED

SERIALIZE Phase A4 (read-only). The WIRE was never the gap — `mapTypeToAst` (bridge.ms, Days 1-7
complete: struct/array/generic/union+disc/modifiers, visited-stack cycle guard) already ships the
type-AST to the VM, and `jsonValueOf` already walks it. The gap was CHECKER-SIDE: the typed-macro-body
regime typed `t.nodeType` by the class decl (`Type`), rejecting every Node-shaped flat read
(`typExprFieldNames`, `discFieldName`, …) with "Property … does not exist on type 'Type'".

**Why std codecs never showed it (root 1, bug053):** `_lastEngineCheckErrors` is a module-global slot;
`appendProgramToImage` triggers on-demand helper compiles (`ensureCompiledIntoEngine` — e.g.
`detectUnionDisc`) whose nested `transformForEngine` OVERWRITES the slot before `compileMacroIntoEngine`
reads it. Any macro body that calls an imported helper had its check errors silently replaced by the
helper's clean compile. Same lesson as bug051, new coat: never let an error's EXISTENCE depend on
incidental sequencing. Fix: snapshot/restore around `appendProgramToImage` (recursion-safe).
Found by additive bisect: full jsonValueOf copy green in /tmp, minimal clone red, shield isolated to
the `detectUnionDisc(tt)` call. In-battery guard in eval.ms (58→59) proven RED by toggling the fix.

**A4 typing (root 2, bug052):** engine-mode view, NOT a decl change — `nodeType: Node` in std/meta
wedged the toolchain (src/ast/node.ms is a re-export of std/meta; the COMPILER reads
`nodeType.typeChildren` as Type in ~859 places; caught only post-sync because msc resolves the
compiler's own "std/meta" from INSTALLED std, so battery-under-gen-5 measured the OLD decl).
Reverted; instead `checkExprPass.ms` gives engine mode three interceptions: member READ
(`t.nodeType` → Node class type), literal WRITE (`nodeType: ft` key expects Node), call-arg
same-name exemption (§2 row 9). `std/serialize/{json,cbor}/decode.ms` stopped reading `ftype.value`
(NumberLiteral/StringLiteral `value` conflicts under the DU unique-field rule) — push the literal
type-AST node into the emitted tree directly.

Guards: `bug052.ms` (interface fields via nodeType; union members+disc; demo-B witness-pattern key
validation with the macro's own message) + `bug053.ms`, both proven RED pre-fix;
`compileToCWithStd` added to `src/test/helpers.ms` (plain compileToC leaves stdPath empty — std/
entry imports NEVER resolved there, which is why no green macro+std/meta e2e existed before).
Stale `src/test/c/json.ms` rows modernized (atomic arrays are V1.5-supported; discDetect + the CBOR
pair now actually load std via `compileToCWithStd` + the unqualified-identifier import list) — file is
**14/14**, nothing KNOWN-RED.

**Misdiagnosis worth remembering (withdrawn §2 row):** the first shape of this fix returned
`resolvedObjType` — the Ref-PEELED Struct — from the read override, so `detectUnionDisc(tt)` failed
against its `Ref<Node>` parameter as `got Node, expected Node`. That message reads like two distinct
Type instances of one class, and `loader.ms:456`'s real double-load warning made the story plausible;
it was filed as a loader/module-identity debt and papered over with a same-NAME exemption. Measuring
instead of reasoning killed it in one probe: printing `kind` on both sides showed **18 (Struct) vs 27
(Ref)** with `sameSym=y` — one class, one Symbol, two REPRESENTATIONS. Rule: when a mismatch message
names the same type twice, print the TypeKinds before blaming module identity. Guard: bug052 test 4
(`nodeType` flows into a Node-typed parameter), proven RED against the peeled form.

Facts for the next codec session:
interface/class witnesses arrive Ref-wrapped (peel `TypeGeneric → typExprArgs[0]` first — kind 76
vs TypeObject 80 cost this session a bisect); TS-style DU `discFieldName` is empty on the wire
(checker stores no disc — compute via `detectUnionDisc`); bare object literals carry NO contextual
nodeType pre-expansion (validate via a witness param, decode.ms:25 pattern).

### 2026-07-27 (late night, S1b) — macro-emitted literals escaped the excess-property check ⚠ UNCOMMITTED

S1b (createStyles as a real macro, `docs/STYLE.md` §4) surfaced it: a typo'd key in a sheet entry or
an inline `style={{ widht: 200 }}` passed the checker CLEAN and died in C
(`no member named 'widht' in 'struct Style'`) — same class the session prompt filed as "inline typo
caught at the C layer". Repro'd in 18 lines with zero Neon (`/tmp/macdiag`): any macro that wraps its
ObjectLiteral argument in a call to a function with a typed struct param.

**Root (recompiler, two halves of one mechanism):** the checker HAD contextually typed the literal as
`Style` (C emitted `_lit1_->widht = 200` — construction went through), only the REPORT vanished.
(a) `bridge.ms` nodeToValue/valueToNode never carried ObjectLiteral `keyLocations` — every
deserialize site reconstructed with `keyLocations: []`. (b) `checkExprPass.ms` gated the
excess-property AND duplicate-key diagnostics on having a key location, with no fallback — no
location meant the ERROR ITSELF was dropped, not just its range. (The field-type-mismatch check two
branches up always had a location fallback; only these two could vanish.)

**Fix:** (a) `setLocs`/`readLocs` serialize `keyLocations` as `{line, column}[]` under the real field
name — passthrough macros (Neon's createStyles splices the user's literal) now report typos at the
EXACT original key position; (b) both diagnostics fall back to the literal's own location, so no
serialization path can ever swallow them again. Left alone deliberately: the six `keyLocations: []`
sites in `expand.ms` (quote lowering / nodeToASTLiteral build synthetic literals with no source keys
— the (b) fallback covers them).

**Guards:** `src/test/fixedbugs/bug051.ms` (compileToC: excess + duplicate key through a
macro-emitted call arg; proven RED pre-fix) and an inline round-trip test in `bridge.ms` — that one
runs IN the battery (3341, up from 3340). Neon side: `probe/style_neg.ms` (deliberate-red, 2
diagnostics) + `tests/render/style.test.ms` "inline style literal routes through the typed channel".

**Neon S1b landed on top (all green):** `createStyles` rewrites entries to `styleOf(entry)` — checker
does name validation + sheet typing, hand-written `Sheet` interface deleted from the test; static
guards reject non-literal entries and any style field calling a function (sheet AND inline paths,
`Macro 'x':` error at the exact node) until S4. `@comptime` fold deliberately skipped — it would
strip the named typing (STYLE.md §4 note). Projection cache (S1b-4) NOT done — still owed.
**Gates:** battery 3341/3341 ×1 + fixedbugs closure 2763/2763 ×1 (pre-battery); Neon 16/16
file-by-file with `rm -rf out`, `render/style` now 4 tests.

### 2026-07-27 (night, S1 style unblock) — two checker roots under one symptom (`msUnion_gddi8r`) ⚠ UNCOMMITTED

S1 of `docs/STYLE.md` was code-complete but RED: the neon+yoga combined build died with
`operand of type 'msUnion_gddi8r' where arithmetic or pointer type is required` across every
yoga width/height/margin line. The prior session suspected a union C-name hash collision —
**refuted by measurement**: `djb2("union(number|string)") = gddi8r` and
`djb2("union(float32|string)") = 1n6fyl`, exactly the two names observed, so the Type object itself
was corrupted upstream of codegen. Two independent checker roots, both fixed at root, no workarounds.

**A — Maybe cache fused every anonymous composite payload (`checker/types.ms` `maybeCacheKey`).**
Lowering `T | null` → `Maybe<T>` deduped by `"p" + (kind as number)` for any payload with an empty
`typeName` — so ALL anonymous unions shared one key (and all anon arrays another, etc.). Whichever
module checked first claimed the Maybe type; every later module's structurally-different payload
inherited the winner's Type object wholesale. Neon's `Style.width: number|string|null` checked before
yoga's `FlexStyle.width: float32|string|null` → yoga's field became `union(number|string)` → its
`as float32` had no member to select → raw C cast on a struct. **Latent silent-miscompile class**:
`Maybe<number[]>` vs `Maybe<string[]>` fused the same way.
*Fix:* structural suffix for anon composite payloads — checker `typeKey` gained Union/Span/SizedArray
arms and `maybeCacheKey` appends `identSafeKey(typeKey(inner))` for Union/Array/Tuple/Span/SizedArray.
*Guard:* native tier `maybe-union-identity` (LibA `number|string|null` + LibB `float32|string|null`,
main imports A-then-B; RED on pre-fix compiler with the exact neon+yoga signature, GREEN after).
*Nim anchor:* Option[T] instantiation dedups by full type identity — a lossy cache key has no Nim
counterpart to diverge from; this was an MS-side bug, no NIM-REF row involved.

**B — Structural object compat ignored field REPR; `as<X>` synthesis missing at assignment + nullable formals.**
Probe (`compatProbe`): `A{w: number|string|null}` was silently accepted where
`B{w: float32|string|null}` was expected — call-arg AND assignment — and ran to garbage (read 0,
stored 5): structural assign raw-casts the ref, no per-field conversion exists, and per-field
`isAssignable` allowed `number→float32` inside the union. Same class as NIM-REF "Container element
assignability" (Nim `typeRel` keeps elements INVARIANT, sigmatch.nim:1502; enforcement CENTRAL in
fitNode, SCOPED to `isReinterpretUnsafe` — that scope was re-traced 2026-07-21 and is TERMINAL, so
this fix EXTENDS the memory-safety class rather than flipping on general `!isAssignable`):
- `compat.ms isObjectAssignable`: shared-name fields now also require repr match
  (`fieldReprMismatch` — union fields member-for-member: C tag = member index, payload width = member
  repr; numeric fields same C width; pure string-literal unions ≡ `string` ≡ literal — msString repr).
- `compat.ms isReinterpretUnsafe`: Struct-vs-Struct arm walking SHARED fields only (disjoint names
  ignored — `T|null→T` flows and Ref→Ptr cursor divergence untouched), plus `X | null` peels both
  directions, plus depth guard.
- `checkExprPass.ms trySynthesizeAsCoercion`: targets/receivers/returns peel `X | null` and unnamed
  `Ref` wrappers (interface members sit behind kind=Ref, typeName="" — method naming and return-type
  match previously bailed on them). Result: `layoutStyle = style` now auto-inserts `.asFlexStyle()`
  exactly as `docs/STYLE.md` §5 designed — assignment joins var-decl/call-arg/return as a working
  coercion context — and with no extension in scope it is a compile ERROR, never a raw store.
*Guards:* `src/test/handoff/typeCoercion.ms` +9 unit (struct field repr) and NEW
`src/test/c/asCoercionNullable.ms` 4 e2e (assignment synthesis, nullable-field error, var-decl error,
call-arg-through-nullable synthesis). ⚠ Split from `protocols.ms` because that file is PRE-BROKEN
(its 4 `compileProjectToC` call sites reject un-annotated `const entries = [{...}]` arrays — reproduced
on the pre-session binary; NOT caused by this work; the battery never runs it — §7 family).
*Neon side:* `setDim` restructured to the established `typeof`-guarded if/else with `v as number`
member-select (symmetric with the `v as string` branch — the same idiom yoga uses; the earlier
`(v as number) as float32` double-cast was dropped: number→float32 narrows implicitly at the call).
`setStyle` stays exactly as designed — no manual projection call.

**Gates (all on the gen-4 binary, `rm -rf out` per step):** recompiler battery **3340/3340 (163/163)**
×2 (after A, after A+B); `typeCoercion.ms` 464/464; `asCoercionNullable.ms` closure 2764/2764; native
`maybe-union-identity` green; **Neon 16/16 files** including NEW `render/style` (typed sheet → VNode →
void host asFlexStyle projection → yoga layout, legacy string path, `withStyle`).
Changed: recompiler `src/checker/{types,compat,checkExprPass}.ms`,
`src/test/handoff/typeCoercion.ms`, `src/test/c/asCoercionNullable.ms`,
`src/test/native/{manifest.ms,programs/maybeUnionIdentity*.ms}`; neon `src/platform/void/host.ms`
(setDim narrowing shape only).

### 2026-07-27 (late, deep-probe pass) — two more roots the first "green" hid ⚠ UNCOMMITTED

Both were found by probing the Root-2 fix rather than trusting it, and **neither was caused by it**.

**A — Raiser: string `<` `>` `<=` `>=` compared HANDLES (silent wrong answer).**
`compileBinaryExpr` (`codegen/raiser/expressions.ms:369`) computes
`isStrCmp = isComparisonOp(op) && exprIsString(...)` — and `isComparisonOp` returns true for all eight
operators — but only `==`/`===` (EqStr) and `!=`/`!==` (NeStr) had branches. The other four **fell
through to the numeric tail** and compared the two string handles with `BxxI64`. So the code proved the
operands were strings and then discarded that fact. Wrong in macros **and** `@comptime`; correct at
runtime. `"abc" < "abd"` → **false**. ⚠ The trap that hides it: `<=`/`>=` on two EQUAL strings returned
true even while broken (equal handles), so equality-only coverage looks fine.
*Nim (read this session):* `<`/`<=` on strings are magics (`lib/system/comparisons.nim:42,85`
LeStr/LtStr) → their own opcodes (`vmgen.nim:1216-1217`) → real lexicographic compare
(`vm.nim:1250-1255`). `>`/`>=` need no opcode — Nim derives them by swapping operands. There is no
path by which an unhandled string comparison becomes integer comparison. NIM-REF: **0 hits** for any of
this, so nothing was intentional. **Verdict DIVERGE-INCOMPLETE → SAME** (the mechanism existed, only
the equality half was ever built).
*Fix:* append `LtStr`/`LeStr` to the opcode enum + disasm + VM handlers, and one codegen arm covering
all four operators via operand swap. ⚠ **Appended at the END on purpose:** `src/raiser/vm_dispatch.c`
hardcodes opcode NUMBERS (`#define OP_EQ_STR 29`), so a mid-enum insert would silently desync it —
that file is currently INACTIVE (not `@include`d, already missing `CallHost`), which is what makes
appending safe.
*Guard:* `src/test/lang/comptime.ms` — 12 ordering cases including strictly-ordered `<=`/`>=`, param
receivers, and `"Z" < "a"` / `"ab" < "abc"`. RED evidence: `/tmp/sc` on the pre-fix binary printed
`lt=0;gt=0` and `CT_lt=0`.

**B — hash mixing overflowed a signed int64 → UB trap. This was the `reconcile` "flake".**
`msPtrHash` (`runtime/core/system.h:436`) did `(int64_t)folded * (int64_t)2654435761LL`. `folded` is a
full 32-bit XOR-fold of the pointer, so the product reaches ~1.14e19 — past `INT64_MAX` (9.22e18) —
which is undefined behaviour and **traps**: `thread panic: signed integer overflow: 3724608947 *
2654435761`. It fired only when the ASLR'd pointer folded high enough, which is exactly why it looked
like a flake. Measured on `reconcileHard`: **2 failures in 6 runs** before, **0 in 8** after; the whole
Neon suite then ran 2×15 files with 0 failures. Chain:
`reconcile.ms:72 map.has(...)` → `Map_set__unknown_number` → `struct.ms:99 hash()` → `msPtrHash`.
`std/core/struct.ms:82` `hashNumber` had the **identical** bug and is reachable deterministically
(`hashString` was already safe — it masks inside the loop).
*Nim:* all hash mixing is unsigned — `hashWangYi1` uses `uint64` constants and `hiXorLo(a, b: uint64):
uint64`, casting to the signed `Hash` only at the end (`lib/pure/hashes.nim:166-178`).
**Verdict DIVERGE-UNINTENTIONAL → SAME.** *Fix:* do the multiply in `uint64` in both places (verified
empirically that MS `uint64` wraps instead of trapping: `(2^32-1) * 2654435761 & 0xFFFFFFFF =
1640531535`). Masked results are unchanged for every input that did not trap.
*Guard:* an inline test in `std/core/struct.ms` pinning `hashNumber` at the 32-bit boundary + a
`Map<number,_>` round-trip. **This one runs IN the battery** (163 files / 3339 tests, up from
162/3338) — unlike the handoff guards, it cannot be silently skipped. Expected values were computed,
not guessed (one of three was wrong on the first write).

**DRY (the part that keeps B from coming back).** The two Knuth copies were the reason one got fixed
and the other stayed wrong, so they are now one: the C side folds only (`msPtrHash` → **`msPtrFold`**,
single caller) and `hash(this u: unknown)` routes through `hashNumber`. Exactly one mixing site exists,
and `struct.ms`'s in-battery test asserts the routing (`a.hash() === hashNumber(msPtrFold(a))`) so a
reintroduced second mixer drifts visibly instead of silently. Left alone deliberately: the djb2
duplicated between `struct.ms` and `std/hash/index.ms` — they are independent layers with no import
relation, and `struct.ms`'s own DRY note already tracks it (docs/GAP.md #7). Not a layering change to
make mid-session.

**Class audit (bounded, not a spot fix).** The hazard is exactly `32-bit-masked value × multiplier
≥ 2^31`. Every candidate checked: djb2 `×33` → 1.4e11 ✅, FNV-1a `×16777619` → 7.2e16 ✅,
`tv_sec × 1000` → 1.7e12 ✅. Only Knuth's 2654435761 crosses INT64_MAX. **Both instances fixed; no
third exists.**

**⚠ The crash was luck, and that matters more than the crash.** `msc test` defaults to **zig cc**
(`cc.ms:141` auto-detect prefers it) whose debug UB checks trap signed overflow — that is the only
reason this surfaced. Under `--danger`/release the same line is **silent UB**: the optimizer may assume
no overflow, the hash degrades to garbage, Map lookups miss and reconciliation goes wrong **without a
crash**. This bug was strictly more dangerous in production than in the test suite.

**Gates:** battery **3340/3340 (163/163)**, exit 0; Neon **15/15 twice over, 0 failures in 30
file-runs**; new guard `unknownKeyIsBorrowed` green under drc.
⚠ `src/test/guard/run.sh` is **6/7 unbuildable in this environment** — zig cannot parse the macOS SDK
`.tbd` stubs (`failed to parse TBD file: NotLibStub`), which is why the new guard could only be
verified under drc. The 7th, `asyncRethrowPropagates`, builds and **deterministically aborts with
DOUBLE-DESTROY of Error** — it is an UNTRACKED file from an earlier session, red before this one, and
its own header points at `/trace-nim buildExcRouting`. **Neither is this session's doing; both are
open debts.**

### 2026-07-27 (late) — `voidHost` GREEN: FOUR roots, and the filed diagnosis was wrong on both counts ⚠ UNCOMMITTED

**The row said "1 test-code type error + a missing native dependency". Neither was true.** The type
error had already been fixed by an earlier session and never re-measured; `sokol_gfx.h` was present
at `void/deps/sokol/` the entire time. Peeling the real blocker off exposed three more beneath it —
each only reachable once the one above it cleared, which is why one "environment gap" hid four bugs.

**Root 1 — `@passC` relative `-I` resolved against CWD, not the declaring module (COMPILER).**
`@compile("./x.c")` resolves module-relative (`compile.ms` explicit `./`/`../` arm), `@include` adds
`-iquote<moduleDir>` automatically, `@link` uses `getModuleDir` — **`@passC` alone had no
module-relative path**, so `resolveIncludeDir` tried CWD then the global include search list. A
module carrying `@passC("-Ideps/sokol")` therefore compiled **only while the process ran from its own
project root**, and broke the instant a second project imported it. Neon → `void/src/sokol/gpu.ms` is
exactly that shape, and it surfaced as `fatal error: 'sokol_gfx.h' file not found` — which reads as a
missing dependency, hence the wrong diagnosis. Reproduced in **6 lines with zero Neon/void
involvement** (`/tmp/passcrel`): GREEN when run from the module's own dir, RED from anywhere else.
Fix: `collectOneDirective`'s passC arm (`checker/checkPass.ms`, +25) resolves a `./`- or
`../`-prefixed `-I`/`-iquote`/`-isystem` against `getModuleDir(ctx.modulePath)`, mirroring the arm
`@compile` already had. Bare dirs keep CWD-then-search so std's `-Ivendor/...` is untouched.
Void-side: `gpu.ms` + `gpu.wms` now say `-I../../deps/sokol`.
**Guard:** `src/test/handoff/passCModuleRelativeInclude.ms` + `fixtures/passCRel{Include,Shared}/`
(covers both `./sub` and `../sibling`) — proven RED (`'passcRelDot.h' file not found`) → GREEN.

**Root 2 — the Raiser inferred "is this a string?" from the AST instead of the resolved type
(COMPILER).** ⚠ **This row originally recorded a SYMPTOM PATCH and was rewritten after `/trace-nim`;
read the correction, it is the more useful lesson.**

*First (wrong) diagnosis:* a macro body doing string work died on `Unknown host function:
msStringCharAt`, so `charAt`/`slice` bridges were added to `compiler/meta/hostTable.ms`. That made the
error go away and **it was not the root** — it was pattern-matching the failing idiom.

*What the trace found.* `exprIsString` (`codegen/raiser/expressions.ms:142`) is headed
*"String type inference (AST-based, no checker needed)"* and its Identifier arm is
`return isLocalString(s, d.name)` — an **early return**. A function **parameter** is an Identifier that
no local-string table knows, so it answered false and never reached the `node.nodeType` check sitting
at the bottom of the same function. One short-circuit, two symptoms: `.length` on a string param
emitted **ArrayLen** against a string handle (`array handle out of bounds: 0`) and `charAt`/`slice`
missed their opcodes and fell to CallHost. The bridges only ever hid the second symptom.

*Nim (`vmgen.nim:1122`, read this session).* Nim dispatches on the operand's **semantic type**:
`case n[1].typ.skipTypes(abstractVarRange).kind` → `opcLenStr` / `opcLenCstring` / `raiseAssert` —
`mHigh` (:1276) does the same. Nim has no AST-based guessing layer and **never silently falls back to
the seq opcode**. NIM-REF row 70 makes the Raiser's standalone-Program VM DIVERGE-INTENTIONAL, but it
also records that this pipeline runs `check + refineTypes`, so the resolved type **is** available —
nothing licensed the AST-first order. **Verdict: DIVERGE-UNINTENTIONAL → SAME.**

*Fix (1 file):* hoist the resolved-type check to the top of `exprIsString`, making the type the
authority and the syntactic arms a fallback for genuinely untyped nodes.
*And the symptom patch was REMOVED:* with the invariant restored the bridges are dead code — proven by
rebuilding with the registrations deleted (`mscNB`) and watching the param ladder still print
`len=5;loop=abc;slice=bcd`. They were deleted rather than left in, because a second dispatch path
would silently absorb the next instance of exactly this bug instead of surfacing it.
**Guard:** `src/test/lang/comptime.ms` — `@comptime` calling helpers whose receiver is a *parameter*,
now anchored on `.length` and a `while (i < s.length)` scan, which have **no** CallHost fallback and so
fail on the root alone. RED evidence: `/tmp/aud2` on the pre-fix binary, **with the bridges present**,
`Macro 'mLen' failed: array handle out of bounds: 0`.

⚠ **How Root 2 was actually caught — the first "15/15 green" was hollow.** With only the bridges in
place the whole suite reported green, and it was WRONG: `element.ms`'s `cleanJsxText` ran on the broken
`.length` dispatch and silently mangled its output. A dedicated whitespace test written afterwards
showed `<p a="1">\n hello \n</p>` rendering as **`<p a="1"></p>` — the text destroyed**, which is worse
than the bug being fixed. It passed only because **every pre-existing JSX test in this repo is written
on one line**, so multi-line JSX was entirely unexercised. Two lessons worth keeping: a green suite
proves nothing about a path no test walks, and the algorithm was exonerated by lifting it verbatim into
a **runtime** test (5/5 pass) — which is what localised the fault to the macro VM rather than the code.

**Root 3 — the `element` macro never applied JSX whitespace rules (NEON).** Multi-line JSX produced
literal newline/indent text nodes: the div had **5** children instead of 2, and `p`/`button` were
off by one, so `children[0]` indexed into whitespace and the binary died with
`index 0 out of bounds (length 0)`. This is not a compiler bug — `LANG-JSX.md:92` and JSX-ROADMAP 2.3
state the design explicitly: JSXText is emitted as the **raw slice**, "neither lexer nor parser trims,
the **consuming macro** applies any whitespace rules, keeping the compiler opinion-free". Neon's macro
simply never implemented its half. It went unnoticed because every other JSX test
(`counter`, `element`, `renderToString`) is written on **one line**. Fix: `cleanJsxText` in
`src/macros/ui/element.ms` implements Babel's `cleanJSXElementLiteralChild` — a text child spanning
lines has each line's indentation stripped and is rejoined with single spaces; a whitespace-only one
collapses to `""` and is dropped; text with no newline is significant and passes through untouched.
⚠ `element.ms` is a **sacred file** — all 15 Neon files were re-run after this change.

**Root 4 — the test's own expectations were never valid (NEON).** The file was committed RED (§4) and
had therefore never executed a single assertion. Two were simply wrong: `<p>Count: {x}</p>` yields
**two** host children (a static label + an independently-updatable dynamic one), not one merged
`"Count: 0"` label — the DOM host behaves identically, and merging would defeat fine-grained updates.
Also `FlexStyle.width` is `float32 | string | null` (yoga accepts `"50%"`), so it needs yoga's own
proven `typeof`-guarded narrow, not `===` against a raw number. ⚠ **A probe of mine first concluded
`as float32` was a compiler gap; that was wrong** — `as` narrows only inside a `typeof` branch, as
`yoga/src/style.ms:167` already does. Checked before "fixing" the compiler; worth repeating.

**Gates (re-run after the Root-2 root fix, all exit 0):** battery **3338/3338 (162/162)**; Neon
**15/15**, `rm -rf out` per file; both guards standalone (`comptime.ms` 334, `passCModuleRelativeInclude`).
⚠ Per the toolchain note **the battery does not run the guards** — run them standalone or they are skipped.
`render/element` went 276 → **282**: +6 whitespace tests, the coverage whose absence let Root 2 hide.
Changed: recompiler `src/codegen/raiser/expressions.ms` (the root), `src/checker/checkPass.ms`,
`src/test/lang/comptime.ms`, `src/test/handoff/{index.ms,passCModuleRelativeInclude.ms,fixtures/…}`;
void `src/sokol/gpu.{ms,wms}`; neon `src/macros/ui/element.ms`, `tests/render/{element,voidHost}.test.ms`.
`src/compiler/meta/hostTable.ms` is back to its original content — the bridges added mid-session were
removed once the root landed. **All of it is UNCOMMITTED.**

### 2026-07-26 (late) — #6 closed: cross-module `new Generic<T>()` never instantiated its constructor ✅ COMMITTED `1e1db2a` — DEPLOYED Jul-27

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

### 2026-07-26 (late) — #7 closed: NOT a compiler bug — `indexArray` index-stored past the end (Neon-side) ✅ COMMITTED `f5824b7`

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

### 2026-07-26 (late) — #2 closed: the C array prelude never had a generic `slice` ✅ COMMITTED `33dca18` — DEPLOYED Jul-27

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

### 2026-07-26 (late) — flow #3+#4 closed: THREE compiler roots, none where BUGS.md pointed ✅ COMMITTED `bbc2e3c`+`c41f1a3`+`6422400` — DEPLOYED Jul-27

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
Landed one commit per root: `bbc2e3c` (parser typeArg), `c41f1a3` (anon `?`), `6422400` (ref
truthiness + the three guard registrations). Deployed Jul-27 with the rest of the session.

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

`signal`, `memo`, `dispose`, `array`, `element`, `host`, `hostOps`, `reconcile`, `reconcileHard`,
`renderToString`, `region`, `counter`, `flow`, `terminal`, `voidHost` — **all 15 files green on the
installed `msc`** (deployed 2026-07-27 late, verified post-deploy sweep). The reactive core + render
layer + control flow + the Void host are solid;
re-run them on every compiler deploy. Two of the last three compiler fix attempts were caught by
exactly this suite and not by the battery (the rejected void-callback inference fix regressed 7 of
these while the battery stayed clean at 3330/7) — **the Neon suite is a stronger gate than the
battery for closure/inference work.**

---

## §7 — Small debts (not bugs, but owed)

Each is cheap, none blocks anything, all were surfaced by the sessions that closed §1.

- ~~**JS std string is ~19 exports behind cms**~~ **CLOSED 2026-07-29 (night)**: 18 exports ported
  as pure-MS byte loops matching `runtime/core/string.c` semantics + `lastIndexOf` gained
  `startIdx`/int64 (silent signature drift). Same pass fixed FOUR cross-backend divergences —
  same source, different answers per backend: `toLowerCase/toUpperCase` (JS Unicode vs C ASCII
  `tolower`; `"ÉÀ"` repro), `replace` (JS interprets `$&`/`$1`/`$$`, C is literal), `split("")`
  (UTF-16 chars vs BYTES), `byteLength` (int32 vs int64). Surface guard in `src/test/js/basic.ms`
  (red-proven); semantics verified by dual-backend probe — one source under `./msc run` vs `node`,
  59/59 values identical (the suite has no C-vs-JS runner, so the probe is the only guard for this
  class). ⚠ Two traps for future `.jms` work: a `.jms` export SHADOWS the JS global of the same
  name (`parseFloat` recursed into itself — use `Number.*`), and the with-std harness checks std
  export signatures only, NOT bodies (three int64/int32 errors passed a green suite). Committed
  recompiler `5d7b0dc`+`80d12da`. Still open: `String<T>` (`String(42)` is a type error on JS —
  collides with `extern class String`; needs a design call, see the same-scope redeclaration row).
  Follow-up: single-source std string blocked only by the §2 asBytes row.
- ~~**The gen-20 two-phase fix has NO automated guard.**~~ **CLOSED 2026-07-29 (late evening,
  gen-21 session)**: `compileProjectToJS` refactored to two-phase (`emitJSTwoPhase` — expand ALL,
  then transform ALL, macro diags surfaced as `ERROR: expand [mod]`), new
  `compileProjectToJSWithStd` (std from disk, `.jms`), and the jsxmacMod/jsxmacUse pair baked into
  `src/test/js/basic.ms`. Guard proven RED the honest way: with expansion merely *skipped* it stays
  green (gen-19 made check-time expansion cover the all-checks-first order) — the toggle that
  reproduces gen-20 is re-adding an INTERLEAVED `transformProgram` inside the check loop (exactly
  1 fail in 2769). js/basic closure 2769/2769, js/result closure 2766/2766.
- **cmdRunRaiser and the C build loops still interleave transform with expansion** — same hazard
  family as gen-20 root 1. C survives today because its expansion runs post-mono inside the same
  iteration, before that module's OWN transform; whether the engine tolerates every C-transformed
  helper body is unproven. Align on the two-phase shape when next touched.
- **`instantiateClassConstructor` still fails silently.** #6 was invisible for weeks because the
  function `return`s when it cannot reach the ClassDecl. With the fix the reachable path is correct,
  but a genuinely unreachable declaration should be a loud checker error, not silence. Not done in
  the #6 commit on purpose: the `pickBodyCtx` fallback also fires when the defining module's ctx is
  not registered yet (import cycles), so a hard error could fire on shapes that work today —
  **it needs a battery measurement before it is turned on**, not a guess.
- **LANG.md never specifies optional fields.** `field?: T` is accepted on both the interface token
  path and (since `c41f1a3`) the anon-object string path, and on both it is **cosmetic**: no
  missing-key check exists anywhere, an omitted field is zero-init (`ref → NULL`, value-Maybe →
  `present = false`). That de-facto rule should be written down, or deliberately tightened.
- **`msc test src/test/index.ms` is broken on a pristine tree** (74 type errors, reproduced on
  installed-pristine as well). It is a stale aggregator, not a regression — but while it is broken
  the handoff guards only run standalone, so a future session can silently skip them. Either fix it
  or delete it.
- **Neon `probe/` housekeeping** — `macro_disambig` / `macro_lenval` still assert the formerly-WRONG
  values (deliberate RED bracket-tests); `macro_narrow` N1 is red BY DESIGN (Nhịp-2 marker). Rewrite
  truth-only or delete at leisure, but do not read them as failures.
- **"Yoga vendoring never happened / `deps/` is EMPTY" was FALSE** (corrected 2026-07-27 late).
  `deps/yoga -> ../../yoga/deps/yoga` exists and resolves to a real checkout — it is what `voidHost`
  links against, and the yoga port in `~/metascript/yoga` is a working MS binding (`FlexStyle`,
  `applyStyle`, `layoutPass`). What is missing is only a *vendored in-repo copy*; the dependency
  itself is present and used. CLAUDE.md still lists `src/yoga/` as an empty TODO — also stale, the
  layout engine lives in its own repo.
- **`src/test/guard/run.sh` is 6/7 unbuildable here** — zig cannot parse the macOS SDK `.tbd` stubs
  (`failed to parse TBD file: NotLibStub`), so most nim-guards cannot run in either gc mode and the
  new one could only be verified under drc. Either pin a working SDK/zig pair or teach run.sh to fall
  back to `--cc=clang`. Until then the guard suite reports environment noise, which is how a genuinely
  red guard can hide in it.
- **`src/test/guard/asyncRethrowPropagates.ms` is RED and UNTRACKED.** Deterministic
  `DOUBLE-DESTROY of Error`; written by an earlier session, never committed, red before 2026-07-27.
  Its header already names the trace target (`buildExcRouting` in generatorLower.ms + the ThrowStmt arm
  of analyzer/inject.ms). Commit it or delete it — an uncommitted red guard is invisible to everyone.
- **`Map<unknown, V>` does not own its keys, and nothing says so.** Row 57 makes `unknown` RC-inert by
  design (Nim `pointer`), so this is correct — but `type HostNode = unknown` means Neon's whole host
  layer relies on it silently. A cache keyed by `unknown` that outlives its keys dangles with no
  diagnostic. Guarded now (`unknownKeyIsBorrowed`) + NIM-REF row added; still owed a line in LANG.md
  and in Neon's `hostTypes.ms` stating the borrow contract.
- **`@passC`/`@compile` project-root-relative paths are a trap for any cross-project import.**
  Root 1 in §5 fixed `@passC`'s `./`+`../` forms, but `void/src/sokol/gpu.wms` still carries
  `@compile("src/sokol/bridge.c")` (project-root-relative), which breaks identically from another
  CWD. Not fixed here because the wasm path is unexercised — fix when it surfaces.
