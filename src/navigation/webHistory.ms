import { Signal, untrack } from "../core/signal";
import { flush } from "../core/runtime";
import { createRenderEffect } from "../core/effect";
import { createRoot } from "../core/owner";
import { Cleanup, Dispose } from "../core/types";
import {
	RoutePlan,
	RoutingError,
	RoutingParticipant,
	encodeRouteComponent,
} from "./routing";
import { RoutingSession } from "./routingHistory";
import { WebHistoryItem, WebNavigationError, WebNavigationNode, WebNavigationOwner } from "./webNavigation";

export interface WebHistory {
	participant: RoutingParticipant;
	enable: (session: RoutingSession) => Dispose;
	suppressed: (commit: () => void) => RoutePlan;
	grouped: (change: () => void) => void;
}

interface HistoryNode {
	key: string;
	path: string;
	parameters: Map<string, string>;
	children: HistoryNode[];
}

interface KeyNode {
	key: string;
	children: KeyNode[];
}

struct StoredNode {
	key: string;
	children: int32;
}

struct StoredHistory {
	nodes: StoredNode[];
}

interface StoredCursor {
	nodes: StoredNode[];
	at: int32;
}

interface HistoryMirror {
	push: (history: HistoryNode[][]) => void;
	pop: (count: int32, nodes: HistoryNode[]) => void;
	rewrite: (history: HistoryNode[][]) => void;
	updateUrl: (nodes: HistoryNode[]) => void;
}

interface MirrorRecord {
	items: WebHistoryItem<string>[];
	counts: int32[];
	child: MirrorRecord | null;
}

function childNavigation(item: WebHistoryItem<string>): WebNavigationNode | null {
	const owner = item.child;
	return owner === null ? null : (owner as WebNavigationOwner).webNavigation;
}

function published(navigation: WebNavigationNode): WebHistoryItem<string>[] {
	const items = navigation.history();
	if (items.length === 0) {
		throw new Error("web history: a navigation published an empty history");
	}
	return items;
}

function nodeOf(item: WebHistoryItem<string>, children: HistoryNode[]): HistoryNode {
	return { key: item.key, path: item.path, parameters: item.parameters, children };
}

function nodeTreeOf(item: WebHistoryItem<string>): HistoryNode {
	const child = childNavigation(item);
	return nodeOf(item, child === null ? [] : nodeHistory(child as WebNavigationNode));
}

function treesOf(items: WebHistoryItem<string>[]): HistoryNode[] {
	const nodes: HistoryNode[] = [];
	for (const item of items) { nodes.push(nodeTreeOf(item)); }
	return nodes;
}

function nodeHistory(navigation: WebNavigationNode): HistoryNode[] {
	return treesOf(published(navigation));
}

function historyOf(item: WebHistoryItem<string>): HistoryNode[] {
	const child = childNavigation(item);
	if (child === null) { return [nodeOf(item, [])]; }
	const nodes: HistoryNode[] = [];
	for (const entry of entriesOf(published(child as WebNavigationNode), [])) {
		nodes.push(nodeOf(item, entry));
	}
	return nodes;
}

function entriesOf(items: WebHistoryItem<string>[], previous: HistoryNode[]): HistoryNode[][] {
	const entries: HistoryNode[][] = [];
	const prefix = previous.slice(0);
	for (const item of items) {
		const itemHistory = historyOf(item);
		for (const node of itemHistory) {
			const entry = prefix.slice(0);
			entry.push(node);
			entries.push(entry);
		}
		prefix.push(itemHistory[itemHistory.length - 1]);
	}
	return entries;
}

function trimSlashes(path: string): string {
	let trimmed = path;
	while (trimmed.startsWith("/")) { trimmed = trimmed.substring(1, trimmed.length); }
	while (trimmed.endsWith("/")) { trimmed = trimmed.substring(0, trimmed.length - 1); }
	return trimmed;
}

function collectAddress(
	node: HistoryNode,
	segments: string[],
	parameters: Map<string, string>,
): void {
	if (node.path !== "") { segments.push(trimSlashes(node.path)); }
	for (const [name, value] of node.parameters) { parameters.set(name, value); }
	if (node.children.length > 0) {
		collectAddress(node.children[node.children.length - 1], segments, parameters);
	}
}

