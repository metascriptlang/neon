import { Host, HostNode } from "../render/hostTypes";
import { VoidHost, VoidNode } from "../platform/void/host";

export interface DevArea {
	vh: VoidHost;
	pointer: (x: float32, y: float32, pressed: boolean) => void;
	text: (text: string) => void;
	cancel: () => void;
	busy: () => boolean;
}

export enum DevScopeError { NotAVoidArea, NotInArea, Removed }

export enum DevRefusal {
	ScopeClosed,
	ForeignScope,
	NotIssued,
	Removed,
	OutsideScope,
	NotLaidOut,
	Intercepted,
	NotFocused,
	ForeignFocus,
	TargetGoneDuringPress,
	Busy,
	HandlerFailed,
}

export class DevRef {
	scope: DevScope;
	node: VoidNode;

	constructor(scope: DevScope, node: VoidNode) {
		this.scope = scope;
		this.node = node;
	}
}

export interface ScopeNode {
	ref: DevRef;
	tag: string;
	text: string;
	value: string | null;
	focused: boolean;
	pressable: boolean;
	x: float32;
	y: float32;
	w: float32;
	h: float32;
	children: ScopeNode[];
}

export interface ScopeTree {
	root: ScopeNode;
	truncated: boolean;
}

export interface DevActRefusal {
	reason: DevRefusal;
	detail: string;
	hit: DevRef | null;
}

export interface ScopeLimits {
	maxNodes: int32;
	maxDepth: int32;
}

const areas: DevArea[] = [];

function refusal(reason: DevRefusal, detail: string, hit: DevRef | null = null): DevActRefusal {
	return { reason, detail, hit };
}

export class DevScope {
	area: DevArea | null;
	root: VoidNode;
	issued: VoidNode[] = [];

	constructor(area: DevArea, root: VoidNode) {
		this.area = area;
		this.root = root;
	}
}

const scopes: DevScope[] = [];

export function registerDevArea(area: DevArea): () => void {
	areas.push(area);
	return (): void => {
		const at = areas.indexOf(area);
		if (at >= 0) { areas.splice(at, 1); }
		for (let i = scopes.length - 1; i >= 0; i -= 1) {
			if (scopes[i].area === area) { closeScope(scopes[i]); }
		}
	};
}

export function openDevScope(host: Host, root: HostNode): Result<DevScope, DevScopeError> {
	let found: DevArea | null = null;
	for (const a of areas) {
		if (a.vh.host === host) { found = a; }
	}
	if (found === null) { return Result.err(DevScopeError.NotAVoidArea); }
	const area = found as DevArea;
	if (!(root instanceof VoidNode)) { return Result.err(DevScopeError.NotInArea); }
	const n = root as VoidNode;
	if (n.disposed) { return Result.err(DevScopeError.Removed); }
	if (!inside(area.vh, n, area.vh.root as VoidNode)) { return Result.err(DevScopeError.NotInArea); }
	const scope = new DevScope(area, n);
	scopes.push(scope);
	return Result.ok(scope);
}

export function closeScope(scope: DevScope): void {
	scope.area = null;
	scope.issued = [];
	const at = scopes.indexOf(scope);
	if (at >= 0) { scopes.splice(at, 1); }
}

function owns(vh: VoidHost, n: VoidNode): boolean {
	return n.row >= 0 && n.row < vh.tree.nodes.length && vh.tree.nodes[n.row] === n;
}

function inside(vh: VoidHost, node: VoidNode, top: VoidNode): boolean {
	if (!owns(vh, node) && node !== top) { return false; }
	let cur: VoidNode | null = node;
	while (cur !== null) {
		if (cur === top) { return true; }
		cur = vh.tree.parentOf(cur as VoidNode);
	}
	return false;
}

function openArea(scope: DevScope): Result<DevArea, DevActRefusal> {
	const a = scope.area;
	if (a === null) { return Result.err(refusal(DevRefusal.ScopeClosed, "the scope was closed or its area released")); }
	if (scope.root.disposed) {
		closeScope(scope);
		return Result.err(refusal(DevRefusal.ScopeClosed, "the scope's root was removed"));
	}
	return Result.ok(a as DevArea);
}

export function scopeTree(scope: DevScope, limits: ScopeLimits): Result<ScopeTree, DevActRefusal> {
	const opened = openArea(scope);
	if (!opened.ok) { return Result.err(opened.error); }
	const vh = opened.value.vh;
	if (!vh.laidOut()) { return Result.err(refusal(DevRefusal.NotLaidOut, "the area has not been laid out")); }
	const settled = vh.settle(scope.root);
	if (settled === null) {
		closeScope(scope);
		return Result.err(refusal(DevRefusal.ScopeClosed, "the scope's root was removed"));
	}
	const issued: VoidNode[] = [];
	let truncated = false;
	const visit = (n: VoidNode, depth: int32): ScopeNode => {
		issued.push(n);
		const d = vh.describe(n);
		const children: ScopeNode[] = [];
		if (depth < limits.maxDepth) {
			for (const c of vh.tree.childrenOf(n)) {
				if (c.disposed) { continue; }
				if (issued.length >= limits.maxNodes) {
					truncated = true;
					break;
				}
				children.push(visit(c, depth + 1));
			}
		} else if (vh.tree.childrenOf(n).length > 0) {
			truncated = true;
		}
		return {
			ref: new DevRef(scope, n),
			tag: d.tag, text: d.text, value: d.value, focused: d.focused, pressable: d.pressable,
			x: d.x, y: d.y, w: d.w, h: d.h,
			children,
		};
	};
	const root = visit(scope.root, 0);
	scope.issued = issued;
	return Result.ok({ root, truncated });
}

