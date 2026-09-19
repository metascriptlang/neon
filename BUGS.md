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
off-path compiler debts in §2 — **loop + nested-closure snapshot CLOSED 2026-08-07**; the silent
wrong-answer debts now are the `FnN` void-arrow assignability row (new) and the uint8[] non-push
methods (the void-generic-instantiation row CLOSED 2026-08-07 late — the 4 blocked Neon tests
are green) —
(3) the small debts listed in §7.

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

## §2 — Open compiler bugs (16 + JS flat-scope stage B; converter name-keying row CLOSED 2026-08-09 same day via /trace-nim (resolved-type matching, bug101, staged); the 2026-08-09 D4 row — generic class methods emit `function …(this)` on JS — **CLOSED same day via /trace-nim** (receiver binding `$this`, staged in recompiler, deploy pending); two rows added 2026-08-09 by the D3 flatten probes — macro-engine local-closure holes, `msc run` test-block facts; expr-bodied-arrow env row CLOSED 2026-08-07 late) — flat-scope row added AND stage-A closed same day 2026-07-30; rows 1-3 + 5-7 re-verified 2026-07-25 late; row 4 added 2026-07-26 late; row 8 added 2026-07-27 late; row 9 CLOSED 2026-07-28 (kept struck-through, its severity note is a lesson) and two rows were added the same day by the probes that closed it; same-scope redeclaration row added 2026-07-29; asBytes-on-C row added 2026-07-29 night and CLOSED 2026-07-29 late night (kernel pair landed, see §5) — the probes that closed it added two rows (uint8[] method widening, bug006 standalone divergence) and the /trace-nim audit added a third (bridge ownership, 3 holes); the A4 "dual-Node" row was WITHDRAWN — misdiagnosis, see §5; two rows added 2026-07-30 by the component-design probes (thunk-field closure garbage — SILENT, and expr-bodied-arrow env); the converter name-keying row was added 2026-08-09 by the D5 P1 probe and BLOCKS the direct-emission build switch