function addressOf(nodes: HistoryNode[]): string {
	const segments: string[] = [];
	const parameters = new Map<string, string>();
	collectAddress(nodes[nodes.length - 1], segments, parameters);
	const path = "/" + segments.join("/");
	const pairs: string[] = [];
	for (const [name, value] of parameters) {
		pairs.push(encodeRouteComponent(name) + "=" + encodeRouteComponent(value));
	}
	return pairs.length === 0 ? path : path + "?" + pairs.join("&");
}

function storeNodes(nodes: HistoryNode[], stored: StoredNode[]): void {
	for (const node of nodes) {
		stored.push({ key: node.key, children: node.children.length as int32 });
		storeNodes(node.children, stored);
	}
}

function encodeHistory(nodes: HistoryNode[]): string {
	const stored: StoredNode[] = [];
	storeNodes(nodes, stored);
	const history: StoredHistory = { nodes: stored };
	return JSON.stringify(history);
}

function readLevel(cursor: StoredCursor, count: int32): Result<KeyNode[], RoutingError> {
	const level: KeyNode[] = [];
	for (let i = 0; i < count; i += 1) {
		if (cursor.at >= cursor.nodes.length) { return Result.err(RoutingError.IncompleteSnapshot); }
		const stored = cursor.nodes[cursor.at];
		cursor.at += 1;
		if (stored.children < 0) { return Result.err(RoutingError.IncompleteSnapshot); }
		const children = try readLevel(cursor, stored.children);
		level.push({ key: stored.key, children });
	}
	return Result.ok(level);
}

function decodeHistory(state: string): Result<KeyNode[], RoutingError> {
	const parsed = JSON.parse<StoredHistory>(state);
	if (!parsed.ok) { return Result.err(RoutingError.IncompleteSnapshot); }
	const cursor: StoredCursor = { nodes: parsed.value.nodes, at: 0 };
	const roots: KeyNode[] = [];
	while (cursor.at < cursor.nodes.length) {
		const root = try readLevel(cursor, 1);
		roots.push(root[0]);
	}
	if (roots.length === 0) { return Result.err(RoutingError.IncompleteSnapshot); }
	return Result.ok(roots);
}

function applyKeys(navigation: WebNavigationNode, nodes: KeyNode[]): boolean {
	const keys: string[] = [];
	for (const node of nodes) { keys.push(node.key); }
	const applied = flush((): Result<void, WebNavigationError> => navigation.navigate(keys));
	if (!applied.ok) { return false; }
	const items = published(navigation);
	for (let i = 0; i < items.length; i += 1) {
		const child = childNavigation(items[i]);
		if (child === null) { continue; }
		if (i >= nodes.length) { return false; }
		if (!applyKeys(child as WebNavigationNode, nodes[i].children)) { return false; }
	}
	return true;
}

function keyTreeOf(nodes: HistoryNode[]): KeyNode[] {
	const keys: KeyNode[] = [];
	for (const node of nodes) { keys.push({ key: node.key, children: keyTreeOf(node.children) }); }
	return keys;
}

function allowsTraversal(navigation: WebNavigationNode): boolean {
	const items = published(navigation);
	const child = childNavigation(items[items.length - 1]);
	if (child !== null && !allowsTraversal(child as WebNavigationNode)) { return false; }
	return navigation.onBeforeNavigate();
}

function keysOf(items: WebHistoryItem<string>[]): string[] {
	const keys: string[] = [];
	for (const item of items) { keys.push(item.key); }
	return keys;
}

function startsWith(keys: string[], prefix: string[]): boolean {
	if (prefix.length > keys.length) { return false; }
	for (let i = 0; i < prefix.length; i += 1) {
		if (keys[i] !== prefix[i]) { return false; }
	}
	return true;
}

function sameParameters(a: Map<string, string>, b: Map<string, string>): boolean {
	if (a.size !== b.size) { return false; }
	for (const [name, value] of a) {
		if (!b.has(name) || b.get(name) !== value) { return false; }
	}
	return true;
}

function sameItems(a: WebHistoryItem<string>[], b: WebHistoryItem<string>[]): boolean {
	if (a.length !== b.length) { return false; }
	for (let i = 0; i < a.length; i += 1) {
		if (a[i].key !== b[i].key || a[i].path !== b[i].path || a[i].child !== b[i].child ||
			!sameParameters(a[i].parameters, b[i].parameters)) {
			return false;
		}
	}
	return true;
}

