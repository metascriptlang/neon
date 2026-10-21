import { flush } from "../../src/core/runtime";
import { Accessor, Signal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { createRenderEffect } from "../../src/core/effect";
import { Cleanup, Dispose } from "../../src/core/types";
import { NeonNode } from "../../src/render/hostTypes";
import { Style } from "../../src/render/style";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { NavigationChild } from "../../src/navigation/children";
import { ChildPanels, ChildPanelsMode, createChildPanels } from "../../src/navigation/childPanels";
import { renderPanels } from "../../src/navigation/childView";
import { RoutePlan, RoutingError, RoutingRegistry } from "../../src/navigation/routing";
import {
	RoutingHistory,
	RoutingHistoryEntry,
	RoutingSession,
	createMemoryRoutingHistory,
	createRoutingSession,
} from "../../src/navigation/routingHistory";
import { WebKeySerializer, WebNavigationError, childPanelsWebNavigation, webNavigationNode } from "../../src/navigation/webNavigation";
import { createWebHistory } from "../../src/navigation/webHistory";
import { visibleText } from "./navHarness";

type ItemPanels = ChildPanels<string, string, string, string, string, string>;

interface App {
	panels: ItemPanels;
	width: Signal<number>;
	memory: RoutingHistory;
	session: RoutingSession;
	root: MockNode;
	stop: Dispose;
}

let mounts = "";
let writes = "";
const counts = new Map<string, Signal<int32>>();

function same(value: string): string {
	return value;
}

function instance(configuration: Accessor<string>, active: Accessor<boolean>): string {
	return configuration();
}

const text: WebKeySerializer<string> = {
	encode: (value: string): string => value,
	decode: (value: string): Result<string, WebNavigationError> => Result.ok(value),
};

function List(child: NavigationChild<string, string>): NeonNode {
	mounts += "list;";
	return <h1>list</h1>;
}

function Item(child: NavigationChild<string, string>): NeonNode {
	const id = child.configuration();
	mounts += "item " + id + ";";
	const count = new Signal<int32>(0);
	counts.set(id, count);
	return <h1>{"item " + id + " " + count.get().toString()}</h1>;
}

function Pick(): NeonNode {
	return <h1>pick an item</h1>;
}

function bump(id: string): void {
	const count = counts.get(id) as Signal<int32>;
	count.set(count.peek() + 1);
	flush();
}

function recorded(memory: RoutingHistory): RoutingHistory {
	return {
		writable: true,
		read: memory.read,
		index: memory.index,
		push: (entry: RoutingHistoryEntry): void => { writes += "push " + entry.url + ";"; memory.push(entry); },
		replace: (entry: RoutingHistoryEntry): void => { writes += "replace " + entry.url + ";"; memory.replace(entry); },
		go: (delta: int32): boolean => { writes += "go " + delta.toString() + ";"; return memory.go(delta); },
		listen: memory.listen,
	};
}

function open(url: string, width: number): App {
	mounts = "";
	const panels = createChildPanels<string, string, string, string, string, string>(
		{ main: "list", details: null, extra: null, mode: ChildPanelsMode.Dual },
		same, same, same, instance, instance, instance,
	);
	const web = createWebHistory(
		"main",
		webNavigationNode(childPanelsWebNavigation<string, string, string, string, string, string>(
			panels, text, text, text,
			{
				pathMapper: (shown: ItemPanels): string | null => {
					const details = shown.details();
					return details === null ? "items" : "items/" + (details as NavigationChild<string, string>).configuration();
				},
			},
		)),
		(address: string | null): Result<RoutePlan, RoutingError> => {
			const path = address ?? "";
			if (path === "/items") { return Result.ok({ commit: (): void => panels.navigateTo("list", null, null) }); }
			if (!path.startsWith("/items/")) { return Result.err(RoutingError.NoMatch); }
			const id = path.substring(7, path.length);
			return Result.ok({ commit: (): void => panels.navigateTo("list", id, null) });
		},
	);
	const registry = new RoutingRegistry("main");
	registry.register(web.participant);
	const memory = createMemoryRoutingHistory({ url, state: "" });
	const opened = createRoutingSession(registry, recorded(memory), (error: RoutingError): void => {
		throw new Error("panels pattern: " + error.toString());
	});
	if (!opened.ok) { throw new Error("panels pattern: the session does not open"); }
	const session = opened.value;
	const unmirror = web.enable(session);
	const size = new Signal<number>(width);
	const unmode = createRoot((dispose: Dispose): Dispose => {
		createRenderEffect<ChildPanelsMode>(
			(prev: ChildPanelsMode | null): ChildPanelsMode => size.get() < 600 ? ChildPanelsMode.Single : ChildPanelsMode.Dual,
			(mode: ChildPanelsMode, prev: ChildPanelsMode | null): Cleanup | null => { panels.setMode(mode); return null; },
		);
		return dispose;
	});
	const root: MockNode = mockNode("root");
	const unmount = render(renderPanels<string, string, string, string, string, string>(
		panels, List, Item, null, { dualWeights: [1, 2], secondPanelPlaceholder: Pick },
	), mockHost(), root as unknown as HostNode);
	flush();
	writes = "";
	return {
		panels,
		width: size,
		memory,
		session,
		root,
		stop: (): void => {
			unmount();
			unmode();
			unmirror();
			session.dispose();
			panels.dispose();
			flush();
		},
	};
}

function resize(app: App, width: number): void {
	app.width.set(width);
	flush();
}

function frameFlex(app: App, at: int32): number {
	const frames = app.root.children[0].children.filter((child: MockNode): boolean => child.style !== null);
	const frame = frames[at];
	return ((frame.style as Style).flex ?? 0) as number;
}

test "master and detail sit side by side when wide and stack when narrow, under one address that resizing keeps" {
	const app = open("/items", 900);
	assert visibleText(app.root) === "list|pick an item", visibleText(app.root);
	app.panels.activateDetails("2");
	flush();
	assert visibleText(app.root) === "list|item 2 0", visibleText(app.root);
	assert frameFlex(app, 0) === 1 && frameFlex(app, 1) === 2, "dual weights";
	assert app.memory.read().url === "/items/2", app.memory.read().url;
	bump("2");
	writes = "";
	resize(app, 400);
	assert visibleText(app.root) === "item 2 1", visibleText(app.root);
	resize(app, 900);
	assert visibleText(app.root) === "list|item 2 1", visibleText(app.root);
	assert writes === "", "a resize writes no history: " + writes;
	assert app.memory.read().url === "/items/2", app.memory.read().url;
	resize(app, 400);
	assert app.panels.back();
	flush();
	assert visibleText(app.root) === "list", visibleText(app.root);
	assert app.memory.read().url === "/items", app.memory.read().url;
	assert !app.panels.back(), "back from the list alone is not the panels'";
	assert mounts === "list;item 2;", mounts;
	app.stop();
}

test "a cold address opens its detail in the mode the width picks" {
	const narrow = open("/items/3", 400);
	assert visibleText(narrow.root) === "item 3 0", visibleText(narrow.root);
	narrow.stop();
	const wide = open("/items/3", 900);
	assert visibleText(wide.root) === "list|item 3 0", visibleText(wide.root);
	wide.stop();
}
