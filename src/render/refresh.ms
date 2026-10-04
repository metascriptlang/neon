// Neon Refresh — the shared granular-refresh runtime.
// Solid-refresh's model on Neon's row/owner machinery: a dev-only transform
// registers component definitions and JSX template regions under stable ids
// with signature getters, and mounts each instance under its own owner with
// its row span and captured props recorded. A transport (native std/hcr, JS
// import.meta.hot) reports a module update through refreshModule and the same
// decision runs everywhere: a changed template signature rebuilds only that
// region's nodes and effects while the owning component's signals stay alive;
// a changed component signature remounts its boundary, which resets only that
// component's local state. Instances read signatures and code through the
// registry entry, never through captured closures: a native reload forwards
// the registered addresses to the newest generation, and a JS module
// re-evaluation re-runs the registration with fresh ones. Production builds
// never reference this module (the transform emits no calls without
// -d:neonRefresh).

import { Host, HostNode, NeonNode } from "./hostTypes";
import { ComponentFn } from "./node";
import { Row, makeRow, mountAt, removeRow } from "./reconcile";
import { Computation } from "../core/types";
import { createComputation, cleanNode, getOwner } from "../core/runtime";
import { runWithOwner } from "../core/owner";
import { untrack } from "../core/signal";
import { onCleanup } from "../core/cleanup";

export type SigFn = () => string;
export type ErasedTmplFn = (host: Host, parent: HostNode, before: HostNode | null, props: unknown) => void;

export interface RefreshSummary {
	kept: int32;
	rebuilt: int32;
	remounted: int32;
}

interface TmplEntry {
	sigFn: SigFn;
	tmpl: (host: Host, parent: HostNode, before: HostNode | null, props: unknown) => void;
}

interface TmplInstance {
	entry: TmplEntry;
	key: string;
	keyFile: string;
	props: unknown;
	host: Host;
	parent: HostNode;
	anchor: HostNode;
	row: Row;
	owner: Computation;
	parentOwner: Computation | null;
	sig: string;
}
interface CompEntry {
	sigFn: SigFn;
	comp: ComponentFn<unknown>;
}

interface CompInstance {
	entry: CompEntry;
	key: string;
	keyFile: string;
	props: unknown;
	host: Host;
	parent: HostNode;
	anchor: HostNode;
	row: Row;
	owner: Computation;
	parentOwner: Computation | null;
	sig: string;
}

function noop(): void {}

const tmplEntries = new Map<string, TmplEntry>();
const tmplInstances = new Map<string, TmplInstance[]>();
const compEntries = new Map<string, CompEntry>();
const compInstances = new Map<string, CompInstance[]>();

function keyOf(moduleFile: string, id: string): string {
	return moduleFile + "#" + id;
}

function pushTmpl(key: string, inst: TmplInstance): void {
	const list = tmplInstances.get(key);
	if (list === undefined) { tmplInstances.set(key, [inst]); } else { list.push(inst); }
}

function pushComp(key: string, inst: CompInstance): void {
	const list = compInstances.get(key);
	if (list === undefined) { compInstances.set(key, [inst]); } else { list.push(inst); }
}

function dropFromTmpl(list: TmplInstance[], inst: TmplInstance): boolean {
	const at = list.indexOf(inst);
	if (at < 0) { return false; }
	list.splice(at, 1);
	return true;
}

function dropFromComp(list: CompInstance[], inst: CompInstance): boolean {
	const at = list.indexOf(inst);
	if (at < 0) { return false; }
	list.splice(at, 1);
	return true;
}

function freshOwner(parentOwner: Computation | null): Computation {
	if (parentOwner === null) { return createComputation(noop, false); }
	const made = runWithOwner(parentOwner, (): Computation => createComputation(noop, false));
	return made;
}

function mountTmpl(inst: TmplInstance): void {
	runWithOwner(inst.owner, (): number => untrack((): number => {
		const row = makeRow((host: Host, parent: HostNode, before: HostNode | null): void => {
			inst.entry.tmpl(host, parent, before, inst.props);
		});
		inst.row = row;
		mountAt(inst.host, inst.parent, inst.anchor, row);
		return 0;
	}));
}

function mountComp(inst: CompInstance): void {
	runWithOwner(inst.owner, (): number => untrack((): number => {
		const row = makeRow((host: Host, parent: HostNode, before: HostNode | null): void => {
			const node = inst.entry.comp(inst.props);
			node(host, parent, before);
		});
		inst.row = row;
		mountAt(inst.host, inst.parent, inst.anchor, row);
		return 0;
	}));
}

function rebuildTmpl(inst: TmplInstance, sig: string): void {
	removeRow(inst.host, inst.parent, inst.row);
	cleanNode(inst.owner, true);
	inst.owner = freshOwner(inst.parentOwner);
	runWithOwner(inst.owner, (): number => { onCleanup((): void => { dropTmplInstance(inst); }); return 0; });
	pushTmpl(inst.key, inst);
	inst.sig = sig;
	mountTmpl(inst);
}