function recordLevel(navigation: WebNavigationNode): MirrorRecord {
	const items = published(navigation);
	const counts = untrack((): int32[] => {
		const counted: int32[] = [];
		for (const item of items) { counted.push(historyOf(item).length as int32); }
		return counted;
	});
	const child = childNavigation(items[items.length - 1]);
	return {
		items,
		counts,
		child: child === null ? null : recordLevel(child as WebNavigationNode),
	};
}

function entryCount(record: MirrorRecord, at: int32): int32 {
	const child = record.child;
	if (at === record.items.length - 1 && child !== null) {
		return totalCount(child as MirrorRecord);
	}
	return record.counts[at];
}

function totalCount(record: MirrorRecord): int32 {
	let total: int32 = 0;
	for (let i = 0; i < record.items.length; i += 1) { total += entryCount(record, i); }
	return total;
}

function mirrorChange(
	items: WebHistoryItem<string>[],
	previous: MirrorRecord,
	mirror: HistoryMirror,
): void {
	const newKeys = keysOf(items);
	const oldKeys = keysOf(previous.items);
	if (newKeys.length === oldKeys.length && startsWith(newKeys, oldKeys)) {
		mirror.updateUrl(treesOf(items));
	} else if (startsWith(newKeys, oldKeys)) {
		mirror.push(entriesOf(items.slice(previous.items.length), treesOf(previous.items)));
	} else if (startsWith(oldKeys, newKeys)) {
		let count: int32 = 0;
		for (let i = items.length; i < previous.items.length; i += 1) {
			count += entryCount(previous, i);
		}
		mirror.pop(count, treesOf(items));
	} else {
		mirror.rewrite(entriesOf(items, []));
	}
}

function nestedMirror(
	mirror: HistoryMirror,
	inactive: HistoryNode[],
	active: WebHistoryItem<string>,
): HistoryMirror {
	const wrap = (children: HistoryNode[]): HistoryNode[] => {
		const nodes = inactive.slice(0);
		nodes.push(nodeOf(active, children));
		return nodes;
	};
	const wrapAll = (history: HistoryNode[][]): HistoryNode[][] => {
		const wrapped: HistoryNode[][] = [];
		for (const children of history) { wrapped.push(wrap(children)); }
		return wrapped;
	};
	return {
		push: (history: HistoryNode[][]): void => mirror.push(wrapAll(history)),
		pop: (count: int32, children: HistoryNode[]): void => mirror.pop(count, wrap(children)),
		rewrite: (history: HistoryNode[][]): void => mirror.rewrite(wrapAll(history)),
		updateUrl: (children: HistoryNode[]): void => mirror.updateUrl(wrap(children)),
	};
}

function mirrorLevel(
	navigation: WebNavigationNode,
	previous: MirrorRecord,
	mirror: HistoryMirror,
): MirrorRecord {
	const items = published(navigation);
	if (!sameItems(items, previous.items)) {
		untrack((): void => mirrorChange(items, previous, mirror));
		return recordLevel(navigation);
	}
	const active = items[items.length - 1];
	const child = childNavigation(active);
	const previousChild = previous.child;
	if (child === null || previousChild === null) { return previous; }
	const inactive = untrack((): HistoryNode[] => treesOf(items.slice(0, items.length - 1)));
	return {
		items: previous.items,
		counts: previous.counts,
		child: mirrorLevel(
			child as WebNavigationNode,
			previousChild as MirrorRecord,
			nestedMirror(mirror, inactive, active),
		),
	};
}

function goBack(session: RoutingSession, count: int32, landed: () => void): void {
	if (!session.go(-count, landed)) {
		throw new Error("web history: the history cannot go back " + count.toString() + " entries");
	}
}

function sessionMirror(
	session: RoutingSession,
	write: (nodes: HistoryNode[], replace: boolean) => void,
): HistoryMirror {
	const rewrite = (history: HistoryNode[][]): void => {
		write(history[0], true);
		for (let i = 1; i < history.length; i += 1) { write(history[i], false); }
	};
	return {
		push: (history: HistoryNode[][]): void => {
			for (const nodes of history) { write(nodes, false); }
		},
		pop: (count: int32, nodes: HistoryNode[]): void => {
			const current = session.index();
			const popCount = count < current ? count : current;
			if (popCount <= 0) { write(nodes, true); return; }
			goBack(session, popCount, (): void => {
				if (popCount < count) { write(nodes, true); }
			});
		},
		rewrite: (history: HistoryNode[][]): void => {
			const current = session.index();
			if (current <= 0) { rewrite(history); return; }
			goBack(session, current, (): void => rewrite(history));
		},
		updateUrl: (nodes: HistoryNode[]): void => write(nodes, true),
	};
}

