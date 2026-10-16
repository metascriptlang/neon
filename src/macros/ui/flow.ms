// Control flow — For / ForKeyedBy / ForUnkeyed / Repeat / Show. Each returns a region NeonNode;
// the engines in core/array.ms and the host reconciler do the work. A row is described here and
// mounted by the reconciler at its final position, so nothing below touches the host.

import { mapArray, mapArrayKeyedBy, mapArrayByPosition, repeat } from "../../core/array";
import { createMemo } from "../../core/memo";
import { Accessor, Signal, accessor } from "../../core/signal";
import { createErrorBoundary, routeThrown } from "../../core/boundary";
import { createOwner, getOwner, flush, disposeChildren } from "../../core/runtime";
import { onCleanup } from "../../core/cleanup";
import { runWithOwner } from "../../core/owner";
import { Computation, NotReadyError, ContextEntry } from "../../core/types";
import { isServer } from "../../render/environment";
import { serverCaught } from "../../render/ssr";
import { NeonNode, regionNode } from "../../render/node";
import { Host, HostNode } from "../../render/hostTypes";
import { Row, makeRow, mountAt, removeRow } from "../../render/reconcile";
import { List } from "../../core/list";
import { listRegion } from "../../render/listRegion";

function fallbackRow(fb: NeonNode | null): (() => Row) | null {
	if (fb === null) { return null; }
	const view = fb as NeonNode;
	return (): Row => makeRow(view);
}

function indexRead(declared: boolean | null): boolean {
	return declared === null ? true : (declared as boolean);
}

export function For<T>(props: {
	each: Accessor<T[]>;
	children: (item: T, index: Accessor<number>) => NeonNode;
	fallback?: NeonNode | null;
	usesIndex?: boolean | null;
}): NeonNode {
	return regionNode((h) => mapArray<T, Row>(
		props.each,
		(item: T, index: Accessor<number>): Row => makeRow(props.children(item, index)),
		fallbackRow(props.fallback),
		indexRead(props.usesIndex),
	));
}

export function ForKeyedBy<T, K>(props: {
	each: Accessor<T[]>;
	keyed: (item: T) => K;
	children: (item: Accessor<T>, index: Accessor<number>) => NeonNode;
	fallback?: NeonNode | null;
	usesIndex?: boolean | null;
}): NeonNode {
	return regionNode((h) => mapArrayKeyedBy<T, K, Row>(
		props.each,
		props.keyed,
		(item: Accessor<T>, index: Accessor<number>): Row => makeRow(props.children(item, index)),
		fallbackRow(props.fallback),
		indexRead(props.usesIndex),
	));
}

export function ForUnkeyed<T>(props: {
	each: Accessor<T[]>;
	children: (item: Accessor<T>, index: number) => NeonNode;
	fallback?: NeonNode | null;
}): NeonNode {
	return regionNode((h) => mapArrayByPosition<T, Row>(
		props.each,
		(item: Accessor<T>, index: number): Row => makeRow(props.children(item, index)),
		fallbackRow(props.fallback),
	));
}

export function Repeat(props: {
	count: Accessor<number>;
	from?: Accessor<number> | null;
	fallback?: NeonNode | null;
	children: (index: number) => NeonNode;
}): NeonNode {
	return regionNode((h) => repeat<Row>(
		props.count,
		(index: number): Row => makeRow(props.children(index)),
		props.from === null ? null : (props.from as () => number),
		fallbackRow(props.fallback),
	));
}

export function ForList<T>(props: {
	each: List<T>;
	children: (item: Accessor<T>) => NeonNode;
	keyed?: ((item: T) => number) | null;
}): NeonNode {
	return listRegion<T>(props.each, props.children, props.keyed);
}

class MountedState {
	failed: boolean = false;
	contentFailed: boolean = false;
	scope: Computation | null = null;
}

function mountGuarded(mount: () => void, state: MountedState): boolean {
	try {
		mount();
		return true;
	} catch (e) {
		if (e instanceof NotReadyError) { throw e; }
		routeThrown(e);
		state.failed = true;
		return false;
	}
}

function mountedUnder(children: NeonNode, context: ContextEntry | null, state: MountedState): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = createOwner();
		scope.context = context;
		state.scope = scope;
		runWithOwner(scope, (): number => {
			if (!mountGuarded((): void => { children(host, parent, before); }, state)) { state.contentFailed = true; }
			return 0;
		});
	};
}

type ErroredFallback = (err: Accessor<Error>, reset: () => void) => NeonNode;

