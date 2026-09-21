# Neon — cross-platform reactive UI framework in MetaScript

Solid-style fine-grained reactivity, a React Native-style component surface, JSX lowered by compile-time macros into one `NeonNode = (host, parent, before) => void`. C backend for desktop, mobile and terminal; JavaScript backend for the browser. Open source. Neon also dogfoods the compiler: what it cannot express becomes a compiler card, never a workaround.

Workspace rules (toolchain, compiler boundary, arcs and cards, code style) are in `~/metascript/CLAUDE.md` and are not repeated here.

## Where the truth is

| question | file |
|---|---|
| what we build next, in order | `docs/ROADMAP.md` |
| which of Solid's core concepts Neon still owes | `docs/SOLID.md` |
| how JSX becomes mount code: tiers, lifecycle | `docs/RENDER-MODEL.md` |
| who paints on each platform (Neon × Void × host) | `docs/RENDER-LAYERS.md` |
| style, variants, theme | `docs/STYLE.md` |
| module map against the original Nim Neon, history | `docs/PORT-STATUS.md`, `docs/nim.md`; the original source is `~/projects/neon` |
| open bugs | `BUGS.md` for the framework; a compiler bug is a card in `~/metascript/.inbox/compiler/` |
| project generator, collaboration model | `docs/PROJECT-GENERATOR.md`, `docs/COLLAB.md` |
| the language | `~/metascript/recompiler/docs/`: `LANG.md`, `LANG-METAPROGRAMMING.md`, `LANG-JSX.md`, `PROTOCOLS.md` |

## Layout

- `src/core/` — the reactive runtime: signal, effect, memo, owner, cleanup, runtime, array.
- `src/render/` — renderer-agnostic: `hostTypes.ms` (the `Host` contract and `NeonNode`), `node.ms` (hand-written builders), `bind.ms` (one effect per dynamic spot), `reconcile.ms`, `component.ms`, `context.ms`, `template.ms`, `style.ms` / `css.ms` / `sheet.ms`, `ssr.ms`, `host.ms` (render + the mock host).
- `src/macros/ui/` — `element.ms` (JSX → NeonNode), `flow.ms` (`Show` / `For`), `reactive.ms`, `style.ms` (`createStyles`), `theme.ms`. `src/converters.ms` is the JSX converter every consumer names in `globalImports`.
- `src/components/primitives.ms` — `View`, `Text`, `TextInput`, `Pressable`.
- `src/platform/` — `browser/dom.ms` (JS), `terminal/`, `void/host.ms` (Void scene graph + yoga). `deps/yoga` is a symlink into `~/metascript/yoga`. iOS and Android hosts are not written; nothing in the compiler blocks them.
- `tests/` mirrors `src/`: `core/`, `render/`, `style/`, `platform/`, plus `macros/` (programs the checker must reject), `apps/`, and `browser/` (real Chrome).

Platform and backend are `when` blocks: `when (macos) { @passL("-framework Metal"); }`, `when (js) { … }`. A branch not taken is never type-checked, so it may call APIs the other target lacks. One backend-agnostic extern surface with the directives gated around it is the shape to copy (`~/metascript/void/src/sokol/gpu.ms`). Flags: `msc --help-defines`.

## Working method

- TDD in this order: make it visible, make it right, make it solid. No code without a test that will show it working; a problem that cannot be seen yet gets made visible first.
- The smallest increment that produces something runnable beats a large unfinished one.
- A user program that does not build is a finding about the framework: reduce it, probe around it, fix Neon; do not fix their code to get past it.
- Macro output is inspected through a test, not a CLI: mount on `mockHost()` and assert on `mockToString` (`tests/render/emit.test.ms`).

## Contracts that need a yes before they change

| file | what breaks |
|---|---|
| `src/core/signal.ms` | every reactive consumer |
| `src/render/hostTypes.ms`, `src/render/node.ms` | every host and every renderer |
| `src/macros/ui/element.ms` | the JSX surface; `tests/render/element.test.ms` and `tests/macros/` hold it |

Anything under `src/platform/` is proven on its own host; examples and docs are free to change.

## Commands

```bash
msc test tests/core/signal.test.ms           # one file, native; add --target=js for the JS lane
bash tests/macros/run.sh                     # the rejection programs
bash tests/run.sh                            # the full gate: macros, apps, every file native, then JS, then Chrome
msc run examples/counter.ms
```

No `rm -rf out`: the object cache is fingerprint-keyed and correct; wiping it makes every suite cold for minutes. Wait while machine load exceeds the core count instead of building under it.

## Git

Neon follows the arc model of `~/.claude/CLAUDE.md` and lands with the plain-git recipe of `~/metascript/CLAUDE.md` §Arcs. What only neon adds:

- `claude --worktree <name>` from this checkout creates or re-enters `../neon-wt-<name>` on `wt/<name>` with the `deps/yoga` symlink a worktree needs (`tools/worktreeHook.sh`, the WorktreeCreate hook). Removing it through Claude runs the WorktreeRemove hook, which refuses a worktree holding a dirty or untracked file, an ignored file outside `out/` and `deps/` (a probe), or a commit missing from `main`. By hand: `git worktree add -b wt/<name> ../neon-wt-<name> main`, then `mkdir deps && ln -s ../../yoga/deps/yoga deps/yoga`; `unlink deps/yoga` before `git worktree remove`.
- **The gate is `bash tests/run.sh`, read by its exit code.** A commit runs the test files of the module it touches plus their importers; the full gate runs before a land that changes `src/` or a shared contract. One `msc` per directory at a time.
- The SessionStart hook prints the card of the `wt/<name>` branch a session starts on and counts the notes in `~/metascript/.inbox/neon/`: notes from other repos about fixes that landed and sites to unpark. Read them first.