export function createWebHistory(
	scope: string,
	navigation: WebNavigationNode,
	resolve: (address: string | null) => Result<RoutePlan, RoutingError>,
): WebHistory {
	const applied = new Signal<int32>(0, null, true);
	let pending: HistoryNode[] | null = null;
	let reported = false;
	const current = (): HistoryNode[] => {
		return pending === null ? nodeHistory(navigation) : pending as HistoryNode[];
	};
	let applying = false;
	let holding = false;
	const released = new Signal<int32>(0, null, true);
	const grouped = (change: () => void): void => {
		const outer = holding;
		holding = true;
		try {
			flush(change);
		} finally {
			holding = outer;
		}
		if (!outer) { released.set(released.peek() + 1); }
	};
	const suppressed = (commit: () => void): RoutePlan => ({
		commit: (): void => flush((): void => {
			const outer = applying;
			applying = true;
			try {
				commit();
			} finally {
				applying = outer;
			}
			applied.set(applied.peek() + 1);
		}),
	});
	const write = (session: RoutingSession, nodes: HistoryNode[], replace: boolean): void => {
		pending = nodes;
		reported = false;
		try {
			const written = session.sync(replace);
			if (!written.ok) {
				throw new Error("web history: the address does not encode: " +
					written.error.toString());
			}
			if (!reported) {
				throw new Error("web history: the session's registry does not hold scope " + scope);
			}
		} finally {
			pending = null;
		}
	};
	return {
		participant: {
			scope,
			prepare: (address: string | null): Result<RoutePlan, RoutingError> => {
				const plan = try resolve(address);
				return Result.ok(suppressed(plan.commit));
			},
			address: (): Result<string | null, RoutingError> => {
				if (pending !== null) { reported = true; }
				const address: string | null = addressOf(current());
				return Result.ok(address);
			},
			capture: (): string => encodeHistory(current()),
			restore: (state: string, address: string | null): Result<RoutePlan, RoutingError> => {
				const stored = decodeHistory(state);
				if (!stored.ok && address === null) { return Result.err(stored.error); }
				if (!allowsTraversal(navigation)) { return Result.err(RoutingError.Refused); }
				if (!stored.ok) {
					const plan = try resolve(address);
					return Result.ok(suppressed(plan.commit));
				}
				const nodes = stored.value;
				return Result.ok(suppressed((): void => {
					const live = keyTreeOf(nodeHistory(navigation));
					if (applyKeys(navigation, nodes)) { return; }
					if (!applyKeys(navigation, live)) {
						throw new Error("web history: the live keys do not apply again");
					}
					if (address === null) {
						throw new Error("web history: unusable stored keys have no address");
					}
					const plan = resolve(address);
					if (!plan.ok) {
						throw new Error(
							"web history: stored keys that do not apply fall back to an address " +
							"that does not resolve: " + plan.error.toString(),
						);
					}
					plan.value.commit();
				}));
			},
		},
		enable: (session: RoutingSession): Dispose => {
			const mirror = sessionMirror(session, (nodes: HistoryNode[], replace: boolean): void => {
				write(session, nodes, replace);
			});
			write(session, nodeHistory(navigation), true);
			let record: MirrorRecord | null = null;
			let seen: int32 = 0;
			return createRoot((dispose: Dispose): Dispose => {
				createRenderEffect<int32>(
					(prev: int32 | null): int32 => {
						recordLevel(navigation);
						released.get();
						return applied.get();
					},
					(epoch: int32, prev: int32 | null): Cleanup | null => {
						if (holding) { return null; }
						if (record === null || applying || epoch !== seen) {
							seen = epoch;
							record = recordLevel(navigation);
							return null;
						}
						record = mirrorLevel(navigation, record as MirrorRecord, mirror);
						return null;
					},
				);
				return dispose;
			});
		},
		suppressed,
		grouped,
	};
}
