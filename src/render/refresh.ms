import { Host, HostNode, NeonNode } from "./hostTypes";
import { Row, makeRow, mountAt, removeRow, place, needsStartMarker } from "./reconcile";
import { Computation } from "../core/types";
import { createComputation, cleanNode } from "../core/runtime";
import { runWithOwner } from "../core/owner";
import { untrack } from "../core/signal";
import { onCleanup } from "../core/cleanup";

export type SigFn = () => string;

export interface RefreshSummary {
	kept: int32;
	rebuilt: int32;
	remounted: int32;
}

class ComponentSlot<P> {
	body: (props: P) => NeonNode;
	sigFn: SigFn;

	constructor(body: (props: P) => NeonNode, sigFn: SigFn) {
		this.body = body;
		this.sigFn = sigFn;
	}
}

class TemplateSlot<E> {
	fn: (env: E) => NeonNode;
	sigFn: SigFn;

	constructor(fn: (env: E) => NeonNode, sigFn: SigFn) {
		this.fn = fn;
		this.sigFn = sigFn;
	}
}

interface Instance {
	render: () => NeonNode;
	sigFn: SigFn;
	key: string;
	keyFile: string;
	host: Host;
	parent: HostNode;
	anchor: HostNode;
	row: Row;
	owner: Computation;
	sig: string;
}

function noop(): void {}

const compSlots = new Map<string, unknown>();
const tmplSlots = new Map<string, unknown>();
const compInstances = new Map<string, Instance[]>();
const tmplInstances = new Map<string, Instance[]>();
const moduleSigs = new Map<string, string>();

function keyOf(moduleFile: string, id: string): string {
	return moduleFile + "#" + id;
}

function track(instances: Map<string, Instance[]>, inst: Instance): void {
	const list = instances.get(inst.key);
	if (list === undefined) { instances.set(inst.key, [inst]); } else { list.push(inst); }
	runWithOwner(inst.owner, (): number => {
		onCleanup((): void => { untrackInstance(instances, inst); });
		return 0;
	});
}

function untrackInstance(instances: Map<string, Instance[]>, inst: Instance): void {
	const list = instances.get(inst.key);
	if (list === undefined) { return; }
	const at = list.indexOf(inst);
	if (at < 0) { return; }
	list.splice(at, 1);
	if (list.length === 0) { instances.delete(inst.key); }
}

function mountInstance(inst: Instance): void {
	runWithOwner(inst.owner, (): number => untrack((): number => {
		const row = makeRow((host: Host, parent: HostNode, before: HostNode | null): void => {
			inst.render()(host, parent, before);
		});
		inst.row = row;
		mountAt(inst.host, inst.parent, inst.anchor, row);
		return 0;
	}));
}

function rebuild(instances: Map<string, Instance[]>, inst: Instance, sig: string): void {
	removeRow(inst.host, inst.parent, inst.row);
	cleanNode(inst.owner, false);
	track(instances, inst);
	inst.sig = sig;
	mountInstance(inst);
}

function instanceNode(
	instances: Map<string, Instance[]>,
	moduleFile: string,
	key: string,
	render: () => NeonNode,
	sigFn: SigFn,
): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		if (needsStartMarker(parent)) { place(host, parent, host.createText(""), before); }
		const anchor = host.createText("");
		place(host, parent, anchor, before);
		const inst: Instance = {
			render: render,
			sigFn: sigFn,
			key: key,
			keyFile: moduleFile,
			host: host,
			parent: parent,
			anchor: anchor,
			row: makeRow((h: Host, p: HostNode, b: HostNode | null): void => { h.insertBefore(p, anchor, b); }),
			owner: createComputation(noop, false),
			sig: sigFn(),
		};
		track(instances, inst);
		mountInstance(inst);
	};
}

function collect(instances: Map<string, Instance[]>, moduleFile: string): Instance[] {
	const found: Instance[] = [];
	for (const list of instances.values()) {
		for (const inst of list) {
			if (inst.keyFile === moduleFile) { found.push(inst); }
		}
	}
	return found;
}

function patch(instances: Map<string, Instance[]>, found: Instance[], forced: string[]): int32[] {
	let kept = 0 as int32;
	let changed = 0 as int32;
	for (const inst of found) {
		if (inst.owner.disposed) { continue; }
		const sig = inst.sigFn();
		if (sig === inst.sig && forced.indexOf(inst.key) < 0) { kept += 1; continue; }
		rebuild(instances, inst, sig);
		changed += 1;
	}
	return [kept, changed];
}