function rebuildComp(inst: CompInstance, sig: string): void {
	removeRow(inst.host, inst.parent, inst.row);
	cleanNode(inst.owner, true);
	inst.owner = freshOwner(inst.parentOwner);
	runWithOwner(inst.owner, (): number => { onCleanup((): void => { dropCompInstance(inst); }); return 0; });
	pushComp(inst.key, inst);
	inst.sig = sig;
	mountComp(inst);
}

function dropTmplInstance(inst: TmplInstance): void {
	const list = tmplInstances.get(inst.key);
	if (list === undefined) { return; }
	if (dropFromTmpl(list, inst) && list.length === 0) { tmplInstances.delete(inst.key); }
}

function dropCompInstance(inst: CompInstance): void {
	const list = compInstances.get(inst.key);
	if (list === undefined) { return; }
	if (dropFromComp(list, inst) && list.length === 0) { compInstances.delete(inst.key); }
}

export function refreshTemplate(moduleFile: string, id: string, sigFn: SigFn, tmpl: ErasedTmplFn): void {
	const key = keyOf(moduleFile, id);
	const entry = tmplEntries.get(key);
	if (entry === undefined) {
		tmplEntries.set(key, { sigFn: sigFn, tmpl: tmpl });
	} else {
		entry.sigFn = sigFn;
		entry.tmpl = tmpl;
	}
}

export function refreshRegion(moduleFile: string, id: string, props: unknown): NeonNode {
	const key = keyOf(moduleFile, id);
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const entry = tmplEntries.get(key);
		if (entry === undefined) { throw `neon refresh: region ${id} mounted before its registration in ${moduleFile}`; }
		const anchor = host.createText("");
		host.insertBefore(parent, anchor, before);
		const inst: TmplInstance = {
			entry: entry,
			key: key,
			keyFile: moduleFile,
			props: props,
			host: host,
			parent: parent,
			anchor: anchor,
			row: makeRow((h: Host, p: HostNode, b: HostNode | null): void => { h.insertBefore(p, anchor, b); }),
			owner: createComputation(noop, false),
			parentOwner: getOwner(),
			sig: entry.sigFn(),
		};
		runWithOwner(inst.owner, (): number => { onCleanup((): void => { dropTmplInstance(inst); }); return 0; });
		pushTmpl(key, inst);
		mountTmpl(inst);
	};
}

export function refreshComponentDef(moduleFile: string, id: string, sigFn: SigFn, comp: ComponentFn<unknown>): void {
	const key = keyOf(moduleFile, id);
	const entry = compEntries.get(key);
	if (entry === undefined) {
		compEntries.set(key, { sigFn: sigFn, comp: comp });
	} else {
		entry.sigFn = sigFn;
		entry.comp = comp;
	}
}

export function refreshBoundary(moduleFile: string, id: string): (props: unknown) => NeonNode {
	const key = keyOf(moduleFile, id);
	return (props: unknown): NeonNode => {
		return (host: Host, parent: HostNode, before: HostNode | null): void => {
			const entry = compEntries.get(key);
			if (entry === undefined) { throw `neon refresh: boundary ${id} mounted before its registration in ${moduleFile}`; }
			const anchor = host.createText("");
			host.insertBefore(parent, anchor, before);
			const inst: CompInstance = {
				entry: entry,
				key: key,
				keyFile: moduleFile,
				props: props,
				host: host,
				parent: parent,
				anchor: anchor,
				row: makeRow((h: Host, p: HostNode, b: HostNode | null): void => { h.insertBefore(p, anchor, b); }),
				owner: createComputation(noop, false),
				parentOwner: getOwner(),
				sig: entry.sigFn(),
			};
			runWithOwner(inst.owner, (): number => { onCleanup((): void => { dropCompInstance(inst); }); return 0; });
			pushComp(key, inst);
			mountComp(inst);
		};
	};
}

export function refreshModule(moduleFile: string): RefreshSummary {
	let kept = 0 as int32;
	let rebuilt = 0 as int32;
	let remounted = 0 as int32;
	for (const list of tmplInstances.values()) {
		for (let i = list.length - 1; i >= 0; i -= 1) {
			const inst = list[i];
			if (inst.keyFile !== moduleFile) { continue; }
			const sig = inst.entry.sigFn();
			if (sig === inst.sig) { kept += 1; continue; }
			rebuildTmpl(inst, sig);
			rebuilt += 1;
		}
	}
	for (const list of compInstances.values()) {
		for (let i = list.length - 1; i >= 0; i -= 1) {
			const inst = list[i];
			if (inst.keyFile !== moduleFile) { continue; }
			const sig = inst.entry.sigFn();
			if (sig === inst.sig) { kept += 1; continue; }
			rebuildComp(inst, sig);
			remounted += 1;
		}
	}
	return { kept: kept, rebuilt: rebuilt, remounted: remounted };
}

export function refreshReset(): void {
	tmplEntries.clear();
	tmplInstances.clear();
	compEntries.clear();
	compInstances.clear();
}