function errorRows(host: Host, children: NeonNode, fallbackOf: ErroredFallback, failure: Signal<Error | null>, state: MountedState, server: boolean): Accessor<Row[]> {
	let content: NeonNode | null = null;
	let fallback: NeonNode | null = null;
	let contentRow: Row | null = null;
	const home = getOwner();
	const holder = host.createElement("view");
	onCleanup((): void => { host.release(holder); });
	const showsContent = createErrorBoundary<boolean>(
		(): boolean => {
			const failed = failure.get();
			if (failed !== null) { throw failed; }
			if (content === null) { content = mountedUnder(children, (getOwner() as Computation).context, state); }
			return true;
		},
		(err: Accessor<Error>, reset: () => void): boolean => {
			const caught = err();
			failure.set(caught);
			const shown = server ? serverCaught(caught) : err;
			fallback = (host: Host, parent: HostNode, before: HostNode | null): void => {
				mountGuarded((): void => {
					fallbackOf(shown, (): void => { flush((): number => { failure.set(null); reset(); return 0; }); })(host, parent, before);
				}, state);
			};
			return false;
		},
	);
	return createMemo<Row[]>(() => {
		if (showsContent()) {
			if (contentRow === null) {
				const row = runWithOwner(home, (): Row => makeRow(content as NeonNode));
				row.keep = server ? null : holder;
				contentRow = row;
			}
			return [contentRow as Row];
		}
		if (server || state.contentFailed) {
			if (contentRow !== null) { (contentRow as Row).keep = null; }
			contentRow = null;
			state.contentFailed = false;
			if (state.scope !== null) { disposeChildren(state.scope as Computation, true); }
		}
		return [makeRow(fallback as NeonNode)];
	});
}

function settledOnServer(rows: Accessor<Row[]>, state: MountedState): Accessor<Row[]> {
	const settled = makeRow((host: Host, parent: HostNode, before: HostNode | null): void => {
		const first = rows()[0];
		mountAt(host, parent, before, first);
		if (!state.failed) { return; }
		flush();
		removeRow(host, parent, first);
		mountAt(host, parent, before, rows()[0]);
	});
	return accessor((): Row[] => [settled]);
}

export function Errored(props: {
	children: NeonNode;
	fallback: (err: Accessor<Error>, reset: () => void) => NeonNode;
}): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const failure = new Signal<Error | null>(null, null, true);
		const state = new MountedState();
		const server = isServer();
		regionNode((h) => {
			const rows = errorRows(h, props.children, props.fallback, failure, state, server);
			return server ? settledOnServer(rows, state) : rows;
		})(host, parent, before);
		if (!server && state.failed) { flush(); }
	};
}

function shownRows(on: boolean, children: NeonNode, fallback: NeonNode | null): Row[] {
	if (on) { return [makeRow(children)]; }
	if (fallback !== null) { return [makeRow(fallback as NeonNode)]; }
	return [] as Row[];
}

// Conditional: children rebuild only when the condition's truthiness flips (equals memo).
export function Show(props: {
	when: Accessor<boolean>;
	children: NeonNode;
	fallback?: NeonNode | null;
}): NeonNode {
	return regionNode((h) => {
		const cond = createMemo<boolean>(() => props.when());
		return createMemo<Row[]>(() => shownRows(cond(), props.children, props.fallback));
	});
}

export function ShowKeyed(props: {
	when: Accessor<boolean>;
	children: NeonNode;
	fallback?: NeonNode | null;
}): NeonNode {
	return regionNode((h) => createMemo<Row[]>(() => shownRows(props.when(), props.children, props.fallback)));
}

export function ShowWith<T>(props: {
	when: Accessor<boolean>;
	value: Accessor<T>;
	children: (value: Accessor<T>) => NeonNode;
	fallback?: NeonNode | null;
}): NeonNode {
	const narrowed = accessor((): T => {
		if (!props.when()) { throw new Error("<Show>: the narrowed value was read while its condition is false"); }
		return props.value();
	});
	return Show({
		when: props.when,
		children: (host: Host, parent: HostNode, before: HostNode | null): void => { props.children(narrowed)(host, parent, before); },
		fallback: props.fallback,
	});
}

export function ShowKeyedWith<T>(props: {
	when: Accessor<boolean>;
	value: Accessor<T>;
	children: (value: T) => NeonNode;
	fallback?: NeonNode | null;
}): NeonNode {
	return ShowKeyed({
		when: props.when,
		children: (host: Host, parent: HostNode, before: HostNode | null): void => { props.children(props.value())(host, parent, before); },
		fallback: props.fallback,
	});
}

export function showWhen<M>(source: () => M, use: (value: Accessor<M>) => NeonNode): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		use(createMemo<M>((prev: M | null): M => source()))(host, parent, before);
	};
}