function target(scope: DevScope, ref: DevRef): Result<DevArea, DevActRefusal> {
	const opened = openArea(scope);
	if (!opened.ok) { return opened; }
	if (ref.scope !== scope) { return Result.err(refusal(DevRefusal.ForeignScope, "the ref belongs to another scope")); }
	if (ref.node.disposed) { return Result.err(refusal(DevRefusal.Removed, "the node was removed")); }
	if (scope.issued.indexOf(ref.node) < 0) { return Result.err(refusal(DevRefusal.NotIssued, "the scope's latest tree did not hand out this node")); }
	if (!inside(opened.value.vh, ref.node, scope.root)) { return Result.err(refusal(DevRefusal.OutsideScope, "the node moved out of the scope")); }
	return opened;
}

function hitRef(scope: DevScope, vh: VoidHost, hit: VoidNode | null): DevRef | null {
	if (hit === null || !inside(vh, hit as VoidNode, scope.root)) { return null; }
	return new DevRef(scope, hit as VoidNode);
}

function failed(message: string): Result<void, DevActRefusal> {
	return Result.err(refusal(DevRefusal.HandlerFailed, message));
}

const NOT_AN_ERROR = "a handler threw a value that is not an Error (a thrown string is unreadable until .inbox/compiler/2026-11-13-a-caught-string-narrowed-by-typeof-emits-a-pointer-to-msstring-cast.md)";

export function scopePress(scope: DevScope, ref: DevRef): Result<void, DevActRefusal> {
	const aimed = target(scope, ref);
	if (!aimed.ok) { return Result.err(aimed.error); }
	const area = aimed.value;
	const vh = area.vh;
	if (vh.settle(ref.node) === null) { return Result.err(refusal(DevRefusal.Removed, "the node was removed")); }
	const d = vh.describe(ref.node);
	const x = d.x + d.w / 2.0;
	const y = d.y + d.h / 2.0;
	const hit = vh.hitAt(x, y);
	if (hit === null || !inside(vh, hit as VoidNode, ref.node)) {
		const at = hitRef(scope, vh, hit);
		const what = hit === null ? "no node" : at === null ? `<${(hit as VoidNode).tag}> outside the scope` : `<${(hit as VoidNode).tag}> inside the scope`;
		return Result.err(refusal(DevRefusal.Intercepted, `the point (${x}, ${y}) lands on ${what}`, at));
	}
	const receiver = vh.receiverOf(hit as VoidNode);
	if (receiver !== null && !inside(vh, receiver as VoidNode, scope.root)) {
		return Result.err(refusal(DevRefusal.Intercepted, `the press would reach <${(receiver as VoidNode).tag}>'s handler outside the scope`));
	}
	if (area.busy()) { return Result.err(refusal(DevRefusal.Busy, "a button is already held on this area; its gesture is left alone")); }
	try {
		area.pointer(x, y, true);
	} catch (e) {
		area.cancel();
		if (e instanceof Error) { return failed((e as Error).message); }
		return failed(NOT_AN_ERROR);
	}
	if (ref.node.disposed || scope.area === null || scope.root.disposed || !inside(vh, ref.node, scope.root)) {
		area.cancel();
		return Result.err(refusal(DevRefusal.TargetGoneDuringPress, "the target left during the press; the gesture was cancelled and no release was sent"));
	}
	try {
		area.pointer(x, y, false);
	} catch (e) {
		if (e instanceof Error) { return failed((e as Error).message); }
		return failed(NOT_AN_ERROR);
	}
	return Result.ok(undefined);
}

export function scopeType(scope: DevScope, ref: DevRef, text: string): Result<void, DevActRefusal> {
	const aimed = target(scope, ref);
	if (!aimed.ok) { return Result.err(aimed.error); }
	const area = aimed.value;
	const focused = area.vh.focused();
	if (focused !== ref.node) {
		if (focused !== null && !inside(area.vh, focused as VoidNode, scope.root)) {
			return Result.err(refusal(DevRefusal.ForeignFocus, "a field outside the scope holds focus"));
		}
		return Result.err(refusal(DevRefusal.NotFocused, "the target does not hold focus", hitRef(scope, area.vh, focused)));
	}
	try {
		area.text(text);
	} catch (e) {
		if (e instanceof Error) { return failed((e as Error).message); }
		return failed(NOT_AN_ERROR);
	}
	return Result.ok(undefined);
}