| bug | repro | measured today |
|---|---|---|
| ~~**a closure mutating a captured local writes a DUPLICATE env field — the outer frame never sees the write (SILENT)**~~ ✅ **CLOSED 2026-09-05 (recompiler, this session)** — root: `tailCallLower` (pass 16) rewrites a self-tail-recursive fn into `while (1) { … }`, so every body-scope local sits inside a LOOP BODY by the time `lambdaLifting` (pass 20) runs; the lifter's loop rule then allocates a per-closure SNAPSHOT env and marks the rewrite `snapshotOnly`, which by design leaves the enclosing code reading the function-wide shared env — two homes for one mutated variable. The Neon symptom was the narrow end of it: the same defect hits an ORDINARY `for` loop whenever the body reads or writes a captured local AFTER the closure is created (guard cell measured `per-iteration=10,11` instead of `110,111`). Fix follows Nim's env-placement rule (an env belongs to the scope that DECLARES the captured var; a mutated capture is never duplicated): a captured name declared inside the loop body makes the snapshot env that iteration's only home, so the rewrite activates for the rest of the body and RECLAIMS the `_env_fn_->x` member reads that the shared-env rewrite already installed at the OUTER statement level (`redirectFrom` — needed because the whole closure-bearing statement is rewritten as one subtree before the lifter ever descends, so matching bare idents alone finds nothing left). Names declared outside the loop keep the old path, so bug092's per-iteration cells stay green. Guard `src/test/guard/tailrecClosureEnvAlias.ms` (GUARD-JS, both facets, PROVEN RED pre-fix on drc AND orc via a same-tree same-session control binary). Gates: battery **178 files / 3559 tests / rc=0**, minimal repro `tailrec=[written]`, Neon `probe/ctxSsr_e2e_a9f4.ms` now `ssr=[<div>blue</div>]`. Original report below | 11-line minimal repro: a self-tail-recursive fn whose non-tail branch declares `let out = ""`, hands `() => { out = "written"; }` to a helper, then returns `out` — the twin with the recursive call moved OUT of tail position is GREEN. E2E `probe/ctxSsr_e2e_a9f4.ms` — `ssr=[]` while the closure's own re-read prints `inner=[<div>blue</div>]`. ⚠ the original single-delta ladder (`scopeStrCap`/`scopeRts_v2`/`v3`/`v4a`/`rts4mod`+`rts4use`) was ALL GREEN and sent the first diagnosis down a "needs recursion + generics + 3 modules" path — not one of those probes put the closure inside a TAIL-recursive fn, which was the only load-bearing ingredient | ❌ C evidence: TWO env structs `dollarEnv_renderToString_shared_` + `dollarEnv_renderToString_7_` EACH carrying `out`; `_lit8_->dollarup_ = _env_renderToString_` (up-chain CORRECT) but `_lit8_->out = dollarborrow_39_` is a VALUE snapshot; the lifted body writes `env7->out`, the enclosing fn reads `_env_renderToString_->out` → `""`. The `while (1) {` wrapper at the top of the emitted function is the tell. Pin `tests/render/context.test.ms` "renderToString sees through a provider" was RED on C / GREEN on JS; the C fix is proven by the probe, but the test file cannot be re-run under the fixed binary yet — recompiler main carries a SEPARATE pre-existing regression that breaks Neon's globalImports/JSX lowering (`Undefined variable 'createComponent'`, 26 errors; a control binary at the same commit without this fix fails identically) |
| **a LOCAL variable mutated by a closure inside an `async` fn is not seen by the caller after `await`; module-level vars are** (NEW 2026-09-03, suspicion found while measuring the std timer; NOT root-caused — needs its own arc) | `probe/timerC_w7p4.ms` — `let log = ""; const id = setTimeout(() => { log = log + "fired;"; }, 20); await sleepAsync(60);` then print `log`; the JS twin `probe/timerJs_v3k8.ms` runs the same shape | ⚠️ C lane: the callback RUNS (its own `console.log` prints) but `log` still reads `""` after the await — the mutation landed on a copy or a dead frame. Module-level `let fired` in `probe/timerTest_b5j9.test.ms` observes fine (assert passes), which is why the test lane never caught it. Neon dodge (shipped): `press.test.ms` records gesture callbacks into SIGNALS (`createSignal`), never into a captured local read after `await` |
| **engine-synthesized expr-bodied thunk AROUND a user arrow miscompiles on C (rc=255, silent); the identifier variant is a SILENT no-op on JS** (NEW 2026-09-03, found shipping the RN components; CURRENTLY UNREACHABLE from handler props — arrow attrs cross raw since the prop-contract change — but live debt for any arrow-valued thunk prop) | ladder in `probe/`: m1 `closureRetByVal_q7f` (local double-call) GREEN ×2 lanes · m2 `thunkField_q8g` (thunk in struct field, block+expr bodies) GREEN ×2 · m3 `compEvt_r9h` (hand-written createComponent + thunk prop + evt + fireEvent) GREEN C+JS · m4 `macroThunk_s2j` — through the REAL element() macro: m4a (identifier thunk, i.e. a user passing a thunk-valued handler = double-thunk) crashes C rc=255 AND prints hits:0 on JS; m4b (inline arrow, correct usage at the time) also killed C before the m4a fix landed | ❌ the delta m3→m4 is ONLY that the thunk arrow is ENGINE-SYNTHESIZED (`{arrowParams: [], arrowBody: <user arrow>}`) rather than parsed. Same family as the DRC "no type info" warnings for engine fns (`emitEl` etc.): synthesized nodes miss what lifting needs. NOT root-caused. Neon dodge (shipped): arrow/function-literal ATTRS cross RAW and take the field's flat type — bug118's padding makes arity subsumption safe — so handler props never synthesize thunks; the double-thunk shape is now a loud type mismatch |
| **converter registry cannot serve array-typed boundaries — a single element child into a USER component's `children: NeonNode[]` prop has no lowering; registering a `NeonNode[]` converter hijacks OTHER targets and its nested MacroInvocation never expands** (NEW 2026-09-03, found migrating children contracts) | `<Wrap><li>only</li></Wrap>` with `children: NeonNode[]` → `error: JSX expression must be consumed by a macro; import a converter targeting 'NeonNode[]'`; adding `jsxToNodeArray` to converters.ms fixed nothing but BROKE Card (`children: NeonNode`) and Show (`children: NeonView`) — the array converter matched THEIR targets, and its ArrayLiteral element (`<none>[]`) never lowered | ⚠️ two stacked compiler debts: (1) registry matching is loose — a converter returning NeonNode[] was selected for NeonNode/NeonView fields; (2) a MacroInvocation nested inside a CONVERTER result does not re-expand (macro-emitted ones do). Neon dodge (shipped): the starter vocabulary's single-element children wrap `[element(…)]` MACRO-side (tag-name set in element.ms/direct.ms); user components with array children write multiple children or expressions until this closes |
| ~~**declared `: number` return with an int64-returning body emits NO conversion on JS**~~ ✅ **CLOSED 2026-09-03 (bug121, recompiler)** — root: `fitNode` marks the 64-bit representation boundary with a `HiddenStdConv`, but `isWideningInt64Conv` guarded on the TARGET KIND (`Int64`/`Uint64`) while `integerRank` already ranks floats above int64 (7/8 vs 9/10), so the EXIT leg (64-bit → float slot) matched neither predicate and `lowerBigIntJS` had nothing to consume. Fix = guard on "one side is 64-bit", keep the rank test; both consumers already handled it (`bigConvert`'s `isFloatKind` row emits a bare `Number(x)`, C emits the cast it was doing implicitly, `rangeCheckInject` skips float targets). Measured: JS matrix 4/4 positions correct, C unchanged, battery 176/3533, fixedbugs A/B identical red set, **neon sweep now C 30/30 · JS 30/30**. Original report below | (NEW 2026-09-03, PRE-EXISTING — self-built v0.2.52 control @`1a82ae9b` fails IDENTICALLY, so NOT the v0.2.53 padding arc; std skew also ruled out, repo-std leg fails the same) | `probe/parseIntRet_j6w.ms` — `function toNum(v: string): number { return parseInt(v); }` then `80 - toNum("3") * 2`; real hit: `getAttrNum` (`src/platform/terminal/paint.ms:121`) → `tests/platform/terminal.test.ms` is the ONE red in the 28×2 sweep (JS lane only) | ❌ JS: `TypeError: Cannot mix BigInt and other types` at `p * 2` — the checker accepts int64→number at the return fit but JS emission materializes no conversion; C escapes because assigning to `double` converts implicitly. Same law as the 2026-09-02 nullable arc: a relation and its conversion must read ONE selection. ⚠ invisible until now because the sweep harness itself was false-green TWICE (zsh: a failed glob aborts the whole `ls`, sweep ran over an EMPTY set printing bad=0; unquoted `$files` does NOT word-split in zsh, 28 paths became ONE token). Sweep discipline: `find … > /tmp/list` + `while read f; do …; done < /tmp/list` |
| ~~**an expression-bodied arrow's implicit return was never checked against the contextual return type**~~ ✅ **CLOSED 2026-09-04 (bug123, recompiler main — fix + guard landed, commit this session)** — root: `checkArrowExpr` (`src/checker/checkExprPass.ms`) already ran `fitNode` on the body (its own comment claims checkReturnStmt parity) but never the assignability + `addError` pair, so the expression form was the one unchecked return in the language; the block-bodied twin `() => { return n(); }` and the named-function form were both rejected correctly all along. Fix = the same `isAssignable` + `addError` step after the fit; void slots keep swallowing (arity-padded callbacks into `() => void` stay legal), generic returns skipped. On arrival the check exposed 2 real bugs in the compiler's own source: two `lambdaLifting` rewrite arrows declared `: Node` but returned `Node | null` into `mapChildren`'s non-null `Visitor` — null could land directly in an AST child slot (the family the LSP segfaults came from); both now return the child when the rewrite declines. This row supersedes the "`{sig()}` số rớt auto-stringify" framing: there IS no auto-stringify at a return position on any lane — the JS lane "worked" only through `console.log` polymorphism, and every `dynText(() => n())` thunk is this exact shape (met as ref.test.ms's number-signal fixture, worked around with a string signal there). After deploy, all these become located checker errors instead of a clang crash. Pin `src/test/fixedbugs/bug123ArrowExprReturnCheck.ms` (3 cells: reject / void-swallows / widening-keeps-conversion), CLI-verified under the built fix — battery error list ZERO-DELTA vs the self-built control (470 = 470 lines, only pre-existing line numbers shifted by the edit); the pin cannot RUN until the parallel narrowing arc re-enables self-host (79–103 pre-existing errors stop the harness before codegen) | minimal `/tmp/w7q4_stringify.ms` — `take(f: () => string)` + `const n = (): number => 7; take(() => n());` | was ❌ checker SILENT both lanes → C died at clang `returning 'double' ... incompatible result type 'msString'` at the lifted return; JS printed `7` |
| **generic alias instantiation — 2 facets still red after the 2026-08-30 fix** (NEW 2026-08-30, found designing the theme brand; 5 of 7 matrix cells CLOSED by recompiler `b3907f8`+`d936a21`+`0898b5b`) | `/tmp/alias_k9v2/{c,g}.ms` — c: `type Brand<T> = T` + a CLASS type arg; g: `type Box<T> = T[]`. Green controls in the same matrix: b (no alias), e (non-generic alias), h (`type Pair<T> = {a:T,b:T}`) | ❌ **c**: C `member reference type 'P *' … did you mean to use '->'` — member-access codegen still reads the UN-peeled instance (`codegen/c/expressions.ms`), so the new `peelTransparentInstance` never reaches it. ❌ **g**: `Return type mismatch in 'mk__int32': expected <kind:Ref>, got int32[]` — `instantiateGenericBody` (`checker/types.ms:1289`) accepts only Struct/Union/Conditional/GenericParam/GenericInstance bodies, so an ARRAY body never gets `typeReturn` and the peel cannot fire. Both loud, neither silent. Root family is the same as the closed cells: a generic ALIAS instantiation carries no identity of its own (Nim `ccgtypes.nim:186 irrelevantForBackend`, `:413 of tyGenericInst → skipModifier`)  **facet g CLOSED 2026-09-11** by recompiler `707bcd54` (see the 11-09 row: instantiateGenericBody instantiates every body kind); facet c still open. |
| **`msc test src/index.ms` exits 255 after the last file and prints NO summary — 162 files / 3336 tests, the tail of the graph never runs** (NEW 2026-08-30, PRE-EXISTING at recompiler `879859c`, not caused by any local change) | `msc test src/index.ms > log 2>&1; echo $?` in a CLEAN worktree. ⚠ do NOT pipe to `tail` — `$?` then reports **tail's** status and the run reads as rc=0 (this false-green cost a full re-run) | ⚠️ measured 3× IDENTICAL — main+local changes, main control (changes reverted), and a clean `git worktree` at HEAD: RC=255, 162 ✓, 0 ✗, 3336 tests, no `Tests N passed (N)` line. A single-file run (`msc test src/checker/compat.ms`) exits 0 and DOES print the summary (485/485). Last file printed is `compiler/lsp/handlers/completion.ms` and the log tail holds `[LSP] loadFile` lines → suspect teardown of the LSP handler tests. The 3510/168 baseline in the session ledger was probably measured from a different entry (`src/test/index.ms`). **Consequence for gating: the battery currently cannot prove the last ~6 files**, so "zero delta vs a self-built control" is the strongest claim a change can make today |
| **a generic instantiated with an ANONYMOUS object type declares its `Eq` companion but never defines it — link fails** (NEW 2026-08-18, found probing the S4c theme design; C only, js unaffected) | `const dark = { bg: "#1e1e2e" }; const [p, setP] = createSignal(dark);` → `/tmp/anon_*/a2.ms`; nesting (`{ colors: { bg } }`) fails the same way (`a3.ms`); the control `interface Pal { bg: string }` + `const dark: Pal = …` is GREEN (`a1.ms`) | ❌ `link failed: undefined symbol: ___anon1__bgsEq` (nested: `___anon2__colorsx__spacexEq`). **Loud, not silent** — it cannot corrupt, it just refuses to link, and the user-side escape is to name the type. Root NOT traced: only the symptom (declaration emitted, body not) and the named/anonymous split are measured. Same family as the companion-naming row below — companion names are minted in the transform layer off the bare type spelling, and an anon type's spelling is synthesized — so it should be fixed WITH that arc, not before it. Not blocking Neon: `createTheme` bakes token literals into getters and keeps only the theme NAME in a signal, which is the compile-time-first shape anyway (a fix would not bring the palette-object version back), but app code hitting `createSignal({ … })` will meet this |
| **companion functions are still keyed by the BARE type name — two modules with same-named destructor-carrying types collide at link** (NEW 2026-08-17, found closing the TypeInfo row; LATENT — not triggered by any current suite) | none yet; shape = module A and module B both declare `interface Item { s: string; }` (a managed field forces a hook), both get a strong `ItemDestroy`/`ItemCopy`, link them together | ⚠️ by construction, not observed: the 2026-08-17 arc qualified the C TYPE name but deliberately left `<T>_init` / `<T>Destroy` / `<T>Copy` / `<T>Eq` on the bare spelling, because those names are minted in the transform layer (`destructorLifting`, `ctorLower`) which is shared with the JS backend — qualifying them is a second arc. Today the collision is invisible only because same-named types in the linked graph rarely both carry hooks. Fix direction: mint companion names from the same identity oracle as the type, or qualify at the transform layer for the C target only |
| **monomorphized TypeInfo is emitted `__attribute__((weak))` in every consuming module — the same mono name over DIFFERENT type args merges at link** (NEW 2026-08-17, same arc; LATENT) | shape = `Box<Item>` instantiated in two modules whose `Item` declarations differ in layout; both emit `Box__ItemTypeInfo` weak, the linker keeps ONE | ⚠️ by construction: weak linkage was the pre-existing dedup strategy for mono instances (`ensureTypeInfoDef`), and it is only safe while the mangled mono name is a complete identity. It is not — `mangleMonoName` builds the suffix from type-arg NAMES, which are themselves unqualified. Same root as the closed TypeInfo row, one level up. The arc deliberately did NOT widen mono naming (the `__` spelling is load-bearing for `genHasDestroyHook` and for the isGeneric branch) |
| **31 srctest files / 71 test failures are PRE-EXISTING but were invisible — the suite died at link before it could count them** (NEW 2026-08-17, unmasked by the TypeInfo fix) | `msc test src/test/index.ms` now runs to completion; per-file A/B against a clean `a44ebe3` build proved 17 of them identical BASE vs PATCH (`src/test/c/{classes,control,expressions,functions,json}.ms`, `handoff/{enumValues,userDestructor}.ms`, `js/basic.ms`, `lang/syntax.ms`, `fixedbugs/{bug016,bug021,bug023,bug035,bug036,bug085,bug088}.ms`) | ⚠️ needs triage as its own arc — these are in-process `compileToC` harness cells, so each is a real compiler-behaviour claim that has been failing unnoticed for an unknown length of time. Two already have §2 rows (bug023 mono double-wrap, bug088 predicate narrow). **Do not read the 71 as fallout of the TypeInfo arc** — battery is 3469/3469 identical to baseline and the per-file A/B above is the proof. `src/test/lang/syntax.ms` is the one already known (`null as unknown as string` not producing a real null; `>>>` has no C emit) |
| ~~**C backend cannot invoke a returned closure in place**~~ ✅ **FIXED 2026-08-12 (recompiler `0bc1e2f`+`b0c9557`)** (NEW 2026-08-11, found building the direct-row probe) | `props.children(item, idx)(host)`; re-verified here by deleting the workaround from the row region and rebuilding | ✅ C builds it (47 modules, rc=0) and prints byte-identical output to the bound form. Root cause was NOT the emitter: closure-call dispatch was gated on the callee's NodeKind, so a callee that only exists after lowering (`rvalueLower` hoists the inner call into `$tmp`) was owned by no pass. The fix reads the callee type's callConv, which forced `createIterator` to stop typing its `next` field as a plain function. **Unblocked the real `For.children` widening, which landed the same day** — `For`/`Index`/`Show` now take `NeonView`, and a bare JSX row lowers through the target's converter (template-clone on js, tree on C). Real-DOM sweep through the PUBLIC api, min of 3 runs, 500 rows: 2.86x static → 1.21x fully dynamic, matching the private-`ForDirect` numbers this row was blocking |
| ~~an optional field of FUNCTION type cannot be omitted~~ (NEW 2026-08-12) | `interface Box { a: int32; cb?: (x: int32) => int32; }` then `const b: Box = { a: 1 };` — `/tmp/optfn/p.ms` | ✅ **CLOSED 2026-08-13 in the recompiler.** Root was global, not fn-specific: `?` was consume-and-discarded at EVERY declaration site (interface/class token paths, anon-object string path). Now `?` desugars to `(T) \| null` — omission → null, narrow → call; the desugar is idempotent, so `fallback?: NeonView \| null` in `flow.ms` is unchanged. requiresInit for a BARE fn field stands (intentional), `?` is the opt-out. `p.ms` green both lanes, neon suite 292/292 under the fixed compiler, corpus guard `015-optionalFieldNull` proven red pre-fix. The `cb?: Cb \| null` spelling is no longer required (still valid). |
| **`as int32` does not truncate on JS** (NEW 2026-08-11) | `probe/timerCheck2.ms` — `const casted: int32 = (t1 - t0) as int32;` on both lanes | ❌ C prints `7`, JS prints `2.9187499999999993`. C only truncates because assigning to `int32_t` truncates implicitly; the JS emitter never lowers float→int at all (no `\| 0`, no `Math.trunc`). Silent wrong value, not an error — a differential-corpus shaped bug |
| **module-level array destructuring loses nodeType** (NEW 2026-08-11) | `const [a, b] = createSignal("x");` at MODULE scope (first cut of `probe/treeCloneResidual.ms`); same line inside `main()` is fine | ❌ `Internal Error: missing nodeType on Identifier 'a'` (one per bound name, emitted as a *warning*), binary still links, then run exits **rc=255**. `probe/bench.ms` only escapes it by destructuring inside `main()`. An internal error reported as a warning is the real defect — it should be loud |
| **`performance.now()` prints `<object>` on JS** (NEW 2026-08-11) | `probe/timerCheck.ms` on both lanes | ❌ JS: `d1=<object>ms` while `d1 > 0.0 && d2 > d1` is TRUE — arithmetic is fine, only `.toString()` misdispatches. Root: `std/core/performance/index.jms` is `export extern class performance from "performance"` with **no method signatures**, so `now()`'s return type is untyped. Two fixes, both valid: annotate at the call site (`const t: float64 = performance.now()`) or give the shim a signature — `probe/benchDom.ms` already works around it by declaring its own `extern class performance { static extern now(): number; }`. Same family as the `Date.now()` note in `probe/bench.ms`'s header |
| **`msc build --target=js` artifact vanished twice, rc=0 — UNEXPLAINED** (NEW 2026-08-11) | seen with `out/rowSweep.js` and `out/sweep6.js`: `ls` right after the build shows the file (183131b / 197122b), a later `curl` of the same path returns **404** and `out/` holds only `debug/` | ⚠️ **Not reproduced on demand** — the obvious hypothesis (a second `--target=js` build wipes the first artifact) was tested directly and REFUTED: `build sweep6; ls; build sweep12; ls` keeps both. Cost: three rounds of Chrome measurements silently returned an empty page (script 404) and looked like a broken probe. **Defence until root-caused: `curl -o /dev/null -w '%{http_code}'` the bundle immediately before every browser run**; a green build line is not evidence the file is there |
| **an optional-field call argument spliced through a macro gets its Maybe fit applied TWICE — C refuses at clang, JS silently drops the value** (NEW 2026-09-02, found wiring the reactive variants selector; ✅ FIX STAGED same day on `fix/macro-wire-maybe-fit` in `/tmp/wt_maybewire_VR38-9231` — /trace-nim verdict DIVERGE-UNINTENTIONAL: Nim `implicitConv` (sigmatch.nim:2232) always wraps in a conv NODE, MS `synthMaybeWrap` (checker/fit.ms:286) materializes the `{value, present}` carrier at the CHECKER layer, so bug107's kind-based wire strip cannot see it. Minimal return-to-Nim step: `stripMacroArgWrappers` (compiler/meta/bridge.ms) unwraps the carrier by TYPE (IsMaybe stamp — unspellable by a user). Corpus pin `751-macroArgMaybeFit.ms` red pre-fix both lanes / green post-fix; battery 3528/3528 rc=0; neon C 25 files + JS 24 files bad=0. Full alignment (synthMaybeWrap → HiddenStdConv + transform materialization) = follow-up arc. Merge + deploy pending approval) | `probe/vr/p7_jsxPlainFnCall.ms` — `pick({ state: "on" })` where `pick(sel: { state?: string })`, INSIDE a JSX attr: `element(<div style={pick({ state: "on" })}></div>)`; `p6_jsxVariantCall.ms` = same through a createStyles variants arrow. Control: the IDENTICAL call outside JSX is green both lanes (`tests/render/styleVariants.test.ms`, 7 tests) | ❌ C: `assigning to 'msString' from incompatible type '__anon2__values__presentb'` on `_lit2_.value = _lit1_` — the literal was already fitted to Maybe<string>, then wrapped again. ❌ JS **SILENT**: p7 prints `#334` (compare `sel.state === "on"` misses), p6 prints `null` — wrong pixels, no diagnostic. Trigger is the element macro re-emitting the attr expression; hypothesis: the fit conversion survives the macro wire and fit runs again on re-check — same family as the union-equality fix ("strip at nodeToValue, never expose convExpr on the wire"). Static variants are unaffected (no JSX splice of the selector) |
| **`boolean && string` emits a C bool-cast of the string — clang fails** (NEW 2026-09-02, found probing the variants selector) | `probe/vr/p3_andSelector.ms` — `pick({ state: pressed && "on" })` into a `state?: string` field; control `probe/vr/p4_ternSelector.ms` (ternary) is green both lanes | ❌ checker PASSES, C dies at clang: `operand of type 'msString' where arithmetic or pointer type is required` on `(MS_BOOL)(MS_STRING_LIT(…))` then `assigning to 'msString' from incompatible type 'MS_BOOL'`. JS lane prints `P3 ON` — correct. Loud on C, not silent. Blocks the `pressed() && "on"` spelling from docs/STYLE.md §2; variants v1 ships with the ternary spelling until this closes |
| **nullfn bind-order** | `probe/nullfn_bindorder.ms` | ❌ `passing 'msClosure' to parameter of incompatible type` (:78) |
| **nullfn explicit type-arg** | `probe/nullfn_explicit_targ.ms` | ❌ `Argument type mismatch in 'apply' arg 0: got function, expected Maybe_fn_fnnumbernumber17` |
| **union ctor-param proto/def** | `/tmp/mono_union.ms` | ❌ `conflicting types for 'Box__union_number_string_init'` |
| **struct/array ctor-param indirection** (NEW 2026-07-26 late) | `new GcCell<CmgTag>({ label: "x" })` / `new GcCell<number[]>([1,2,3])` from an importing module | ❌ `passing '__anon1__label' to parameter of incompatible type 'CmgTag *'` — the ctor's declaration takes the type arg BY POINTER while the call site passes it by value. Same family as the union row above; pre-existing, but only reachable since #6 made cross-module ctors instantiate at all. Excluded from the #6 guard on purpose (documented inline there). |
| ~~**loop + nested-closure snapshot**~~ | `/tmp/{q1,q2,q3,r1,r2,r3,alias}.ms` (loopesc.ms lost, matrix rebuilt) | ✅ **CLOSED 2026-08-07** — 3 stacked defects (OOB `$up` cast + insideLoop leak + per-call cell); see the §2 row + §5. The old c0:800 was OOB heap reuse — unstable by nature |
| **`canRaise` missing Nim's `sfGeneratedOp` arm** | `/tmp/craise.ms` | latent (not a live bug) |
| **latent `monoConcreteTypeName` siblings** | — | by inspection: anon `Union` / `Conditional` |
| ~~**object spread in object literal**~~ (NEW 2026-07-27 late) | `/tmp/ns_spread/main.ms` (6 lines, `docs/STYLE.md` §7), guard `src/test/fixedbugs/bug094ObjectSpreadLiteral.ms` (7 cells, proven red under pre-fix binary: 8 C errors) | ✅ **CLOSED 2026-08-07** — no pass ever lowered object-literal spread: parser stores key `"..."` + SpreadExpr, checker skips the key BY DESIGN, C mangled it to field `dotdotdot_`, and JS was ALSO broken (emitted `...:` = load-time SyntaxError, and objectLiteralComplete appended omitted fields AFTER the spread — would have clobbered them had the syntax been valid). Fix = new pass `transform/desugar/objectSpreadLower.ms` (both backends, before objectLiteralComplete): expands spread into explicit `f: base.f` member reads (analyzer sees real reads → DRC copies), hoists non-identifier operands to peer temps (evalOnce, `walkExpandBlocks` flat splice). SEMANTICS (diverges from TS knowingly, documented in the pass header + bug094): spread copies every field of the operand's STATIC type — structs have no absent-property state (Nim default-init), so `{...a, ...b}` lets b's null fields override a; array layering stays S3's merge design. Leftover corner (loud, not silent): impure operand inside an expr-bodied arrow can't be statement-hoisted — C error same as before. recompiler `dfd892c`+`d44fc9c`; see §5 |
| ~~on-demand helper compile errors unreported~~ | `src/test/fixedbugs/bug057.ms` | ✅ **CLOSED 2026-07-28** — helper errors now queue in `eval.ms` and merge into the macro's result (`Macro 'X' body: helper 'y': …`). See §5 for the measured severity correction |
| **`string = number` is not a checker error** (NEW 2026-07-28, found probing row 9) | `function f(n: number): number { const s: string = n; return n; }` | ❌ checker PASSES, C fails: `used type 'msString' where arithmetic or pointer type is required`, emitted as `s_1_ = ((msString)(n));`. Same shape as the object-spread row: a check the checker should own, deferred to the C compiler. NOT metaprogramming — plain assignment |
| **an all-nullable interface accepts ANY object** (NEW 2026-07-28, found in S2) | `n.layoutStyle = style` in `src/platform/void/host.ms` — `layoutStyle: FlexStyle \| null`, `style: Style` (a DIFFERENT interface) | ❌ type-checks silently. Every `FlexStyle` field is nullable, and with no missing-field rule (Nim default-init, NIM-REF §1) an all-nullable interface is structurally satisfied by anything — so assignability stops discriminating. S1 shipped this: the void host stored a Neon `Style` where yoga expected a `FlexStyle`, and layout silently read garbage. Fixed Neon-side (`asFlexStyle(style)`), but the CHECKER hole is open. The bug058 rule does not cover it: no field is function-typed. |
| **`async` helper called from a macro body** (NEW 2026-07-28, found probing row 9) | macro body does `value: bad(2)` where `async function bad(n: number): Promise<number>` | ❌ compiles clean — no diagnostic from the module check OR the engine check. The macro VM cannot run async, so the spliced value cannot be the awaited number. ⚠ **only the SILENCE is measured**; the emitted value was not inspected. Verify before assuming it is a wrong-answer bug |
| **same-scope redeclaration is not a checker error → miscompile** (NEW 2026-07-29, found writing the LSP probe) | `let ei = 0; … const ei = findExportedSymbol(…);` in ONE scope | ❌ checker PASSES, C fails (when lucky): the second decl reuses the first's C slot with the FIRST type — `incompatible pointer to integer conversion assigning to 'int32_t' from 'ExportedSymInfo *'`. TS/Nim both reject redeclaration in the same scope. If the two types happen to be ABI-compatible the C compiles and reads garbage silently — same family as the `string = number` row |
| ~~`asBytes` miscompiles on the C backend in every form~~ | `src/test/fixedbugs/bug063_asbytes_zero_copy_bridge.ms` | ✅ **CLOSED 2026-07-29 late night** — HiddenStdConv Cursor branch now picks the cast shape per direction (string = fat value, array = pointer). ⚠ the row's "asString does not exist on cms" claim was WRONG — `@builtin("AsString")` was in index.cms all along, same broken emission, fixed by the same patch. See §5 |
| ~~uint8[] widens onto the 15 remaining number[] extern methods → silent byte corruption on C~~ ✅ **CLOSED 2026-07-31 via /trace-nim — root = ONE line, `isReceiverMatch` (checker/context.ms:590) compared array-receiver ELEMENTS with covariant `isAssignable` while Nim seq elements are invariant (sigmatch.nim:1502-1516) and MS's own container relation already rejects it (row-74 `sameElementRepr`, t13 proved assignment blocked while receiver leaked); fix = `isReinterpretUnsafe` gate at that site + generic T[] surface fill + cap-flag mask in msGenericArrayPush/SetLen; COMMITTED `70a220d`+`f5d32ca`+`66400b3`+`d01fb39` — see §5 2026-07-31** (NEW 2026-07-29 late night, found by the probe that closed the asBytes row) | `const b: uint8[] = []; b.push(104); b[0]` was the proven case — `msNumberArrayPush(b, 104.0)` stores an 8-byte double in a 1-byte payload, reads give the double's LOW BYTE (104 → 0). push is FIXED (bug064: uint8[] overload in index.cms + exact-receiver tiebreak in checker), but at/pop/shift/indexOf/includes/slice/concat/reverse/sort/fill/count/join/setLength/capacity/splice still have NO uint8[] overloads and still bind number[] | ❌ silent wrong answers on C for every listed method on a uint8[] receiver; std's own `serialize/json/accessors.ms:168` pushed uint8 through the broken path before the fix. **Must close before shared.ms algorithms use anything beyond push + indexing.** Runtime only ships Push/At/Destroy/New for uint8 — the other 13 need C runtime fns too. **NEW facet (2026-07-30, found red-proving bug065):** even push still mis-dispatches when the arg is a NON-LITERAL number — `let x = 65; b.push(x)` reads back 0 silently (bug064's tiebreak fires only when the uint8 overload is a candidate; a number-typed arg disqualifies it). Byte-loop code must cast (`as uint8` — Nim-faithful, Nim requires `byte(x)` too), but the silent number[] fallback stays a trap until this row closes |
| **bug006 fails standalone but battery is green — harness/mono path divergence** (NEW 2026-07-29 late night, pre-existing at gen-21) | `msc test src/test/fixedbugs/bug006.ms` under INSTALLED gen-21, zero local changes | ❌ C fails: `msArrayAccess((*(*arr)), 0)` — double deref of a generic indirect param after macro round-trip. Same file passes inside the full battery graph. Standalone-vs-graph compile takes a different mono/indirection path. Also true of bug062 in a worktree (needs its uncommitted checker half — that one is expected). Filed so the next person who runs fixedbugs standalone doesn't chase it as THEIR regression (this session lost ~30 min to exactly that) |
| ~~JS bundle: module-level decls are NOT namespaced — same-name decls collide across modules~~ ✅ **stage A CLOSED 2026-07-30 same day** (found by em's string corpus; exported-name axis = stage B, open) | `/tmp/jsdup`: `a.ms` + `b.ms` each declare private `function helper()`, `main.ms` calls both modules | ❌ duplicate `function` = hoisting, LAST WINS silently — C prints `a=1 b=2`, JS prints `a=2 b=2`; duplicate `const` = SyntaxError at load. C is immune: `codegen/names.ms` qualifies via `sym.modulePath` (stamped by defineOrError). The JS emitter is pure-syntax (`safeJsName(d.name)`, `codegen/js/expressions.ms:134`), the bundle is a flat concat into ONE scope, importers reference bare names (no destructure emitted for static imports), `__mod` registry is registration-only. Exported names collide the same way — not just private. Bit the std TODAY: `shared.ms` + `index.jms` both carried private `isSpaceByte` → any JS bundle reaching both `trim` and `stripInPlace` died at load (fixed std-side: shared owns the helper, jms imports it; my gates were green only because DCE never co-bundled the pair — coverage lesson). Fix direction (staged, mirror C): plumb symbols into the JS gen and qualify by `sym.modulePath` — stage A private top-level decls only (zero `@emit` fallout: `@emit` text only calls EXPORTED std runtime names, which must stay bare as the de-facto JS ABI); stage B exported names (needs import aliasing at reference sites + the @emit ABI boundary made explicit). **CLOSED same session via /trace-nim.** Verdict: DIVERGE-INCOMPLETE — Nim jsgen (jsgen.nim:228-281 mangleName) emits ONE flat scope where every name carries symbol identity, decl and refs agree because both read the same cached symbol name; bare names are reserved for the exportc/compilerproc ABI. MS-C already ported this (names.ms); MS-JS never built it. Fix: `jsSymbolName` (codegen/js/expressions.ms) = single naming oracle for decl AND ref sites (emitIdentifier + emitFunctionDeclInner + emitVariableDeclCore), reusing the C backend's mangledFunctionName/mangledGlobalName — JS private names now IDENTICAL to the C symbol names; bare iff sym null / nativeName / Exported / **Imported** (NEW SymbolFlag stamped by importSymFromRegistry + createSymFromExport). ⚠ First attempt stamped Exported on imported syms — that silently RE-EXPORTED every import (checkPass:1988 builds export registries from the flag; battery is GREEN-BLIND to registry membership; caught only by a registry-tightness grep on the emitted bundle). Guard "same-name private module decls" in src/test/js/basic.ms, proven red, incl. imported-ref-stays-bare asserts. Gates: battery 3364, js/basic 2779, corpus 1xx+627 C==JS, oracle 45/45×2, jsdup a=1 b=2 + c=10 d=20 (C parity), msc-s5 full self-host battery. STAGE B open: two modules EXPORTING the same name still last-wins (Nim analog: exportc-name uniqueness is the user's responsibility — needs a checker diagnostic); enum-member decls and synthesized no-resolvedSym helpers still bare |
| ~~zero-copy bridge ownership model incomplete — 3 measured holes~~ | guards `src/test/fixedbugs/{bug065_asstring_exit_uaf,bug066_asbytes_rvalue_receiver,bug067_literal_view_push_static_clobber}.ms` — each proven RED against the exact hole | ✅ **CLOSED 2026-07-30** (see §5): (a) rvalue receiver → `lowerRvalueBridge` (AsBytes-gated receiver→temp hoist, flat splice) wired into the pipeline — discovery: `lowerRvalue` was NEVER wired despite the index.ms header listing it as pass #21; (b) asString exit UAF → interception removed, call falls to plain extern `msAsString` = COPYING kernel (cstrToNimstr shape) in `runtime/core/array.c`; zero-copy MOVE at analyzer last-use stays a later arc; (c) WORSE than filed — cap flag bits (STRLIT bit 62 + ASCII-cache bits 61/60) read RAW made push's room check see "infinite cap" → in-place writes to static memory that never even reached `msArrayPrepareAdd`; fix = masked compare + flag divert in `msUint8ArrayPush`, copy-on-flag in both `msArrayPrepareAdd/Uninit` (Nim `prepareSeqAddUninit` parity). STILL OPEN by design: heap-source view mutation writes through (Nim-faithful reinterpret semantics), and a mutated literal-view's copied payload may leak if the analyzer skips destroy on literal-init locals (bounded, noted) |
| ~~shared-std string byte-loops miscompile in the SELF-HOST build — "export" lexes as ex\|port~~ ✅ **CLOSED 2026-07-30 — root-caused, NOT a compiler bug: index-space divergence (extern = UTF-16 code units, shared.ms = bytes). See §5 and the index-space row below** | apply `/tmp/string-migration.patch` (re-derivable: `shared.ms` parked UNTRACKED at `std/core/string/shared.ms`; remove the 22 algorithm externs from index.cms + the bodies from index.jms, append the export-list re-export to both), rebuild msc with a GOOD compiler, then `msc run` ANY file | ❌ the produced compiler is broken: std loading dies with `Undefined variable 'ex' / 'port' / 'expo' / 'rt'` (identifier boundaries cut mid-word), `@include` paths garble to `*.h`, phantom "Parse: Unexpected token" errors. EVIDENCE CHAIN: (1) the SAME shared.ms compiled into small programs is byte-perfect — 36/36 dual-backend diff incl. UTF-8 + empty string; (2) still broken with CLEAN std + known-good builder → the orphan-JSDoc accident of attempt 1 is exonerated; (3) breakage exists only in the 287-module whole-compiler context → context-dependent miscompile (suspects: int64 params / default args / extension dispatch under mono+DCE at scale). Bisect recipe: wire ONE function's cms extern → shared re-export at a time (start byteSlice/byteAt — lexer-critical), rebuild with the good wt msc, probe `msc run` on a 1-line file |
| **string API has no single index space — C runtime = UTF-16 code units, jms = bytes, spec = TS** (NEW 2026-07-30, the root behind the self-host row) | `probe/stringSpecOracle.ms` — ONE file, 3 runners: `node` (= TS oracle; strip annotations via `sed 's/: string//g; s/: void//g'`), `msc run`, `msc build --target=js` + `node out/stringSpecOracle.js`; expected baked in `probe/stringSpecOracle.expected.txt` | ❌ 40-row matrix: **JS 18 red** (`length`/`indexOf`/`lastIndexOf`/`padStart` in byte space; astral `charAt(1)` = garbage glyph `𣐀`), **C 6 red** (`padStart` target counted in BYTES; astral `charAt(1)` returns whole `👍` instead of the low surrogate half; astral `slice(1,3)` empty), ascii 16/16 green on BOTH. CONTRACT DECIDED (user 2026-07-30, normative section added to LANG.md §"Index-Space Contract"): TS tier = code-unit TS-exact incl. `s[i]` ≡ `charAt(i)` returning `string`; byte tier = explicit `byte*` names (Nim surface); representation stays UTF-8 bytes + zero-copy asBytes. **JS HALF FIXED 2026-07-30 late (uncommitted): 40/40 vs oracle** — `fromJSStr` lone-surrogate WTF-8 fallback (root of astral garbage: charAt of an astral half fed a lone surrogate back through the pair branch → NaN bytes), `indexOf`/`lastIndexOf`/`padStart`/`padEnd` → native delegation via toJSStr, new `msStringLength` (code-unit byte-walk) + new jsBackend-gated pass `src/transform/coercion/stringLengthJS.ms` (`.length` on String → `msStringLength()`; JS path never ran nativeLower's rewrite — C-only call sites compile.ms:1088/:1479). Gates: battery 3364/3364, js/basic 2778/2778, C harness byte-identical pre/post. **`s[i]` JS also fixed same session** (same pass, `charAt(s,i)` rewrite; harness grew to 45 rows incl. `s[i]` — JS 45/45). **C HALF FIXED same session (uncommitted): 45/45 — BOTH BACKENDS NOW MATCH THE NODE ORACLE 45/45.** `runtime/core/string.c`: new `msWtf8EncodeSurrogate` helper; `msStringCharAt` returns the exact half for astral (was: whole 4-byte glyph for either unit index); `msStringSlice` non-ASCII walk rewritten in unit space with half-inclusion at boundaries (was: `charPos == start` never matches mid-pair → byteStart -1 → EMPTY); `msStringPadStart/PadEnd` target + pad now counted in UTF-16 units via `msStringLength` + `msPadEmitUnits` (was: bytes; astral pad truncation keeps the high half, TS parity — in-code, not fixture-covered). Astral harness rows refitted to `charCodeAt`-based numeric compare (printed-lone-surrogate trap: node writes U+FFFD, C writes raw WTF-8). Gates after C fix: battery 3364/3364, js/basic 2778/2778, stage-2 self-host rebuild green. **Guard bug068 BAKED same session** (`src/test/fixedbugs/bug068_string_index_space.ms`, 5 tests, imported in fixedbugs/index.ms, ported to live): green under fixed runtime (280/280 in the 14-file glob), **proven RED against pre-fix string.c** (3/5 fail: padStart/astral-half/slice — the length/indexOf tests guard the JS half, which fixedbugs cannot run; the neon `probe/stringSpecOracle.ms` 3-runner harness stays the JS-side gate). ⚠ TWO harness facts measured while baking: the BATTERY (`msc test src/index.ms`) contains ZERO fixedbugs tests — guards run ONLY via the per-file glob; and `src/test/fixedbugs/index.ms` as an ENTRY is unbuildable in a worktree without the parallel session's untracked bug062 file. REMAINING for this row: commit; documented deviations (charAt/s[i] out-of-range `""` not `undefined`; C stdout writes lone halves as raw WTF-8) |
| **`s[i]` on JS backend read raw bytes — checker+C were ALWAYS coherent** (2026-07-30; the original "checker type lie" filing was a MISDIAGNOSIS — `checkExprPass.ms:866` `charType()` is the RANGE branch `s[a..b]` → `Span<char>` (byte tier, correct by design); plain `s[i]` was `stringType()` all along at :873, and C emits `msStringArrayAccess` returning a code-unit string) | `const c = "a—b"[1]; console.log(c)` — C prints `—` ✓, JS printed `226` | ✅ **JS HALF FIXED 2026-07-30 late (uncommitted)**: `stringLengthJS` pass also rewrites non-range `s[i]` on String → `charAt(s, i)`; harness `s[i]` rows 5/5 green on JS (45/45 total), js/basic 2778/2778 (no `s[i]=` assignment broke — none exists on the JS path). STILL REAL from the original filing: `char` maps to C `char` = **signed on arm64** (Nim char is unsigned; `> 127` latently broken) and `'é' as unknown as char` emits `(char)MS_STRING_LIT(...)` → clang error. Those two stay open |
| ~~`number[].indexOf` returns -1 for present elements~~ ✅ **CLOSED 2026-07-31 — the filing was MIS-ATTRIBUTED: real `number[]` always worked (control t7 = 1 ✓); `[10,20,30]` unannotated infers `int32[]` which WIDENED onto `msNumberArrayIndexOf` (8-byte stride over 4-byte payload) → -1. Same single root as the uint8[] row above, closed by the same context.ms:590 fix (t14 = 1/1 post-fix). See §5 2026-07-31** | `[10,20,30].indexOf(20)` — clean std, wt debug build | was ❌ `-1` on C |
| **C literal emission: `\xNN` escapes merge with following hex chars** (NEW 2026-07-30) | `const s = "\xC3\xA9abc";` | ❌ clang: `hex escape sequence out of range` — emitted verbatim, C parses `\xC3A` greedily. Needs escape-safe emission (`"\xC3" "\xA9" "abc"` or octal) |
| ~~function-typed field/param receiving a repr-mismatched closure → calls read garbage (SILENT)~~ ✅ **CLOSED 2026-07-30 late (worktree /tmp/wt-fnrepr, NOT yet in live tree/installed msc)** — the filed "variable-held" framing was WRONG twice: trigger = closure whose SIGNATURE carries int32 where the declared slot says number (unannotated `() => 42` arrows and generic `mkG(7)` instantiations both produce `() => int32`); the checker's arg loop had a Function CARVE-OUT skipping ALL closure args (checkExprPass:2992) so nothing was ever checked, and the C call site casts fn to the DECLARED ABI (int in eax, caller reads xmm0 → denormal). Fix = narrow carve-out (literal lambdas + generic-containing formals only) + repr gate in isFunctionAssignable + Function branch in isReinterpretUnsafe. Guard bug070 (6 tests, tree-toggle red-proof). Gates: battery clean (9 lifecycle fails = worktree missing UNTRACKED examples/*.ms — env, re-verified green after copy), Neon sweep 16/16, js/basic 2779/2779. See §5 | `probe/thunkProps.ms` (T1: `const g = () => 42; readP({ count: g })` → `2.14e-314`; T2/S1: signal getter in the field, same garbage), `probe/thunkProps3.ms` (inline-arrow fields V1/V4 GREEN in the SAME module while variable-held T1/S1 read garbage), `probe/componentSemantics.ms` (component thunk-props test red) | ❌ silent wrong answers on C under installed gen-21, zero diagnostics. Inline arrow literals in the field work — ONLY variable-held closures corrupt (signal getters included). Blocks component thunk props outright (`{ count: n }` IS this shape); **latent in `Show`/`For` today** — every existing call site happens to use inline arrows (`when: () => …`); `when: someMemo` would silently read garbage. Same severity family as loop+nested-closure snapshot. JS backend NOT yet measured. **First item of the component arc (PORT-STATUS #2)** |
| ~~expression-bodied arrow whose nested arrow captures an outer binding → C `use of undeclared identifier '_env_…'`~~ ✅ **CLOSED 2026-08-07 late** — root: `walkLiftBody` (lambdaLifting.ms:1612) can only prepend hoisted env decls into a BlockStmt body, and `normalizeArrowBodies` only wrapped bodies that were THEMSELVES an arrow (curried case, bug039) — an arrow nested inside any other expression left the outer arrow expr-bodied, so `setupSharedEnv`'s hoisted `_env_…` decl+init were silently dropped (liftClosure's own block-wrap at :727 runs AFTER the prepend — too late). Fix = `normalizeArrowBodies` wraps EVERY non-block arrow body in `{ return expr; }`, making liftCapturingClosureBody's documented "body is guaranteed BlockStmt" invariant actually true; output-neutral elsewhere (liftClosure AND liftNonCapturing both did the same wrap later anyway), C backend only (`lowerLambda` is `!jsBackend`). Guard `src/test/fixedbugs/bug095ExprArrowNestedCaptureEnv.ms` (5 cells — const-capture, param-capture, mutation-across-calls, double-nesting, no-capture control; 4 cells PROVEN RED under pristine v0.2.37 = 5 C `_env_…` errors). Gates: probes na_n1/na_b4/nestedArrowEnv2 green, bug092 loop-closure guard green, bug07* 2819, bug09* green per-file, self-build 292 modules, Neon sweep 18/18. thunkProps 1+3 stay red at CHECKER stage — pre-existing under pristine, different row. NOT re-measured: the bug094 leftover corner (impure spread operand in expr-bodied arrow) — objectSpreadLower runs before lowerLambda so the wrap may not reach it | `probe/na_n1.ms`, `probe/na_b4.ms`, matrix `probe/nestedArrowEnv2.ms` (block-bodied B1/B2/B5 were GREEN; no-capture B3 GREEN) | was ❌ hard C compile error — the outer arrow's env struct never emitted; unblocks the flat `componentNode(() => untrack(() => Comp(props)), …)` emission — component arc item 3 |
| ~~**TypeInfo symbols collide across test modules in a multi-file link — full fixedbugs entry is RED**~~ ✅ **CLOSED 2026-08-17 (recompiler `67cf77b`+`38b6cbe`+`c2cf215`+`5448752`, deployed)** (NEW 2026-08-06, found landing UNKNOWN-BUG Phase 1+2; PRE-EXISTING — reproduces identically under the pre-split HEAD-built binary, so NOT the split's fallout) | `msc test src/test/fixedbugs/index.ms` (full suite). The ~15-file globs stay green — bug009's glob is 294/294 under both the pre- and post-split binary | ❌ link error: `duplicate symbol definition: _ItemTypeInfo` / `_dollarEnv_test1_shared_TypeInfo` / `_dollarEnv_test2_shared_TypeInfo` (bug009.o vs bug072ExternMethodLiftedEmit.o). Env-struct and struct TypeInfo symbol names carry NO module qualifier, so two test files with a same-named test block + same-named capture (`shared`) or same-named struct (`Item`) collide at link when the full graph links them together. Same family as the JS flat-scope row: `codegen/names.ms` qualifies functions/globals by `sym.modulePath`, TypeInfo emission doesn't. Per-glob runs remain the working fixedbugs gate. ✅ **FIX (Nim `getTypeName` parity, ccgtypes.nim:150-172 — Nim appends `$sigHash`, MS appends the module qualifier already used for procs/globals):** `mangledTypeName` in `codegen/c/names.ms` (extern/ImportC keep the bare C name = Nim's `sfImportc/sfExportc` arm; `$`-generated and mono `__` spellings unchanged), per-TU `cname:`/`bare:` maps registered eagerly at `generateCModule` entry (walk-order independence), plus two compilation-global owner registries (name → module at `defineOrError`, name+fieldNames → module at `ensureShaped`) so a type that LOST its `sym` on a macro-wire/mono round-trip still resolves to the declaring module. Companion functions stay bare (`<T>_init`, `<T>Destroy/Copy/Eq`) with call sites rebuilding through the reverse map, and enum member refs are rebuilt from the enum TYPE (the checker rewrites `E.M` to a bare ident before codegen). **Severity was WORSE than filed — not just a link error:** `src/test/checker3pass/invariant.ms` declares `LeakResult` and so does `src/checker/validate.ms`; at baseline the consumer's bare `extern` bound to the OTHER module's TypeInfo (different type, wrong destroy hook) and linked SILENTLY. Gates after the fix: srctest 0 duplicate/0 undefined, battery 3469/3469 = baseline exactly, guard ALL GREEN, neon 295/305/294 |
| ~~predicate-narrowed `unknown` member access emits void* deref on C~~ ✅ **CLOSED 2026-08-07** — root: the HiddenDeref arm (`codegen/c/expressions.ms`) emitted `(*inner)` from the operand's DECLARED repr (`void*`) while trusting the flow-narrowed nodeType for pointer-ness; nobody spelled out the cast the narrow implies. Fix = when the declared symbol type is `TypeKind.Unknown` and the narrowed nodeType resolves to a concrete desc, emit `(*(Box*)u)` — operand peeled through TypeAssertion chains so the `(u as Box).n` spelling lands on the same path. Guard `src/test/fixedbugs/bug088PredicateNarrowUnknownMember.ms` (4 cells, 3 PROVEN RED by mutation, boolean-only control stays green). Gates: battery 3428/3428, self-build 291 modules, Neon sweep 18/18 + counter, probe builds and prints 7 | `function isBox(u: unknown): u is Box { … }` then `if (isBox(u)) console.log(u.n.toString())` — /tmp/prednarrow/p1.ms | was ❌ C: `member reference base type 'void' is not a structure or union` |
| **top-level destructured binding captured by a closure — analyzer/codegen break two ways** (NEW 2026-08-08, found probing the bare-JSX converter surface; THE blocker for Solid-style module-scope apps) | `probe/bareComponent.ms` (Neon E2E), minimal matrix: b3 = `const [n, setN] = createSignal<number>(1); const f = () => n() + 1;` at module top level → ❌ `cannot move 'n': variable is still used after this point` + internal warnings `missing nodeType on Identifier 'setN'`; b5 = `const [a, b] = [1, 2]; const f = () => a + b;` → ❌ `internal: unresolved type (kind=47) reached codegen … proc <toplevel>`; b4 control = plain `const x = 5` + capture → ✅; b2 control = b3 wrapped in `main()` → ✅ full component E2E green | ❌ two distinct failure modes behind one family: module-scope destructure sugar doesn't give its bindings capture-ready symbols/nodeTypes at `<toplevel>`. Function scope is untouched (every test block uses this shape). Blocks the LOCKED user surface (`examples/counter.ms`-style top-level `const [n, setN] = createSignal(…)` + bare JSX); bare-JSX converter path itself is PROVEN green (b2, and lowercase `probe/converterPrelude.ms`) |
| **calling a cast-of-nullable-closure expression in-place miscompiles C** (NEW 2026-08-08, found closing the component arc — host.ms componentFn expansion loop) | `probe/closureCastCall.ms` — cell B: `let cursor = b.next; while (cursor !== null) { got = (cursor as Producer)(); cursor = null; }` where `next: Producer \| null` | ❌ C: the call emits `cursor_1_.value()` — the Maybe unwrap called as a raw C function (clang: `called object type 'msClosure' is not a function or function pointer`, plus a stray top-level decl `double cursor_1_.value(void);`). Checker passes. Cell A control — unwrap into a `const` local first, then call — is GREEN (the shape host.ms already used). Loud, not silent; C-only (JS not measured) |
| ~~generic component fn passed UNAPPLIED to `createComponent` → instance never emitted~~ ✅ **CLOSED 2026-08-08 same day** — the filed "missing lifecycle fns / typeid-decimal naming" framing was SYMPTOM, not root (`_uN` is every function's uniquifier, proves nothing). THREE stacked roots, all in the checker: (1) checkExpr ObjectLiteral stamped a literal with a generic-CONTAINING expected type (the formal `{v: T}` itself) → `unifyType`'s identity check saw formal === concrete → ZERO bindings → `tryInstantiateGenericCallee` bailed → no instance emitted, literal fields emitted as void*; fix = `hasGenericParams` gate on the adoption branch, literal self-types, unify binds T from its concrete fields. (2) A generic fn passed as a VALUE arg poisoned first-wins binding merge (arg0 bound P to For's own T-containing param type, masking arg1's clean literal binding) AND was itself never instantiated; fix = per-arg generic-containing binding filter + a value-arg instantiation loop in tIGC (unify the generic's signature against the substituted formal, `callInstantiateGeneric`, rebind `resolvedSym`). (3) SEGFAULT after (2): P stayed bound to the literal's TRUNCATED anon type (2 fields) while the For instance reads the declared 3-field param (optional `fallback`) → read past struct end; fix = after value-arg instantiation, IMPROVE eb from the instance's signature, then restamp literal args with the substituted formal (poor-man's Nim `implicitConv`) so codegen emits the instance's struct identity and objectLiteralComplete fills omitted optionals. Fix lives in `checker/checkExprPass.ms` (adoption gate + tIGC loops) + `checker/types.ms` (struct unify BY NAME when both sides have field names — positional pairing would silently bind T from the wrong field). Guard `src/test/fixedbugs/bug098GenericAnonPropsInference.ms` (8 cells, proven RED under v0.2.38: 12 C errors; green 299 under fixed). Gates: battery 3435/3435 ×2, Neon 19/21 under wt binary (2 knowns below) incl. For differential + probes. REMAINING FACETS (open, loud): (a) named generic interface `Props<T>` + literal STILL fails — the eagerly-instantiated annotation body carries Unknown not GenericParam (`/tmp/anonlife/ctrlG.ms`); (b) literal key order ≠ formal field order → loud arg-mismatch (caller validation compares the PRE-restamp anon type; name-aware unify binds T right, don't "fix" positionally) | `probe/directForMin.ms` + `probe/treeForJsx.ms` (now living probes, green), control matrix `/tmp/anonlife/ctrl*.ms` | was ❌ loud missing-symbol C errors in BOTH emissions for JSX `<For>`/`<Index>` |
| **worktree-debug-built compiler panics in `lowerObjectSpread` compiling style.ms/voidHost.ms** (NEW 2026-08-08, surfaced by the D1 A/B — PRE-EXISTING: reproduces under PRISTINE c0d3dfd worktree binary, zero local changes; matches the "SIGABRT pre-existing" note from 2026-08-07 that then "didn't reproduce" — it is BUILD-MODE-dependent) | build any worktree at HEAD with installed msc (`msc build src/index.ms`), then `<wt>/out/debug/index test tests/render/style.test.ms` in Neon | ❌ `thread panic: -1e30 is outside the range of representable values of type 'long long'` at compile.ms:1486 `lowerObjectSpread` — a garbage float→int64 conversion inside the pass when the compiler itself is the worktree debug build; INSTALLED msc compiles the same files clean (double-compile / UB sensitivity, same family as the hash-overflow UB row). Blocks nothing on the installed path; poisons worktree-binary Neon sweeps (style/voidHost read as false-red) |
| **macro-body engine: local closures half-supported — nullable-closure reassign SILENTLY deregisters the macro; arrow self-reference loud-fails; `error()` inside a nested fn folds into its return type** (NEW 2026-08-09, found writing the D3 flatten emitter) | bisect ladder over `probe/flatEmitMod.ms` + `probe/flatEmitUse.ms` (files preserve the WORKING shape; broken variants described here): (a) `let f: ((c: Node) => string) \| null = null; f = (c) => {…}` in a macro body, NO self-reference; (b) `let f = (c: Node): string => { … f(gc) … }`; (c) `error(msg, node)` inside a named local `function` in a macro body (pre-D3 direct.ms had it top-level) | ❌ three facets: (a) **ZERO diagnostics anywhere** — the macro silently drops out of registration and the USE site errors `JSX expression must be consumed by a macro`, nothing points at the macro module (worst facet: pure misdirection; cost this session a bisect to find); (b) loud `Macro 'f' body: Undefined variable 'f'` + `evaluator unavailable` — engine scoping makes a binding invisible inside its own initializer (TS allows `let f = () => f()`); (c) `Return type mismatch in '(anon)': expected string, got __anon…compileError…` — the engine folds error()'s compileError value into the nested function's return type, so error() is top-level-only. ✅ SUPPORTED shape (probe green 2/2, D3 shipped on it): named local `function walk(c: Node): string` with self-recursion, capturing + mutating outer counters and `Node[]`; direct.ms defers error() via a collected-offenders array — same message, same node, error aborts expansion either way |
| **`msc run` never executes test blocks (build-only PASS) + a test-block-only file breaks the dispatcher C compile** (NEW 2026-08-09, found baselining D3) | (a) any probe with `test` blocks: `msc run probe/directFlat.ms` with a deliberately flipped assert → exit 0; the SAME flip under `msc test` → red at the right cell; (b) 3-line file `test "x" { assert 1 === 2, "boom"; }` with no imports, `msc run` it | ❌ (a) is a RECIPE TRAP more than a bug (test blocks are `msc test`'s job) but it silently false-greened every probe sweep to date — "PASS via msc run" only ever proved build+link. Sweep recipe corrected: probes now run under `msc test` (the ~14-sibling glob still executes the target file's own cells — flip-proven). (b) real bug: clang error in the dispatcher, call to the module's mangled `…__Init000()` that was never emitted — a module whose only content is a stripped test block still gets an Init call |
| ~~JS backend: a generic class's methods emit `function …(this)` — SyntaxError at load, the whole browser target is DEAD~~ ✅ **CLOSED 2026-08-09 same day via /trace-nim** (NEW 2026-08-09, found opening D4 — first thing D4 did was run the shipped browser example in real Chrome) | `/tmp/msrepro/gen.ms` — `class Box<T> { value: T; constructor(v: T){…} get(): T { return this.value; } }` + `new Box<int32>(41); b.get()`, `msc build --target=js`, then `node out/gen.js`. Control `/tmp/msrepro/plain.ms` = same class NON-generic → ✅ prints 41. Also: `examples/counterDom.ms` served over http + headless Chrome | ❌ `SyntaxError: Unexpected token 'this'` at load — the monomorphised method is emitted as a free function whose FIRST PARAMETER is literally named `this` (`function Box_get__int32__ZprivateZtmpZmsreproZgenOms_u0(this) {`); `this` is not a legal binding name in a JS parameter list. Non-generic classes keep their methods ON the class (`this` implicit) and are unaffected — so the C-side uncurrying is only wrong on the JS emitter's side of the mono path. **Severity: every Neon browser app is dead today** — `Signal<T>` is generic, so `counterDom.js` (2 such decls) fails to parse before a single line runs. **REGRESSION**: this same example was E2E-verified in real Chrome on 2026-07-29 under gen-21. Fix direction: the JS emitter must rename the uncurried receiver param (C names it explicitly too — `codegen/js` needs the same treatment as `codegen/names.ms`), same family as the JS flat-scope row (JS emitter is pure-syntax where C is symbol-aware). **CLOSED same day.** Verdict DIVERGE-INCOMPLETE: Nim jsgen NEVER emits a reserved word as a binding — `mangleName` (jsgen.nim:228-281) has `"this"` in `reservedWords`, params get `mangleParamExt`, decl+refs agree via the symbol's cached snippet. MS ported that scheme (JS_RESERVED `"$"+name`, NIM-REF row 581 stage A) but EXCLUDED `"this"` from the set because ES-class method bodies need bare `this` — the lifted free functions inherited the exclusion. NOT a strip (body reads `this.value`), NOT fixable at the lowering (`methodToFunctionDecl` SHARES the body node with the class emission — `fnBody: md.methodBody`; a rename there corrupts the class path). Fix = emit-context rename: `emitFunctionDeclInner` binds receiver as `$this` when `params[0]==="this"` + `gen.thisName` state so `emitIdentifier` renames every `this` ref inside that function; class-method emission keeps state at bare `this`. Site claims corrected: leak site = `codegen/js/declarations.ms:22-23` (params verbatim), `~116` is `emitStaticMethodFn` (no receiver — benign). BONUS pre-existing fix the guard forced: `emitJSTwoPhase` (test/helpers.ms) never drained `drainPendingInstances()` → in-process JS harness emitted CALLS to mono decls but never the DECLS (guard false-green on the original bug; pristine-proven) — ported the CLI distribution block (compile.ms:778-799). Guard: js/basic "generic class method lift renames the receiver binding", **proven red** under pre-fix emitter + patched harness. Gates: battery 3435/3435 · js/basic 2827/2828 (1 red = strParity, PRE-EXISTING at HEAD — see new row below) · Neon sweep 295+294 · counterDom `node --check` clean, 4×`($this`, 0×`(this)` · real Chrome over HTTP renders `Count: 0` + button. ✅ COMMITTED recompiler `22c6cb0`+`f283ab5`+`b5e52d1`, neon `9cac31a`; **DEPLOYED msc v0.2.39** (built from clean worktree at b5e52d1, battery 3435/3435 on the deployed binary itself, then verified under the INSTALLED binary: JS generic 41 · JS non-generic 41 · C 41 · counterDom `node --check` clean · real Chrome `Count: 0` · Neon full sweep 18/18). Backup of the previous binary: `/tmp/msc-backup-v0.2.38`. TRAP recorded: running several `msc test` invocations against the same repo concurrently makes them fight over `out/debug/.cache` — surfaces as `CacheCheckFailed` / `unable to open output directory` / undefined-symbol LINK errors on whichever test is heaviest (style/voidHost/renderToString pull in void+yoga), and the shape CHANGES run to run. It is a race, NOT a regression: `rm -rf out` + one serial run turns all three green (style 296/296 twice in a row). Do not chase these as compiler bugs |
| **js/basic `strParity` test is RED standalone at HEAD — `setLength/append/setSlice/stripInPlace` rejected on `string`** (NEW 2026-08-09, surfaced by the `(this)` fix gates; PRE-EXISTING — reproduces under a pristine HEAD worktree binary, green under installed v0.2.38 AND green inside the `msc test src/index.ms` battery graph = bug006-family standalone divergence) | `/tmp/wt-jsthis/msc-pristine run probe_dbg.ms` or `msc test src/test/js/basic.ms` under a HEAD-built binary | ❌ `ERROR: check: Property 'setLength' does not exist on type 'string'` (+append/setSlice/stripInPlace). Suspicion: the TEST is STALE — STRING-CONTRACT §6 mandates the mutation surface be rejected fail-loud (the buffer tier is the typed home), so HEAD enforcing rejection may be CORRECT and the test asserts the pre-contract surface; but then why green in the battery graph + under v0.2.38? Needs its own session: either delete/redirect the 4 mutation lines to the uint8[] tier, or find the graph-order divergence. Do NOT chase as a regression — pristine A/B 2026-08-09 proved it exists without the `(this)` patch |
| ~~indirect interface-extends cycle accepted silently~~ ✅ **CLOSED 2026-08-07** — the filed fix direction was correct: `interfaceCycleChain` (resolvePass) walks the extends graph from each parent via `sym.declNode` (set for every decl in collectPass, so the walk is resolution-order independent) with a visited set, and reports `'A' has a cyclic extends chain ('A' extends 'B' extends 'A')` before `resolveAnnotation` runs; the parent slot takes `errorType()` so the merge loop skips it. Guard `src/test/fixedbugs/bug086InterfaceExtendsCycle.ms` (6 cells — 2-cycle + 3-cycle PROVEN RED, direct self-cycle + generic-parent + diamond-not-a-cycle controls green). Gates: battery 3428/3428, self-build 291 modules, Neon sweep 18/18 | `interface A extends B { a: number; }` + `interface B extends A { b: number; }` — /tmp/ifcycle/indirect.ms | was ❌ no diagnostic, built AND ran |
| ~~**converters are keyed by a syntactic type NAME — a function-type alias can NEVER match**~~ **CLOSED 2026-08-09 same day via /trace-nim** — verdict DIVERGE-INCOMPLETE: the NIM-REF converter row (DIVERGE-INTENTIONAL) covers only WHERE converters apply; the name-string KEY was an undocumented shortcut. Fix follows Nim `userConvMatch` (sigmatch.nim:2297): the declaring module resolves the return annotation (`checkMacroDecl`, line=0 so no new diagnostics), the resolved Type rides the existing export/prelude plumbing (`ExportedSymInfo.converterTargetType`), and `tryConverterAtBoundary` falls back to a `sameType` walk over `converterTargetKeys` (dest-side identity = Nim `isEqual`; name fast-path for nominal targets untouched, tier/dup semantics untouched). Guard `bug101ConverterAliasTarget` 4 cells proven RED pre-fix; battery 3435/3435; converter suite 19/19; `probe/p1ConvAlias.ms` 2/2 differential-green; Neon sweep green. Staged in recompiler live tree, commit+deploy pending. | `probe/p1ConvAlias.ms` — S1 annotated decl (`const m: DirectMount = <div class="box">…</div>`), S2 arg position (`mountInto(<ul>…</ul>, host, root)`), where `type DirectMount = (host: Host) => HostNode` + `export converter jsxToDirectMount(n: Node): DirectMount` | ❌ both cells: `JSX expression must be consumed by a macro (it produces a compile-time Node); import a converter targeting 'function' to lower it at this boundary` — **the diagnostic prints the root**. `collectMacro` (collectPass.ms:522) registers the pair under `d.macroDeclReturnType`, the decl's SYNTACTIC return-type string (`"DirectMount"`); `tryConverterAtBoundary` (checkExprPass.ms:237) looks it up by `typeDisplayName(expectedType)`; `typeNameOf` (types.ms:2434) only names Struct/GenericInstance, so a Function type falls through to the `TypeKind.Function => "function"` arm (types.ms:2533) and the two keys can never meet. Converters therefore work ONLY for named struct/class/generic-instance targets; every alias of a non-struct type (function, array, union, tuple) is unreachable. **Positive finding — the boundary machinery itself is fine:** it fires at BOTH an annotated decl and an argument position (the error is raised with a settled expected type at each), so only the KEY is wrong, not the trigger. Fix direction = match by resolved TYPE, not by name string: `compat.ms:836` already reserves the slot (`convMatches: number; // isConvertible (converters — always 0 for now)`) and Nim's sigmatch searches converters by type relation, never by identifier. Blocks D5: direct emission produces a mount closure `(host) => HostNode`, so the `renderToHost(<App/>, host, parent)` per-target switch cannot be typed without it. Neon must NOT work around it by boxing the closure in a struct |
| **CLOSED 2026-09-15 (re-measured on msc v0.2.54, arc "one NeonNode" P0.2): the abort is gone — C and JS both stop with `Type 'function' is not assignable to type 'function' for field 'children'` at the JSX line (`probe/forRowNodeReturn_p02.ms`, rc=1, one error); the wording is the OPEN diagnostic row of 2026-09-13.** Original: **a `NeonNode` value where a `NeonView` (function) is expected inside a `For` row callback aborts the compiler with NO diagnostic** (NEW 2026-09-03, found folding native onto direct emission) | `tests/render/direct.test.ms` before the fix: `<For each={items()}>{(item: number, i: () => number): NeonNode => element(<li>…</li>)}</For>`, where `For.children` is `(item, index) => NeonView` | ❌ both lanes: `msc test` exits **255**, prints warnings and the DRC notes, then stops — no `error:` line, no `Built`, no location. The same mismatch at a component prop (`children`) DOES report properly (`Type 'NeonNode' is not assignable to type 'function' for field 'children'`), so only the row-callback return path is silent. Isolated repro of the surrounding shapes all COMPILE (`probe/directShowReentry_t3k.ms`: Show nested in an element inside `direct()`, and a component tag as Show's child) — the abort needs the annotated row callback. Loud-failure severity, but with an empty message it reads as a hang/flake |

- **nullfn bind-order** — `apply((v:number)=>v+1, 10)` binds T=int32 from arg 1, overriding the arg-0
  arrow. Nim `paramTypesMatchAux` binds progressively IN ARG ORDER → T=number. Do NOT fix by loosening
  the exact-match wrap gate (masks the divergence). Checker unify-order.
- **nullfn explicit type-arg** — `apply<number>((v:number)=>v+1, 10.5)` → arrow checked against the RAW
  pre-substitution formal → degenerates. Needs the INSTANTIATED formal (Nim `implicitConv` /
  `getInstantiatedType`). Checker.
- **union ctor-param proto/def indirection** — generic class ctor with a union param emits
  `_init(…, msUnion* v)` (definition, by-pointer) vs `msUnion v` (forward decl, by-value).
  Pre-existing; unmasked by the `monoTypeKey` split.
- ~~**loop + nested-closure snapshot**~~ ✅ **CLOSED 2026-08-07** — the filed row was wrong on
  trigger, mechanism AND severity. Trigger = **loop + nesting only** (no array/escape needed:
  `function main(){ for(…){ let c=0; const step=()=>{ const inc=()=>{c=c+1}; inc(); return c };
  step(); step(); } }` miscompiles identically). Severity was UNDERSTATED: not just wrong values —
  the in-function shape was **memory corruption**, every `c` access going to offset 8 of an 8-byte
  heap block (the "0" and the NaN-after-reuse both came from unowned heap). THREE stacked defects
  behind one root ("env-kind decided AFTER the body walk"): **D1** `setupSharedEnv` wired the body's
  `$up` by casting `_envP` to the enclosing fn's shared env, but at a loop site `_envP` is the
  per-closure pair env (8B) → OOB cast (r3/alias shapes); **D2** `insideLoop` leaked into closure
  bodies (never reset per frame) → the INNER closure was forced onto the per-closure snapshot path
  and wrote a private copy while the outer read another cell → lost update (this, not D1, killed the
  module-level shape); **D3** the captured cell lived in the closure's per-CALL shared env, so no
  cell persisted across calls even with D1+D2 fixed. Fix (transform/lowering/lambdaLifting.ms):
  pre-walk `createSnapshotPairEnv` — at a loop site the pair env is built BEFORE the body walk from
  the full capture set (direct ∪ nested refs, both known pre-walk) and becomes the persistent
  snapshot home; `setupSharedEnv` wires the body's `$up` against it with a correctly-typed cast;
  `walkLiftBody` resets `insideLoop` (every call site is a function-frame boundary). Consistent with
  the existing direct-capture snapshot semantics (q2 shape). Guard `fixedbugs/bug092` (3 shapes,
  proven red on pristine). Gates: 7/7 repro matrix green with structural C proof; fixedbugs glob
  batches 295+295+2817 identical pristine vs patched; Neon sweep +1 green (direct.test.ms), 0
  regressions. NOTE: the old row blamed "shared slot via up-chain" — HALF-right for D1 only; and
  `/tmp/loopesc.ms`'s `c0:800` came from OOB heap reuse, inherently unstable, which is why values
  "moved" between sessions. The 4 Neon reds this row was suspected of causing (array/dispose/flow/
  region) are actually the NEW void-generic row below.
- ~~**generic instantiated at `T=void` emits invalid C**~~ ✅ **CLOSED 2026-08-07 late** (NEW same
  day, exposed by the void-arrow return fix) — the filed fix direction held, and the whole bug was
  TWO sites in `codegen/c/statements.ms`, mono/signature side was already correct
  (`void run__void__…(msClosure fn)` emitted fine, callers bare-called it): (1) `genVarDecl` had a
  `cType === "void" → "void*"` guard written for null-literal inits that also swallowed genuinely
  Void-typed locals, declaring `void* result_1_` storage and assigning the void call into it;
  (2) `genReturnStmt` emitted `return <snippet>` unconditionally. Fix: a Void-typed VarDecl emits
  its initializer for effect only (no storage/hoist, `emitCallRaiseCheck` kept); a void return
  argument emits the expression as a statement (identifiers emit nothing — no storage exists) then
  bare `return;` after `blockLeaveActions`. Reference parity: Nim discards void expressions
  (`isEmptyType`); MS must handle it in CODEGEN because TS legally allows `const r = fn(); return r`
  at T=void (DIVERGE-INTENTIONAL at sem, SAME at emission). Guard
  `src/test/fixedbugs/bug093VoidGenericInstantiation.ms` (4 cells: identifier-return, direct-call
  return, createRoot-with-dispose shape, T=number control) — proven RED on pristine (4 clang
  errors, exactly the filed shapes). Gates: probe prints 7/42; fixedbugs globs 2817+295+296 green
  under patched; self-build 291 modules and the produced binary runs; **Neon FULL sweep 18/18
  files green — the 4 blocked tests (core/array 299, core/dispose 296, render/flow 297,
  render/region 293) all pass**, and style + voidHost (the loop-session's "pre-existing SIGABRT")
  are green too under the 2026-08-07 deployed gen. ⚠ UNCOMMITTED in /tmp/wt-deploy at close;
  installed msc (deployed earlier same day, gen at `04ce98e`) does NOT include this fix yet.
- **`const f: FnN = () => {}` with `type FnN = () => number` compiles, calls return 0** (NEW
  2026-08-07, pre-existing on pristine, found while probing the loop row) — TS errors on
  void-body→number-returning assignability; MS accepts silently. Same assignability family as the
  closure-sig-repr row (bug070) but the RETURN side. Silent wrong-answer on C.
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
- ~~**object spread in object literal**~~ — ✅ CLOSED 2026-08-07 via `transform/desugar/objectSpreadLower.ms`
  (see the §2 row + §5). S3's runtime-merge path is unblocked; array layering remains the chosen
  design for provenance, unaffected.
- ~~**on-demand helper compile errors unreported**~~ — CLOSED 2026-07-28, see §5. The plumbing gap was
  real; the *severity* filed here was overstated, and the correction is recorded in the ledger.
- **deferred, not counted:** catch-side `e.message` (object-carrying exceptions) — MS's exception
  runtime is string-based by design; `throw` works, `catch (e) { e.message }` does not.
- **`HashMap<K, V>.get` with a VALUE-typed V assigned straight into a scalar local — checker
  SILENT, dies in C** (NEW 2026-07-31, hit TWICE building the converter arc: `HashMap<string,
  string>.get` → `let s = m.get(k)` emitted `msStringSink(s, Maybe_p1)`, and `HashMap<string,
  int32>.get` → `existingOrigin = m.get(k)` put a `Maybe_p10` in an `if (a === 1 && …)` operand).
  Same family as the open "`string = number` is not a checker error" row. Workaround shape that
  compiles correctly: `const v = m.get(k); if (v !== null) { local = v; }` (flow-narrow unwrap).
  Pointer-shaped V (Node, string[]) passes through fine, which is why the neighboring
  `macroBodyRegistry.get` pattern never surfaced it.
- **a module whose only runtime content is a comptime-alias const emits no `Init000` yet the
  dispatcher calls it → C link error** (NEW 2026-07-31, pre-existing, found by converter probes:
  `const x = <a/>;` alone at module top → `call to undeclared function 'Z…__Init000'`). Off
  Neon's path; filed so the next person probing JSX consts doesn't chase it as a fresh break.
- **post-check diagnostics are dropped on the floor — analyzer errors never fail a build** (NEW
  2026-08-05, found by the UNKNOWN-BUG seam arc): `compile.ms` counts checker errors, CLEARS
  `ctx.errors` (:1023), and never reads the array again — anything transform/analyze pushes
  afterwards vanishes. Interim landed (committed with the seam arc): both codegen loops +
  test-helper C pipelines now fail on errors added DURING `generateCModule` (snapshot count) —
  codegen can no longer error silently; analyze-phase errors still vanish (the compileToC helper
  takes its snapshot AFTER `analyzeProgram`, so the class hides in the helpers too). Fixing the
  class = triage every currently-dropped diagnostic. The promise dropped case is FIXED 2026-08-05
  (`f86dbbe` + guard bug078 proven red): `needsReturnIncref` classified the RAW return node, so
  `return x as unknown as T` (NodeKind 17) fell into the error arm and shipped C without incref —
  member-under-cast was the real UAF (caller's decref stole a count from the field's owner).
  /trace-nim verdict DIVERGE-INCOMPLETE: Nim's "ownership invariance" (conversions recurse with
  the same mode, injectdestructors nkConv/nkCast) was in the walk (`processAssertionWrapper`) but
  not the classifier; fix = `skipConversionWrappers` before classifying. Two SIBLINGS filed, not
  fixed: (a) decl-site `const l = ownedCall() as unknown as Ref` emits msIncref on an owned value
  (rc 0→1, only one decref exists → leak; measured in probe C 2026-08-05); (b) processReturn's
  origKind deep-copy gates (ArrayAccess/MemberExpr/Identifier → passCopyToSink for non-Ref RC)
  also classify the raw kind — `return globalArr as X` skips the copy the uncast form gets
  (double-free class, same invariance, needs its own probe + guard).
  **Fence landed 2026-08-05** (`9968280` compile.ms both loops + `c7a7fd1` the two Result-returning
  C helpers): errors added DURING `analyzeProgram` now fail the build / return `Err`. Measured safe
  — the analyzer has EXACTLY 2 error-push sites and 0 of them fire across a 291-module self-build
  or the 3428-test battery. UNGUARDED on purpose: no proven-red guard exists because both producers
  are currently DEAD (see next row), so the fence is insurance for future producers, not a live fix.
- **`errFailedMove` was dead code — `move x` silently degraded to a copy** — FIXED 2026-08-05
  (`b68f3b3` + guard bug081 proven red). NOT a memory-safety bug: the emitted C for
  `b = move a; readIt(a)` is `$borrow_0 = a; msIncref($borrow_0); b = $borrow_0;
  msPtrWasMoved($borrow_0)` — a balanced COPY with wasMoved landing on the sink temp, so `a` stays
  valid and refcounts are correct (an earlier note in this file called it use-after-move; that was
  wrong, corrected after reading the emitted C). The bug was that `move` became a silent no-op copy
  instead of the compile error `docs/LANG-MOVE.md` (Phase 4, "Status: DONE") promises. Root:
  `isLastReadSafe` short-circuits `SymbolFlag.SinkTemp → true` and the Consumed walk has ALREADY
  rewritten the arg into that temp before the check runs. /trace-nim verdict DIVERGE-UNINTENTIONAL:
  Nim raises errFailedMove at the COPY DECISION under an `inEnsureMove` depth flag
  (injectdestructors `genCopy` + the sink-arg copy path), never from a last-read query. Fix mirrors
  that: `inEnsureMove` on DrcContext, incremented around the move argument's walk, checked in
  `passCopyToSink` + `genCopy`; the dead last-read block deleted. NIM-REF records this diagnostic as
  "abandoned" because analyze-phase errors never printed — the fence above (`9968280`) is what made
  reviving it possible. STILL OPEN, same family: the declaration form (`const b = move a`) never
  reaches a copy decision through `processMove`, so it is not covered by this fix.
- **flagless `TypeKind.Unknown` reaches C emission routinely — Nim-style "unresolved type reached
  codegen" internal error is premature** (measured 2026-08-05, REFUTES the poison-probe
  generalization recorded in memory/Phase 0): flipping the `gateFlaglessUnknown` seam
  (`codegen/c/types.ms`) to addError aborts real user shapes (match exprs, try/Result unwrap,
  toString, anonStructCast handoff files) and ~846 test-mode hits across ~30 modules (all
  `proc=<toplevel>`, ask-and-discard benign today). Two producer families FIXED en route (Nim
  `getSysType(tyPointer)` parity): DRC trace-hook `callback` param (both destructorLifting
  synthesis sites) and every synthesized `"void*"` annotation (`resolveSimpleTypeStr`,
  `transform/util.ms:413` — covered every lifted-lambda env param). Root-env `$up` stays Unknown
  (Ptr<void> attempt reverted — no measured effect). The error became shippable when Phase 3
  made `pendingType()` unconstructible (landed 2026-08-06, seam armed). Full story: recompiler
  `docs/NIM-REF.md` row 58 + the sentinel-kind map at `unknownType` (`src/checker/types.ms`);
  `docs/UNKNOWN-BUG.md` is retired.

### Added 2026-08-10 by the implicit-stringify /trace-nim session (all measured on msc v0.2.42 AND v0.2.43 — pre-existing, none caused by that fix)

| bug | repro | measured today |
|---|---|---|
| ~~implicit stringify of a user type never resolves — C clang error, JS silent `[object Object]`~~ | guard `recompiler/src/test/guard/stringifyProtocolResolved.ms` (13 cells), corpus `714-stringifyProtocol` | ✅ **CLOSED 2026-08-10 via /trace-nim** — the call was planted AFTER the checker by a C-only pass, so nothing bound it; now synthesized + resolved in `checkExprPass`. Committed `350b644`+`d0ce7a3`+`b6bf581`, deployed **v0.2.43**. Verdict + full trace: recompiler `docs/NIM-REF.md` "Implicit stringification" |
| **`String(x)` is C-only and absent on JS** | `/tmp/protostr/t_strfn_{num,cm,ext}.ms` | ❌ JS: `Undefined variable 'String'` even for `String(42)`; C: works for primitives, `no member named 'toString'` for a user type. Same planted-call shape as the row above, in `transform/coercion/typeCoercion.ms` — un-migrated |
| ~~**the debug dump of a struct reads garbage / destroys twice**~~ | guard `recompiler/src/test/guard/debugDumpOwnership.ms` | ✅ **CLOSED 2026-08-10 via /trace-nim** — `console.log(instance)` panicked (`misaligned address … JsonValueData`, a DIFFERENT address each run = uninitialised read) on every binary 0.2.33→0.2.43, and `${instance}` printed `{"v":null}`. Root: `debugLower` hand-built the types of the arguments it synthesized instead of reading them off the `jsonObject` signature — 3 faces (values array as raw pointers, keys array as a bare array passed by `&stackTemp` then destroyed twice, untyped nested MemberExpr → `.` for a `Ref`). Committed `7d81d66`+`a219cdf`+`5651f1d`, deployed **v0.2.44**. Now: `Outer { id: 2, tag: "t", kid: { n: 3 }, ok: true }`, ledger balanced |
| **a type with no (or a wrong-shaped) `toString` in a concat: backends disagree** | `/tmp/protostr/t_notostring.ms`, `adv_arity.ms`, `adv_retkind.ms` | ❌ no `toString`: C prints the JSON debug form (correct values since v0.2.44), JS prints `[object Object]`. Wrong-shaped `toString` (wrong arity/return): both fail at clang. **Policy DECIDED 2026-08-10 (user):** needing a string form of T with no `toString` = a **checker error**, applied to `T + string`, `+=`, `` `${T}` ``, `String(T)`; `console.log(x)` keeps the field-by-field dump but must be identical on both backends. Not implemented — part of the "move string-form + debug lowering into the checker" arc |
| **debug dump gaps left after v0.2.44** | `/tmp/protostr/d_shapes.ms` | ❌ `console.log([1,2,3])` → `<object>` (array dump needs a runtime element walk — a new mechanism, deliberately not invented); JS lane dumps the MANGLED class name (`Leaf__ZprivateZtmp…`) |
| **`extends`: this row was THREE unrelated things — re-measured 2026-08-11** | `/tmp/protostr/adv_inherit_pure.ms`, `/tmp/inh/m_*.ms` | ⚠ **Row rewritten after /trace-nim.** (a) The `misaligned … msTypeInfo` panic was the debug-dump bug — **gone on v0.2.44**, A/B: 0.2.42 crash, 0.2.43 crash, 0.2.44 rc=0. (b) "inherited method not resolved" is **NOT a bug**: method inheritance was never implemented — `docs/LANG-STRUCT.md:359` "Phase 2.8 … NOT STARTED", and `recompiler/src/test/lang/inheritance.ms` (146 lines) tests **only fields + `super()`**, no method cell. An inherited *named* method gives a correct loud checker error (`Property 'label' does not exist on type 'D2'`); only `toString` fails SILENTLY because the JSON fallback swallows it. (c) The JS unmangled base name is the only real defect here, and it kills the **supported** field-only contract too — **FIXED 2026-08-11** (uncommitted, worktree `/tmp/wt-jsext`): `declarations.ms:86` emitted `d.classExtends` raw while :83 mangled; now reads `typeExtra.sym` → `jsSymbolName`. A second, opposite defect fell out of the same probe: `super(...)` was RUN THROUGH the mangler (`super__Z…(i)`) — MS's `JS_RESERVED` lacks both `"super"` and `"this"` where Nim's `mangleName` list has both. Both pinned by a proven-red cell in `src/test/js/basic.ms` |
| **`userType += "str"` reaches clang** | `/tmp/protostr/adv_lhsuser.ms` | ❌ `invalid operands to binary expression ('M *' …)` — no checker diagnostic for a compound-assign whose LHS is a struct |

### Added 2026-08-11 by the `extends`/`super` + rest-param /trace-nim session (every row A/B'd against the pre-fix binary — all pre-existing)

Context for the whole group: rest-ness is the type-level `TypeKind.Varargs` marker (Nim `tyVarargs`) and the wrapper is meant to be transparent. Array annotations resolve to `Ref<Array<T>>` (`resolvePass.ms:487`), so peeling the wrapper to the ELEMENT takes **two** hops; the enum's own example comment said `Varargs(Array(string))` and every hand-rolled peel followed it one hop short. Rest params shipped with a dedicated TypeKind, a dedicated pass, and dedicated arity gates — and **zero end-to-end tests**, which is why they were broken in four independent places at once.

| bug | repro | measured today |
|---|---|---|
| ~~rest params never worked: `f(1,2,3)` rejected by the checker, packed array passed by value into a pointer param~~ | guard `recompiler/src/test/guard/restParamVarargs.ms` (15 cells) | ✅ **FIXED 2026-08-11, UNCOMMITTED** (worktree `/tmp/wt-jsext`). Four sites, one root each: direct-call peel + generic-bound peel (`checkExprPass`, now `getElementType(unwrapRef(unwrapVarargs(…)))`), the member/extension arity gate (computed `extHasRest` but applied it only to "too many", never "too few" — methods with rest demanded every param), and `shimCallArg` (`codegen/c/expressions.ms`, `isPointerType(Varargs)` = false → deref'd the packed array). Guard proven red pre-fix, green on **C and JS**, green under **drc and orc** via `src/test/guard/run.sh` |
| **`quote { splice(b) ? 1 : 0 }` expands to nil** (NEW 2026-08-13, found while landing the macro child accessors) | `macro m(e: Node): Node { const b = true; return quote { splice(b) ? 1 : 0 }; }` | ❌ C: `dollartern_0_ = MS_NIL;` → `incompatible pointer to integer conversion assigning to 'int32_t' from 'void *'`. A splice in the CONDITION slot of a ternary inside a quote loses its value; hoisting the ternary out of the quote (`const v = b ? 1 : 0; return quote { splice(v) };`) is green, so the splice + the ternary are each fine alone. PRE-EXISTING — reproduces identically on installed msc v0.2.46 with no accessor involved. Same family as the conditional-eval positions left open by the js positional-new arc |
| **rest param + overload → no candidate matches** | `/tmp/rest3/g2_overload.ms` | ❌ `error: No matching overload for 'pick'` for `pick(a: number)` / `pick(a: string, ...rest: string[])`. Identical pre- and post-fix, so the varargs peel above does NOT reach overload SCORING (`scoreCandidatePriority` / `scoreCandidateWithSkip` — the consumer set NIM-REF row 80 warns a grep for `typeRelation(` misses) |
| ~~rest param in a constructor is never packed~~ | `/tmp/rest/r2_ctor.ms`, guard `restParamVarargs.ms` (ctor cells) | ✅ **CLOSED 2026-08-12** — committed `2583255` (+ guard `35ecfee`). Root was the one line quoted: `restParamLower` returned early on anything that was not a `CallExpr`, and a constructor call is a **`NewExpr`**; `lowerRestNew` now packs it through the same path. The checker half needed `fb7c9fb` (see the cross-module row below) |
| ~~JS never emits class field initializers~~ | `/tmp/fi/c1_init_noctor.ms`, `c3_init_plus_ctor.ms` | ✅ **CLOSED 2026-08-13** — committed `71c58f7`+`5a34af5`+`ec8cfe2`. Fixed the way this row predicted: NOT in a backend. `transform/lowering/ctorLower.ms` materializes the initializers as assignments inside the constructor (Nim's SEM-level `defaultFieldsForTheUninitialized` shape, TS `[[Set]]` semantics), so `emitClassDeclInner`'s empty `PropertyDecl` arm is now harmless and `emitInstanceFieldDefaults` is DELETED |
| ~~C never chains an implicit constructor to the parent~~ | `/tmp/ctor/d1_parent_ctor_child_none.ms` | ✅ **CLOSED 2026-08-13** — committed `71c58f7`+`5a34af5`+`ec8cfe2`, exactly the agreed design (one canonical ctor per class, lowered once before codegen). ⚠ The hard root was NOT the lowering: `checker/reachability.ms` marked `<Class>_init` alive only when the class carried `SymbolFlag.HasConstructor`, a flag set at Phase 2 collect — so a compiler-SYNTHESIZED ctor was lifted correctly and then dropped SILENTLY by `genDecl`'s `isDeclAlive` gate (codegen's own alive set; the `markAlive` API in `transform/analysis/dce.ms` has no callers at all). Both gates now key on "is a ClassDecl". Measured after: C green on all six construction cells, battery 3450/3450 |
| ~~`super(args)` fails across modules~~ | `/tmp/xmod/main.ms`, guard `crossModuleSuperProto.ms` | ✅ **CLOSED in two halves.** Checker half `fb7c9fb` (2026-08-12): `getCtorParamTypes` now reaches an imported class through `Type.sym` and walks the parent chain — the three helpers live exported in `checker/symbol.ms`. Codegen half `7a4d813`+`e691b26` (2026-08-12): the `super` branch of `discoverCallExpr` emitted `Parent_init(...)` with **no prototype in the consuming module** (`call to undeclared function 'Shape_init'`) — it now mirrors the NewExpr path's proto block, reusing `crossModuleCtorParamTypes` + the `g.declaredProcs` dedup. This is DIVERGE-INCOMPLETE vs NIM-REF row 68 (Nim `genProcNoForward` declares in every module that uses the proc) |

### Added 2026-08-13 by the class-construction hygiene arc (both A/B'd against installed msc v0.2.46 AND a self-built binary at main `c562332` — pre-existing, neither caused by the arc)

| bug | repro | measured today |
|---|---|---|
| **an UNANNOTATED class field default never gets a type — DRC internal error** | `class P { a = 7 }` + `new P()` + `p.a` | ❌ `DRC INTERNAL ERROR: RC member access '.a' reached DRC without a type at 1:0 — a transform built it without setting nodeType`, then `internal: unresolved type (kind=47) reached codegen`. Annotating it (`a: number = 7`) is green and prints `7`. Loud, not silent. The field-default materialization landed 2026-08-13 (`ctorLower`, row above) but infers nothing from the initializer expression, so the synthesized assignment carries no `nodeType`. Same "a transform built a node without a type" family as the debug-dump and implicit-stringify roots |
| ~~a LOCAL declaration is invisible to the collect pass~~ ✅ **Stage 1 FIXED 2026-08-14** (recompiler main `5e60272` fix + `c83d3fa` guard), **Stage 2 FIXED 2026-08-15** (all 8 kinds admitted — see the end of this cell; not yet in installed msc) | `class L { x: number = 1 }` + `function f() { class L { x: number = 2 }; return new L().x }` — and every other decl kind in any non-module scope | was ❌ and WORSE than this row claimed. The old row ("safe, never a silent wrong answer, deliberately not implemented, root = ctorLower/methodToFunction") was refuted on all three counts by measurement: (1) SHADOWING a same-named top-level decl gave a **silent wrong answer** — C/orc printed `1` (binds the OUTER class), JS printed `undefined` (raw nested emit, colliding module-only mangle `L__ZtmpZ…`), vs `2` for TS/Nim; enum shadow identically; decl-only enum/actor/macro/block-class compiled silently as if absent; local `extern function` passed the checker and died at LINK (`_dollarfn_f_1_` — it parses as FunctionDecl with "extern" in fnFlags, so the nested-fn rewrite lifted a bodyless closure). (2) Scope = all 8 decl kinds (class/interface/enum/type/struct/extern/actor/macro) × 4 scopes (fn body, arrow, bare block, test block); only local `function` survives via its own `rewriteNestedFunctionDecl` path. (3) Root is the CHECKER, not the transforms (they never see a symbol that was never made): `collectTopLevel` walks only `programStmts` (collectPass.ms:15) and checkStmt's decl arms swallowed the miss (`checkClassDecl` lookupSymbol→null→silent return, checkPass.ms:592; grouped type-decl arm was `=> {}`). /trace-nim verdict **DIVERGE-UNINTENTIONAL**: Nim enters type symbols into the CURRENT scope (`typeDefLeftSidePass`, semstmts.nim:1444 → `addInterfaceDeclAt(c, c.currentScope, sym)`, lookups.nim:435), tsc supports local decls, and no doc records intent. **Stage 1 (landed)**: `rejectLocalDecl` gate in checkStmt — located error `local <kind> 'X' is not supported yet - move the declaration to module level` for all 8 kinds when scope ≠ Module/Global (Nim loud-fallthrough parity); `when`-block module-level decls unaffected (flattened pre-collect, measured). Guard `src/test/fixedbugs/bug106LocalDeclRejected.ms` proven RED (5/6 pre-fix) → GREEN 6/6 — but it was ORPHANED until late 2026-08-14: never imported into `fixedbugs/index.ms`, so no gate ran it (wired now, uncommitted in the recompiler tree). Battery at clean `c83d3fa` on a self-built binary = **3459/3459**; the 3474 figure was measured on the live tree carrying a parallel session's uncommitted test additions (declaration.ms +3, comptime.ms +1, utils/string.ms +9, paramReassignLower.ms +3) — both numbers valid in their own frame. Both fixedbugs-gate reds (`**` codegen in lang/syntax.ms, 5 dup-symbol link) A/B-isolated as pre-existing, not this change — see the 2026-08-14 baseline-audit rows below. **Stage 2 CLOSED 2026-08-15**: all 8 kinds are now admitted in a non-module scope — the check arms call the module-level `collect*`/`resolve*` pair at the decl (so `defineSymbol` lands in `table.current`, Nim's `addDeclAt`) and lift the node onto `programStmts`, since every transform and both backends discover types by walking module-level statements. The lift goes to the FRONT, not the back: C claims TypeInfo ownership when the decl is emitted (`declaredThings` in genClassDecl), so a decl landing after its use site emitted `extern msTypeInfo <T>TypeInfo` with no definition — found via the local-actor case (`undefined symbol: _TinyTypeInfo`), where destructorLifting also declines to emit TypeInfo because `isClassOrInterface` covers Class/Interface only. Verified on recompiler main `d0a1702`: nim-guard ALL GREEN (new `localTypeDecls` covering alias/interface/struct/enum/class/extern on drc+orc+js, new `localActorDecl` on drc+orc), bug106 11/11, battery 3466/3466, neon 295/305/294. **Residual (own arc)**: a local name is admitted only when free module-wide (`claimLocalTypeName`) — SHADOWING stays rejected where Nim resolves innermost, because C keys the struct and its include guard on the bare name; closing it needs identity-keyed mangling (Nim `getTypeName` + sigHash), same arc as the generic-instance `_ItemTypeInfo` dup-symbol row |
| **an UNANNOTATED self-recursive const closure is rejected** | `const visit = (x: number): number => { if (x <= 0) return 0; return visit(x - 1); };` | ❌ `Undefined variable 'visit'` at the recursive call — TS-valid. Root cause located: `checkPass.ms:341` pre-registers the self-ref symbol ONLY when the const has a declared type (`declType !== null`), so the annotated `const fact: T = n => fact(n-1)` works but the bare `const f = (x) => f(x)` does not. Removing the gate makes the NAME resolve but the recursive call then carries `inferredType` (kind 47) to codegen → worse failure (`internal: unresolved type reached codegen`). The complete fix needs recursive type inference: pre-register with the arrow's SIGNATURE type (built from its param/return annotations) before the body is checked, so the recursive callee is well-typed. Pre-existing on v0.2.46 + HEAD; orthogonal to this arc, logged not fixed |

### Added 2026-08-14 by the Stage-2 baseline audit (worktree /tmp/wt106 at `c83d3fa`, self-built binary, clean cache; both A/B'd WITHOUT the bug106 import — pre-existing)

| bug | repro | measured today |
|---|---|---|
| **`**` operator kills the whole `msc test src/test/index.ms` gate** | `assert 2 ** 3 === 8` (src/test/lang/syntax.ms:45-48, in-tree since `931ca20`) | ❌ `internal: operator '**' reached codegen unresolved in proc __ms_test_3` ×4 → the aggregate test build dies, **0 tests run** — the fixedbugs gate has been dead silently. Checker knows `**` (checkExprPass.ms:878, 2019); the miss is downstream (untraced). Standalone files avoid it; only the aggregate imports lang/syntax.ms |
| **a module whose ONLY top-level statement is a bare block never emits its `__Init000`** | `{ }` as the entire file | ❌ `call to undeclared function '<module>__Init000'` in `_dispatch.c` — the dispatcher calls the module initializer unconditionally, but emission skips it when no executable top-level statement survives. Measured identically on installed **v0.2.48 with zero local changes**, so it is pre-existing and independent of the local-decl arc; it only became REACHABLE there (once a local class/interface/enum is admitted, `{ class L {...} }` becomes a legal file that hits this). Adding any statement (`console.log(1)`) after the block makes it build |
| **fixedbugs aggregate dies at LINK: 5 duplicate symbols** | `./msc test src/test/fixedbugs/index.ms` | ❌ `_ItemTypeInfo` (bug024/bug036/bug062 each declare an `Item` type) + `_dollarEnv_test{1,2,4,7}_shared_TypeInfo` (lambdaLifting names the per-test shared env `$Env_test${counter}_shared` — file-local counter, so sibling FILES collide; destructorLifting then mints TypeInfo globals from those names). TypeInfo emission INTENTIONALLY bypasses mangling (comment at codegen/c/declarations.ms:590: raw name + `__attribute__((weak))`, cross-module identity by name) — but the linker reports hard duplicates, and even a successful weak collapse of two STRUCTURALLY DIFFERENT `Item`s would be silently wrong. Same mangle-key-must-match-emitted-symbol invariant as local-decl Stage 2; needs its own /trace-nim vs Nim `getTypeName` + sigHash (ccgtypes.nim:150). Do NOT fix in passing |

| ~~JS drops the positional arguments of `new C(a, b)`~~ ✅ **CLOSED 2026-08-13** — direction A (materialize once in transform, the arc philosophy): `transform/lowering/newExprLower.ms` (was a no-op skeleton registered C-only) now lowers positional `new` on a ctor-less class into a hoisted temp + field assignments in the SHARED pipeline right after `lowerCtorInit` — `new Pt()` runs `Pt_init` (defaults, super chain), assignments override, both backends, same order the C inline branch had. Positions: var-decl init, expr-stmt, return, if-cond (+ else-if block-wrap); parity C=JS proven on an 8-shape probe (nested new-in-args, call-arg, user-ctor class untouched). Guard `src/test/guard/positionalNewJs.ms` + new `// GUARD-JS` mode in `run.sh` (build --target=js + node-run, pass = exit 0 + GUARD-OK): proven RED on v0.2.46 (ok drc/orc, FAIL js), ALL GREEN + clean RC balance under the fix. Battery 171/3461. Branch `js-positional-new` in recompiler. **RESIDUAL (open, still silent-wrong on JS)**: conditional-eval positions — ternary branch, `&&`/`||` RHS, while-cond — are skipped by design (eager hoist would evaluate args unconditionally); measured C `300` vs JS `NaN` on `flag ? new Pt(100,200) : new Pt(300,400)`. C keeps its inline positional branch in `codegen/c/expressions.ms` for exactly these residuals — do NOT delete it until they are lowered too | `class Pt { x: number; y: number; z: number = 3 }` + `new Pt(1, 2)` | was ❌ silent wrong answer on JS, last red cell of the class-construction matrix |

---

### Added 2026-08-30 by the theme-token arc (bisected on binaries built this session — PRE-EXISTING, not caused by the alias-generic fixes)

| Bug | Repro | Status |
|-----|-------|--------|
| ~~a `<T>Eq` companion is forward-declared with the bare generic-instance name but defined with the module-qualified one — native compile dies wherever two modules share a generic instance~~ ✅ **CLOSED 2026-08-31**, recompiler `d98a3d4`, deployed | `msc test tests/render/style.test.ms` on native (also `styleCss.test.ms`, `direct.test.ms`), using any binary built from recompiler main | was ❌ clang `conflicting types for 'Maybe_p34_unionnumberstring20Eq'` — the cached declaration in `host.ms` says `Maybe_p34_unionnumberstring20`, the definition in `style.ms` says `Maybe_p34_unionnumberstring20__Z…ZstyleOms`; `src/render/style.ms` + `src/render/host.ms` both fail to compile. **PRE-EXISTING — 4-point bisect, every binary self-built this session, all run against ONE pristine neon worktree at `bd0e37f`: `a551213` RED · `2f38676` RED · `6e98171` RED · `9b247e3` RED.** Red already at `a551213` (before every alias-generic fix), so it belongs to the type-identity/mono-identity arc's `<X>Eq` companion facet — the piece the hook-keying work left open. Invisible under the installed msc v0.2.50 only because that binary predates `a551213`. ✅ **FIX** (`d98a3d4`, +12 lines in `codegen/c/names.ms`): `mangledTypeName` never module-qualifies a SYNTHESIZED STRUCTURAL name (`Maybe_`/`msTuple_`/`msAnon_`/`msUnion_`) — one globally cached object per shape, shared by every module, name already encoding its content, so the `sym` it carries is whichever module touched it first, not an owner. Same carve-out as the `$` and mono `__` ones already there. This IS Nim's rule: `sighashes.nim:73 hashTypeSym` hashes `sfAnon`/`skGenericParam` to `":anon"` — no file path, no owner chain — while NAMED types get `customPath(conf.toFullPath(pathFi))` + owner chain. So module-qualification was never the error; applying it to an anonymous carrier was. Guard `src/test/guard/structuralMaybeHookNaming.ms` + fixture proven RED before / GREEN after; against a self-built control at `a8a4021` the guard-suite FAIL set is IDENTICAL and the landed tree adds exactly +2 ok (the new guard). **REMAINING — nhịp 2, the root fix for the whole family**: (1) MS has no `sfAnon` equivalent, so the carve-out sniffs NAME PREFIXES where Nim reads a FLAG on the symbol; (2) `collectTypeAlias` (checker/collectPass.ms:492) stamps the alias's own `sym` onto the aliased type, where Nim's `hashType` treats `tyAlias` as transparent (`c.hashType t.skipModifier`) — an alias must never contribute identity. ⚠ `175ac18` cannot serve as a control — broken as committed (`isWideningInt64Conv` not exported from `./types`) |
| ~~neon main needs a compiler that is not deployed~~ ✅ **CLOSED 2026-08-31 by deploy** | `msc test tests/render/theme.test.ms` with the installed msc | was ❌ `Return type mismatch in 'themeOf…': expected T, got __anon2__…`. The theme-token work (neon `6caf547`…`1431dd1`) rests on recompiler `b3907f8`+`d936a21`+`0898b5b`+`9b247e3` (alias-generic identity), committed but not installed. Deployed as a SET (binary + `std/` + `runtime/`, backups `*.bak-1788127481`) from a tree at `9b247e3` + the `<X>Eq` fix — NOT from main, which is red as committed (row below). Now green: neon `1431dd1` **295/295 native**, `theme.test.ms` 3/3 on both lanes |
| **recompiler main is red as committed — do not deploy from it** | `msc test src/index.ms` and `src/test/guard/run.sh` at `a8a4021` | ❌ battery exits RC=255 with no summary, dying in the LSP handler tests right after `lsp/handlers/completion.ms`; guard suite 8 FAIL / 154 ok — `asyncArrowContextual` + `closureShadowSharedEnv` (build error, both modes), `closureCaptureNullableReturn` (DOUBLE-DESTROY of Thing), `sameNameTypeHooks` (`imbalance Inner alloc=6 destroy=3` — the leak the hook-owner-module-keying work closed on 2026-08-30, back again). Introduced by the 9 commits `12d8438`…`a8a4021` from a parallel session (runtime/linker/platform-tools); at `9b247e3` the same battery ran 3510/RC=0 and the guard suite was ALL GREEN. Measured on binaries built this session from a clean worktree; the landed `<X>Eq` fix at `d98a3d4` reproduces the IDENTICAL fail set, so it is not implicated. Not Neon's to fix — recorded so main is not mistaken for a deployable base |
| **`style.test.ms` cannot be run on the native lane — the link step hangs** | `msc test tests/render/style.test.ms` (native) | ❌ killed at 900s (RC=124), zig at 0% CPU during `zig cc … -o out/debug/_test_style.test`, which pulls `libyoga.a` + `-framework Cocoa/QuartzCore/Metal/MetalKit -lc++` via `platform/void`. Not caused by the `<X>Eq` fix: before the fix the file never reached the link step at all, and a minimal driver importing `src/render/host.ms` links clean (RC=0) under the same binary. The JS lane runs fine (56 ok / 4 fail = the known pre-existing baseline). Blocks native verification of the whole style/theme surface — needs its own trace |

### Added 2026-08-31 by the alias-identity arc (arc B) — PRE-EXISTING, proven independent of type aliases

| Bug | Repro | Status |
|-----|-------|--------|
| ~~a struct `===` emits a call to `<Name>Eq` that nothing defines, when the struct's name is not in the consuming module's scope~~ ✅ **CLOSED 2026-09-01**, recompiler `a88f6d3`, deployed | `import { mkP } from "./decl"; const p = mkP(3); p === mkP(3);` with `P` itself never imported | was ❌ `link failed` / `undefined symbol: _PEq`. `operatorLower` registered the comparison by NAME (`ctx.pendingStructEqs.push(typeName)`) and destructorLifting.ms:2149 fed those names to `ensureEq`, whose `lookupSymbol` only finds names the consuming module can see; it returned silently, so the emitted call had no definition. **FIX**: `registerStructEq` now routes through the channel the design already had beside it — `pendingCarrierEqs`, which carries the TYPE and generates from it, added for synthesized `Maybe<T>` carriers that have no symbol-table entry either. A never-imported struct is the same situation. Proven independent of type aliases: an alias-free probe on the pre-fix binary gave the identical `_PEq`. Guard `src/test/guard/structEqNameNotInScope.ms` + fixture, proven RED on the deployed arc-B binary / GREEN after; battery 3510/3510, guard-suite FAIL set unchanged |


### Added 2026-09-01 by the arc-B guard-suite A/B (both RED on `bee4e5d` WITHOUT arc B — pre-existing, not Neon's)

| Bug | Repro | Status |
|-----|-------|--------|
| **cross-module `super(args)` emits `Parent_init(...)` with no prototype** | `src/test/guard/crossModuleSuperProto.ms` (parent class in another module) | ❌ clang `call to undeclared function 'Shape_init'`. Traced with a codegen print: the super branch IS taken and emits the call, but the proto is gated on `parentChildren !== null` and BOTH sources are blind cross-module — `lookupCtorDefaults("Shape_new")` misses because `registerCtorDefaults` is only ever called from `checker/instantiate.ms` (GENERIC classes only, never a plain class), and `crossModuleCtorParamTypes` reads `sym.declNode`, which for an imported symbol is the **ImportDecl**, not the ClassDecl. **Three fixes measured and REFUTED**: (1) unwrapping `Ref` before `symbolType.sym.declNode` — still red; (2) delegating to the canonical `getCtorParamTypes` (checker/symbol.ms:41, what `new` uses) — still red, so that helper is blind to this symbol too; (3) therefore the defect is upstream, in what `super`'s callee resolves TO (an ImportDecl symbol rather than the class symbol). Its own arc: cross-module symbol identity, not a codegen patch. Reverted all three, tree left clean |
| **`src/test/guard/run.ms` is not a guard probe and fails the suite** | `src/test/guard/run.sh` | ❌ `FAIL run [drc]: exit=1` + `[orc]`. Built and run standalone it exits **0** and prints `nim-guard: ALL GREEN (0 cells)` — it is a MetaScript port of `run.sh` itself, picked up by that runner's own `"$DIR"/*.ms` glob and then failing on its LEDGER (`msStringArrayRefCell alloc=5 destroy=3`). In-flight work from a parallel session — left untouched. Either move it out of the glob (a `tools/` subdir) or make it balance |

### Added 2026-09-02 by the cross-module overload-naming arc (RED on the parallel session's 14:32 binary too — pre-existing, not this arc's)

| Bug | Repro | Status |
|-----|-------|--------|
| **JSX child typing: `NeonNode` not assignable to `children`** | `tests/render/direct.test.ms:188` under `--target=js` — `direct(<div><Show when={on()}><Leak count={n()} label="l" /></Show></div>)` | ❌ `Type 'NeonNode' is not assignable to type 'function' for field 'children'`. A **typecheck** error, before codegen, so no naming/codegen fix can reach it. C lane GREEN (310/310); JS lane only. A/B'd against the installed `msc` the parallel session deployed at 14:32 (same main, neither arc-B nor the naming fix) — identical error there, so pre-existing |

### Added 2026-09-02 by the SSR sheet-lifecycle arc (msc v0.2.52 installed)

| Bug | Repro | Status |
|-----|-------|--------|
| **A nullable type does not widen into a wider nullable union** | `function f(v: number \| string \| null)` called with a `number \| null` / `string \| null` value, or the same widening at an assignment: `got Maybe_p0, expected Maybe_p34_unionnumberstring20` (21 sites, `src/render/css.ms` first draft) | ✅ **FIXED + DEPLOYED 2026-09-02** — recompiler merge `1a82ae9b` (6 commits `a832c962`…`16d6f2cc`), binary synced (`msc --version` still prints v0.2.52, no bump). Root: the bare pair `A → A\|B` converted via `widenVariantToUnion`, but under a Maybe carrier both sides are Struct, so `isAssignableInner`'s same-kind arm sent them to the struct comparison and it refused. One slot lookup (`types.maybePayloadWidenSlot`) now feeds BOTH the relation (`compat`) and the conversion (`fit`/`callResolve`), and the C emitter rebuilds the carrier. Corpus `752-maybePayloadWiden.ms` red pre-fix on both lanes; battery 3528/3528, guard 174 ok, neon C+JS bad=0. `css.ms` keeps its four typed emitters by choice, not by force |

### Added 2026-09-08 by the style-table arc (measured on installed msc v0.2.54; full handoff prompts under `probe/prompts/`)

| Bug | Repro | Status |
|-----|-------|--------|
| **a macro HELPER that builds a node with `createNodeAt` hands the checker a Nil child → SIGSEGV in `checkExprInner`** | `probe/prompts/FULL-bug5-macro-helper-nil-node.md` (p4/p5 pair) | ❌ `createNodeAt` is a syntactic rewrite (`tryRewriteCreateNodeAt`) applied only through `preprocessMacroBody`, so a helper's node reaches the checker with Nil slots and no diagnostic. NOT blocking Neon: every node is built as an inline flat literal inside the macro body. Owner: parallel session |
| ~~**C backend narrows a union by MEMBER type with a reinterpret, not a check**~~ ✅ **FIXED 2026-09-18 in worktree `/Users/le/metascript/.wt/z_b6` on `ee4b9815`, NOT YET COMMITTED** — verdict DIVERGE-INCOMPLETE (trace-nim): Nim's `upConv` (ccgexprs.nim:3343-3364) checks before it reinterprets (`isObj` → `raiseObjectConversionError`) and the pointer cast is sound only under a prefix layout; `codegen/c/expressions.ms:1779` emitted that same shape with NEITHER, because the checker built no conversion for the assertion at all. The correct mechanism already existed and is already recorded SAME in `paper/NIM-REF.md` row 107 — `narrowMaybePayload` + the `_mnarrow` emitter arm rebuild the carrier for a flow-narrowed READ — nothing reached it from an `as`. Fix = 3 hunks: a TypeAssertion arm in `transform/coercion/maybeReadMaterialize.ms` routing the assertion through that same conversion (C-only via the existing `project` flag), the tag check in the `_mnarrow` arm, and `msRaiseVariantError` in `runtime/core/system.{h,c}` (shaped after `msRaiseIndexError`). Cells: A `V`, B `row`, C `no`, D `V`; a WRONG-tag assertion (`a = 42; a as string \| null`) now raises where it used to read a double's bits as an `msString` (`length=0`) — that silent facet was never in the original report. Guards `src/test/fixedbugs/bug186MaybeUnionNarrowCast.ms` (6 cells) + 2 cells in `src/test/c/asCoercionNullable.ms`, both PROVEN RED on a self-built same-commit control (`signal 6`, FAIL) and green on the patch. Gates: suite 3723/3723, corpus 1201 · 18 fail · 6 xfail (fail set entirely off-axis: 704/762 BitSet macro type errors, 619/628/630/711/773/775 js/esm-only where this patch is gated off, 419 the known timeout), Neon native + js all green from a cold `out/`. Deliberate gap, recorded: Nim elides this check under `optObjCheck`/`-d:danger` and ours is always on — codegen has no mode plumbing (`ctx.rangeChecks` lives in the transform layer) and `context.ms`/`index.ms` are held by a parallel session. STILL OPEN and untouched by this fix: a BARE sub-union narrowing with no Maybe carrier (`string \| int32 \| boolean` → `string \| int32` prints `I` for a string on C, `S` on JS) — that is the separate row "a narrowed SUB-union used as a value keeps the storage tag numbering" | `probe/prompts/FULL-bug6-c-union-narrow-cast.md` (`probe/bug5/b6.ms`, `probe/bug6/{e,f,g}.ms`) | was ❌ `takesNarrow(a as string \| null)` with `a: number \| string \| null` panics on C and prints `V` on JS; dropping `null` from the target works, dropping a member type breaks. Latent in `src/platform/browser/dom.ms` (JS-only today) — re-measured 2026-09-18, that call site is GONE, no `src/` site remains |
| ~~**`globalImports` injects an edge back into every module the injected target depends on → any macro invoked there SIGSEGVs with ZERO output**~~ ✅ **CLOSED 2026-09-16 (recompiler, this session; in the working tree, NOT yet committed)** — root (NIM-REF rows 296–297, verdict DIVERGE-UNINTENTIONAL → SAME): build.ms extras were appended to the SAME out-of-graph prelude context as std, so a macro called from one of them expanded with no ModuleGraph and no Module, the engine fell back to `checkProgram`, and that asked for the prelude it was already building (hang under `msc check`/`msc lsp`, rc=139 under a build). Fix = Nim `processImplicits`: extras are loaded into the module graph like any import (`loadExtraGlobalImportModules`, `checker/orchestrator.ms`, one loader shared by build and LSP), checked in Phase 2 with a full ctx, matched by `moduleIdentity()` instead of spelling, promoted into the base ctx by `promoteModuleIntoPrelude`; `isGlobalImport` is std-only (Nim `isImportSystemStmt`); the prelude pack and its `.deps` are std-only and keyed on stdPath; two dead re-entry guards removed (0 hits measured). Bug 168 rode along (`injectConcreteTypeSyms` had no `TypeKind.Function` arm — masked until now because the extras leaked into every std module's scope). Measured on two self-built binaries from `3dfadbb9`: guards `preludeMacroCycle`/`preludeUserModule`/`preludeSymlinkedModule` ok on the patch, and the two load-bearing ones are proven RED on the control — `preludeMacroCycle` blows past 6 GB RSS in 36 s (runaway recursion, killed by a watchdog) where the patch prints `42`, and `bug168FnTypeArgSymInject.ms` reports `Unresolved type 'Host168'` twice where the patch passes 294 tests. a fourth guard, `preludeDepsFresh`, was written and then REMOVED the same day: run by hand against the control binary its scenario stays green, and `-t` shows `seed=0` on both the warm and the second run, so the deps snapshot is never reused there and the gate could not fail on the buggy side (see the deps note below); suite 3708/3708 (control 3705); fixedbugs identical to control (3 pre-existing `new Box()`); Neon `tests/run.sh` all lanes green except the two P0.4 RED js tests (`terminal.test.ms:163`, `hostOps.test.ms:29`); LSP over stdio answers `initialize` and publishes 0 errors on the macro+globalImports fixture; corpus 1184 pass · 19 fail · 6 xfail, the fail list identical to the last self-built control (`ba16897a`, 1178 · 19) except the non-deterministic trio 405/410/419 (see the corpus NOTE below); same-base control corpus deferred to the land-time ladder because HEAD moved 4 commits (`734b5b14`) during the gate. Unblocks generating the four style lists from `STYLE_TABLE`. | `probe/prompts/FULL-bug8-globalimports-macro-cycle.md` | (history) ❌ **STILL OPEN — re-measured 2026-09-15** on a copy of `src` + `build.ms` (`scratchpad/b8`): control with no macro call in `src/render/style.ms` → `OK no type errors in 74 module(s)`; add ONE trivial macro invocation there → `msc check` **hangs with zero output** (killed at 100s). Same hang on the two backup binaries (`backup-20260915-120941` = valueOf without the bug-4 commits, `backup-20260915-115436` = neither), so it is pre-existing and independent of both arcs that landed today. Note the symptom is a HANG under `msc check`; the filed rc=139 was under a full build. ❌ rc=139 for a trivial macro in `src/render/style.ms`; a byte-identical copy outside the project compiles; `build.ms` reverted to HEAD still crashes. Blocks generating `interface Style` / `setStyleField` / `mergeStyle` / `styleToCss` from `STYLE_TABLE`; `tests/style/fields.sh` is the interim gate. **Second facet 2026-09-08**: a pure helper in a NEW macro module (`spread.ms`), called from a macro body, makes the `NeonNode` converter silently stop firing (`converter.test` + `direct.test` red, no crash); the identical function appended to `reactive.ms` is green — so `findSpreadAttr` lives in `reactive.ms` until this lands. No owner |
| ~~**`msc check` cannot resolve a relative import that `msc test`/`build` on the same file resolves**~~ ✅ **CLOSED — re-measured 2026-09-15 on installed msc**: `msc check probe/chk/a.ms` → `OK no type errors in 66 module(s)`, same for a fresh 2-file pair outside the project. Same root as bug 2 (`check` now walks the module setup `build` uses). `tests/macros/run.sh` may go back to `check` | `probe/chk/a.ms` (`import { x } from "./b"`) | was ❌ see `probe/prompts/FULL-bug9-check-relative-import.md` |

### Added 2026-09-18 by the bug-6 detour (measured on the msc deployed 2026-09-18 = recompiler `88a7bf7b`, i.e. `cb672c39` + bug186)

Neon native under that binary: 40 files, **3 red, all pre-existing on a same-commit control WITHOUT bug186** (a `git archive` of `cb672c39` built 2026-09-18 22:51, since deleted — recreate with `git archive cb672c39 | tar -x -C <dir>` + symlink the 4 `vendor/` libs + build, ~3 min). Gate by EXIT CODE: the type-error red below prints `type error(s) found`, which a grep for "fail" misses.

| Bug | Repro | Status |
|-----|-------|--------|
| **`tests/platform/void.test.ms` segfaults at run time (signal 11)** — NEW, a recompiler regression | `msc test tests/platform/void.test.ms` → `rc=139`, `test binary terminated by signal 11` | ❌ green at 08:07 on `ee4b9815`+bug186, red on `cb672c39` with AND without bug186 (A/B 22:51, both rc=139); the `void` repo did not move (last commit 09-16, clean tree). Culprit is in `ee4b9815..cb672c39` (10 commits, 3 of them on a hot path: `4f588330` analyzer nothrow-by-symbol, `24c209fc` nested type symbol before decorators, `a3de26c7` stabilize project compilation). NOT bisected. No owner |
| **`tests/render/{direct,flow}.test.ms`: `in instantiation of 'map<number, function>': Unresolved type 'Host' - missing import?`** — NOT a regression: the bug168 fix is still an UNCOMMITTED hunk in the shared recompiler tree (`src/checker/instantiate.ms`, held by another session), so every clean build of recompiler `main` lacks it | `msc test tests/render/direct.test.ms` (`direct.test.ms:528`, `items.map((n: number): NeonView => …)`) | ❌ red on every binary built clean from `main` (`ee4b9815`, `cb672c39`, `88a7bf7b` = the msc deployed 2026-09-18 16:23 by the bug-6 detour). The one-NeonNode arc gates on `~/metascript/recompiler-wt-capfix/msc` (= `ee4b9815` + bug168 + 2 fixes) and its record says NOT to overwrite `~/.metascript/bin/msc` for exactly this reason — the bug-6 detour did overwrite it (previous binary kept as `~/.metascript/bin/msc.bak-1789723434`, the 06:15 bug185 deploy; its std/runtime were NOT backed up). Closes when bug168 lands |

### Added 2026-09-15 by the bug-4 collect-pass arc (every row MEASURED this day; the four FULL-bug prompts from 2026-09-07 never had rows here)

| Bug | Repro | Status |
|-----|-------|--------|
| ~~**BUG 1 — a generic type argument leaks across modules into a builtin generic's initialization**~~ ✅ **CLOSED — re-measured 2026-09-15**: `msc test tests/render/region.test.ms` → 293 passed, no `got Result<number, unknown>` | `probe/prompts/FULL-bug1-generic-leak.md` | was ❌ a `mapArray<number, HostNode>` call in a Neon test decided the type of `Result.err` inside std |
| ~~**BUG 2 — `msc check` resolves no import at all**~~ ✅ **CLOSED — re-measured 2026-09-15**: a 2-file pair with `./dep` → `OK no type errors in 66 module(s)` | `probe/prompts/FULL-bug2-check-std-resolve.md` | was ❌ `Cannot resolve module './dep'` on every multi-file program |
| ~~**BUG 3 — the same file imported at two depths becomes two modules → duplicate symbol at link**~~ ✅ **CLOSED — re-measured 2026-09-15**: `probe/rg2.test.ms` (depth 1) and `probe/sub/rg.test.ms` (depth 2) both → 293 passed, no `duplicate symbol definition: _gMsFutCbLock` | `probe/prompts/FULL-bug3-import-depth.md` | was ❌ link failed from depth 1 only — and it corrupted every measurement taken from a different depth |
| ~~**BUG 4 — code that references a macro-emitted `interface` SIGSEGVs**~~ ✅ **CLOSED 2026-09-15, recompiler main `22720d63`…`42101d35` (11 commits), DEPLOYED 12:09** — verified on the installed binary: both the prompt's own repro and the order-dependent variant (reference ABOVE the call) pass. ⚠ The 11:54 deploy was a CONTAMINATED build (a leftover gate process `rm -rf out` mid-build in the same worktree) and silently shipped WITHOUT these 11 commits while its acceptance run looked green; caught by `strings ~/.metascript/bin/msc | grep -c "attempt to access a nil address"` → 0. **Check binary vintage with `strings` before trusting any acceptance run.** The filed SIGSEGV facet had already disappeared on its own (measured: the prompt's exact repro → 293 passed on installed msc). What remained was ORDER DEPENDENCE, measured on installed msc: a reference BELOW the macro call passes, the same reference ABOVE it → `Unresolved type 'Sh' - missing import?`. Fix: a module-level `ExprStmt` calling a macro whose declaring module is already checked now expands in the COLLECT pass (`expandModuleStmtMacros`, checkPass.ms), so its declarations are collected like hand-written ones; arguments are untyped there, which is what Nim (`semgnrc`), Haxe (build macros run before fields are typed) and Rust (expansion precedes typeck) also do. Same-module macros stay on pass 3 — Scala 3, Rust and Elixir make that case a hard ERROR, we only fall back. Guard `src/test/guard/macroDeclOrderIndependence.ms` (7 shapes incl. `bindSym` chain and a JSX alias declared below the call) | `probe/prompts/FULL-bug4-iface-segv.md` | Gate run before commit: compiler suite 179 files / 3701 tests, 0 fail. Guard + corpus + Neon deferred to a dedicated session |
| ~~**three roots found under bug 4**~~ ✅ **CLOSED same day, same 11 commits** — (a) a module-level JSX comptime alias (`const card = <div />;`) killed the native build with `internal: unresolved type (kind=47)`: C codegen had TWO entry points for a variable and only the local one skipped comptime-only decls (Nim: `nkConstSection` ∈ `harmless`); (b) an entry file with no top-level code was dropped by DCE while the dispatcher still called its `Init000` → `compile failed for dispatcher` (Nim: `registerModuleToMain` always calls the main module's init); (c) the macro VM trusted a heap operand, so reading a field through `nil` (handle 0) hit ANOTHER LIVE OBJECT silently — now a located `attempt to access a nil address` (Nim `errNilAccess`) | guards `moduleJsxAliasNative.ms`, `entryWithoutTopLevelCode.ms`, `macroNilFieldAccess.ms` + 8 VM tests | (c) is why corpus `701-macroArgReuse` had to change: it read `a.data as NumberLiteralData`, which is always nil on the flat wire — it only passed because nil pointed back at the argument itself. Now uses the `intValue` accessor |
| **the checker recommends a pattern that is always nil inside a macro body** | `resolveEngineNodeVirtualProp` (`src/checker/callResolve.ms`), engine check mode only | ❌ the diagnostic says "narrow with a kind check or `.data as <Kind>Data`" — but the macro wire is FLAT, so `.data` is nil for every node. Correct advice is the kind accessors (`intValue`/`floatValue`/`stringValue`/`isFloatLiteral`). Cost is real: it authored corpus 701's wrong pattern. Fix = change the message |
| **a macro that returns a single declaration at statement position is dropped in silence** | a macro returning e.g. one `InterfaceDecl` NOT wrapped in `SpliceMany` | ❌ falls into `_ => inferredType()` in both the collect pass and pass 3: no declaration, no diagnostic. Pre-existing, not introduced by the collect-pass work. Workaround: always wrap emitted declarations in `SpliceMany` |
| **the arguments of a macro whose expansion failed are never checked** | any macro call that errors during expansion | ❌ the call is left `errorType` + `Sem`, so an error INSIDE an argument only appears after the macro itself is fixed — two round trips for one edit |
| **the calling module's seed symbols shadow the declaring module's** | `src/codegen/raiser/eval.ms:163-170` + `drainSeedSymbols` | ❌ the caller's seeds are pushed first and the first one wins, so a macro body can bind to a same-named symbol belonging to the CALLER, contradicting LANG-METAPROGRAMMING:611. Not touched because a parallel session owns `eval.ms` |
| **a macro that emits a new `macro` into the current module, called from a later statement, stays order-dependent** | — | ❌ the collect-pass expansion runs ONE pass and recurses into what it emitted; it does not re-scan the module. Rust handles this with a fixed-point loop (`fully_expand_fragment` retries `undetermined_invocations` under `force`, rustc_expand/src/expand.rs:489-520) — that loop is the upgrade shape if this ever appears. Never seen in corpus or Neon |

### Added 2026-09-17 by arc "one NeonNode" Lát 0.1 (A/B on binaries built this session)

- **CLOSED compiler (2026-09-17, recompiler `8c9f5af9` fix + `4700d72d` test on `d101b611`, deployed 03:12 binary + `std/meta/node.ms` + `std/core/math/index.{cms,jms,rms}`) — the Maybe carrier of a function payload fused every struct pointee.** `function pick<T>(fn: () => T, equals: ((a: T, b: T) => boolean) | null)` called for `Box` then `Pt` failed the second body check `got Pt, expected Box` (reversed order reversed it); primitives, `T | null`, a non-null function formal were fine. Found by `createMemo((): Style => …)` in a direct.test.ms S13 cell. Root: `typeKey` had no arm for `Ref`/`Ptr`/`Borrow`/`Var`/`Cursor`, so every pointer spelled `Ref` and `maybeCacheKey` returned the first carrier. Fix: those kinds spell wrapper + pointee. Nim: `searchInstTypes` → `compareTypes` → `sameTypeAux` compares tyRef/tyPtr by children (types.nim:1042) — DIVERGE-UNINTENTIONAL → SAME. Evidence: handoff `maybeRefPayloadKey.ms` (2 red before), `fixedbugs/bug175MaybeRefPayloadKey.ms` native 295 + js 59, guard `maybeRefPayloadIdentity` drc/orc/js, battery 3713, guard suite ALL GREEN 332, stage-2. Probes `probe/genDefault_q1..q6.ms`.
- **CLOSED 2026-09-17 03:40 by the owner's redeploy (tip `4700d72d` + bug168 hunk); `direct.test.ms` native 321/321 on it. Was: OPEN compiler (PEER-OWNED, not caused by the row above) — installed msc (03:12, `4700d72d`) fails Neon native `tests/render/direct.test.ms:522` `in instantiation of 'map<number, function>': Unresolved type 'Host'`.** First bad `cccff51f` (bug 8, global imports through the module graph); parent `b8dbdc21` green. `d101b611` + the uncommitted bug168 hunk (`injectConcreteTypeSyms` Function arm, shared-tree `src/checker/instantiate.ms`) + the fix above = 321/321 native. Closes when bug168 lands and msc is redeployed from that tip. Not rolled back: the 00:19 binary lacks bug 8, which the STYLE_TABLE commits need. Owner notified.

- **OPEN compiler — ROOT FOUND 2026-09-19, registered as recompiler `docs/KNOWN-ISSUES.md` L46: a module-level DESTRUCTURING binding read inside a closure reads zeroed memory on C.** The closure env carries `a`/`b` as fields and the caller never writes them; an accessor field is then a null function pointer, hence rc=139. Three parts of the original report are WRONG, re-measured on the L4d tip with the arc gate binary AND installed v0.2.55: the component is not needed (`element(<div>{x()}</div>)` alone is red), a function body is not a cure (only moving the SIGNAL inside cures it), and JSX is not needed at all — `const [a,b] = pair;` of two strings prints `a= b=`. A test block is red too. Repros `probe/l4post_*.ms` (N = 8 lines, no Neon import). Original text: **`direct()` at MODULE level over a component whose child reads a module-level signal segfaults native.** `const [x, setX] = createSignal("v");` then `const mount = direct(<div><Card>{x()}</Card></div>);` as module statements, `Card` taking `children: NeonNode` and returning `el("section", [], [], [props.children])`, mounted through `mockHost` and printed with `mockToString`: native rc=139, lldb frame 0 = `0x0` (a call through a null function pointer); `--target=js` green; the SAME statements inside a function are green native; tree emission (`element`) is green at module level. Family: module-level JSX/closure (the three roots under bug 4 — module-level JSX alias dead on native, entry not a DCE root). Not fixed; recompiler held by another session.

- **CLOSED compiler (2026-09-18, recompiler `e0849640` (binder) + `5f4ea649` (bridge) + `fdbf7b99` (test bug183, 3 cells) on `c73ef933`; NOT DEPLOYED — the installed msc still lacks this AND bug168; gate binary = `~/metascript/recompiler-wt-macroflow/msc` 00:52, main + the bug168 hunk; suite 3716/3716, Neon direct 343 native / 107 js, macros 23/23). Was: OPEN 2026-09-17, PRE-EXISTING, found by Lát 0.11 of the one-NeonNode arc; red on installed msc 16:56 AND `msc.bak-1789593246` 03:40 — a null guard emitted by a call-form macro does not narrow.** A macro returning `() => { const _o0 = <arg>; if (_o0 !== null) { take(_o0); } }` fails `Argument type mismatch in 'take' arg 0: got Maybe_p1, expected string`; the same statements written as source narrow. Repro `probe/l011_macroGuardNarrow/{m,main}.ms`. Root (code reading, recompiler `f8a913e5`): `bindFlowGraph` (`checkPass.ms:1974`) runs while every macro invocation is still a `CallExpr`; `bindCallExpr` (`binder.ms:815`) stamps no `flowNode`; the checker rewrites the node IN PLACE to `MacroInvocation` (`callResolve.ms:767`) and `expand.ms:1844` hands the still-null `node.flowNode` to `bindExpandedSubtree`, which returns early. The seed only exists for a node that was already a `MacroInvocation` at bind time (mono's `bindFunctionFlow`). Second hole on the same path: `bindStatement` has no `SpliceMany` arm, so a hoisting expansion (direct's template tier) is skipped whole. Fix: stamp `node.flowNode` in `bindCallExpr` + a `SpliceMany` arm in `bindStatement`; test `src/test/fixedbugs/bug183MacroCallFlowSeed.ms` (2 cells). Blocks: Neon 0.11 (nullable `on*`/`ref`/`style` emit a presence guard from `direct`). Third hole on the same repro (PRE-EXISTING, `msc.bak-1789593246` segfaults too, repro `probe/l011_ifNoElse/{m,main}.ms` = a macro emitting `if (true) { fn(); }` with no `alternate`): the parser gives an else-less `if` an EMPTY block, never null (`parser/statements/control.ms:63-66`), and every pass walks `alternate` on that invariant; the bridge rebuilt the node with a null `alternate` (`bridge.ms:1662`), so `asyncDesugar.walkAsync` dereferenced null — compiler rc=139, ZERO output (lldb: `walkAsync` ← `walkCheckExpr` ← `transformProgram`). Fix in the same worktree: `valueToNode` restores the empty block; third cell of bug183. A/B 2026-09-17 23:05 on the private binary: repro green native + js, control binary still red with the old type error.
- **OPEN compiler — registered as recompiler `docs/KNOWN-ISSUES.md` L47 (`6241cce5`), re-measured 2026-09-19 on installed v0.2.55: still red on BOTH lanes, two errors; the same `if` body without the closure is green.** Standalone repro (no Neon import) `probe/l011_constNarrowClosure.ms`. Was: **(2026-09-17, PRE-EXISTING, found by Lát 0.11; red on both binaries above) the narrowing of a `const` does not survive into a closure.** `const g = h; if (g !== null) { const k = (): void => { g(2); }; }` → `callee is possibly null (function | null)`; `const t = s; if (t !== null) { const len = (): number => t.length; }` → `Property 'length' does not exist on type 'Maybe_p1'`. Repro `probe/l011_constNarrowClosure.ms`. TypeScript keeps the narrowing for a `const` (and a never-reassigned parameter) captured by a function expression: the flow walk continues from the function's flow container into the enclosing flow. Not fixed. Neon impact: a nullable `onChangeText` cannot be attached conditionally (its text-unwrap wrapper is a closure over the narrowed temp), so `direct` rejects it with "a nullable onChangeText handler is not supported yet" (`tests/macros/optChangeTextDirect{,Flat}Rejected.ms`); lift that error when this row closes.

### Added 2026-09-10 by the react-surface sweep session (A/B on binaries built this session, `/tmp` worktrees at `149eed3e`)

- **recompiler main `13d45b33` `index 1 out of bounds (length 1)` crash — CLOSED upstream by `e4705566`** (fix(checker):
  check explicit and inferred bindings in one rest-aware pass: the unguarded `reconcileLimit` loop over
  `calleeType.typeChildren[ai]` is replaced by a loop bounded by `cd.arguments.length`). History: `tests/run.sh` on the tip-clean
  `149eed3e` binary → 7 red lanes, all the OOB string; bisect over `8de776e4..149eed3e` → FIRST BAD `13d45b33`. Re-measured
  2026-09-11 on a binary built from tip `7b84deb6` (`/private/tmp/wt_sweep_84229/msc`): memo + component green native and js;
  full gate → rc=1 with exactly ONE red lane, `tests/render/direct.test.ms` native (the js lane skips direct) at `:451` and
  `:455` (`<For each={items()}>…</For>`): `error: Argument type mismatch in 'createComponent' arg 1: got
  __anon2__eachx__childrenx, expected object`. Browser 75/75 green. Installed msc v0.2.54: every lane green.
- **CLOSED 2026-09-11 — generic call + object literal (the two rows this replaces): recompiler main `62062560`
  (fix(checker): construct object-literal arguments against the instantiated generic formal) + `b94aa7c9` (tests),
  landed via `update-ref` from `67f3df9d`, deployed to `~/.metascript` the same day (binary + `std/meta/index.ms` +
  `std/meta/node.ms` as named copies; the peer's untracked `std/process/index.ms` left alone).** Root (trace + 9-file
  probe matrix `scratchpad/ccprobe/`; Nim `sigmatch.nim:1260-1263` for the binding rule): the literal was never
  CONSTRUCTED against the instantiated formal — `checkExpr` skips the stamp when the formal still has generic params
  (`checkExprPass.ms:1139`), the pre-instantiation per-arg loop then related the self-typed literal to the
  uninstantiated formal with the layout-prefix relation (`compat.ms:617`, also rejecting a literal that supplies every
  field, via `fieldReprMismatch`), and the reconcile loop only restamped `arg.nodeType`. Fix in `tryInstantiateGenericCallee`
  (`src/checker/callResolve.ms`): (1) `fillArgBindings` — a type parameter bound to two incompatible types INSIDE one
  argument is reported (`Argument type mismatch in 'For' arg 0: 'T' is bound to both int32 and number`) and the argument
  marked conflicted, on Pass 1 and on the generic-fn-as-value pass; (2) `literalAwaitsBinding` — a literal whose formal
  still has generic params skips the pre-instantiation relation; (3) the reconcile loop clears Sem and re-checks the
  literal against the substituted formal (`callCheckExpr`), so an omitted optional field default-inits, an omitted
  function field errors by name, and `argTypes` matches the stamped type. `isObjectAssignable` untouched. Evidence:
  `src/test/handoff/genericLiteralFit.ms` 8 tests (4 RED before), `src/test/fixedbugs/bug140GenericLiteralOptional.ms`
  4 runtime tests (compile error on BASE); battery 3668/3668; full suite errors identical to BASE minus bug140's 9
  (18 pre-existing in old test files: `lang/result`, `lang/trycatch`, `bug129`, `unionNarrow`, …); stage-2 self-build
  green; Neon `tests/run.sh` rc=0 on the worktree binary and on the installed msc (second run, see trap below);
  the silent `item 1e-323` miscompile is now the rejection above on the installed binary. NIM-REF row inserted 2026-09-11 into
  `docs/NIM-REF.md` next to the missing-fields row (the peer's hunks in that file untouched).
- ~~**distinct over a function type: uncallable on C, untyped call, no one-way widen, generic instance hooks unlinkable**~~
  ✅ **CLOSED 2026-09-11** (plan 1.2–1.4; the 4 facets traced 2026-09-10, F1/F2 had been closed by the peer session's
  nominal work `f2f9dbce`/`ff36eaf7`). recompiler main `b75cd3f1` (fix, 8 files +70) + `16cd0147` (tests), landed on
  the peer tip `bd955fef` via `update-ref`, shared tree synced, deployed (binary; std/fs + runtime/fs were already at
  tip). Root: `Thunk<number>` is a GenericInstance whose Distinct base is never instantiated (`instantiateGenericBody`
  skips Distinct so the instance stays nominal), and the callee read, the widening relation and the hook classifier all
  stopped at the wrapper where the reference skips it. Fix: one peel `distinctBody` (checker/types.ms; substitutes via
  `getGenericDecl` + `substituteAllParams`), callee wrapped in `HiddenStdConv → base fn` + `isDirectCall=false`
  (callResolve.ms), `BrandWiden` for a Function base (resolvePass.ms) + GI clause in `isAssignable` (compat.ms),
  classify/lifter peel for locals, fields and array elements, C emits a conversion to a Function type as its operand.
  Surfaced en route and closed in the same commit: `(() => 7) as Thunk<number>` typed the arrow WITHOUT context
  (`() => int32`), so C read the int return as a double (`2.16e-314`) — `as` now types the operand against the
  distinct's function body (checkExprPass.ms). Evidence: handoff `distinctFnAlias.ms` 12 (6 red before), fixedbugs
  `bug141DistinctFnCallee.ms` 7 (native 299/299 + js 63/63), guards `distinctFnCallable.ms` (drc/orc/js GUARD-OK) +
  `distinctFnNoNarrow.ms` (GUARD-CHECK-FAIL), battery 3672/3672, full suite diagnostics identical to 1.0, stage-2
  self-build green, Neon `tests/run.sh` rc=0 on the worktree binary and on the installed msc (first run). Probe matrix
  `scratchpad/p1probe2/` (12) + `p1probe3/` (5). NIM-REF row "Distinct over a function type — call, widen, hooks"
  (hooks SAME; call + one-way widen DIVERGE-INTENTIONAL for Accessor). Still open, parked by design: `const r: string
  = t()` passes the checker and dies in clang — the var-decl general gate (parking lot), not this arc.
- **Trap (2026-09-11)**: the FIRST `tests/run.sh` after deploying a new binary showed `error: Undefined variable 'insChild'`
  / `'dynText'` / `'el'` across 11 native lanes (rc=1); the same lane alone, and then the whole gate, passed on the next
  run with nothing changed. Global cache under `~/.metascript/cache` (`headers/objects/prelude`; prelude key = toolStamp ‖
  std tree hash, `src/checker/preludePack.ms:7`); `src/test/CLAUDE.md:650-655` records the same shape. Rerun before
  calling a regression; rule out with `MSC_NO_PRELUDE_PACK=1 MSC_NO_GLOBAL_CACHE=1`.
- **CLOSED (2026-09-11) — generic alias over a function/array/tuple body had no instantiated body** (found at plan phase 2.1: `type Setter<T> = (v: T) => void` in `createSignal`'s return tuple died in clang `unknown type name 'Setter__int32'`; a field `set: Setter<T>` was refused by the checker; the js lane was green). Root: `instantiateGenericBody` whitelisted Struct/Union/Conditional/GenericParam/GenericInstance bodies (same root as the 08-30 row's facet g), so the instance had no `typeReturn` and `peelTransparentInstance` — the `skipTypes(abstractInst)` analogue — never fired. Fix (recompiler `707bcd54` + `54b05d85`, deployed 18:06): body of every kind except Distinct/Error; `resolveAnnotation` keeps a non-nominal `Ref` inside the instance body (`refWrapsNominal`) instead of re-wrapping it outside; twelve consumers read through the instance (callee read, `closureCallMarker`, C `getCalleeFuncType`, arrow contextual typing, `padLiteralParams`, array-literal expected, index/member receiver in checker + `nativeLower`, C `.length`, `classifyType`/`classifyArray`, `fillBody`/`registerSeqElement`); follow-up `381be2b4` + `cb230e7c` (found by the BitSet session with a phantom alias `type A<T> = int32`: `console.log(x + 1, y)` printed `<object> <A>` on C, values right): five more readers — checker `effLeft`/`effRight`, `builtinLower` toString callers, `debugLower.echoCoerceArg`, `stringOpLower.isStringTyped`, `operatorLower` operand types. Evidence: handoff `genericAliasBody.ms` 8 (4 red before), fixedbugs `bug142GenericAliasBody.ms` 6 (native 298/298 + js 62/62), guard `genericAliasBody.ms` drc/orc/js GUARD-OK, probes `scratchpad/p2probe/a1..a8` all correct on C and JS, corpus 759/760 BitSet unchanged, battery 3673/3673, full suite = base (18 pre-existing type errors), stage-2 green, Neon gate rc=0 with the 2.1 edits in place (worktree binary with caches on, and installed msc on the FIRST run). NIM-REF row "Generic alias instantiation — body of any kind" inserted (docs, not committed). Closes facet **g** of the 08-30 row; facet **c** (class type arg through an alias instance in member-access codegen) is untested by this fix and stays open.
- **CLOSED (2026-09-11) — the "first gate after deploy" flake had a root: the global prelude pack was keyed without `globalImports`** (`src/checker/preludePack.ms`: `key = hash(toolStamp ‖ stdTreeHash ‖ backendExt)`; the `.version` marker wipes the whole `~/.metascript/cache/prelude/` on a toolStamp change). So after every binary switch the FIRST process to build a prelude — a probe run from a directory with no `build.ms`, another project, another session's binary — wrote a pack without Neon's `./src/converters`, and every later Neon lane loaded it: `Undefined variable 'insChild'/'dynText'/'text'/'dynAttr'/'evt'` + `JSX expression must be consumed by a macro` across the 12 converter lanes, reproducible 2/2 in `tests/run.sh` with a worktree binary, while every one of those lanes passed alone after `rm -rf out` (the pack is global, `out/` is not the cache that mattered) and the whole gate passed with `MSC_NO_PRELUDE_PACK=1 MSC_NO_GLOBAL_CACHE=1` (71 lanes rc=0). Fix (recompiler `68aef59e`): the key now includes `globalImports()` (std defaults + build.ms extras); inline test "preludePack: the key follows the build.ms global imports". Still open (noted, not fixed): the key hashes the extras' PATHS, not their content — editing `src/converters.ms` with the same binary/std keeps the stale pack unless the `.deps` snapshot invalidates it (untested). **Designed out 2026-09-16 (recompiler working tree, with bug 8) — but NOT reproduced on this base, read the measurement:** an earlier note this session claimed the staleness was measured red on a control binary. Re-measured directly against the self-built control at `3dfadbb9` it is **green**: a globalImports module that gains an import rebuilds correctly (prints `2`) in two independent iterations, the second with a warm cache that the run demonstrably reused. So the guard `preludeDepsFresh` does not discriminate patch from control and must not be trusted as a red-first gate. Why it cannot be observed here, measured with `-t` (the `graphLoad:` line, `compiler/compile.ms`): **`seed=0` on BOTH the warm run and the second run**, so `loadPreludeModules` never seeds from the snapshot at all and staleness has no path to bite. Two contributing facts: (a) `~/.metascript/cache/prelude` is ONE global directory shared by every msc binary on the machine, and it stores a single `.version` (toolStamp) — any binary with a different stamp wipes the whole directory, so with four concurrent sessions each holding its own msc, the cache is wiped continuously (`.version` observed as four different values across one hour: `b42b0235_38dd0c65`, `bd08a810_494866ce`, `9338c282_ffc09e2`, `d9392946_f4e4469e`, while `runtime/` and `vendor/` hashes stayed constant); (b) 0 `.pack` files were written across every run observed. Consequence worth its own row: the `prelude=3687ms → 221ms` pack win does not hold on this machine, and the second run was SLOWER than the first (`preludeMods` 258 ms → 916 ms). Plausible fix if build time matters: key the cache DIRECTORY by toolStamp instead of wiping one shared directory. The pack and its `.deps` are now std-only (`key = hash(toolStamp ‖ stdPath ‖ stdTreeHash ‖ backendExt ‖ defaultGlobalImports)`), extras are re-read every build. The `preludeDepsFresh` guard was dropped before land (recompiler `cb3b5900`); the fresh-process gate is `src/test/guard/run.sh` on fixture `preludeMacroCycle`. A second key hole surfaced while gating: `stdTreeHash` is path-relative but `.deps` rows are absolute, so two checkouts of one commit shared a snapshot and a control worktree compiled the other worktree's `std/core/struct.ms` — hence `stdPath` in the key. The 11-09 trap entry above is this bug; "rerun before calling a regression" is no longer the rule — a red converter lane after a binary switch is this key unless proven otherwise.
- **OPEN compiler (2026-09-11, found at plan 2.2)** — an arrow literal passed where a NON-function parameter is expected is not reported: `function g(v: int32): void {} g(c => c + 1);` dies at the emission gate with `internal: unresolved type (kind=47) reached codegen` instead of "Argument type mismatch: got function, expected int32" (same for a closure-typed callee and a `Setter<int32>` alias). Repro `scratchpad/p2probe/b1..b3_*.ms`. Loud, not silent; diagnostic quality only. Family: the general fitNode/argument gate in the parking lot.
- **CLOSED compiler (2026-09-11, plan 2.2 detour) — `typeof v === "function"` narrowing + narrowed union reads on C.** Root (four facets of ONE feature, all pre-existing):
- **OPEN compiler (2026-09-11, found while measuring, NOT fixed) — calling a union of callables is accepted by the checker and dies in clang.** `function run(v: (() => int32) | ((p: int32) => int32)): int32 { return v(1); }` → checker clean, clang `called object type 'msUnion_…' is not a function` (probe `p3probe/d13`). Same family as the var-decl fitNode gate: neither the callee position nor the call-argument position asks the relation for a union of callables — `const one: () => int32 = v` (`e2`) and `take(v)` with `take(f: () => int32)` (`p4/e3`) are both accepted with 0 errors. `typeof v === "function"` keeps such a union whole (both members carry the tag), which is correct; the missing rejection is the consumer's.
- **OPEN compiler (2026-09-11, boundary recorded) — anonymous unions carry no lifecycle hooks.** `destructorLifting` names hooks by `typeName` (:1254 "anonymous types … can't name hooks"); only the inline primitive-union path handles a `string` member of an anonymous `float32 | string` FIELD. An anonymous `int32 | ((prev: int32) => int32)` never increfs/decrefs the closure environment through union copies: borrowed bits — fine for a call parameter (Neon `Setter<T>` shape), unsound if the union is STORED past its source. Named unions (`type U = …`) take the DU hook path, whose `typeNeedsHooks` probes `peelToStruct(member).typeNames` — for a Function member that is the PARAMETER list, so a closure member is still invisible there.
- **OPEN compiler (2026-09-11, boundary recorded) — narrowed MemberExpr field reads are not projected on C.** `declaredTagUnionOf` (fit.ms) reads Identifier storage only; `if (typeof s.w === "number") { s.w + 1 }` narrows in the checker but C reads the whole union (only `s.w as float32` extracts, via the TypeAssertion union arm). Not exercised by Neon.
- **OPEN compiler (2026-09-11, boundary recorded) — a narrowed SUB-union used as a value keeps the storage tag numbering.** `string | int32 | boolean` narrowed to `string | int32` by an earlier guard then passed to `f(u: string | int32)`: the checker types it as the new 2-member union while the C bits are the 3-member struct (`_tag` 0/1 happen to line up here, not in general). `projectNarrowedUnions` skips Union-typed reads on purpose; a re-tag conversion is the missing piece.
- **CLOSED compiler (2026-09-12, same detour, recompiler `14970a11` (fix) + `7d71dc49` (test), landed on `755c0a79` 2026-09-12 08:58) — a Ref-kind member (array) of a tagged union was never wrapped at a call site.** `function pick(v: int32[] | int32)`; `pick([1, 2, 3])` passes the raw `int32_tArray*` where `msUnion*` is expected (no `_tag`/`.v0` construction; clang silent): `widenVariantToUnion` → `primitiveMemberIndexInUnion` matches a `Ref` member by identity only (types.ms `child.kind != Struct && child.kind != Ref` guard), so a fresh literal never finds its slot. Probe `p3probe/d12` prints garbage for the length on C; JS fine. `typeof v === "object"` narrowing + projection are correct on top of it (`p4/e4`, struct member, is green on both backends), Fix: `widenVariantToUnion` (fit.ms) falls back to `sameType` over the members and dereferences the operand only when the slot holds a struct by value; `fixedbugs/bug144UnionArrayMember.ms` (array literal, array variable, `T | ((prev: T) => T)` with `T = int32[]` through both branches) native + js. This was the real blocker for Neon 2.2: 14 array signals / 22 `setX([...])` calls would have crashed.
- **CLOSED compiler (2026-09-12, same detour, recompiler `403bf444` (fix) + `28a78982` (tests), landed on `63f4f094` 2026-09-12 14:40) — a literal argument took no contextual type from a union formal.** With `Setter<T> = (v: T | ((prev: T) => T)) => void`, `setCount(c => c + 1)` failed "got function, expected int32 | function" (arrow param untyped) and `setItems([1, 2])` on a `number[]` signal failed "got int32[], expected number[] | function" (literal defaulted to `int32[]`); the object-literal case already worked (`findUnionVariant`). Root: `checkAnonymousFunction`/`padLiteralParams` and the ArrayLiteral arm peeled only the Maybe carrier (`fn | null`, `T[] | null`, NIM-REF row "Contextual arrow param/return typing peels Maybe"). Fix: `soleUnionMember(u, pred)` (checker/types.ms) hands the union's unique function / array-shaped member down as the contextual type (TS `getContextualSignature` parity, NIM-REF row "Contextual typing through a union formal"). Two members of one kind → no contextual type (pinned). Tests: `handoff/unionContextual.ms` 6, `fixedbugs/bug145UnionContextual.ms` 3 (native + js). Commits: recompiler `403bf444` (fix) + `28a78982` (tests), landed on `63f4f094` 2026-09-12 14:40.
- **OPEN compiler (2026-09-12, found while pinning bug145, PRE-EXISTING) — a union that mixes an interface (Ref<Struct>) member with a non-struct member is unsound on C.** `interface P { x: int32 }`, `function take(v: P | (() => int32)): int32 { return (v as P).x; }`, `take({ x: 7 })` → clang "indirection requires pointer operand" on `(*((*v)).v0).x` (probe `p6/g1`), IDENTICAL on the pre-arc binary `backup-20260911-183036` (cb230e7c): the variant slot holds the struct BY VALUE (genUnionType peels the Ref) while the checker keeps the member typed `Ref<P>`; the object literal is emitted as an anonymous 4-byte struct and its address passed as `msUnion*` (UBSan: "misaligned address … requires 8 byte alignment" once a closure member makes the union 8-aligned, probe `p6/f4`); a VALUE struct member (`type PV = { x: int32 }`) fails differently ("called object type" on the projected closure, `p6/f6`). The updater half (`set(p => ({ x: p.x + 1 }))`) works (`p6/f5`). Neon has no struct-valued signal today (number / number[] / Todo[] / string / boolean only), so `Setter<T>` is not blocked; `Setter<Style>`-like shapes wait here. Same family as the pointer-slot migration noted in NIM-REF row "Union → member projection" (2026-08-13).
- **CLOSED compiler (2026-09-12, same detour, recompiler `403bf444` (fix) + `28a78982` (tests), landed on `63f4f094` 2026-09-12 14:40) — a function whose parameter is a tagged union fit a slot whose parameter is the bare type.** `const s: Setter<number> = …` (param `number | ((prev: number) => number)`) was accepted for `take(f: (v: number) => void)`, `store.push(s)` and a `(v: number) => void` field (probe `p7/h1`, 0 errors): `fnSlotReprMismatch` peeled only the nullable carrier, so a `msUnion*` parameter met a `double` call site through the raw closure cast — Neon's `array.ms` stored the new setters in `(v: number) => void` slots and both `array.test` and `flow.test` died on a null `Signal__number` (the union bytes read as a pointer). Nim: `procParamTypeRel` keeps proc-type parameters invariant. Fix: one side a Union and the other not → representation mismatch (compat.ms `fnSlotReprMismatch`); Neon `array.ms` slots now declare `Setter<number>` / `Setter<T>`. Tests: `handoff/fnSlotUnionRepr.ms` (4). Commits: recompiler `403bf444` (fix) + `28a78982` (tests), landed on `63f4f094` 2026-09-12 14:40.
- **CLOSED compiler (2026-09-12, same detour, recompiler `403bf444` (fix) + `28a78982` (tests), landed on `63f4f094` 2026-09-12 14:40) — three more consumers read a generic alias instance raw (facet c of the 08-30 phantom-alias row).** Surfaced the moment Neon's `array.ms` slots became `Setter<number>` / `Setter<T>`: (1) `valueSetters.slice(0, n)` → "in instantiation of 'slice<Setter>': Unresolved type 'Setter'" — `injectConcreteTypeSyms` (checker/instantiate.ms) injected Struct/Enum/Distinct/Union names into a generic body's re-check scope but never a GenericInstance's alias name (`monoConcreteTypeName` already spells `Setter<number>`); (2) `setter: Setter<number> | null` was carried as a tagged union, not a nullable function (`isMaybeWrappable` switched on the raw kind) → JS "cell.setter is not a function" in `array.test`/`flow.test`; (3) `typeRelation` compared a `Setter<number>` ARGUMENT's type-argument list `[number]` against a `(v: number) => void` formal's parameters and reported Exact (probes `p7/h3-h5`) — the reason the slot-repr hole above slipped through the alias. Fix: GenericInstance arm in `injectConcreteTypeSyms` (alias symbol + its arguments), `peelTransparentInstance` at the head of `typeRelationInner` (mirror of `isAssignable:262`) and in `isMaybeWrappable`. Tests: `fixedbugs/bug146AliasInstanceConsumers.ms` (2, native + js), `handoff/fnSlotUnionRepr.ms` now red-proven through the alias. Commits: recompiler `403bf444` (fix) + `28a78982` (tests), landed on `63f4f094` 2026-09-12 14:40.
- **OPEN compiler (2026-09-12, boundary recorded, parked gate family) — an annotated arrow assigned into an array element or variable of a different function type is not checked.** `idxStore[pos] = (newPos: number): void => {…}` with `idxStore: Setter<number>[]` (param `number | fn`) type-checks, and the closure is later called through the `msUnion*` ABI while its body reads a `double` — the env register is garbage (UBSan "misaligned address … dollarEnv_mapArray…", found when Neon's `array.ms` index-controller slots were briefly mistyped as `Setter<number>[]`). Call arguments now reject this pair (`handoff/fnSlotUnionRepr.ms`); var-decl / assignment / array-element sites belong to the parked general fitNode gate (plan parking lot).
- **OPEN compiler (2026-09-12, boundary recorded) — a value-or-updater setter still enters a plain-setter array through a generic method.** `store.push(s)` with `store: ((v: number) => void)[]` and `s: Setter<number>` is accepted (probe `p7/h4`) although the direct call `take(s)` is now rejected (`h3`): the generic method's `T` is bound from the receiver and the argument is reconciled through unification, which does not apply `fnSlotReprMismatch`. Same parked family as the var-decl / assignment gate.
- **CLOSED compiler (2026-09-12, same detour, recompiler `403bf444` (fix) + `28a78982` (tests), landed on `63f4f094` 2026-09-12 14:40) — a parameter typed as a distinct over a function was passed by pointer (arc 1.3/1.4 facet).** Neon 2.4 made `For.children`'s row index an `Accessor<number>`; `<For>` callbacks written `(item, i: () => number)` (tree AND direct paths) then died in `msIncRef` (UBSan "misaligned address 0x8b7", `direct.test` lane) because the slot `(item, index: Accessor<number>) => NeonView` took `msClosure* idx` while the callback's own signature takes `msClosure i` — `ccgIntroducedPtr` (transform/native/pointerParam.ms and its codegen twin) promotes EVERY non-awaitable GenericInstance parameter to a pointer, a rule meant for generic struct instances that also caught a distinct over a function and transparent aliases such as `Setter<T>`; `shouldIndirectParam` then treated the instance as a struct. Repro `fixedbugs/bug147DistinctFnParamAbi.ms` (rc=255 before). Fix: `genericInstanceAbiRepr` (checker/types.ms) resolves an instance to its representation (transparent body, or the distinct body when it is not a struct) and both predicates decide on that; struct instances keep the old rule. Commits: recompiler `403bf444` (fix) + `28a78982` (tests), landed on `63f4f094` 2026-09-12 14:40.
- **OPEN compiler (2026-09-11, boundary recorded) — `v as int32` on an un-narrowed `string | int32` reaches clang.** Without a `typeof` guard the checker treats the cast as a numeric conversion and C emits `msCheckRangeI32((*v), …)` on the whole union (probe `p3probe/d6`). Inside a `typeof` branch the same cast is an identity over the projected slot and works. The checker should either reject the un-guarded cast or route it through the union `as` extraction (`(expr).vN`) that the TypeAssertion arm already has for struct variants.
- **CLOSED compiler (2026-09-12, plan 3.0, recompiler `7a7cd32f` (fix) + `d352f145` (test), landed on `330e944d` 2026-09-12 17:52) — a generic instance over `distinct T` was emitted with the un-substituted body.** `type Wrap<T> = distinct T`: a parameter, return or field typed `Wrap<int32>` came out as `void *` in C (clang `passing 'void *' to parameter of incompatible type 'double'`), `type Box<T> = distinct T[]` crashed at run time; js was fine (probes `scratchpad/p9/w1..w5`, phantom `Cnt<E> = distinct number` and alias bodies were green). Root: `distinctInstanceRepr` returned the declaration body with `T` free while only `distinctBody` substituted — the C type desc, `peelToRepr` (bigIntJS/rangeCheckInject) and the parameter ABI read the raw one. Fix: one `instanceBody` behind both helpers (eager body when the instance carries one, else `substituteAllParams`). Guard: `fixedbugs/bug148DistinctInstanceBody.ms` (4 cells, native+js).
- **CLOSED compiler (2026-09-12, plan 3.1–3.6, recompiler `c68fc77a` + `50a65756` (fix) + `9299d750` (tests), landed on `f1b1a671`) — auto-call: a bare read of a distinct over a zero-parameter function is its value.** `autoCallIfAccessor` (checker/callResolve.ms) rewrites an Identifier/MemberExpr read whose type is `distinct (() => T)` into a CallExpr flagged `NodeFlag.AutoCall` (new, ordinal 17 of `std/meta/node.ms`) through `checkCallExpr`, so the 1.3 distinct peel applies on both backends; fires when the expected type is not callable (`expectsCallable`: Function, distinct-over-function, or a union/Maybe holding one), including no expected type (operands, conditions, template, JSX child/attr, `const` without annotation, for-of, member object); held by `ctx.autoCallHold` on exactly the callee, an update operand and an argument during overload pass 1 (deferred like a context-sensitive arg, decided by the winner's formal in pass 2). Measured consequences (LANG.md §Distinct Types): `const c2 = count` snapshots; `id<T>(count)` binds the value; `() => count` is a value thunk; `on(count)` with overloads follows the winning formal. The hold is compared through hidden conversions and derefs (`peelHidden`, exported from checker/sendable.ms) because `foldComptimeNodeAliasArgs` re-checks a const-JSX clone whose callee the 1.3 peel already wrapped in `HiddenStdConv`; before that the Neon gate emitted `name()()` for `const view = <p>Hi {name()}</p>; element(view)` (js `name(...) is not a function`, C `called object type 'msString' is not a function`), pinned by `fixedbugs/bug153AutoCallHeldThroughHidden.ms` (3 cells, native+js). Two earlier tests aliased a thunk without annotation (`bug141` `keep141`, guard `distinctFnCallable` `keep`) and now read `const y: Thunk<number> = x` — by design that alias is otherwise a snapshot. Guards: `handoff/accessorAutoCall.ms` (11), `fixedbugs/bug150…bug154` (native+js), `guard/accessorAutoCallJs.ms` (drc/orc/js). Neon gate green on the landed binary with no Neon change (explicit `count()` is a callee → never doubled). Caveat kept from the parked var-decl gate: `const s: string = count` (now `count()`) still passes the checker and dies in clang; the call boundary reports `got number, expected string`.
- **CLOSED compiler (2026-09-12, same slice, `c68fc77a`) — `Accessor<T> | null` (distinct thunk) was a C tagged union with no fit-site wrap.** Found by bug152: `const p: Opt = { v: c }` compiled clean and clang rejected `assigning to 'msUnion_…'`; before that the checker refused the assignment outright (`Type 'Accessor<number>' is not assignable to type 'Accessor<number> | null'`, probes `scratchpad/p10/q3a,q3b`) because the brand-widen clause returned the widened relation. Fix: `isMaybeWrappable` peels the distinct body (a nullable distinct thunk is a `Maybe` like `Setter<T> | null` already was) and `isNominalMismatch` relates a nominal source to the Maybe payload; `if (p.v != null) p.v * 2` narrows and auto-calls, the un-narrowed read is refused `operand of '*' is possibly null` (before: a Union with a Null member let `p.v * 2` through silently).
- **OPEN compiler (2026-09-12, PRE-EXISTING, measured on the installed, boot and tree binaries) — parameter destructuring binds nothing.** `function call({ f }: Q): number { return f(); }` → `Undefined variable 'f'` in every shape (`export function`, arrow, two fields, non-function field); a stray global of the same name (`count`) gets resolved instead. The parser has `parseObjectPattern` for declarations; the checker only binds `const { a } = obj` (works, auto-call included). Neon writes `const { … } = props` today (`Pressable`). Blocks plan phase 4's `function C({ label, count }: Props)` → new step 4.0 before 4.1.
- **OPEN compiler (2026-09-12, PRE-EXISTING on the installed msc) — a const JSX alias at module top level dies in native codegen.** `const view = <p>Hi {name()}</p>; const node = element(view);` outside any function: `internal: unresolved type (kind=47) reached codegen … proc <toplevel>` (the alias symbol carries `noneType()` and the global slot is still emitted); js runs it. Inside a function or `test` block it works, which is how Neon's `element.test.ms` uses it. Probe: `scratchpad`-free, see `tests/render/_p3probe.ms` history in the Phase 3 log.
- **OPEN cosmetic (2026-09-12) — an argument mismatch prints the Maybe carrier name.** `needsNum(p.v)` with `v?: Accessor<number> | null` reports `got Maybe_Accessor, expected number` (`typeDisplayName` of the carrier) where the var-decl path prints `Accessor<number> | null`.
- **CLOSED compiler (2026-09-12, plan 4.0, recompiler `593703f9` (fix) + `5c21d90a` (tests), landed on `9299d750`) — a destructured parameter bound nothing.** `function C({ label, count }: Props)` failed `Undefined variable` in every shape on both backends because `parseParamList` skipped the pattern and named the slot `_destructure`. Fix (parser-level sugar, as TS specifies): the pattern is parsed with the declaration pattern parsers (registered through `statements/callbacks.ms`), the slot is named `_destr<N>`, and `const <pattern> = _destr<N>;` is prepended to the body (an expression-bodied arrow becomes a block returning the expression); the existing `DestructuringDecl` checker/lowering path binds the fields with their declared types, so an `Accessor<T>` field auto-calls. A pattern with no annotation and no contextual type is refused `a destructured parameter needs a type annotation`. Guards: `handoff/paramDestructure.ms` (6), `fixedbugs/bug155ParamDestructure.ms` (6 cells native+js), `guard/paramDestructureCapture.ms` (drc/orc/js). Formatter prints the desugared form (`_destr0: P` + the decl) — it printed `_destructure` before, so no roundtrip regression, but a fmt row stays open.
- **OPEN compiler (2026-09-12, PRE-EXISTING on the installed msc, C only) — `assert` over an expression whose nested arrow destructures dies in clang.** `test { assert each((p) => { const { a } = p; return a + 1; }) === 21; }` → `use of undeclared identifier 'a'` (probe `scratchpad/p12/f3_testAssertManual.ms`); the same arrow assigned to a const first, then asserted, runs. js runs both. Likely the powerAssert capture clones the expression before `destructuringLower` ran on the copy.
- **OPEN compiler (2026-09-12, PRE-EXISTING, C only) — a module-level call with a struct literal holding a string is hoisted as a static constant that C cannot initialise.** `f({ a: 1, b: "x" })` at top level → `initializer element is not a compile-time constant` (`.b = msCharTable[120]`), probe `scratchpad/p12/d14_konstPlain.ms`; inside a function it runs. js runs it. Re-hit 2026-09-15 (arc "one NeonNode" P0.3a): `Label({ label: "a" })(host, root, null)` at module level → `.label = msCharTable[97]`, `probe/placeShape_p03a.ms` (the same shape inside a function is the control).
- **OPEN compiler (2026-09-15) — recompiler main `b707175d` breaks every Neon NATIVE lane; do not deploy from it.** Every native lane dies in clang at `src/render/host.ms:53` (`passing 'Maybe_p34_unionnumberstring20 *' to parameter of incompatible type …; remove &` + `conflicting types for '…Eq'`); guard cells `structuralMaybeHookNaming` / `unionMemberEquality` fail the same way under drc and orc. JS lanes and browser 75/75 stay green. Reproduced on binaries built from a clean `b707175d` (this session and the `fix-macro-excess-property-checks` session); `cc25bd38` builds both cells green. Proven cause (that session, from the emitted C): `src/codegen/c/forward.ms:125` hardcodes the `Eq` hook's forward prototype BY VALUE (`MS_BOOL ${callee}(${typeName} a, ${typeName} b)`), while the definition and call site follow `shouldIndirectParam`. The layout-table commits of 2026-09-15 pad a union correctly (Maybe<number|string> 24 → 32 > threshold 24), which flips it to by-pointer and exposes the latent hardcode; the old unpadded size is fossilized in the mangled name `…unionnumberstring20`. Nim's model: prototype and definition share one generator (`genProcPrototype` cgen.nim:1662 and `genProcAux` :1476 both call `genProcHeader`, ccgtypes.nim:1313). Fix owned by that session, pending their user. Latent and separate: `SIZE_NOT_COMPUTABLE = -3` reads as "small" at the three `> ptrThreshold()` sites, where the old estimator returned "large"; no test exercises it.
- **CLOSED compiler (2026-09-15, recompiler `57c217cc` + `1a819ca9` (fix) + `ba16897a` (tests) on `30b8be8d`, deployed 22:20 binary + `std/meta/node.ms`; found by arc "one NeonNode" P0.3d) — a call argument of ANY non-function type passed the checker into a function-typed parameter.** Installed msc now reports `Argument type mismatch in 'take' arg 0: got Maybe_fn_fnnumbervoid15, expected function` for `probe/nullFnArg_s1.ms` (before: clang `msClosure`). Fix, all Nim-model: (1) the argument loop relates EVERY argument through one relation (`paramTypesMatchAux`), deferring only a still-generic formal when either side is a function; `null` no longer meets a function type (NIM-REF row 92, `proc {.not nil.}`); (2) `hasGenericParams` walks every type with a mark bit (`containsGenericType` via `iterOverType`) instead of skipping every named struct — that skip hid the generic Maybe carrier `Maybe_fn_fnTT…`; (3) `ensureHooks` stops on a still-generic type (`createTypeBoundOps` returns on `tfHasMeta`), `genClassDecl` skips a generic body, and the post-binding reconcile updates `argTypes` after the Maybe/union wrap (`implicitConv` types the node with the instantiated formal). Gate: battery 3705, genericArgFit 2401, suite = base, guard 316 ALL GREEN, stage-2, Neon `tests/run.sh` rc=0. The "named or lifted function into a `fn | null` slot" family described inside this row is NOT fixed — it is the OPEN row right below. Original report: `function takeF(f: (x: number) => void)` then `takeF(5)` / `takeF("x")` / `takeF(null)` / `takeF(h)` with `h: ((x: number) => void) | null` all type-check; C dies in clang (`passing 'int' / 'const msString' / 'void *' / 'Maybe_fn_…' to parameter of incompatible type 'msClosure'`), JS throws `TypeError: f is not a function` at the call. Same through an interface field closure (`sink.cb(h)`) and through `host.addEvent(el, "onPress", h)` emitted by `direct` for `onPress={nullableHandler}`. Found beside it, SEPARATE and PRE-EXISTING (same on the unpatched compiler): a NAMED function stored into a nullable function variable (`const h: ((x: number) => number) | null = dbl;` then `if (h !== null) { h(2); }`) dies on C with `assigning to 'msClosure' from incompatible type 'double (double)'` at the narrowed read; JS prints the right values; a named function passed straight into a nullable PARAMETER works (`probe/namedFnIntoNullable.ms`). The same C error also hits an ARROW: `const h: ((x: number) => number) | null = (x: number): number => x * 2;` then `takeMaybe(h)` or `viaParam(h)` into a `((x: number) => number) | null` parameter → `assigning to 'msClosure' from incompatible type 'double (double)'` — the local is flow-narrowed to the function by its initializer, and the narrowed read re-wrapped into a Maybe slot carries the raw lifted function; reproduced identically on a binary built from the unpatched base `b707175d`. Narrowing is not the trigger. The common shape is a function (named or arrow) flowing into a `fn | null` slot at a DECLARATION or a `return`: `function pick(on: boolean): ((x: number) => number) | null { if (on) { return (x: number): number => x * 2; } return null; }` and then `viaParam(pick(false))` fail the same way on the base binary. At an ARGUMENT, an arrow literal and `null` wrap correctly (`takeMaybe((x: number): number => x + 5)`, `takeMaybe(null)`, and a nullable parameter narrowed then forwarded into a plain one all run on C), but a NAMED function does not: `takeMaybe(dbl)` and `narrowed(dbl)` into `((x: number) => number) | null` parameters fail with the same `'double (double)'` error, identically on a binary built from base `b707175d` and on the patched one (bug166 draft, measured 2026-09-15). So the family is "a named or lifted function reaching a `fn | null` slot outside the arrow-literal wrap", not a narrowing bug. A class method (`holder.run(7)`, and `solo.go("text")` into a `number` parameter, `probe/nullFnArg_s8.ms`) is NOT this row: class methods resolve through `extPreResolved`, which is the 2026-09-14 OPEN row "an extension-method argument is never related to its parameter". Controls that ARE rejected: `number | null` / `string | null` / `Box | null` into a non-null param (`Argument type mismatch … got Maybe_p0, expected number`), and `return h` from a function returning `(x: number) => void`. Cause (read): the per-argument loop in `callResolve.ms` (~1272-1303) splits the relation into kind-based branches — a function-typed formal is skipped unless the argument is itself a function value (`fnPairCheckable`), and a LAMBDA LITERAL is never related at all, so `takeN(() => 1)` into a `number` also dies in clang and `takeF((s: string): void => {})` into `(x: number) => void` compiles and RUNS with the wrong parameter type (`probe/argLoop_q1.ms`, `argLoop_q2.ms`). Nim relates every argument through one `typeRel` (`paramTypesMatchAux`, sigmatch.nim:2499). Fix in progress in a worktree: one relation per argument, deferring only a formal that still holds a type parameter when either side is a function; a named function's return type stays invariant (`eff(one)` with `one(): number` into `() => void` is rejected before and after, as Nim `procTypeRel`). Probes `probe/nullFnArg_s1..s6.ms`, `probe/jsxNullHandler_p03d1.ms`. On the arc path: after the type switch `NeonNode` IS a function type.
- **CLOSED compiler (2026-09-16, recompiler `b1b290dd` (fix) + `3dfadbb9` (test) on `e51df3c2`, deployed 16:57 binary only — std and runtime had no drift) — a named or lifted function reaching a `fn | null` slot outside the arrow-literal wrap died in clang.** Fix: the function-to-closure thunk (`synthClosureThunk`, checker/fit.ms) is decided by the two types instead of the node shape, and the carrier builders apply it to their payload before wrapping — `synthMaybeWrap` for a Maybe, `widenVariantToUnion` for a tagged union. Test `fixedbugs/bug169NamedFnIntoCarrier.ms` (7 cells, native + js). Measured shapes, all of them now green, kept here as the original report: Measured shapes, all C `assigning to 'msClosure' from incompatible type 'double (double)'`, JS runs: `const h: ((x: number) => number) | null = dbl;` then `if (h !== null) { h(2); }`; `takeMaybe(dbl)` and `narrowed(dbl)` into a `((x: number) => number) | null` parameter (this supersedes the earlier note in the row above that a named function straight into a nullable parameter works); an arrow-initialized nullable local forwarded (`takeMaybe(h)`, `viaParam(h)`); `return (x: number): number => x * 2` from a function returning `((x: number) => number) | null`, then `viaParam(pick(false))`. Controls that run on C: an arrow literal or `null` passed straight into the nullable parameter, a nullable parameter narrowed then forwarded into a plain one. Identical on a binary from base `b707175d` and after `ba16897a`; `bug166FnFormalArgFit.ms` pins only the green shapes. Probe `probe/namedFnIntoNullable.ms`. On the arc path: after the type switch `NeonNode` is a function type, so `children: NeonNode | null` will meet this.
- **CLOSED compiler (2026-09-16, recompiler `b1b290dd` (fix) + `3dfadbb9` (test)) — a function value whose storage type was inferred from a named function, or a namespace member naming a function, died in clang.** Shapes: `const o = { f: dbl }`, `[dbl]`, `[dbl, tri]`, `function pick() { return dbl; }`, `() => dbl`, `id(dbl)`, `flag ? dbl : tri`, `let f = dbl; f = tri`, and `L.tri` from `import * as L` into any closure slot (bare, `fn | null`, `fn | string`, inferred `const f = L.tri`, call argument) — C `assigning to 'msClosure' from incompatible type 'double (double)'` or `called object type 'msClosure' is not a function`; JS ran. Root: the thunk was keyed on the node shape at three sites, an inferred storage type kept the non-closure calling convention although every C slot holding a function value is an `msClosure`, and the analyzer's "a function symbol is not a location" exemption covered only an Identifier, so a namespace member was sink-copied through `msClosureCopy`. Fix: `closureStorageType` (checker/types.ms) at every inference site — var decl, object-literal field, array element, branch join, inferred return of a function and of an arrow, generic binding; the thunk keyed on the two types in `synthClosureThunk` and in `closureCallMarker`; `fitJoinedBranch` compares the calling convention; `processMember` exempts a namespace member naming a function. Tests `fixedbugs/bug171FnValueInferredStorage.ms` (native + js), guard `namespaceFnValueThunk.ms` (C only — JS `import * as` is a separate open row), corpus `777-namedFnClosureStorage.ms` (parity across c/orc/danger/js/esm + SAN). Probes `scratchpad/fnnull/ns/`.
- **OPEN compiler (2026-09-15, PRE-EXISTING, split out of the rows above) — constructor arguments are never related, Maybe-wrapped or thunked.** `new H((x: number): number => x * 3)` into `constructor(f: ((x: number) => number) | null)` dies in clang (`passing 'msClosure' to parameter of incompatible type 'Maybe_fn_…'`); `new H(dbl)` into a BARE ctor parameter dies too. `checkNewExpr` only calls `callCheckExpr(arg, expected)`. JS runs.
- **OPEN compiler (2026-09-15, PRE-EXISTING) — a class-method argument into a `fn | null` parameter is never Maybe-wrapped.** `k.run((x: number): number => x * 3)` and `k.run(dbl)` die in clang; a bare-fn method parameter runs. Class methods leave the common argument loop early through `extPreResolved`, so they skip the wrap at `callResolve.ms:1291`, the narrowing check and the `HiddenStdConv` insertion. Session `recompiler-80` is measuring a fix that routes method calls through that loop; this row closes with it.
- **OPEN compiler (2026-09-15, PRE-EXISTING) — an overload with a `fn | null` parameter never matches a function argument.** `ov(dbl, 3)` → `No matching overload for 'ov'`; `ov((x: number): number => x * 3, 3)` and `ov(null, 3)` → `Ambiguous call`, both lanes. A bare-fn overload parameter matches.
- **OPEN compiler (2026-09-16, PRE-EXISTING) — a class field initializer without an annotation is never typed.** `class C { f = dbl; }` and `class C { f = (x: number): number => x * 2; }` → `internal: unresolved type reached codegen` on C; JS runs.
- **OPEN compiler (2026-09-16, PRE-EXISTING) — `import * as L` does not exist on JS.** `L.tri(2)` → `ReferenceError: L is not defined`; C runs. This is why the namespace guard is C-only.
- **OPEN compiler (2026-09-16, PRE-EXISTING) — a static method read as a value is broken on both lanes.** `const g: (x: number) => number = M.dbl`, `takePlain(M.dbl)` and a `fn | null` slot give C `use of undeclared identifier` and JS `g is not a function`; the direct call `M.dbl(2)` runs.
- **CLOSED compiler (2026-09-16, found by arc "one NeonNode" P0.4; landed 2026-09-17 recompiler `57fa72e8` + `f8bc3dc1` + `7f0c7c09` on `f6c426d2`, deployed 00:19) — under ORC, a failing `assert` whose message is a local owning a heap string aborts the test binary, and `msc test` reports it as a silent exit 255.** Repro, no Neon: `function make(): string { return "ab" + "c".repeat(2); }` then `test "t" { const got = make(); assert got === "zzz", got; }`. `msc test f.test.ms --gc=orc` → rc=255, no output at all; the built binary run directly aborts (rc=134, SIGABRT) on 10 of 20 runs and prints the right `AssertionError: abcc` on the other 10, so the failure path frees something it does not own. Every neighbour is green on both lanes: the same file under DRC, a message bound to a literal (`const got = "abc"`), a literal message on the heap string, a fresh concat message (`"got " + got`), and a PASSING assert with the heap-string message. Two holes: (1) the ORC failure path of `assert` with an owned local as its message; (2) the runner swallows a crashed test binary — no signal, no partial output, just 255. Found because the P0.4 host-contract cells print the observed contract as their message (`assert got === HOST_MOVE_CONTRACT, got`); on JS and on the void native lane the same cells report correctly. Probes `scratchpad/p04/assertmsg/a1..a5`. **Root cause (ASAN): the C codegen of `assert` copied the message bitwise and destroyed it unconditionally while the analyzer never walked the statement, so a message that is a LOCATION (local, arrow parameter, alias) was freed twice — under DRC as well as ORC; the "ORC only, 50%" was macOS malloc's nondeterministic double-free detection. Fix: every assert is lowered to `if (!cond) { msAssertFail(msStringToCString(msg), __FILE__, line); }` before the analyzer, which then owns the message like any call argument (`transform/native/assertLower.ms`; `genAssertStmt` deleted); `msAssertFail` has a test body (`msTestCheckFail` + `msErr`) selected by `MS_TEST_BUILD` and an abort body in `system.h`. Runner: `msProcessExecFile` returns `128 + signal` and `msc test` prints `test binary terminated by signal N`. Pinned by `guard/assertMessageBorrow.ms` (ASAN drc + orc), `guard/testRunnerReportsSignal.ms` (exit 134) and `fixedbugs/bug173AssertMessageLowering.ms` (native + js). Verified on the installed msc: the repro prints `AssertionError: abcc` with rc=1 under ORC, and the aborting fixture exits 134 with the signal named.**
- **OPEN compiler (2026-09-15, PRE-EXISTING) — `Map<K, T | null>.get` fails to instantiate.** `new Map<string, number | null>()` then `m.get("a")` → `Return type mismatch in 'Map_get__string_Maybe_p0': expected Maybe_Maybe_p0, got Maybe_p0` on C; JS runs.
- **OPEN compiler (2026-09-12, PRE-EXISTING) — nested object patterns bind nothing.** `const { a: { x }, s } = o;` → `Undefined variable 'x'` on both backends (`defineForOfPatternBindings` only binds an Identifier alias). Same for a nested pattern in a parameter now that the parameter form desugars to the same decl.
- **CLOSED std (2026-09-13, plan 5, recompiler HASH_B (fix) + HASH_T (tests), landed on TIP_P5) — `Array.map` did not exist** (`Property 'map' does not exist on type 'Array'`, even on `number[]`). The 09-12 note that phase 5 would keep `xs.map(...)` away from the checker was wrong: a JSX `{expr}` child is checked BEFORE the macro runs (that is where auto-call happens), so the missing method fired there too. Fix = portable `map<T, U>(this arr: T[], fn: (x: T, i: number) => U): U[]` beside `sortBy`/`slice` on the C and Erlang lanes, native `#.map(#)` on JS; guard `bug160ArrayMap.ms` native + js.
- **CLOSED compiler (2026-09-13, plan 5, recompiler HASH_B (fix) + HASH_T (tests), landed on TIP_P5) — JSX at a nullable boundary found no converter.** `<Show fallback={<b>no</b>}>` (`fallback?: NeonView | null`) reported `import a converter targeting 'Maybe_fn_fnRefUnknown15'`: `tryConverterAtBoundary` keyed the lookup on the slot type as given, and a nullable value slot is the Maybe struct, whose name no converter declares. Now the payload names the converter and the expansion is re-checked against the full slot, so the fit wraps it like any `T → T | null` flow (same rule as assignment, `isMaybeWrappable`); `Ref | null` stays a Union and was already found. Guard `bug159JsxConverterNullableSlot.ms` (4 cells, 3 red before).
- **CLOSED compiler (2026-09-13, plan 5, recompiler HASH_B (fix) + HASH_T (tests), landed on TIP_P5) — an extension generic was instantiated from the receiver alone.** `map<T, U>(this arr: T[], fn: (x: T, i: number) => U)` died with `in instantiation of 'map<number>': Unresolved type 'U'` (C) or emitted an undeclared `map__number` (top-level call): `checkMemberExpr` instantiated the extension as soon as the receiver bound `T`, before any argument was seen, and `instantiateGenericFunction` only refuses a GenericParam type arg, never a missing name. Now the member read instantiates only when the receiver binds every declared parameter (`bindingsCoverDecl`), and the call instantiates afterwards through `tryInstantiateGenericCallee` seeded with the receiver bindings (arguments first, contextual return only fills gaps — Nim `generateInstance` after the full `sigmatch`). Handoff `extGenericFromArg.ms` (3 cells, 2 red before).
- **CLOSED compiler (2026-09-13, plan 5, same slice) — the untyped `arrayMethodInline` transform fired once `.map` type-checked.** `src/transform/desugar/arrayMethodInline.ms` (2026-02, C only) rewrote `arr.map/filter/reduce(fn)` in a `const`/`return` position into a while loop whose temps were typed `noneType()` and matched the receiver by method NAME only; it was dead while the checker rejected `.map`, and with `Array.map` in std it produced `internal: unresolved type (kind=None) reached codegen` for every used result (an unused `xs.map(f);` called the std instance and worked). Removed from the pipeline (docs/TRANSFORM.md already listed it as "needs type info, marginal benefit"); `filter`/`reduce` remain absent from std (OPEN below).
- **CLOSED compiler (2026-09-13, plan 5, recompiler HASH_B (fix) + HASH_T (tests), landed on TIP_P5) — a row arrow inside a generic component's props literal kept its pre-instantiation type.** `<For each={items()}>{(x: number, i): NeonView => …}</For>` (second parameter unannotated) and every one-parameter `.map` row (padded to two under `Array.map`, then re-checked under `For`) compiled on JS but died on C with `internal: unresolved type (kind=None) reached codegen`; a plain `comp(GRow, { children: (x, i) => … })` reported `Type 'function' is not assignable to type 'function'`. The generic-call reconcile loop (plan 1.0) re-checked the props literal against the instantiated formal with only the literal's own `Sem` cleared, so a nested arrow and its normalized body block kept the first pass's types (field type still carrying the component's `T`). Fix = re-arm nested closures/literals before the reconcile re-check — but only where the RAW field still carried a generic parameter, and descending into a nested ObjectLiteral only where the field type really is a struct. The checker synthesizes its coercions AS object literals — `synthMaybeWrap` (fit.ms:251) builds a Maybe as `{ value, present }`, and a named function in a closure slot becomes `{ fn, env }` — so a blind walk strips their stamp and the re-check wraps a SECOND time (`_lit6_.value = _lit5_`, both `{value,present}`, clang `assigning to 'msClosure' from incompatible type '__anon2__valuex__presentb'`). That regression was caught by the gate, not by the unit tests: `tests/render/flow.test.ms` at its pre-phase-5 revision was green on the installed msc and red on the slice; 25-line repro `scratchpad/p5r/r4.ms` = two calls of one generic, one literal omitting the optional closure field and one supplying it. Both shapes caught by the gate, not by unit tests: the Maybe one as a clang error in Neon's `flow.test.ms` at its pre-phase-5 revision, the closure one as the single extra diagnostic in the full-suite diff (`handoff/explicitTargGenericBody.ms`, `Type '__anon2__fnx__envx' is not assignable to type 'function' for field 'each'`). Handoff `arrowInGenericLiteral.ms` (4 cells) + `bug161ArrowInGenericLiteral.ms` native + js (3 cells, incl. the two-literal runtime case). Neon consequence: React-style `items.map(t => …)` rows now type on C; the row index reads as `Accessor<number>`, so an explicit `i: number` annotation is rejected (write none, or `Accessor<number>`).
- **CLOSED compiler (2026-09-13, plan 5 follow-up) — a `quote {}` block at a typed boundary was never offered to the converter.** `LANG.md` converter rule 1 admits any compile-time-only source, but `checkExprInner` routed `QuoteExpr` through the shared `noneType()` arm with `RegexLiteral`/`JSXText`, so `tryConverterAtBoundary` ran for JSX literals only. `QuoteExpr` now gets the same boundary arm; guard `bug162QuoteConverterBoundary.ms` (declaration, nullable slot, argument). Measured while tracing the converter surface: the trigger is NOT narrower than Nim per fit SITE — the JSX arms run wherever the expression appears and read the position's expected type — it was narrower per SOURCE KIND, and `quote` was the missing kind.
- **OPEN compiler (2026-09-13, PRE-EXISTING — identical on the previous binary and the installed msc) — a `quote {}` that finds no converter raises no checker diagnostic at all.** JSX has `reportUnconsumedJsx`; `quote` has nothing, so `const s: string | null = quote { 1 }` passes the checker and dies in the C backend with `expected expression` (repro `scratchpad/p5quote/q1.ms`). No fixedbugs cell: `compileToCWithStd` stops before the C compiler, so a codegen-stage failure reads as success there — this one needs a guard program, not a helper cell.
- **OPEN compiler (2026-09-13, measured while answering "can std give JS truthiness") — conditions are not a coercion site, and the declaration gate lets C semantics leak instead.** The `as<TargetType>` protocol fires at variable initializer, assignment RHS, argument and return — not at `if`/`while`/ternary conditions — so an `asBoolean` extension cannot give a type JS-style truthiness. Today: `if (n)` with `n: number` passes the checker and dies in clang (`member reference base type 'double' is not a structure or union`); `if (s)` with `s: string` "works" only because a C string is a pointer; and `const b: boolean = n` with `n = 0` prints **`false` on C and `0` on JS** — silent backend divergence, the worst shape. Fix shape recorded in `docs/LANG.md` (§Convention-based dispatch protocols): add the condition position as a coercion site and declare `asBoolean` in std for `number`/`string`/arrays; the declaration gate itself is the parking-lot fitNode row.
- **OPEN compiler (2026-09-13, safety trace of auto-call) — arithmetic on a CALL RESULT typed `Accessor<T>` passes the checker.** `typed(count) * 2` (a function returning `Accessor<number>`) and `(… as Accessor<Accessor<number>>) * 2` are accepted; C dies at clang `invalid operands to binary expression ('msClosure' and 'int')`, JS prints **`NaN` silently**. Control: a plain `const f: () => number` in `f * 2` is refused on both backends (`operator '*' cannot be applied to types 'function' and 'int32'`), so the operator check does not see a distinct over a function as a function. Auto-call is not involved (it only rewrites Identifier/MemberExpr reads); the plan for Phase 3 expected exactly this shape (`createMemo(...) * 2`) to be an error. Real Neon exposure: an inline `createMemo(() => x) * 2`. Nim: a distinct borrows no operator, so the reference refuses it. Probes `scratchpad/p7safe/k1.ms`, `k2.ms`, `s3.ms`.
- **OPEN compiler (2026-09-13, safety trace of auto-call, PRE-EXISTING on C) — `Map<K, Accessor<T>>` leaves the method's `V` unbound.** `new Map<string, Accessor<number>>()` then `m.set("k", …)`: C refuses `in instantiation of 'set<string, <inferring>>': cannot pass value type <inferring> as unknown` even when the argument is a call result (`typed(count)`, no auto-call — `m3.ms`); `Map<string, number>` and `Map<string, () => number>` both run (`m1`, `m2`). On JS the unbound `V` turns into two silent wrongs: a bare `count` argument is auto-called against the unresolved formal and the VALUE is stored (`m4` prints `1` after `setCount(5)`), and a stored accessor read back after narrowing is not auto-called (`m3` prints `[Function (anonymous)]`). Root is the generic binding with a distinct-over-function type argument; auto-call amplifies it because an unresolved formal is not "callable". Probes `scratchpad/p7safe/m1..m4.ms`, `s1.ms`.
- **OPEN compiler (2026-09-14, PRE-EXISTING, found by the valueOf spike) — an extension-method argument is never related to its parameter.** The non-extension argument loop in `checkCallExprInner` reports `Argument type mismatch`; the `extPreResolved` loop only converts, so a wrong argument to an extension method passes the checker (spike 09-13: `Math.max("a", 3)` reached clang; `Math.max` has been generic since recompiler `1876a2a8`, so that exact repro no longer applies). The valueOf protocol inserts at that site and inherits the missing report.
- **OPEN compiler C (2026-09-14, PRE-EXISTING, matrix `scratchpad/vop/mx/h18`) — a generic formal over a distinct instance does not bind from an argument.** `function dbl<T>(a: Accessor<T>): T { return a(); } dbl(count)` → `Argument type mismatch in 'dbl' arg 0: got Accessor<number>, expected Accessor<T>` on both lanes, on the auto-call baseline as well. Neon writes the explicit type argument today.
- **OPEN compiler C (2026-09-14, matrix `h13`) — `===` between two closure values dies at clang.** `const c2 = count; c2 === count` → `invalid operands to binary expression ('msClosure' and 'msClosure')`; JS prints `true`. The checker accepts it (both sides are function-shaped). Surfaced by valueOf because an alias now keeps the accessor; the auto-call baseline compared the two numbers.
- **OPEN compiler (2026-09-14, matrix `v29`) — `typeof` of an accessor is `object` on C and `function` on JS.** With valueOf, `typeof count` inspects the handle (by design); the two backends disagree on the name of a closure's kind.
- **OPEN compiler C (2026-09-14, PRE-EXISTING, matrix `v30`) — an array spread reaches codegen untyped.** `const both = [...list, 4]` with `list: number[]` → `internal: unresolved type (kind=48) reached codegen`; JS prints `4`. Identical on the auto-call baseline, not about accessors.
- **OPEN compiler (2026-09-13, PRE-EXISTING, C only — found while writing the Phase 6 guard) — a module-level `const` whose initializer is a `as` cast is emitted as a local of `<toplevel>`, not as a module global.** Isolation (`scratchpad/p6probe/`): `const thunk = () => cell;` at module scope works (g1 — C emits `msClosure thunk__<module>;` in the GlobalVars section, before the functions), but `const thunk = (() => cell) as (() => int32);` (g3) and `const s = "hi" as string;` (g6) die at clang with `use of undeclared identifier 'thunk_1_'` — the `_1_` suffix is the C **local** conflict counter (`codegen/c/context.ms:229`), and the definition lands at the bottom of the module init instead of the GlobalVars section. Not about `distinct`: g4 (`const count: Acc = mk()`, distinct type, call initializer) runs; not about all casts: g5 (`const n = 1 as int32`) runs because the number folds into a C global initializer. `genTopLevelStmt` routes every Program-level `VariableDecl` to `genGlobalVar`, which always emits the declaration — so the decl is no longer at Program level by the time C runs: a transform hoists the cast and takes the declaration into the toplevel proc with it. JS is green on all six. Loud, not silent. Scaffolding for `bug163` was reshaped to the g4 form rather than fixing this here.
- **OPEN compiler (2026-09-13, introduced by the bug161 fix, diagnostics only) — an erroneous row arrow inside a generic literal reports its diagnostic twice.** `Idx<number>({ each: () => [1, 2], children: (item, i) => needsStr(item) })` prints `got number, expected string` once on the installed msc and twice after the fix: the reconcile re-check re-runs the arrow body and re-reports. Only fires on code that is already rejected, so it never changes what compiles. Not suppressed on purpose — silencing diagnostics during the re-check would hide errors that only the instantiated types can find; the honest fix is de-duplication by (message, line, column) at `addError`, which is wider than this arc.
- **OPEN compiler (2026-09-13, PRE-EXISTING on the installed msc, C only) — a row arrow with NO annotated parameter at all still reaches codegen untyped.** `<For each={items()}>{(x, i): NeonView => …}</For>` → `internal: unresolved type (kind=Inferred) reached codegen in src/macros/ui/flow.ms` (repro `scratchpad/p5/k_for_unannot_both.ms`; identical on the installed msc, so not from this slice). One annotated parameter is enough (`(x: number, i)` works, and so does every `.map` row after phase 5 lowering). Likely the same seam as the closed bug161 but on the path where the FIRST parameter has no annotation to anchor the row type.
- **OPEN compiler (2026-09-13, found by plan 5) — an explicit type argument cannot be an object type.** `comp<{ value: string }>(...)` → `Parse: Unexpected token: :`; use a named interface. Minor, parser-only.
- **OPEN compiler (2026-09-13, PRE-EXISTING on the installed msc, C only) — a generic body that declares a local `T[]` dies when `T` is an alias to an anonymous struct.** `type Q = { x: number }; const qs: Q[] = [{ x: 1 }]; qs.slice(0, 1)` → `internal: unresolved type (kind=48 Inferred) reached codegen in std/core/array/index.cms proc <toplevel>` (repro `scratchpad/p5/c3f_slice_alias.ms`; same for a same-module `mapIt<T, U>` with `U = Q`, and for `xs.map((n: number): Q => …)`). `interface Q { x: number; }` works, and a struct-alias RECEIVER works (`ps.map((p: P): number => p.x)`), so the hole is the clone's local annotation `const out: T[] = []` after `replaceTypeVars` when the concrete type has no nominal name (`injectConcreteTypeSyms` only injects named Struct/Enum/Distinct/GenericInstance/Union). Consequence for Neon: `{items.map(...)}` lowered to For never runs `map`, but the pre-macro check still instantiates it, so an alias-struct item type would trip this on C — write item types as `interface` until fixed.
- **OPEN neon direct (2026-09-13, PRE-EXISTING, found by plan 5) — a region as the sole child of a component under `direct` cannot mount.** `direct(<div><Show when={true}><Show when={on()}><i/></Show></Show></div>)` throws `renderNode cannot mount a region (For/Show/Index) without a parent anchor` (repro `scratchpad/p5/n_nested_show_direct.ms`, js): the inner component child crosses raw to the NeonView converter, whose direct emission mounts via `renderNode` at root position. Tree emission (`element`) handles the same nesting. Phase 5 lowering inherits it: `<Show …>{a && <X/>}</Show>` works under `element`, not under `direct`; the direct test keeps the flat forms only.
- **OPEN std (2026-09-13) — `Array.filter`, `Array.reduce`, `Array.forEach` do not exist** (same `Property 'x' does not exist on type 'Array'`); add them beside `map` as portable generics when a caller needs them.
- **OPEN compiler parser (2026-09-13, found by plan 5) — `out` used as a variable name inside a MACRO body is parsed as the `out` argument marker.** `let out: Node | null = null; … kids.push(out as Node)` in `macro element` → `Parse: Unexpected token: )` and, after a rewrite, `Undefined variable 'as'` + `cannot compile node kind OutExpr at comptime`. The same `const out: T[] = []` compiles fine in a plain function (`std/core/array` `slice`), so the keyword is only greedy in some contexts; Neon renamed the variable (`lowered`). Minimal repro: any macro body with `let out: Node | null = null; if (out !== null) { f(out as Node); }`.
- **CLOSED compiler (2026-09-12, found by plan 4.1, recompiler `eddce0bd` (fix) + `130bf103` (tests), landed on `ac997a5e`) — every `Maybe` over an instance of one generic shared a single wrapper type.** `Pressable`'s `delayLongPress?: Accessor<number> | null` was checked as `Accessor<Style>` once `style?: Accessor<Style> | null` sat in the same interface (`Return type mismatch in '<arrow>': expected Style, got int32`, `setTimeout … got Style`). Root: `maybeCacheKey` keyed the wrapper by `inner.typeName`, which for a generic instance is the bare generic name; `typeKey` had the same hole, so a tuple over two instances hashed to one `msTuple_` name. Fix: `typeKey` renders an instance as `Name<args>` and `maybeCacheKey` keys an instance through it. This is the real cause behind the earlier "cosmetic" `got Maybe_Accessor` row — that row is now moot (the carrier prints `Maybe_gi_…`; still a display nit, not an identity bug). Guards: `handoff/maybeGenericPayload.ms` (3), `fixedbugs/bug156MaybeGenericInstancePayload.ms` (2 cells native+js; probes `scratchpad/p13/m1,m4`).
- **CLOSED compiler (2026-09-12, found by plan 4.1, same slice `eddce0bd`/`130bf103`) — a generic call stored into a nullable slot was instantiated without the slot's payload type, and a distinct instance accepted a differently-typed instance.** `Pressable`'s `delayLongPress={120}` fired the long press at once on C: `accessor(() => 120)` bound `T = int32` from the literal because contextual return binding unified `Acc<T>` against the `Maybe` wrapper rather than its payload; the resulting `Acc<int32>` then flowed into the `Acc<number>` payload because the GenericInstance arm of `isAssignable` compares type arguments covariantly — so the closure returned an int where the C reader loaded a double (`2.12e-314`; js was fine). Fix: `unifyType` peels a Maybe on the concrete side (the mirror of its `Union<T,null>` bridge) and a nominal (distinct-backed) instance requires identical type arguments (`sameType`), so `const i = accessor(() => 1); { a: i }` into `Acc<number>` is now a checker error — annotate `accessor<number>` or write `1.0`, the same rule as `createSignal(0)`. Guards: `handoff/genericReturnIntoMaybe.ms` (2), `fixedbugs/bug157GenericReturnIntoMaybe.ms` (3 cells native+js; probes `scratchpad/p13/n1,n2,n3`).
- **OPEN compiler (2026-09-12, PRE-EXISTING, C only) — a nullable generic-struct field links against a missing hook.** `interface Box<T> { v: T; }` with `a?: Box<number> | null; b?: Box<string> | null;` → `undefined symbol: _Box__stringDestroy` (the `Maybe_gi_Box…` destroy hook calls a `Box<string>` hook nobody emitted); js runs it. Probe `scratchpad/p13/m3_twoMaybeBox.ms`; the checker half (two wrappers) is fixed by the row above, this is the hook-lifting half.
- **CLOSED compiler by peer (2026-09-12, found by the 4.1 gate on `tests/style/theme.test.ms` js, recompiler `3d184031` on `ac997a5e`) — a theme float token baked as `0`.** `createTheme({ o5: 0.5 })` emitted `:root{--o5:0}` because `floatValue(v)` inside a macro returned 0 on the installed binary built from `789941c7`. Root (peer trace): `checkMatchExpr` took the FIRST arm's type as the match type when an expected type was present, so `unboxInt`'s `match` (Int arm then Float arm) truncated the float once `RaiserValue.intVal` became int64; JS stayed 0.5. Fix: always join the arm types. A/B by own builds: `5c21d90a` 0.5, `789941c7` 0, `ac997a5e` 0.5. Still OPEN and pre-existing on every binary: `f * 2.0` inside a macro prints 0 (macro VM picks the float opcode from a static flag; `+` is right, `*` and `/` are wrong) — recorded in the recompiler KNOWN-ISSUES.
- **OPEN compiler diagnostic (2026-09-13, found while building `examples/components/todoList.ms` after phase 2.4) — a distinct-over-function mismatch reads `Type 'function' is not assignable to type 'function' for field 'children'`.** The callback was annotated `(todo: Todo, i: () => int32)` against For's `index: Accessor<number>`; the rejection is right (nominal), but `typeDisplayName` renders the distinct instance as its base kind, so both sides print the same word. Expected: `Accessor<number>` (the declared name) on the formal side. The example now annotates `i: Accessor<number>`.
- **CLOSED compiler (2026-09-15, plan phase 6, recompiler `40c0f712` (fix) + `cc25bd38` (tests), landed on `42101d35`, deployed 12:09) — the source-typed auto-call is gone; a bare read of a distinct thunk now goes through the `valueOf` protocol.** `valueOf(this x: T): U` joins the convention-dispatch family (`as<T>`, `toString`, `getDynamicField`, `toItems`): the checker rewrites the node into `x.valueOf()` flagged `NodeFlag.ProtocolCall` (renamed from `AutoCall`, ordinal 17 kept, single-step) and only ever AT A POSITION THAT ALREADY FAILED — `fitNode` when `!slotTakesValue`, a non-overloaded argument (after `as<T>`, re-checked for assignability before fitting, else the mismatch is reported with the new type), an extension-method argument, an operand exactly where `binaryOperandsFail`/`relationalOperandsFail` says no (compound through `compoundBase`, string concat beside `synthStringify`), for-of before `toItems`, a missing member before the universal `toString`, and `as U`. **Never inside overload resolution** (precedent `as<T>` + converter rule 6; deliberate divergence from Nim, recorded in NIM-REF). The receiver must match by strict name `typeNameOf(src) == ext.receiverTypeName` (precedent `setDynamicField`), after peeling a readonly view and one Ref/Ptr. Removed whole: `autoCallIfAccessor`, `autoCallTarget`, `expectsCallable`, `ctx.autoCallHold` and its three hold sites. Consequences by design: `const d = count` keeps the accessor and `d()` works (the 09-12 row's snapshot rule is dead), `const h = onClick` never runs the handler, `console.log(count)`/`String(count)` print the handle (two sites that accept every type, so there is no error to convert). Scope law: a module only reads bare if it can see `valueOf` (import from the declaring module or a re-exporting hub) — pinned by a cross-module ERROR cell in `src/test/c/protocols.ms`. Guards: `handoff/valueOfProtocol.ms`, `handoff/functionValueMisuse.ms`, `fixedbugs/bug164ValueOfProtocol.ms` (native+js; 163 went to a peer mid-flight), `guard/valueOfProtocolJs.ms`, `protocols.ms` +3. Gate: battery 3701/3701, suite 303 vs base 304 (the delta is one import warning that disappeared), guard ALL GREEN, stage-2, Neon `tests/run.sh` rc=0 including browser 75/75 and `tests/macros/run.sh` rc=0. Supersedes the 2026-09-12 auto-call row above.
- **CLOSED compiler (2026-09-15, same slice) — arithmetic on a CALL RESULT typed `Accessor<T>` is refused** (the 2026-09-13 OPEN row above). `binaryOperandSkip` skipped every GenericInstance and `arithOperandsOk`/`equalityOperandsOk` waved through every Distinct, so `typed(count) * 2` reached clang (`invalid operands ('msClosure' and 'int')`) and printed `NaN` on JS. Fix: `operandShape` (checker/fit.ms) peels the distinct body through `distinctBody` bounded by `PEEL_MAX_DEPTH` (now exported from types.ms) before the operand classes are consulted, and the two Distinct escape clauses are gone. Without it the scope law above could not report anything either: a module that does not import `valueOf` got silence instead of an error. Measured on the installed msc after the deploy (`scratchpad/vop/probe711/`): with `valueOf` declared, `typed(c) * 2` runs and asserts `42` (`msc test callResultArith.ms` → 293 passed); with the declaration removed, `msc test noProtocol.ms` → `operator '*' cannot be applied to types 'Acc2<number>' and 'int32' — declare \`function \`*\`(a: Acc2<number>, b: int32)\``, 1 type error, stopping before codegen.
- **CLOSED compiler (2026-09-15, same slice) — five positions where a function value was accepted and died later now have a TypeScript-shaped diagnostic**, each of which fires `valueOf` first: a function used for truthiness (condition, ternary, `!`, left of `&&`/`||` — "a function is always truthy — call it to test its result", TS2774); unary `-` on a non-numeric operand (TS2362); indexing a function value and a non-number array index (TS2538); spreading a function value; a `switch` case not comparable to the discriminant (TS2678). Measured before the fix (`scratchpad/vop/g2/c1..c4`): the checker accepted all five, C died at clang and JS was silently wrong. Note for the parser: MetaScript has no unary `+`, so only `-` is covered.
  11 `null → Node` sites = the "absent element is a null entry in a parallel `Node[]`" convention (`arrowDefaults`, `typeExprs`,
  `patternDefaults`, `_lastDefaults`, `monomorphize/clone.ms`; Nim uses `nkEmpty`); 2 `Symbol.symbolType` sites (declared `Type`
  in `std/meta/node.ms:171`, stored null by `makeSymbol`; measured `Type | null` → ~66 new errors); 3 `types.ms` sites
  (`createPromise`/`createLockedCell` store a null payload meaning void). The general gate (plan phase 1 step 3) waits on these.

- ~~**OPEN compiler (2026-09-16, found while closing bug 8, PRE-EXISTING on a control binary) — a declaration a macro emits with `fnFlags: "export"` never reaches the export registry.**~~ ✅ **CLOSED 2026-09-17 — NOT a compiler bug: `"export"` is not a fnFlags token anywhere in the checker (recognised: `extern`, `async`, `overload`, `generator`, `template`), so the emitted decl is simply private. A macro exports a declaration by emitting `ExportDecl { exportedDecl: FunctionDecl }` — exactly the shape `src/macros/style/fields.ms` already uses — and that crosses modules: 3-file probe (`mac.ms` → `lib.ms` invokes at module level → `main.ms` imports `styleArea`) prints `84` on the installed msc; the same probe with `fnFlags: "export"` reproduces `has no export`. Residual compiler nit, not filed: an unknown fnFlags token is ignored silently (Nim rejects an unknown pragma).** Original text: Another module importing it gets `has no export 'styleArea'`; identical through a plain `import` and through `globalImports`; use inside the emitting module works. This is the remaining link if the functions generated from `STYLE_TABLE` must be exported out of `src/render/style.ms`; generating them for same-module use is unblocked now.
- **OPEN compiler (2026-09-16, PRE-EXISTING) — a module-level `const` with a mismatched initializer passes the checker.** `const LOCAL: int32 = "not a number";` in the ENTRY module: `msc check` prints `OK no type errors in 48 module(s)`. Inside a `globalImports` module the same line is also OK under `msc check` (47 modules) and the build dies in clang on the mangled C name (`assigning to 'int32_t' (aka 'int') from incompatible type 'msString'` at `BAD__Zprivate…giOms`), so the "swallowed diagnostic" facet is this bug seen late, not a prelude bug. Reported to the peer recompiler session the same day; no repro file filed yet.
- **OPEN compiler (2026-09-17, PRE-EXISTING, found by Lát 0.7 of the one-NeonNode arc) — a call on a non-function value passes the checker.** `const s: string = "lit"; s(1);` and `("lit")(2)` type-check clean: `--target=js` emits the artifact (throws only at runtime), native dies in clang (`called object type 'msString' is not a function or function pointer`). Neon consequence: `ref="lit"` on direct emission used to compile silently on js and die in clang on C (both tiers), so `direct.ms` now routes every ref through `applyRef(node, fn: RefFn)` and the typed parameter produces the checker error the raw call never did (`tests/macros/refLiteral*Rejected.ms`). The hole itself is still open: the checker needs a "not callable" diagnostic at the call site. Repro is the two-line file above; no fixedbugs cell filed yet (recompiler tree held by the bug168 session).
- **OPEN compiler (2026-09-18, found while writing the `{...props}` contract) — an array-pattern destructure over a `Map` for-of is accepted silently and yields the KEY as `<object>`.** `for (const [k, v] of m)` where `m: Map<string, int32>`: the checker reports nothing. If `v` is READ, the failure is a raw clang error with no MetaScript span — `probe/mapiter/destructureOnString.ms` → `error: use of undeclared identifier 'v'` in the emitted C (measured `msc build probe/mapiter/destructureOnString.ms`). If `v` is UNUSED the build is clean and the loop prints the wrong value — `probe/mapiter/destructureSilent.ms` prints `k=[<object>]` where the key is `"ab"` (measured, same command + run). Root direction: `for (const x of map)` rewrites to `map.toItems()` which returns `K[]` (LANG.md:2486-2488), so the element type is a plain `string` and the checker must reject an array pattern on it — a destructure over a non-tuple element has no field to bind. Workaround in use everywhere in Neon: `for (const k of m) { const v = m.get(k); }`.
- **OPEN docs (2026-09-18) — `LANG.md:780` documents `for (const [key, value] of map)` as valid while `LANG.md:2488` defines `Map<K, V>.toItems()` as `K[]`.** The two sections contradict each other and the first one is what a TypeScript reader copies. Decide the direction before touching either: TS semantics (a Map is an iterable of `[K, V]` pairs, so `toItems` should yield tuples and the destructure is correct) or the current model (keys by default, and line 780's example must be deleted). The checker bug above is independent of that decision — an array pattern on a `string` element must be rejected either way.
- **NOTE corpus (2026-09-16) — `405-lockedSharedCounter`, `410-awaitStructSpawnStored`, `419-leakSendMovedArgAsync` are non-deterministic cells.** Across four full corpus runs on two binaries built from one tree they flipped side (red on control in one run, red on the patch in the next) and lane (`[orc]` vs `[drc]` vs `[danger]`), each rerun alone was green, and hung cell processes from earlier days were found still running in the recompiler root. Read them as concurrency flakes, never as a regression signal, until someone owns them.

## §3 — Neon-side / environment — 0 OPEN (the multi-node range row CLOSED 2026-09-19), 4 PARKED by the one-NeonNode arc; `Index` does not grow CLOSED 2026-09-18; direct-emission style CLOSED 2026-09-17; `voidHost` CLOSED 2026-07-27 (late)

- **~~`Index` never mounts a row appended to the list~~ ✅ CLOSED 2026-09-18 (Lát 4c, Neon `8644587`
  fix + `b1cfb19` guard) — the suspected root was WRONG, and `src/core/array.ms` was never touched.**
  Filed by Lát 1.1 as "suspect `indexArray` pushes onto a value-copied array parameter". Measured:
  `indexArray` grows correctly on its own (`probe/l4c/indexAppend.ms` — 1 → 2 → 3 rows). The real
  root is an ALIAS across the producer/consumer boundary: `indexArray` mutates the very array it
  handed out last time (`mapped.push(row)` then `mapped = mapped.slice(0, newLen)`), while
  `mountRegion` (`src/render/host.ms`) kept `current = next`. `probe/l4c/aliasCheck.ms` prints it:
  after one append the array returned by the PREVIOUS call has length 2 for `indexArray` and 1 for
  `mapArray` (which rebuilds `nextMapped` fresh). So `reconcileArrays(host, parent, current, next,
  anchor)` was handed `a === b`, matched every row, and did nothing. Solid has the same producer
  behaviour (`array.ts:243` `return (mapped = mapped.slice(0, len))`) and is safe only because its
  consumer never keeps the memo's array — `insertExpression` holds a normalized DOM-node array. Fix
  is therefore on the consumer, one line: `current = next.slice(0, next.length)`. Guard
  `tests/render/flow.test.ms` "Index grows and shrinks with the list" (append, second append, shrink),
  proven RED on the line before the fix.

- **~~OPEN Neon (2026-09-18, found by Lát 3 of the one-NeonNode arc) — a range of more than one node
  does not survive the reconciler's replace branch.~~ ✅ CLOSED 2026-09-19 (one-NeonNode arc: fix Lát 4b
  `df93941`+`9f23709`+`facb35b`, guard Lát 5 `e3d87ae`).** `reconcileArrays` (`src/render/reconcile.ms`)
  was rewritten on the Svelte model settled below: there is no replace branch, a row that survives is
  never detached, a row not in the host yet is mounted at its final position (`mountAt`), and the
  destination is the start of the row occupying the slot in the NEW order, or the region anchor.
  Measured: the fuzz of this row ported to the `Row` API with FRAGMENT rows of 1–3 nodes between a
  leading sibling and a trailing anchor — 2400/2400 steps, 1301 multi-node rows, 0 lost or misplaced,
  on C and `--target=js` (`msc run probe/l3_rangeFuzz/mainRowApi.ms`; `main.ms` beside it still speaks
  the retired `Range` API and no longer compiles). It is now
  a cell of `tests/render/reconcile.test.ms`, "fragment rows of one to three nodes survive random
  reorder, drop and remount", proven RED by making `moveRow` carry only the first node of a span
  (4 of 6 cells red, this one included) and green on restore. The record of the failure follows.
  `reconcileArrays` (`src/render/reconcile.ms`)
  now runs on `Range {start, end}`; every range operation walks `start → end` by `nextSibling`.
  udomdiff's map-fallback `replaceChild` detaches `a[aStart]` even though the map proves it reappears
  later in `b`, and re-inserts it from the caller's array on a later step. A detached single node is
  still insertable; a detached RANGE is not — `nextSibling(start)` is null, so only the first node
  comes back and the rest are lost. Measured with `probe/l3_rangeFuzz/main.ms` (400 trials × 6 steps,
  ranges of 1–3 nodes): **0 failures with every range `{n, n}`** (2400/2400, so the port is faithful
  for today's rows), and an immediate loss of nodes as soon as a range holds two. Not a regression:
  rows are `{n, n}` until Lát 4b. **Direction settled 2026-09-18 against the Svelte source** (cloned
  to `~/projects/svelte`, `packages/svelte/src/internal/client/dom/blocks/each.js`): `reconcile` there
  NEVER detaches a row that survives — a live row is always `move(effect, next, anchor)`, and only
  rows in `to_destroy` are removed. `move` itself matches this port line for line (next sibling read
  BEFORE the insert, stop at `end`) with ONE difference that is the whole answer: its destination is
  `next.nodes.start` — the start of the row that follows in the NEW order — not `nextSibling` of the
  row that precedes in the OLD tree, which is what udomdiff's ref node is. So 4b should drop the
  replace branch and move to a next-row destination. The measured failure of a naive "move, do not
  remove" (32/2400 even for single-node rows) does NOT contradict this: that variant kept udomdiff's
  old-tree ref node, so it was a hybrid of the two models, not Svelte's.

- **NOT A BUG — deliberate, decided 2026-09-18 after reading both references: `ref` follows REACT,
  not Solid.** `ref` is component/event surface, and the standing rule is reactivity = Solid,
  component/event surface = React Native. React attaches refs innermost-first, after the subtree is
  built: `~/projects/react/packages/react-reconciler/src/ReactFiberCommitWork.js` runs
  `recursivelyTraverseLayoutEffects` (`:682`, `:627`) BEFORE `safelyAttachRef` (`:700`, `:641`).
  Neon does the same on both emissions, and the older cell pinning that a `ref` already sees a bound
  reactive child follows from it. Solid is the one that differs — `dom-expressions`
  (`~/projects/dom-expressions`, `packages/babel-plugin-jsx-dom-expressions/src/dom/element.js`)
  `unshift`s a `use(ref, el)` onto that element's own `exprs` (`:676`, `:694`, `:704`) while
  `transformChildren` `push`es each child's `exprs` afterwards (`:1122`), and attributes are
  transformed before children (`:171` before `:188`). A parent's `ref` therefore runs BEFORE any
  child's `ref`, and before the `insert(...)` that binds a dynamic child. Neon runs React's order:
  `tests/render/ref.test.ms` pins innermost-first, and an older cell pins that
  a `ref` already sees a bound reactive child (`"<p>7</p>"`) — both stay. What all three agree on:
  `ref` fires before the site root is placed (Solid calls `use` inside the IIFE, before
  `return _el$`). Lát 4d only has to keep this order when the two emitters merge into one.
- ~~**OPEN 2026-09-15 — direct emission FREEZES a whole-style call SILENTLY, and rejects the per-field
  reactive styles that tree emission supports.**~~ ✅ **CLOSED 2026-09-17 by Lát 0 of the one-NeonNode
  arc, every table row now a differential cell in `tests/render/direct.test.ms` (47/47 native and
  `--target=js`):** whole-style call → `bindStyleAll` `8ad2bb8` (0.1); object literal → static
  fields once + `bindStyleProp` per reactive field `0dc155e` (0.2); layer array → compile-time merge
  or `layerStyles` `ff0a42e` (0.4); static sheet → `applyStaticStyle`, the CSS-class route `9cce2b6`
  (0.5); a reactive layer is rejected at expansion on BOTH macros `ec2d383` (0.8). The stale docs
  sentence ("same S4 field validation") is corrected in `direct.ms` and RENDER-MODEL.md by 0.10.
  Was: measured on the installed msc (deployed 2026-09-15
  12:09) with Neon at `ee953bc`, every probe in `probe/` (gitignored), tree emission as the oracle:

  | `style=` | tree (`element.ms`) | direct (`direct.ms`) | probe |
  |---|---|---|---|
  | `{s()}`, `s` reads a signal | `padding:10px` → `20px` | **stays `10px`, no diagnostic** — D4 and D3, native and `--target=js` | `styleWholeCall.ms`, `styleWholeCallD3.ms` (a `<Text>` child forces the flat tier) |
  | `{{ padding: w }}`, bare accessor | reactive, `10px` → `20px` | compile error `Argument type mismatch in 'setStyle' arg 1: got __anon1__paddingx, expected Style` | `styleTreeReactive.ms`, `styleBareAccessor.ms` |
  | `{{ padding: w(), margin: 4 }}` | split at COMPILE time: `padding` one effect, `margin` one constant | macro error `a style field cannot call a function … (reactive style fields land in S4)` — stale, S4 landed in `element.ms:330-352` | `styleTreeReactive.ms`, `styleCallField.ms` |
  | a static sheet style | constant, CSS-class route (`cssId` → `setStyleClass`, `dom.ms:174`) | always inline `setStyle` (`applyCss`, `dom.ms:168`) | code reading |

  Cause: `direct.ms` binds `const _s = <expr>` and calls `host.setStyle(_r, _s)` ONCE — D4 wire
  (~352-364) and D3 `emitEl` (~564-581) — with no `isReactiveExpr`/`isAccessorTyped` test, while
  `element.ms:406-414` routes the same whole-style expression to `withDynStyleAll` (one whole-style
  effect) and `:330-352` peels reactive fields into `withDynStyle`. The runtime pieces direct would
  emit already exist (`bindStyleAll` / `bindStyleProp`, `host.ms:126-132`).
  Why nothing caught it: `direct.test.ms` has no cell with a reactive style, so the differential never
  compared one. Same asymmetry as fragments — tree gained S4 and it was never mirrored, and the docs
  claim otherwise: RENDER-MODEL §Selection lists `style={s()}` under "direct — one effect per spot",
  and §Naming says direct has "the same S4 field validation as element.ms".
  Fix direction: port `element.ms`'s three-channel style classification into direct (whole reactive →
  `bindStyleAll`, reactive field → `bindStyleProp`, static → constant + class route, compile-time
  layer merge), differential cells red first. It belongs to the "one NeonNode" merge (the merged macro
  must carry the UNION of both macros' compile-time analyses), but a silent freeze should not wait on
  that arc if it slips.
- **PARKED 2026-09-17 (one-NeonNode arc, outside Lát 0) — `on*` is classified two ways.** On a
  lowercase tag both macros test `startsWith("on")` (`element.ms:424`, `direct.ms:381/429/516/758`);
  a component prop needs `on` + an uppercase letter (`reactive.ms:62`). Code reading, not probed.
  One rule for both when the macros merge (Lát 4).
- **PARKED 2026-09-17 (one-NeonNode arc) — flow lowering does not cover `||`, `??` or
  `.map(namedFn)`.** Only `&&`, the ternary and `.map(arrow)` are lowered (`element.ms:171-188`).
- **~~PARKED 2026-09-17 (one-NeonNode arc) — a fragment inside a prop of a NESTED element is reported
  as "inside an expression".~~ ✅ CLOSED 2026-09-19 (`d9a46c8`): the message and `findFragment` are gone;
  a fragment prop value lowers through the converter (`fragment.test.ms` "a fragment is a fallback").** Code reading: `findFragment` walks every child subtree attrs included
  (`reactive.ms:76`), so a fragment that is a prop VALUE gets the expression-container message.
- **PARKED 2026-09-17 (one-NeonNode arc) — `isAccessorTyped` exists twice (`element.ms`,
  `direct.ms`) and matches neither a type alias of `Accessor<T>` nor `Accessor<T> | null`.** The
  Lát 4 macro merge deletes the copy; the alias and nullable arms are the real gap.
- **PARKED 2026-09-17 (one-NeonNode arc, Lát 0.9 cleanup) — the component-children wrapping block
  exists three times:** `direct.ms` root (~:259) and nested component (~:903), plus `element.ms`.
  A shared helper cannot be written today: outside a macro body a `Node` only exposes
  `childCount`/`childAt` (`reactive.ms:10`). The Lát 4 macro merge deletes the copies.
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

### 2026-09-02 — a named function in a value slot had two representations ✅ MERGED `2b75a240` (recompiler main), DEPLOYED (binary + 2 std number files)

Found probing the `variants` design (a sheet entry with variants = a function-typed field). Six-shape
matrix: C died when the slot was INFERRED (`const a = pick` → raw fn ptr assigned to `msClosure`,
clang error), JS died when the slot was DECLARED (annotation / object field / return type →
`{fn, env}` record emitted at the store, call site calls it bare → `TypeError: not a function`).
Arrow-valued slots and param passing were green on both lanes — the boundary that pinned the trace.

/trace-nim verdict: DIVERGE-INCOMPLETE. The uniform `msClosure` repr is documented
DIVERGE-INTENTIONAL (NIM-REF row 81) and stands; the checker's fn→closure wrap (`fit.ms:786`, the
`nkClosure` analog) simply had two consumers missing: (1) the inferred-decl path never ran fit, so
`checkVariableDecl` now closure-ifies the var type and routes the init through the same `fitNode`
arm; (2) JS codegen had NO `nkClosure` arm at all (Nim jsgen:2971; MS-JS is the `jsNoLambdaLifting`
mode — arrows are native closures), so `emitObjectLiteral` now emits a Closure-flagged literal as
the bare function. Pin `750-fnValueClosureRepr.ms` proven RED both lanes pre-fix. Gates: battery
174/3528, neon C 23/23 + JS 22/22 files, 18/18 shape matrix. Deploy trap hit again: the 10 fresh
main commits had touched `std/core/number/index.{cms,jms}` — binary-only deploy left a std skew
that broke typechecking machine-wide until the two files were synced (deploy-as-a-SET rule).

### 2026-09-02 — one name exported by two modules got two different JS names ✅ COMMITTED `e95bfd1`+`0ca5182` (branch `fix/js-multi-file-overload-names`), DEPLOYED **v0.2.52**

The JS buffer module (`7f69c02`, landed by a parallel session that morning) exports `byteAt`/`byteLength`
— the first time two std modules exported one name on the JS lane. Per-file ESM naming then disagreed
across sides: the declaring module compiles alone and saw a sole function (plain `byteAt`), every
importer saw the cross-module overload set (`byteAt_u0`), and the forced-export pass emitted
`export { byteAt_u0 }` for a function that file never defines — so **every** `msc test --target=js` on
the machine died inside `std/core/string`, including a two-line program in `/tmp`.

Found by printing symbol state at the naming decision (`nativeName`, `overloads`, `modulePath`,
`location`); four earlier verdicts taken from recall were all wrong. Fix: `jsMultiFileName` reads the
collision off the export surface (`modExportKeys`/`modExportVals` — the one table the driver hands
identically to every unit) and derives the slot from unit order, so both sides always agree; a name
only one module exports stays byte-identical. Pinned by corpus `749-crossModuleOverloadNames.ms` on
both backends; battery 3520/3520.

### 2026-08-10 — implicit stringification was planted after the checker, so nothing ever bound it ✅ COMMITTED `350b644`+`d0ce7a3`+`b6bf581`, DEPLOYED **v0.2.43**

Found from a Neon question — "why does `<span>{n().toString()}</span>` need the explicit call?".
The `toString` protocol that `PROTOCOLS.md` listed as DONE had no checker synthesis at all. The
insertion lived in `stringConcatFlatten` (post-checker, C-only) and in `typeCoercion` for
`String(x)`, both carrying a `// Follows reference *.zig` header — ported from the pre-self-hosted
pipeline, where a backend lowering was the right home. The planted `x.toString()` never met the
checker, so it had no `resolvedSym` and no `NF_ExtCall`, and `extensionMethodLower` — which keys
off exactly those — skipped it. C printed it as a struct member call (`a->toString()` → clang
error); JS never ran the pass and fell through to its own `+` coercion, which is right by luck for
a class METHOD and silently `[object Object]` for an extension-declared `toString`. Primitives and
hand-written calls always worked, which is why this survived so long.

Fix follows Nim's phase: `synthStringify` plants the call at the `+`/`+=` site in
`checkExprPass.ms` and CHECKS it, keeping the result only when the trial is diagnostic-free,
string-typed, and bound to a symbol with a real `declNode`. Everything else keeps the builtin path
untouched, so primitives, enums and the numeric-subtree atomicity are byte-identical.
`stringConcatFlatten` needed no edit — a resolved operand is already a string leaf. Template
literals ride the same `+` path.

Two defects in the fix itself were caught by an adversarial matrix, not by the happy path: the
trial `checkExpr` leaked diagnostics for a receiver it then declined, and it accepted a
`toString(radix)` binding and emitted a 0-argument call. Both closed by making "the trial produced
zero diagnostics" the acceptance criterion.

Gates: guard proven RED (13 clang errors) → GREEN drc+orc; battery 3437/3437 (A/B against pristine
HEAD); guard suite ALL GREEN; corpus 714 C≡JS; 12-cell parity matrix C≡JS; Neon 18/18 under the
INSTALLED v0.2.43. Full verdict + Nim citations: recompiler `docs/NIM-REF.md` "Implicit
stringification". Adjacent holes measured and filed in §2, none of them regressions.

Neon follow-up (not done here): `element.ms`/`direct.ms` can now emit `"" + (expr)` for a dynamic
spot, which is what lets JSX drop the explicit `.toString()` on both backends.

### 2026-08-07 (late) — expr-bodied arrow + nested capture: hoisted env decls dropped on non-block bodies ✅ UNCOMMITTED (worktree /tmp/wt-narrow, live tree staged, awaiting approval)

Root was a false invariant: `liftCapturingClosureBody` documents "`body` is guaranteed BlockStmt
via `normalizeArrowBodies`", but the normalizer only wrapped bodies that were THEMSELVES an
arrow/fn-expr (the bug039 curried case). An arrow nested inside any other expression —
`() => call(() => x + 1)` — left the outer arrow expression-bodied; `setupSharedEnv` then pushed
the outer env's decl+init into `state.hoistedEnvDecls`, and `walkLiftBody`'s prepend
(lambdaLifting.ms:1612) silently dropped them because there was no BlockStmt to prepend into.
The inner closure still referenced `_env_<outer>_` → hard C error `use of undeclared identifier`.
`liftClosure`'s own block-wrap (:727) runs after the prepend, so it never rescued the decls.
Fix = one condition in `normalizeArrowBodies`: wrap EVERY non-block arrow body in
`{ return expr; }` (was: only direct arrow/fn-expr bodies). Output-neutral by construction —
both `liftClosure` and `liftNonCapturing` already did the identical wrap downstream; runs before
`detectPass` so detection's node-identity keys are unaffected; C backend only (`lowerLambda` is
gated `!jsBackend` in transform/index.ms:127). Guard `bug095ExprArrowNestedCaptureEnv.ms`
(5 cells; 4 proven RED under pristine v0.2.37 — 5 distinct `_env_…` C errors incl. the
double-nested cell). Gates: bug092 green after the change, bug07* 2819/2819, bug09* green
per-file (⚠ multi-file `msc test` runs only the FIRST file — loop them), self-build 292 modules,
Neon sweep 18/18, probes na_n1/na_b4/nestedArrowEnv2 green. thunkProps 1+3 red at CHECKER stage
under pristine AND fixed — different row (checker fn-repr), untouched. Component arc item 3
unblocked: the flat `componentNode(() => untrack(() => Comp(props)), …)` shape now compiles.

### 2026-08-07 — object spread in object literal: nobody ever lowered it ✅ COMMITTED recompiler `dfd892c`+`d44fc9c`

Root was an ABSENCE, not a defect: parser stores the spread entry as key `"..."` + SpreadExpr,
the checker special-cases the key (skips excess/dup checks — pass-through by design), and no
transform pass ever expanded it, so BOTH codegens emitted it raw — C as a field assignment to
`dotdotdot_` (hard clang error), JS as `{ ...: ...base }` (load-time SyntaxError; worse,
`objectLiteralComplete` had already appended the omitted nullable fields AFTER the spread entry,
so valid syntax would have silently zero-clobbered spread-provided fields on JS). Fix = new
post-check pass `transform/desugar/objectSpreadLower.ms`, both backends, wired after constFold and
BEFORE objectLiteralComplete: stage 1 hoists non-identifier operands to peer const temps
(`walkExpandBlocks` flat splice, evalOnce, stops at fn/block boundaries); stage 2 expands each
spread into explicit `f: op.f` MemberExprs with stamped nodeTypes — the analyzer then sees real
member reads and inserts DRC copies (a codegen-only fix would have skipped increfs on managed
fields = silent double-free). Fields overridden by a later explicit key or later spread are
dropped at expansion (last-wins, never assigned twice — avoids leaking the overwritten managed
value). Semantics decision: spread copies the operand's STATIC type fields — MS structs carry no
absent-vs-null distinction (Nim default-init), so `{...a, ...b}` lets b's null fields override a;
diverges from TS, documented in the pass header + bug094. Convergent with JS reality anyway:
completion fills absent fields with null before any spread could run. Guard bug094 (7 cells:
override, spread-alone, two-spread last-wins, explicit-before-spread, call-operand evalOnce,
argument position, string-field copy-after-mutation) proven RED under the pre-fix binary (8 C
errors, exact `dotdotdot_` shape). Gates: bug07* 2819 == pristine 2819 (the "2817" expectation
was stale), bug09* 295, self-build 292 modules + runs, Neon sweep 18/18. Leftover corner filed in
the struck §2 row: impure operand inside an expr-bodied arrow can't be statement-hoisted — stays
a LOUD C error. Method note: `msc test` with multiple file args silently runs only the FIRST —
the 18-file Neon sweep must loop per file (the "15 files" it prints are std inline-test modules).

### 2026-08-07 — loop + nested-closure snapshot: three stacked defects behind one late decision ✅ worktree /tmp/wt-loopesc, NOT committed

Root: `liftClosure` decided shared-vs-per-closure env AFTER `walkLiftBody`, so `setupSharedEnv`
wired the body's `$up` against the wrong runtime identity — at a loop site `_envP` is the 8-byte
per-closure pair env, cast as the enclosing 16-byte shared env → **OOB read/write at offset 8**
(D1, the r3/alias corruption; the "phantom counter" adjacent heap slot even produced correct-looking
1/2 output once — structural C proof, not program output, was the deciding gate). Stacked on it:
`insideLoop` never reset per function frame → inner closures inside a loop-closure's body forced
onto the snapshot path → wrote private copies (D2 lost update — the ACTUAL killer of the
module-level q3 shape, which has no OOB at all); and the captured cell lived in the closure's
per-CALL shared env → nothing persisted across calls (D3). Fix, all in
`transform/lowering/lambdaLifting.ms`: `createSnapshotPairEnv` pre-walk (pair env from the FULL
capture set — `detectCaptures(raw body) ∪ detection's nested refs`, both computable pre-walk;
fields complete in one `makeInterfaceDeclFromTypes` call, no append machinery), `setupSharedEnv`
takes the pair env and wires `$up`/chain against it, `walkLiftBody` save/restore `insideLoop = 0`
(all five call sites are function-frame boundaries). Semantics verdict: at a loop site the pair
env is the persistent snapshot home (JS-let-per-iteration approximation, consistent with the
direct-capture q2 behavior); chain walks terminate at the pair env; grandparent skip bypassed there
(`noAncestorSkip`). Guard `fixedbugs/bug092` (3 shapes; red on pristine via the bug-#1 gate at
build AND via measured 0/0/NaN runtime values on the bug#1-only intermediate). Gates: 7-shape
matrix green + C structural proof; glob batches 295/295/2817 zero-delta pristine-vs-patched; Neon
sweep +1 (direct.test.ms), 0 regressions. Session traps: the WORKTREE battery graph aborts on 3
pre-existing bug042 'Person' errors under EVERY config (pristine ×3, cache-purged) — it never ran
a single test there, so all verification moved to glob batches + saved differential binaries
(`/tmp/msc-pristine`, `/tmp/msc-patched`); `msc test fixedbugs/index.ms` standalone crashes
identically on pristine (unsupported harness path); the handoff's 4 red Neon tests were
MIS-ATTRIBUTED to this row — they die on the new void-generic-instantiation row (see §2).

### 2026-08-06 (late) — UNKNOWN-BUG Phase 3 batch 4 (FINAL): pendingType() deleted, emission gate ARMED ✅ UNCOMMITTED

The kind-split debt is CLOSED end-to-end (doc §8.4 item 4, all sub-items). (a) Error-scrutiny:
14 post-addError recovery sites (resolvePass any/unresolved-name/cyclic-extends, template
depth/arity, checkExprPass dynamic-field compound-assign + 2 internal ArrayAccess + macro
depth×2 + macro-sentinel×2) → `errorType()`; the SILENT probe paths (line===0) keep Inferred —
flipping those would leak pointer-shaped Error into 0-diagnostic builds (§5 family). Guard
`handoff/b4ErrorRecovery.ms` 4 cells proven red→green; cyclic-extends gained true Nim cascade
suppression (parent-merge skips Error parents silently; was 2 errors, now 1). The enum-member
site (662) is addWarning-only → stays Inferred BY VERDICT (Error would flow into a proceeding
build). Template-depth cell dropped: 100-deep expansion overflows the TEST-RUNNER thread stack
(standalone compile errors cleanly — worker threads have smaller stacks); site still flipped,
battery-covered. Macro cells dropped: checkSource single-module never populates
macroBodyRegistry (the known subset-build no-op) — macro sites battery-covered. (b)
predicateSentinel rides kind=None now; TWO readers existed, not one (flow:906 kind check +
checkExprPass:3284 `isUnresolvedType(typeExtra)` + "asserts:" prefix — the second would have
silently died when isUnresolvedType shrank); proven by half-flip red (3 predicate tests) →
both-flip green. (c) typeofString flag → None (pure rename, producer+caller). (d+e)
`pendingType()` DELETED; `emptyType()` kind default Pending→None after a caller audit found
exactly ONE non-overwriting caller (collectTypeAlias placeholder → now explicit
`inferredType()`, fresh-per-call verified); hidden producer found OUTSIDE the plan:
bridge.ms:3051 test scaffolding `makePrimType(TypeKind.Pending)` → None; promiseLower typeTag
`Void|Pending` arm → Void-only (Inferred already fell to the int tag under B3, battery-green);
isUnresolvedType → Inferred-only; compat gates + 8 leniency cells → inferredType();
substituteType/isPrimitiveKind-list/typeDisplayName/anonFieldKey/unwrapRefNullUnion/
isMaybeWrappable arms dropped; guard cells now compare `TypeKind.Pending` enum directly or
construct adversarially via `createPrimitive`. (f) `gateFlaglessUnknown` ARMED = Nim
ccgtypes else-branch internal error. Population re-measured BEFORE arming: battery 0, Neon
sweep 0, self-build **1** — root: `cond ? m.nodeType.typeChildren : []` (3 sites in
actorLower.ms) kept `Array<Inferred>` on the empty branch; ConditionalExpr with null expected
never re-fit branch literals (Nim fits both to commonType). Fixed narrowly:
`retypeEmptyArrayBranch` — an empty array literal branch adopts the other branch's concrete
array type. Guard fixedbugs bug085, proven red by mutation UNDER THE ARMED SEAM (the mirrored
`cond ? [] : xs` cell is the one that bites; `xs : []` alternate is masked by
conditionalExprLower using the merged type). The 3 DEBT cells (unknownKindReaders §E,
noneKindNoType, b3InferredKind) INVERTED to error cells per their in-file instructions.
Identification method worth keeping: 6 caller-site instruments all missed (the Inferred was
NESTED in a composite reached by getTypeDesc recursion) — lldb breakpoint on the seam +
`bt 20` found genArrayLiteral→genArrayType in one shot. Gates: battery 3428/3428 (−1 =
deleted suggest display cell, accounted), handoff 180/182 (same 2 pre-existing), fixedbugs
glob green (bug085 file 135/135), Neon sweep signal/memo/element/reconcile/counter + counter
example RUN under the fixpoint binary, self-build fixpoint **d3≡d4 at 0 bytes** (d2→d3 =
transition gen, 5.3M drift, same B3 c2 pattern). Binary `msc-d3` kept at recompiler root =
deploy candidate. NOT deployed; installed msc still v0.2.32 pre-B4.

AUDIT PASS (same session, user-requested): full diff re-read hunk-by-hunk (zero stray
instruments; `505-jsonBasics.ms` in the stat is the PARALLEL session's — exclude from commit);
ALL gates re-run from `rm -rf out` clean state (battery 3428, fixedbugs 2813, handoff 180/182
same 2, Neon sweep) and the fixpoint chain REBUILT clean — d3′≡d4′ at 0 bytes again; kept
binary replaced with the clean-built one (2480/93.5M cross-chain byte delta = UUID/codesign
noise, same size). Runtime probes under the armed seam: match expr, Result unwrap, anon
struct, ternary-[] BOTH orientations, predicate boolean, `asserts` — compile AND run correct
on C, and the JS bundle prints the IDENTICAL 6 lines under node (JS bundles don't auto-invoke
main; same pre-B4 — appended call manually). Negative-path UX byte-identical to v0.2.32
(`any` ×2, unresolved ×2 — pre-existing two-pass duplicate; cyclic = 1 with the new
suppression). One NEW pre-existing bug found and filed in §2: predicate-narrowed `unknown`
member access emits `(*void*).field` on C (fails identically under v0.2.32).

AUDIT ROUND 2 (same session, post-deploy, user-requested "cover edge cases"): probing the
armed seam's UX found that LEGAL user shapes with no elem-type donor — `flag ? [] : []`,
`const x = []; x.push(1)`, and match-arm `[]` — died with the LOCATION-LESS internal error
(pre-B4 they compiled silently onto void*-elem arrays, the §4.1 corruption; the gate made
them loud but mislabeled a user inference gap as a compiler bug). Two follow-up fixes,
committed as the 0.2.34 arc: (1) the empty-array refit GENERALIZED to match arms
(checkMatchExpr post-loop walk, expr bodies + block-return tails, donor = the unified
returnType) — the `match (n) { 1 => xs, _ => [] }` shape now compiles and runs on both
truths; (2) a LOCATED checker error "cannot infer the element type of an empty array
literal — annotate the variable type" at unannotated variable decls, scoped SYNTACTICALLY
to initializer kinds ArrayLiteral|ConditionalExpr|MatchExpr to avoid false positives on
transient recursive-return inference. Blast radius measured FIRST: zero unannotated bare
`= []` decls in compiler/std/Neon (all annotated or field-assigns with expected types).
bug085 grew to 5 cells (match donor ok; both-empty and bare-[] assert the user message AND
the absence of "internal:") — red-proof = the recorded pre-fix probe outputs. Gates re-run:
battery 3428, fixpoint e3≡e4 at 0 bytes, Neon sweep 4 files + counter, handoff 180/182
(same 2). One transient signal.test SIGABRT (exit 134) did not reproduce across three
subsequent runs — shared neon/out cache race, noted not filed. Audit round 2 also filed the
indirect interface-extends cycle row in §2 (accepted silently, pre-existing by code path).
⚠ deployed v0.2.33 does NOT contain these two fixes — 0.2.34 redeploy required.

### 2026-08-06 — UNKNOWN-BUG Phase 3 batch 3: all ~182 production pendingType() sites classified ✅ COMMITTED + DEPLOYED

COMMITTED recompiler `0440292..39c006d` (5 commits incl. version bump), neon `d979c38`; DEPLOYED
v0.2.32 via sync-local-binary.sh (post-deploy smoke: Neon signal 295 + counter under installed
msc). `TypeKind.Inferred` landed (enum END, ordinal-stable, fresh-per-call). Worktree
/tmp/wt-phase3 kept, binaries msc-c1..c5 inside. The batch's discovery: sentinel kinds are
a PROTOCOL between ~182 producers and ~100 readers — flipping producers first broke 17 tests
(DU narrowing, extension resolution, LSP completion), reverted; the working order is one central
predicate (`isUnresolvedType` = Pending‖Inferred, 87 reader sites) THEN producers per protocol.
Distribution: inference/accessor-miss/bail-outs → Inferred; post-checker fallbacks + scaffolding
+ macro/module syms → None; deliberate-void* family → Ptr<void> (emission unchanged); matchLower
`$matched` → boolean (real fix). Proofs: battery 3429/3429 every step; inferredReturn tightened
to Inferred-only = measured no-Pending-flows; guard b3InferredKind 8 cells, 3 proven red ×2
mutations + P3 mutation 4 cells red; self-build fixpoint c3≡c4 at 1 byte (c2 = transition gen,
1.29M drift = singleton→fresh identity change, verified converged); fixedbugs glob 2823, handoff
2824, Neon sweep 295+301+counter. B4 debts filed in doc §8.4 item 4: post-addError Error
candidates, predicateSentinel's hand-built Pending marker, typeof enum-flag, Never candidate at
flow 1205/1207, the four intentional Pending pins.

### 2026-08-06 — UNKNOWN-BUG Phase 3 batches 1+2: cancelled→Error, no-type→None ✅ UNCOMMITTED, DEPLOYED

Phase 3 opened (docs/UNKNOWN-BUG.md §8.4). B1: the single cancelled site (checkExprPass:184,
LSP-cancel) → `errorType()` — a cancelled check's type is never read by codegen (§7); NOT
proven-red (needs an LSP cancel context that no fixedbugs harness has), shipped battery-no-regress
only. B2: new `TypeKind.None` for "no type for this node kind", appended at enum END
(ordinal-stable, `getSysType` fresh-per-call like Unknown); consumers written BEFORE producers:
compat gates 282/742/975 keep None lenient (JSX-as-macro-arg must keep matching — scoping waits
for B4), `isPointerShapedForUnknown` None=>false as an EXPLICIT arm (the §5-family trap arm),
`typeDisplayName` "<none>", `getTypeDesc` mirrors the Pending seam (gate + "void*" until Phase 3's
exit criterion), substituteType/isPrimitiveKind passthrough, sumGeneric 1. `isPointerType` (ABI
reader) untouched — None falls to default false, so checker and ABI readers agree by construction.
Producers: the 8 no-type kinds = RegexLiteral|QuoteExpr|JSXText arm (:361) + 5 JSX statement
sites (:371–:393) → `noneType()`. Guard `src/test/handoff/noneKindNoType.ms`, 7 cells, 2 proven
red by targeted mutation (producer revert reddens the symbol-kind cell at :26; None=>true reddens
the pointer-shape cell at :36). Gates: worktree gen chain (installed-copy gen0 → b2 → b3
self-build fixpoint, 291 modules), battery 3429/3429 under BOTH msc-b2 and the installed binary
post-deploy, handoff glob 2824, fixedbugs globs at baseline (294/295/297/295/2812/2192), Neon
core 295 + render/JSX 301 + counter under both binaries. Deployed via sync-local-binary.sh
(binary + std). pendingType() population: 262 → 255 production sites (grep reads 257; 2 are the
guard's own Pending-vs-None cells). Remaining: B3 (~250 inference sites → new `TypeKind.Inferred`,
per-file batches, each site read individually) then B4 (scope compat gates to Inferred, delete
`pendingType()`). Worktree /tmp/wt-phase3 left in place with msc-b2/b3.

### 2026-08-06 — UNKNOWN-BUG Phases 1+2: the kind split ✅ COMMITTED `c525037`+`8e7b31b`+`1b45823`+`2168357`+`a37ef0b` (installed msc still PRE-split; deploy of msc-p4 pending user approval)

The docs/UNKNOWN-BUG.md arc's safe stop point, shipped as one arc because the bootstrap A/B proved
std follows the BINARY (renamed source + installed msc dies at clang). `c525037` = mechanical
rename (52 files, 433±, sole non-rename line = the enum member; TokenKind.Unknown/pendingTypeArg
traps honoured). `8e7b31b` = the payoff: user `unknown` gets fresh end-of-enum `TypeKind.Unknown`
(ordinal-stable, getSysType-fallback fresh-per-call), `TypeFlag.UserUnknown` + `userUnknownType()`
deleted, `isUserUnknown` = kind check, 8 flag readers converted — plus a NINTH reader the doc's §1
list missed: extension receiver match (context.ms:566/568/594) served `this: unknown` receivers
via kind Pending; std's catch-all `hash(this u: unknown)` stopped resolving on Map until converted
(battery caught it — the ONLY Phase 2 fallout). Both-meaning sites gained the Unknown arm
(unwrapRefNullUnion, isMaybeWrappable, substituteType, isPrimitiveKind, typeDisplayName,
compat 281/740/972, fitNode + call-arg cluster). `1b45823` = the Phase-0 DEBT disagreement cells
inverted to assert agreement. Landing probe matrix (7 behaviours × {msc-base, msc-p4} × {C, JS})
proved semantics preserved with two upgrades: `u.foo` now a clean checker error (was clang
`member reference base type 'void'`), and `u + 1` — which compiled and CRASHED AT RUNTIME under
BOTH binaries, pre-existing — closed by `2168357`+`a37ef0b` (bug084, 7 cells, 4 proven red:
allowlist gate, equality/logical/`??`/`=` stay legal). Gates: battery 3429/3429 under
p1/p2/p3(fixpoint)/p4, handoff at baseline (2 pre-existing), bug069 glob 2192 + bug076 glob 301,
Neon 295+294+307+counter, dual-backend probe C==JS. Found + filed while landing: full-fixedbugs
link RED = pre-existing TypeInfo symbol collision (§2 row). Design verdict recorded: MS `unknown`
is a POINTER-shaped top type by row-58 design (Nim tyPointer model), not TS's universal top —
value types need boxing/reinterpret on purpose; `(u as number)` erroring is CORRECT, don't "fix"
it. Keyword-honesty question (keep `unknown` vs a more explicit spelling) left open with the user
— `Ptr<void>` already exists as the explicit raw-pointer spelling.

### 2026-08-06 — unknown enum member escaped the checker ✅ COMMITTED `9950b88` + `61b510d`

`Color.Purple` on an enum without `Purple` type-checked CLEAN and blew up one layer down:
C → clang `use of undeclared identifier 'Color_Purple'`, JS → `ReferenceError` at run time —
wrong layer, mangled name, no source location. Root: `checkMemberExpr`
(`checkExprPass.ms:4326`) computes `memberExists`, uses it ONLY to pick the returned type, then
rewrites the node to a mangled Identifier either way. Isolation matrix: interface field (p2) and
class static (p3) already errored correctly — enum was the only leaking shape.

Nim parity measured by RUNNING nim, not reading it: `tryReadingTypeField` → nil → sem
`Error: undeclared field: 'Purple'`. Verdict SPLIT — the `E.M` → mangled-Identifier rewrite stays
(NIM-REF row 72, DIVERGE-INTENTIONAL, keeps enums out of every codegen backend); the missing
"not found → error" arm is DIVERGE-UNINTENTIONAL. Fix = 3 lines, reusing the struct path's
existing message format.

Extern enums measured too (`extern enum Flags { A, B }` + `Flags.C`): nim rejects an `importc`
enum member that the Nim declaration omits EVEN WHEN the C header defines it — the binding is the
contract. Our new behaviour matches exactly; ecosystem has 0 hand-written `extern enum`
declarations, so nothing broke. Pinned as guard cells 4–5.

Guard bug083 = 5 cells, 2 proven red ("expected an error, compiled clean"). Gates: battery
3428/3428 · self-build 291 modules · corpus leak 70/70 · Neon 4 files (295/294/294/301).

⚠ COORDINATION TRAP (self-inflicted): I wrote my `import "./bug083…"` line into the parallel
session's working-tree copy of `fixedbugs/index.ms` so their next commit wouldn't drop it — they
then `git add`ed that file and committed a dangling import, leaving HEAD `7e80d83` RED for the
fixedbugs suite until `61b510d` landed the file. Never write into a live file another session is
staging; keep the line in the index only.

### 2026-07-31 — JSX-ROADMAP Phase 9 `converter` routine kind ✅ MERGED TO MAIN `9ce47eb` (7 commits, rebased onto 0f0b8de; installed msc NOT yet rebuilt — converter needs a gen-26 deploy before Neon can use it under the installed binary)

Merge maneuver (the "blocked" verdict was stale by one parallel-session commit): live dirt had
shrunk to 7 src files; only checkExprPass+context intersected the branch. Parked EXACTLY those
2 via `git stash push -- <2 files>` → `merge --ff-only` → pop → verified restored content
byte-identical against a pre-merge snapshot (`/tmp/parallel-dirt-snapshot.patch` kept the full
7-file dirt as belt-and-braces). Their hunks were point-insertions ≥15 lines from converter
edits → 3-way pop merged clean. Post-merge gates on 9ce47eb content: c-suite 2787/2787, Neon
core 278 + render 277 + platform 290, all green under the worktree-built msc.

**Audit round (user-requested, pre-commit)**: full patch re-read; expand.ms addKindFields
MacroDecl arm was missing `macroDeclReturnType` → fixed (macro bodies reading MacroDecl nodes
now see the field); `createContext` confirmed the SOLE CheckerContext factory (no LSP null-map
risk); hash.ms doesn't exist (stale memory ref — walkers are visitor/walker, child-only, safe).
Noted, deliberately not expanded: overload NO-MATCH path lacks the JSX explicit-call hint (only
the ambiguous path has it); registry target matching is nominal-simple-name textual (annotation
text vs `typeDisplayName`) — generic/alias-spelled targets won't match, V1 limitation.
**HEAD-crash differential**: `msc test src/index.ms` on PRISTINE d01fb39 dies exit-255 after
exactly 153 ✓ files (last = lsp/format.ms, next = lsp handlers) — identical point with the
converter patch applied (153 = 153, zero delta) and identical under gen-23 AND gen-25 boot
binaries; green at 2c50927+patch. The crash arrived with the wt-u8 landing (or its window) and
is the parallel session's to own — their stash "session-kill delta + never-fix (park for HEAD
re-anchor)" suggests they know. Converter gates that DO hold on the committed tree: c-suite
sibling run 2787/2787 (134 files, 17 converter guards + c/jsx.ms), runtime E2E, Neon sweep
(ran pre-rebase; re-run post-merge). Installed msc was REPLACED mid-session (gen-25, 01:03).

TDD arc, spec = LANG.md "Converter Declarations" (7 rules) + LANG-JSX "Boundary Lowering via
Converter" + JSX-ROADMAP 9.1-9.5. **All gates green in the worktree**: 17 converter guards
(proven red first: 15/17 red under gen-23, staged greens per layer), sibling suite 2787/2787
(134 files incl. c/jsx.ms), battery 3364/3364, Neon sweep clean (core/render/platform globs,
0 fail), runtime E2E `x=7 y=7 sum=14` (annotated-decl + return boundaries, real converter).
Patch: `recompiler/.git/converter-phase9.patch` (404 lines, vendor excluded) + untracked test
`converter-phase9-test-converter.ms` (→ `src/test/c/converter.ms`, + 1 import line in
`src/test/index.ms`).

Implementation shape (what a lander needs):
- **Parse**: `converter` = hard keyword (`std/meta/token.ms`, inserted after `Template` INSIDE
  the isIdentLike range — NOT at enum end, JSX tokens must stay outside that range);
  `parseConverterDecl` → MacroDecl node + `NodeFlag.Converter` (32768) + return annotation in
  `node.typeExpr`; rejects ≠1 param / non-`Node` source / missing return type at parse time.
  MacroDeclData gained `macroDeclReturnType: string` (std/meta/node.ms union + alias + bridge
  round-trip both directions; plain macros now capture their return annotation too).
- **Registry (scope law)**: `registerConverter` in collectPass — 3 ctx maps (converterTargets
  target→name, converterTargetOrigin 0-local/1-import, converterTargetByName name→target for
  the export pipeline); local shadows import, two same-origin pairs = error; export carries
  `ExportedSymInfo.converterTarget`; import side registers under the local alias.
- **Application**: `tryConverterAtBoundary` in checkExprPass JSXElement/JSXFragment branches —
  fires only when `expectedType !== null` (settled) and `jsxMacroArgDepth === 0`; rewrites the
  JSX node IN PLACE into `MacroInvocation(convName, [jsxCopy])` and re-enters `checkExpr`,
  riding the existing eager-expansion + re-check path (rules 2/5/6 come free: re-checked
  against the same expectedType, depth limit bounds chains, overload scoring checks args with
  null expectedType so the converter can NEVER fire during scoring — measured, not assumed).
  Return position and resolved call args already flow expectedType → zero extra wiring.
- **Diagnostics**: unconsumed-JSX message gains an import hint when a settled expected type
  exists; ambiguous-overload site mentions calling the converter explicitly when an arg is JSX.
- **Behavior change (deliberate, spec-conformant)**: `const x: T = <jsx/>` was SILENTLY
  swallowed by the ComptimeNodeAlias branch (annotation ignored, initializer dropped, binary
  built with x dead — measured hole). Now an annotation = settled boundary: converter applies
  or error+hint. Unannotated const keeps the compile-time-Node alias feature (LANG-JSX:
  "no boundary → stays a compile-time Node").

Traps burned into this session:
- **Bootstrap recipe when compiler source references a new std field**: installed msc resolves
  `std/` by argv[0]-walk (`resolveRuntimeDir`) → worktree std is INVISIBLE to it. Break the
  cycle: `cp ~/.metascript/bin/msc wt/msc-boot` (argv[0] now inside the worktree → picks up
  worktree std) → `./msc-boot build src/index.ms --output=./msc` → run everything via `./msc`.
  No install, no parallel-session interference.
- **`msc test src/index.ms` (the "battery") = compiler INLINE tests ONLY** (166 files) — it
  does NOT include src/test/c/*, fixedbugs, handoff, fmt (their hub src/test/index.ms is not
  in src/index.ms's graph). The c/ suite rides sibling-glob runs (`msc test
  src/test/c/<any>.ms` → 134 files). A full-coverage claim needs BOTH runs.
- **c/jsx.ms E2E is bistable**: 3 of 4 tests FAIL standalone (`const x = <a/>` in-function →
  ok=true via the alias path) but PASS in battery-graph runs — same order-dependence class as
  the bug006 trap. compileToC results are process-state-dependent for const-JSX. Not chased.
- vendor/ in a fresh worktree misses submodule content → swap for a symlink to the live
  repo's vendor (excluded from the patch).

**Tooling round (2026-07-31, user asked "syntax/LSP đã solid chưa?") — found a DATA-LOSS bug:**
`msc fmt` printed every MacroDecl as `"macro " + name` with the return annotation DROPPED, so
formatting a converter file silently rewrote `export converter toNum(n: Node): number` into
`export macro toNum(n: Node)` — routine kind AND target type gone (plain macros lost their
`: Node` too; pre-existing since macros never printed returns). Fixed in
`src/compiler/fmt/printer/declarations.ms` (NodeFlag.Converter → keyword, macroDeclReturnType →
annotation); 2 guards in `src/test/c/converter.ms` red-proven under an unfixed build. ✅ LANDED
main `c58af7a` (2 commits on 7dd8993). Trap worth keeping: the first version of the macro guard
asserted `out.contains(": Node")` and passed BOTH ways — the param `n: Node` matched it; a
return-position assertion must anchor on `"): Node"`.

Editor tooling state (measured, NOT all solid):
- vim syntax + vscode tmLanguage: `converter` added (regex-based, effective immediately) —
  PARKED on branch `converter-editor`, NOT merged: the parallel session has those exact files
  dirty (they are mid-regeneration on the nvim tree-sitter grammar).
- tree-sitter: grammar.js rule written (also parked) but **parser.c CANNOT be regenerated** —
  `tree-sitter generate` fails on PRISTINE HEAD with "Non-terminal symbol 'identifier' cannot be
  used as the word token" (grammar.js:99 `word: $ => $.identifier` where identifier is a
  `choice(...)` non-terminal), under BOTH the installed CLI 0.25.8 and the pinned 0.20.8. So
  nvim tree-sitter highlighting cannot learn `converter` until that defect is fixed.
  ⚠ Do NOT add `converter` to `queries/*/highlights.scm` before the parser is regenerated — a
  query naming an unknown anonymous token errors the whole query file and kills highlighting
  for the entire language.
- LSP: there is NO keyword-completion list at all (no keyword path in completion.ms), so
  `converter` is exactly as (un)completable as `macro`/`function` — systemic, not converter-
  specific. Converter symbols are SymbolKind.Macro so they ride the macro symbol path;
  UNMEASURED, and the handler tests that would prove it are inside the pre-existing lsp-handlers
  crash (battery stops after 153 ✓ files). Ties into 9.5.

Remaining Phase 9 scope: LSP parity guard (9.5) — planned with the Neon component arc.
build.ms precedence tier: MEASURED 2026-07-31 — build.ms has NO globalImports field yet
(BuildConfig schema in std/build/index.ms: entry/root/resolve.alias/fmt/cc/package/deps only;
prelude.ms hardcodes the list with "Later: merge with build.ms" ×2; consumers compile.ms:350 +
checkPass.ms:2019 read prelude only) — the converter tier hooks in when that wiring lands
(needs origin=2 so a module import SHADOWS the build.ms inject instead of erroring).
Post-merge closures: C runtime E2E re-verified on main content (`x=7 y=7 sum=14`); JS backend
VERIFIED — converter expands identically (`const x = 7` in the bundle); note `msc build
--target=js` emits main_ without invoking it for ALL programs (plain no-JSX differential),
a pre-existing driver behavior, not the converter's. Docs status flipped 2026-07-31
(LANG.md/LANG-JSX.md/JSX-ROADMAP.md, left uncommitted per repo docs rule). Two Maybe-assign
checker holes + comptime-alias-module link error filed in §2.

### 2026-07-31 — /trace-nim uint8[] widening: receiver dispatch bypassed container invariance ✅ COMMITTED `70a220d`+`f5d32ca`+`66400b3`+`d01fb39` (on `2c50927`) + **DEPLOYED as gen-25** — built in the worktree and synced from THERE, not from the live tree (live working tree carries the parallel session's in-flight enum/checker work; building it would ship their unfinished code, the gen-13 trap). Content diff installed-vs-worktree was exactly the 2 changed files; guard re-verified 283/283 and probes value-correct UNDER the installed binary

**Verdict DIVERGE-UNINTENTIONAL, one root, three §2 rows.** `isReceiverMatch`
(`src/checker/context.ms:590`) unwrapped array receiver/object and compared ELEMENTS with
covariant `isAssignable` — `isAssignable(uint8, number)` = true → a `uint8[]`/`int32[]` receiver
bound `this number[]` externs (8-byte stride on 1/4-byte payloads). Nim cannot have this hole:
the receiver is arg 0 through the same `typeRel`, and seq elements are INVARIANT
(`sigmatch.nim:1502-1516`, element rel < isGeneric ⇒ isNone). MS's own central relation already
enforces exactly this (NIM-REF row 74, `sameElementRepr`, compat.ms:204) — measured contrast:
`const n2: number[] = d` REJECTED ("memory layout differs") while `d.indexOf(20)` bound number[]
silently. The row-74 Nim column names the failure mode verbatim: enforcement is central "so no
site can forget the relation" — this was the forgotten site. Boundary (14 probes,
`/tmp/u8trace`): every method LACKING a matching-repr overload corrupted (indexOf −1, pop 1e-323,
join "1.0153e-320", fill = heap-overflow crash before print, view.slice len-right/contents-0);
every correctly-typed path was already right (push-uint8, indexing, length, literal-init, asBytes
reads). Predictions held: fill, view-slice, and `[10,20,30]` (infers int32[]) → indexOf −1 = the
"number[].indexOf" row's real mechanism (msNumberArrayIndexOf in emitted C, 2 sites).

**Fix (return to Nim, staged):** (A) generic `T[]` surface filled in `std/core/array/index.cms` —
indexOf/includes/count/fill/reverse/shift/concat as MS-level generic fns (slice<T>/sortBy<T>
precedent = Nim strutils pure-loop shape); join/sort deliberately absent → loud "no matching
overload" (Nim: no matching proc; join needs toString<T>, sort needs default compare).
(B) `context.ms:590` gains `if (isReinterpretUnsafe(objT, recvT)) return false;` before element
assignability — single-oracle reuse (canFormAcycle-unification precedent). (C) `runtime/core/
array.h` `msGenericArrayPush`/`msGenericArraySetLen` cap checks gained the bug067 three-clause
flag mask (raw cap compare read STRLIT/ASCII bits as "infinite room" — the bug067 class would
have REOPENED through the generic path the moment narrow arrays routed there). Runtime
prerequisite for Nim's model was ALREADY present: `msArrayPrepareAdd(..., elemSize)` +
`sizeof(p->data[0])` in the generic macros = `prepareSeqAddUninit(..., sizeof(T))`. The BUGS.md
row's proposed fix ("13 msUint8Array* C fns") was a convenience divergence — rejected per the
trace-nim rule; zero new C functions needed.

**Consequences by design:** `b.push(x)` with number-typed x is now a COMPILE ERROR demanding
`as uint8` (Nim `byte(x)` parity) — closes the push facet; `u8.join/sort` = loud error until
someone needs them. Guard `src/test/fixedbugs/bug071ElementNarrowArrayWidening.ms` (**12 tests**:
8 runtime-value + 4 checker-negative/control) proven RED on BOTH halves, by two DIFFERENT
mechanisms — the distinction matters for whoever maintains it. (i) The 8 value tests follow the
BINARY: under installed gen-24 an isolated-dir run gave 6 assert-fails (silent class) + concat =
C-compile fail (ABI class — `msNumberArrayConcat` takes `msNumberArray` BY VALUE, the only loud
member of the 15). (ii) The 4 negative tests use `compileToCWithStd`, i.e. the checker AS A
LIBRARY, so they follow the SOURCE TREE (bug070's rule): red-proved by commenting out the
`isReinterpretUnsafe` line in a worktree — **exactly 2 fail (2780/2782)**, the two `!c.ok` rows,
while both `c.ok` control rows stay green (proving the harness itself is not simply erroring).
They cover the LOUD half the value tests structurally cannot see: `b.push(x)` with a number-typed
arg must ERROR (not silently bind number[]), and `u8.join` must ERROR (no generic form) — with
`push(x as uint8)` and `number[].join` as accept-side controls. Gates (all under wt msc): 14 probes = 11 value-correct + t2/t10 loud +
t13 still rejected; battery 153 files / 3080 tests / 0 fail (this HEAD's graph; live-tree 165-file
counts include the parallel session's extras); js/basic 2779/2779; Neon globs 282+276+290 / 0
fail; string oracle C-half IDENTICAL to expected (byte tier untouched).

**Residue (named, open):** `.rms` raiser prelude did NOT get the new generic fns. ⚠ CORRECTION to
this row's first filing: that is a PRE-EXISTING parity gap, NOT a consequence of this fix —
`std/core/array/index.rms` is 34 lines carrying ONLY push/pop/at/setLength/capacity/splice×2/sortBy,
so `arr.indexOf(x)` at macro time was already an error for EVERY element type (measured, this
session). The file's own header defines the obligation ("Mirrors index.cms minus C-only directives
+ the number[]/string[] specializations"), so Stage A's 7 generic fns are now owed to it. Mutating a LITERAL asBytes view via generic fill/shift writes element-stores in place —
the pre-existing "view mutation writes through" edge (bug067 covered push/prepareAdd, not plain
element assign); unchanged by this work. int32[]-family call sites that silently corrupted now
compile-error — battery/Neon showed ZERO such sites in std/compiler/neon.

**Worktree traps burned:** git worktree materializes submodule `vendor/` as EMPTY dirs — `@compile`
died on psa_util.c; `ln -sfn` into an EXISTING dir silently nests the link inside it (created
`vendor/vendor`, then `runtime/crypto/crypto`) — `rm -rf` the empty tree first, then symlink;
`@compile` bare paths resolve CWD-then-`resolveRuntimeDir()` (walks up from argv0 to the dir
holding `std/core/system/index.ms` — worktree root qualifies once vendor is linked).

### 2026-07-30 (late night) — bug B closed: the checker never looked at closure args ⚠ IN WORKTREE /tmp/wt-fnrepr, NOT in live tree

**Boundary (falsifiable, all measured):** a closure whose signature carries int32 in a slot the
declared type says number, reaching ANY declared fn-type position. Producers of `() => int32`:
unannotated arrows returning int literals (`const g = () => 42` — THE thunkProps3 T1 shape),
generic instantiation from int literals (`mkG(7)`, `createSignal(7)`). Annotated `(): number =>`
arrows are fine — that's why m1-m6/t1/r2/t3 stayed green and the "variable-held" framing was wrong.

**Two stacked roots:**
1. **Arg loop Function carve-out** (checkExprPass.ms:2992-2996): the ENTIRE arg-vs-param check
   was skipped when param OR arg had kind Function — `want(mkN(7))` with `want(s: string)`
   compiled (!), `wantF(f: () => string)` receiving `() => number` compiled AND RAN. Nim has no
   such hole (paramTypesMatch checks every arg; lambdas are sem'd with the formal then still
   relation-checked). Verdict DIVERGE-UNINTENTIONAL.
2. **ABI truth**: closures are raw-copied msClosure; the call site casts `.fn` to the DECLARED
   signature (`((double(*)(void*))f.fn)(f.env)`) — callee returns int32 in eax, caller reads
   xmm0 → 9e-323/2.1e-314 denormals. Emitted-C diff gred vs ggreen pinned it.

**Fix (staged toward Nim, in worktree):** carve-out narrowed — closure VALUES (identifier/call
result) are now checked; literal lambdas (contextual typing) and generic-containing formals stay
skipped (the ec38c20 false-positive family; full Nim parity = own arc). `isFunctionAssignable`
gained a repr gate via new `fnSlotReprMismatch` (peels `X | null` — nullable-ref repr = pointer,
the registry-callback shape `(Node) => RaiserContext|null` vs `(Node) => RaiserContext` must stay
assignable; that FP was hit and fixed). `isReinterpretUnsafe` gained the Function branch (fitNode
sites). Error message extended: "…or function signature repr".

**Crash trap burned (cost 3 builds):** first carve-out version called
`findFirstGenericParamName(paramType)` per arg — that walker has NO cycle guard and macro guards
(bug051/bug055) carry cyclic types (`(n: Node) => Node`, Node self-referential) → silent SIGSEGV
(exit 139, zero output) even in a checks-on build. Swapped to depth-capped `hasGenericParams`.
Rule: never call an uncapped type-walker from a per-arg path.

**Guard:** `src/test/fixedbugs/bug070_closure_sig_repr.ms` — 3 reject (int32-closure at number
slot, closure at string param, wrong fn-vs-fn return) + 3 accept (exact match, nullable-union
callback, literal lambda). ⚠ Red-proof is TREE-TOGGLE, not binary-toggle: the guard exercises the
checker AS A LIBRARY (compileToCWithStd), so red/green follows the SOURCE TREE — 4 reject tests
measured red on the pre-patch tree under installed msc.

**Harness facet (named, unfixed):** compileToCWithStd leaves a generic call's `() => T` return
UNSUBSTITUTED (probe70 ok=true while CLI rejects the same source) — the generic-source variant
can't be guarded through the harness; family of the bug006 standalone/battery divergence row.

**Gates (all under worktree msc, HEAD 675bfab + patch):** battery 3355/3364 where the 9 =
lifecycle phase5/6 reading examples/*.ms that are UNTRACKED in the live repo (absent from any
worktree — copied over, file re-runs 2959/2959; NOT a regression), Neon sweep 16/16 file-by-file,
js/basic 2779/2779, matrix gred/t12/t13 reject + ggreen/p1 accept, thunkProps3 T1/S1 now compile
errors at exactly the two ex-garbage lines. **Files:** src/checker/compat.ms,
src/checker/checkExprPass.ms, src/test/fixedbugs/{bug070_closure_sig_repr,index}.ms.
⚠ Live recompiler tree untouched (parallel session holds checkExprPass.ms edits); staging needs
coordination. Neon-DX consequence to design around in the component arc: `createSignal(7)`
getters are `() => int32` — thunk props typed `() => number` will now ERROR until the ergonomics
arc (contextual generic binding / number literals) is decided.

### 2026-07-30 (unify-std session) — single-source std string LANDED ✅ COMMITTED `ab11745`+`d8fedf5`+`1ef6b0b`

The migration the struck row above blocked is DONE, via the two-tier contract (no compiler
change needed): shared.ms = byte tier (byteLength/At/Slice + NEW byteIndexOf/byteLastIndexOf —
the old byte-indexed indexOf/lastIndexOf renamed) + 15 space-free TS-tier algorithms; offset
tier (length/s[i]/charAt/slice/indexOf/pads/…) stays per-backend kernel (Nim magic model,
traced in ~/projects/nim: strs_v2/jssys kernels + strutils pure loops + when-gated fast paths
that must agree bit-for-bit). Invariant: INSIDE shared.ms every search goes through
byteIndexOf — a bare s.indexOf binds the unit-index kernel and corrupts byte math. Gates:
stage-2 AND stage-3 self-host builds green (the old ex|port symptom dead), battery 3364/3364
under both, js/basic 2778/2778, oracle 45/45 C+JS, 4-way differential (105 rows × 5 string
classes): C ZERO-diff vs old externs, JS diffs = exactly the old jms split/replace/replaceAll
unit/byte-mix garbage now FIXED, new-C vs new-JS byte-identical; Neon 278+277. Deployed as
gen-23 (msc-s3, self-hosted on wired std, v0.2.27).

Same session, both found by em's corpus work: (1) JS self-append alias-unsafety — `s = s + s`
looped forever (msStringAppend re-read the growing array; asBytes on JS returns the storage
itself); fixed mirror-C: length snapshot in append, sameBytes(@emit ===) alias detect + one-time
original-payload snapshot in AppendArr; 627-stringSelfAppend @skip-js REMOVED, both lanes
byte-identical (`d8fedf5`+`1ef6b0b`). (2) duplicate private isSpaceByte (shared.ms + index.jms)
= JS load-time SyntaxError → new §2 flat-scope row above; std-side fix ⚠ UNCOMMITTED:
shared.ms exports isSpaceByte, index.jms imports it (first cross-module import inside the string
prelude — works).

Round 3 (same day, /trace-nim): the flat-scope row itself CLOSED at stage A — see the struck row
in §2 for the full mechanism, the Exported-vs-Imported flag trap, and the stage-B residue.
Deployed as gen-24 (msc-s5, self-hosted incl. the naming change). NIM-REF.md gained the jsgen
mangleName row (working tree — docs never commit per repo rule).

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

- **`imported but never used` is a FALSE POSITIVE for names used only in a MACRO BODY** (2026-09-03,
  the import-hygiene sweep). `src/macros/ui/style.ms` imports `SourceLocation` from `std/meta` and
  uses it only inside the `createStyles` macro body; the warning pass does not read macro bodies, so
  it reports the name dead. Acting on it breaks expansion for every consumer:
  `Macro 'createStyles' body: Unresolved type 'SourceLocation'` + `evaluator unavailable` → 9 red
  files across both lanes, measured. **Never trust the warning in a module that declares a macro** —
  the working rule now is: only remove an import the warning flags in BOTH lanes AND whose module
  declares no macro, then re-sweep. Compiler-side fix would be to walk macro bodies in the same
  aliveness pass.

  **That rule is not sufficient — TYPE-position uses are missed too** (2026-09-07, the barrel
  sweep). `src/render/context.ms` declares no macro, yet the warning flags `Computation`, which is
  used at `context.ms:43` as the annotation of `const scope: Computation = {…}`. Same shape in
  `src/macros/ui/style.ms:153` (`let locs: SourceLocation[]`). So the aliveness pass counts only
  VALUE positions: an import reachable solely through an annotation reads as dead. Removing on the
  warning's word yields an unresolved type, not a cleanup. Until the pass walks type positions as
  well as macro bodies, the warning is advisory only — grep the name before touching the import.

- **fn VALUES don't get arity subsumption — only literals do** (2026-09-03, the event arc).
  msc v0.2.53 pads a LITERAL lambda to its slot's arity (`onClick={() => …}` works), but a 0-arg
  fn passed by NAME (`const inc = () => …; onClick={inc}`) is still a loud
  `Argument type mismatch` — the strict `isFunctionAssignable` relation was kept for values on
  purpose (no conversion exists to materialize; an adapter closure through the lifter is a real
  arc — "Stage 2" in the bug118 design). Workaround, used in `counter.test.ms`/`direct.test.ms`:
  annotate the decl (`const inc: (e: NeonEvent) => void = () => { … }`) so the literal is padded
  at its own check site. TS allows the value form, and RN idiom (`const onPress = …`) hits it —
  promote Stage 2 when the starter components go RN.

- **The type-owner registries are process-global and never reset** (2026-08-17, the TypeInfo arc).
  `recordGlobalTypeOwner` / `recordGlobalTypeShape` (`src/checker/context.ms`) accumulate for the
  life of the PROCESS, so in a test binary they carry entries across independent in-process
  compiles. That leaked once already: the `types.ms` unit cells ("enum emits typedef and defines",
  "interface emits struct") build synthetic types with no `sym` and expect the bare `Color`/`Point`,
  but picked up an owner recorded by an earlier snippet compile and got a qualified name. Shipped
  fix gates the fallback on `g.checkerCtx !== null` — synthetic types stay bare — which is correct
  but indirect. The honest shape is a per-compilation reset (idiom already in the tree:
  `resetGenDestroyHooks()` / `resetGenericTypeInsts()`); do it the next time that code is touched,
  and note that the expectations were NOT edited to accept the new spelling.

- **JSX fragment `<>…</>` is silently dropped by BOTH emissions** (NEW 2026-08-09, found
  auditing D3 solidity before D4): `element(<><p>a</p><p>b</p></>)` AND
  `direct(<>…</>)` both compile clean and mount NOTHING — `probe/fragProbe.ms` prints
  `<root></root>` for both. Parity holds (differential can't catch it) but semantics are
  wrong vs Solid, and there is zero diagnostic. Tree = spec is affected too, so per the
  arc rule the fix goes tree-first through `element.ms` (sacred — needs design + approval):
  either a real fragment branch (multi-root NeonNode) or a loud macro error rejecting
  fragments until then. `direct.ms` mirrors afterward. Not a D4 blocker (template-clone
  operates on elements).
  **2026-09-10: loud rejection LANDED** — `findFragment` (`src/macros/ui/reactive.ms`) walks every child,
  both macros `error("fragments are not supported yet")`; gate `tests/macros/fragmentRejected.ms` proven red
  without the guard. Real fragments = plan phase 7 (flatten in child position, multi-root over `regionNode`).

  **2026-09-13: real fragments LANDED in the TREE emission** (phase 7, tree-first — `direct.ms` still
  rejects and is the remaining half). `tests/render/fragment.test.ms` = 5 cells, green on C and js;
  `tests/macros/fragmentRejected.ms` is gone (its contract is obsolete) and
  `tests/macros/fragmentInExprRejected.ms` replaces it.

  **The `regionNode` route named above was REFUTED by reading Solid.** `insertExpression`
  (`dom-expressions/src/client.js`) flattens nested arrays in `normalizeIncomingArray` and sets
  `dynamic` only when an item is a FUNCTION; a static array takes `appendNodes(parent, array)` — no
  effect, no anchor, no `reconcileArrays`. Routing a static fragment through `regionNode` would apply
  Solid's DYNAMIC branch to a static value: it buys an anchor text node plus an effect, and
  `renderToString` throws on regions, so it would also break SSR. The Nim original is no reference
  here — its `Fragment` (`src/core/component.nim:111`) is dead code, called from nowhere, and
  `render*(container, elementProc: proc(): Element)` is single-root.

  Shipped shape: the macro flattens fragments at COMPILE time (`flattenFragments`, matching
  `normalizeIncomingArray`'s recursion), a root fragment emits `fragmentNode([...])`, and `mountInto`
  splices its children into the parent — Solid's static `appendNodes`. `renderNode` throws on one (it
  must return exactly one host node) exactly as it does for a region.

  `NeonNode` gained `isFragment: boolean`. The first cut inferred the variant instead
  (`tag === ""` with non-empty `children`) and that was the wrong call twice over. It broke a
  degenerate case — `fragmentNode([])` is byte-identical to `text("")`, so a bare `element(<></>)`
  mounted one stray empty text node where Solid mounts none — and, worse, it made fragments the only
  variant in the type with no field of its own, readable solely by elimination, so any future text
  node carrying children would silently become a fragment. Every other variant already declares
  itself (`isDyn`, `region`, `componentFn`, `scope`), and `isDyn` is precedent for a bare boolean, so
  the field IS the house model and the inference was the improvisation. Only `node.ms` builds these
  literals, so the change is 7 literals plus the interface line; the three readers
  (`renderToString`, `renderNode`, `mountInto`) now test the field.

  **2026-09-15: the DIRECT half LANDED — phase 7 closed.** `direct.ms` carries the same
  `kidsOf`/`flattenFragments` pair as `element.ms`, so a fragment child is folded into the parent's
  op sequence at compile time and emits nothing of its own; nested fragments and `<></>` erase the
  same way. Nothing in the runtime moved: flattening happens entirely inside the macro, and a
  component that returns a fragment already mounted correctly through the child seam
  (`renderToHost(_kN, host, _rN)` → `mountInto` → `isFragment`).

  A root fragment is REFUSED at compile time, and that is the design, not a missing feature. Direct
  emission is `renderNode` partially evaluated (RENDER-MODEL §Direct emission), a mount closure IS a
  `NeonView`, and `NeonView` returns exactly one `HostNode` — the same wall `renderNode` hits at run
  time. The macro raises it one phase earlier with the escape hatches named:
  `"a fragment has no single host node to return: wrap the children in one element, or build it with
  element() and mount via renderToHost"`. `Host` has no fragment primitive to return instead
  (`hostTypes.ms` is create/append/insertBefore only — terminal and void have no `DocumentFragment`),
  so inventing one would be a mechanism with no model behind it.

  The blanket `findFragment(node)` guard is gone from `direct.ms`; the narrower stray check it was
  replaced by (`kidsOf` loop, byte-identical to `element.ms`) is pinned by
  `tests/macros/fragmentInExprDirectRejected.ms`, and the root refusal by
  `tests/macros/fragmentDirectRootRejected.ms`. `tests/render/fragment.test.ms` gained 6 cells, five
  of them differential against tree emission (the oracle), covering child flatten, nested flatten,
  empty-fragment erasure, a fragment under a component tag, a reactive spot inside a flattened
  fragment, and a component returning a fragment.

  **✅ CLOSED 2026-09-19 (one-NeonNode arc) — the root fragment, the fragment row, and (a) the
  fragment inside an expression (`d9a46c8` + cells `ea92f08`).** (a): an `&&` or `?:` arm that is a
  fragment lowers to `Show` exactly as an element arm does (`lowerFlowTree` runs before
  `flattenFragments`), a fragment prop value or call argument lowers through the converter, and the
  fragment-specific rejection plus `findFragment` are DELETED — measured with the check off, a
  fragment and an element behave identically in every expression position: both work as a call
  argument, both are rejected by the COMPILER under `??` and in a ternary mixed with a string ("JSX
  fragment must be consumed by a macro", pinned by `tests/macros/fragmentNullishRejected.ms`). Seven
  cells in `tests/render/fragment.test.ms` (&& between siblings, fragment/fragment, fragment/null,
  null/fragment, fragment/element, nested condition + live spot, static condition, `fallback`, call
  argument), RED before the change with the old message; `bash tests/run.sh` rc=0 on all four lanes.
  The first half of this note, as written before (a) landed:
  **the root fragment and the fragment row CLOSED; only (a) below was left, and it was loud.** A NeonNode is `(host, parent, before) => void`, so it may own any number of
  host nodes: a root fragment lowers through the flat tier with every root placed in front of
  `before`, and a region row records the span `place` produced, so a row may be a fragment.
  `tests/macros/fragmentDirectRootRejected.ms` is gone with the refusal. Measured on msc v0.2.55:
  `msc test tests/render/fragment.test.ms` rc=0 on C and `--target=js` ("a top-level fragment mounts
  as siblings under one parent", "a fragment row moves and leaves as one span", "a row that opens
  with a closed region still moves with its span"), plus the fuzz cell named in §3. What follows is
  the 2026-09-15 record; its (b) and its root-fragment case no longer hold.

  Still open, and the honest gap vs Solid — ONE family, every case loud, none silent: a fragment
  only works where a parent is already in hand. (a) Inside an expression container
  (`{cond && <>…</>}`) BOTH macros reject it at compile time. (b) Through `viewOf` — hence as a `For`
  row, since `For` mounts rows with `mountView` — it throws at run time, because a `NeonView` must
  return exactly ONE host node; a root fragment handed to `direct()` is the SAME case, caught at
  compile time instead. All of it is Solid's dynamic-array branch, the one place `regionNode`
  really is the right machinery; closing them means teaching a region that a row may expand to n
  nodes, which is `reconcileArrays` work, not macro work.

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
- **fn-repr diagnostics print `function vs function`** (2026-08-08, component arc): the invariance
  error on e.g. a `() => int32` getter into a `() => number` field reads `Type 'function' is not
  assignable to type 'function'` — correct verdict, useless words. Print the signatures
  (`() => int32` vs `() => number`). QoL only, checker diagnostic formatting; repro = 
  `probe/thunkProps3.ms` S1.
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
