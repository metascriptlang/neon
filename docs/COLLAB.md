# Neon Collaboration Model — CRDT + AST + Git

Status: brainstorm consolidated (2026-07-03). Not yet implemented.

## Product Vision Context

Neon is a Figma-like platform with two structural differences:

1. **Design IS code** — the editor produces real, runnable JSX-structured `.ms` files, not a design-only artifact.
2. **Compiler-owned** — built on MetaScript, so drag-and-drop + scripting compose like Unreal/Unity, and the toolchain can rely on the compiler for parsing/printing guarantees no external tool has.

This demands a collaboration model that is Git-like in power but Figma-like in experience: branching, merging, history — with zero Git ceremony visible to designers, while developers still see a normal Git repo.

## Source of Truth: Real `.ms` Files

The truth is **canonically pretty-printed `.ms` source code** stored in a **real Git repository** — not a proprietary scene-graph database (explicitly NOT the Figma model).

- Designers never see Git. Developers `git clone` and get ordinary code.
- One truth, two windows: canvas for designers, files for developers.
- Canonical printer discipline: one semantic unit per line (one prop per line), so text diffs stay meaningful.

## Why Line-Based Merging Is Not Enough

The defining failure case (the "Login button" scenario):

> An drags the Login button from footer to header. Bình recolors the Login button blue. Correct merge: ONE button, in the header, blue.

A line-based merger (Git, and also Manyana's line weave) sees An's drag as "delete 5 lines here, insert 5 lines there" — it cannot know both blocks are the *same button*. Bình's edit lands on the deleted lines. Result: a duplicated button or a meaningless conflict.

```
Line-based merge:                 Tree-based merge:
  header: [Login]                   header: [Login, blue]  ✓
  footer: [Login, blue]             footer: (empty)
  → TWO buttons ✗
```

Move/reorder is the #1 operation in a design tool. **Merging must see moves as moves — that requires operating on the tree, not on lines.**

Key insight: *"truth is text" does not force "merge by text."* Because the compiler round-trips `text ↔ AST` losslessly with a canonical printer, text is the **storage format** while the **merge algebra runs on the AST**. Tools like Mergiraf must *guess* structure via tree-sitter; Neon *knows*, because it owns parser and printer.

## Architecture: Three Layers

```
                (storage: git-friendly, vim-editable)
   .ms file  ────────────────────────────────────────────
      │ parse (compiler)                  ▲ print (canonical)
      ▼                                   │
     AST  ◄── branch merge + realtime sync happen HERE ──►
```

| Layer | Mechanism | Notes |
|---|---|---|
| **Storage / history** | Real Git under the hood: auto-commit checkpoints, branches, full DAG | Hidden from designers; CI/GitHub/PR review work unchanged for devs |
| **Branch merge** | Compiler-owned structural 3-way merge: parse base/left/right → tree merge keyed on stable node identity → canonical print | Deterministic thanks to owned printer + node IDs. NOT a pure CRDT (see caveat) |
| **Live multiplayer** | Semantic op streaming (move, setProp, insertNode) within a shared session; ops apply to the in-memory AST, text re-printed continuously | Figma-style server-authoritative LWW is the proven baseline; full CRDT optional later |
| **Text inside nodes** | Manyana line-weave CRDT for function bodies / expressions / script blocks | This is exactly what line weaves are good at |

### Where Manyana Fits (and Doesn't)

`~/metascript/manyana` — Bram Cohen's weave CRDT for version control (~550 LOC Python, public domain). Merges never fail, always converge regardless of merge order; conflicts presented as "what each side did" rather than ours/theirs blobs.

- ✅ **Use for**: text inside nodes (script bodies, expressions); its conflict-presentation philosophy and safe rebase/squash model applied to Neon's history UX.
- ❌ **Not for**: UI structure. Line weaves treat move as delete+insert → concurrent moves duplicate nodes.
- 🔮 **Future upgrade path**: lift the weave algebra from lines to AST nodes ("node-weave": weave of all nodes ever existed + generation counting + an explicit move op) → true eventual-consistency merging for the whole tree. Feasible, not needed for v1.
- ⚠️ Manyana bakes the diff interpretation into state at commit time — whatever diff/printer we choose must be locked down and heavily tested from day one; changing it later changes the meaning of stored history.

## Seamless UX Mapping

| User sees | Actually is |
|---|---|
| Live cursors, co-editing | op-sync / CRDT session layer |
| "Create draft" | `git branch` (auto-named, auto-created) |
| "Merge into main" + visual review ("An moved the button, Bình recolored it") | compiler AST merge; diff rendered as canvas, never `<<<<<<< HEAD` |
| Auto-saved history, 1-click restore | automatic git commits (checkpoints); no Save button, no staging, no commands |
| Dev: `git clone`, vim, PR | the same repo, the same `.ms` files |

Conflict prompts only when two people touch *the same property of the same node* — and the prompt is visual (two versions side by side, pick one).

## Research Findings (Exa survey, 2026-07)

- **Figma internals**: NOT pure CRDT. Server-authoritative; file = `Map<NodeGUID, Map<Property, Value>>`; conflict resolution = last-writer-wins per property; child ordering via fractional indexing; branching = object-level 3-way merge over stable GUIDs. Lesson: stable node identity + a server makes tree merging dramatically simpler. (figma.com/blog: multiplayer tech, realtime ordered sequences, branching; sujeet.pro case study)
- **Movable tree CRDTs**: Kleppmann et al., "A highly-available move operation for replicated trees" — concurrent moves converge without duplication/cycles. Production implementation: **Loro** (movable tree + fractional index). (loro.dev/blog/movable-tree)
- **Grove** (POPL 2025, Hazel group): version control for ASTs as a CmRDT — all edits commute, conflicts represented in-tree as typed holes, *every editor state typechecks*. The academic gold standard for Neon's "every checkpoint runs" ambition. (hazel.org/papers/grove-popl25.pdf)
- **Mergiraf**: syntax-aware Git merge driver via tree-sitter, 33 languages, growing adoption (LWN 2025-10). Validates the "AST merge on Git" path; Neon does it stronger because the compiler knows the exact grammar and prints canonically.
- **Eg-walker** (Gentle & Kleppmann, EuroSys 2025): event-graph replay for text collab — CRDT-class convergence with OT-class memory. Text-only today; relevant as a future direction for the op-log layer.

## Decisions

### Decided (this round)

1. Truth = canonical `.ms` text in real Git; no scene-graph database.
2. Merge algebra runs on the AST via the compiler; never raw line merge for structure.
3. Manyana scoped to text-inside-nodes + history/conflict-UX philosophy.
4. Git fully hidden from designers; fully normal for developers.

### Open

1. **Node identity placement** (load-bearing, blocks schema design):
   - (a) inline in code — tool-managed `key`, idiomatic per React/JSX precedent;
   - (b) sidecar file mapping structural paths → IDs — clean code, drift risk;
   - (c) pure structural matching — no annotation, heuristic fails on identical siblings.
   - Current lean: structural matching by default, printer injects `key` only where ambiguous.
2. Live-session backend: server-authoritative LWW (Figma-proven, simpler) vs full CRDT op-log (offline/P2P capable). v1 lean: server-authoritative.
3. Node-weave (manyana algebra lifted to nodes) as v2 upgrade for mathematically guaranteed whole-tree convergence.

## Honest Caveat

The branch-merge layer as specified is a *structural 3-way merge* — deterministic and rarely interactive thanks to node identity, but without Manyana's mathematical "merges never fail" guarantee. That guarantee currently covers only the text-inside-node layer. Upgrading the whole tree to that standard is the node-weave path above.