function patchModule(moduleFile: string, forced: string[]): RefreshSummary {
	const comps = collect(compInstances, moduleFile);
	const tmpls = collect(tmplInstances, moduleFile);
	const boundaries = patch(compInstances, comps, forced);
	const regions = patch(tmplInstances, tmpls, forced);
	return { kept: boundaries[0] + regions[0], rebuilt: regions[1], remounted: boundaries[1] };
}

function componentSlot<P>(key: string, body: (props: P) => NeonNode, sigFn: SigFn): ComponentSlot<P> {
	const found = compSlots.get(key);
	if (found !== undefined) { return found as ComponentSlot<P>; }
	const slot = new ComponentSlot<P>(body, sigFn);
	compSlots.set(key, slot);
	return slot;
}

function templateSlot<E>(key: string, fn: (env: E) => NeonNode, sigFn: SigFn): TemplateSlot<E> {
	const found = tmplSlots.get(key);
	if (found !== undefined) { return found as TemplateSlot<E>; }
	const slot = new TemplateSlot<E>(fn, sigFn);
	tmplSlots.set(key, slot);
	return slot;
}

export function refreshComponent<P>(
	moduleFile: string,
	id: string,
	body: (props: P) => NeonNode,
	sigFn: SigFn,
): void {
	const slot = componentSlot<P>(keyOf(moduleFile, id), body, sigFn);
	slot.body = body;
	slot.sigFn = sigFn;
}

export function refreshComponent0(
	moduleFile: string,
	id: string,
	body: () => NeonNode,
	sigFn: SigFn,
): void {
	refreshComponent<boolean>(moduleFile, id, (unused: boolean): NeonNode => body(), sigFn);
}

export function refreshBoundary<P>(
	moduleFile: string,
	id: string,
	body: (props: P) => NeonNode,
	sigFn: SigFn,
	props: P,
): NeonNode {
	const key = keyOf(moduleFile, id);
	const slot = componentSlot<P>(key, body, sigFn);
	const render = (): NeonNode => slot.body(props);
	return instanceNode(compInstances, moduleFile, key, render, (): string => slot.sigFn());
}

export function refreshBoundary0(
	moduleFile: string,
	id: string,
	body: () => NeonNode,
	sigFn: SigFn,
): NeonNode {
	return refreshBoundary<boolean>(
		moduleFile,
		id,
		(unused: boolean): NeonNode => body(),
		sigFn,
		false,
	);
}

export function refreshTemplate<P, E>(
	moduleFile: string,
	id: string,
	fn: (env: E) => NeonNode,
	sigFn: SigFn,
	setup: (props: P) => E,
): void {
	const slot = templateSlot<E>(keyOf(moduleFile, id), fn, sigFn);
	slot.fn = fn;
	slot.sigFn = sigFn;
}

export function refreshTemplate0<E>(
	moduleFile: string,
	id: string,
	fn: (env: E) => NeonNode,
	sigFn: SigFn,
	setup: () => E,
): void {
	const slot = templateSlot<E>(keyOf(moduleFile, id), fn, sigFn);
	slot.fn = fn;
	slot.sigFn = sigFn;
}

export function refreshRegion<E>(
	moduleFile: string,
	id: string,
	fn: (env: E) => NeonNode,
	sigFn: SigFn,
	env: E,
): NeonNode {
	const key = keyOf(moduleFile, id);
	const slot = templateSlot<E>(key, fn, sigFn);
	const render = (): NeonNode => slot.fn(env);
	return instanceNode(tmplInstances, moduleFile, key, render, (): string => slot.sigFn());
}

export function refreshModule(moduleFile: string): RefreshSummary {
	return patchModule(moduleFile, []);
}

export function refreshModuleEval(
	moduleFile: string,
	moduleSig: string,
	dependents: string[],
): RefreshSummary {
	const previous = moduleSigs.get(moduleFile);
	moduleSigs.set(moduleFile, moduleSig);
	if (previous === undefined || previous !== moduleSig) { return patchModule(moduleFile, []); }
	const forced: string[] = [];
	for (const id of dependents) { forced.push(keyOf(moduleFile, id)); }
	return patchModule(moduleFile, forced);
}

export function refreshReset(): void {
	compSlots.clear();
	tmplSlots.clear();
	compInstances.clear();
	tmplInstances.clear();
	moduleSigs.clear();
}
