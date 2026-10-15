// Control flow — For / ForKeyedBy / ForUnkeyed / Repeat / Show. Each returns a region NeonNode;
// the engines in core/array.ms and the host reconciler do the work. A row is described here and
// mounted by the reconciler at its final position, so nothing below touches the host.

import { mapArray, mapArrayKeyedBy, mapArrayByPosition, repeat } from "../../core/array";
import { createMemo } from "../../core/memo";
import { Accessor, accessor, createSignal } from "../../core/signal";
import { catchError } from "../../core/error";
import { NeonNode, regionNode } from "../../render/node";
import { Host, HostNode } from "../../render/hostTypes";
import { Row, makeRow } from "../../render/reconcile";
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

export function ErrorBoundary(props: {
	children: NeonNode;
	fallback: (err: Error, reset: () => void) => NeonNode;
}): NeonNode {
	return regionNode((h) => {
		const [failed, setFailed] = createSignal<Error | null>(null);
		const reset = (): void => { setFailed(null); };
		const guarded: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
			catchError(
				(): void => { props.children(host, parent, before); },
				(err: Error): void => { setFailed(err); },
			);
		};
		return createMemo<Row[]>(() => {
			const err = failed();
			if (err !== null) { return [makeRow(props.fallback(err as Error, reset))]; }
			return [makeRow(guarded)];
		});
	});
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
		use(createMemo(source))(host, parent, before);
	};
}
