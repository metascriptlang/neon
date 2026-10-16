import { Accessor, Signal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/hostTypes";
import {
	HostNode,
	MockNode,
	mockNode,
	mockHost,
	render,
	mockToString,
} from "../../src/render/host";
import { NavigationChild } from "../../src/navigation/children";
import { createChildStack } from "../../src/navigation/childStack";
import { createChildPages } from "../../src/navigation/childPages";
import { renderPages, renderStack } from "../../src/navigation/childView";
import { visibleText } from "./navHarness";

let mounts = "";
const counts = new Map<string, Signal<int32>>();

function named(name: string): string {
	return name;
}

function instance(configuration: Accessor<string>, active: Accessor<boolean>): string {
	return configuration();
}

function screen(child: NavigationChild<string, string>): NeonNode {
	const name = child.key;
	mounts += name + ";";
	const count = new Signal<int32>(0);
	counts.set(name, count);
	return <h1>{name + " " + count.get().toString()}</h1>;
}

function bump(name: string): void {
	const count = counts.get(name) as Signal<int32>;
	count.set(count.peek() + 1);
}

function mounted(view: NeonNode): MockNode {
	mounts = "";
	const root: MockNode = mockNode("root");
	render(view, mockHost(), root as unknown as HostNode);
	return root;
}

test "a covered stack screen is hidden and keeps its state until it is uncovered" {
	const stack = createChildStack<string, string>(["list"], named, instance);
	const root = mounted(renderStack<string, string>(stack, screen));
	bump("list");
	assert visibleText(root) === "list 1", visibleText(root);
	stack.push("detail");
	assert visibleText(root) === "detail 0", visibleText(root);
	assert mockToString(root).includes("list 1"), mockToString(root);
	stack.pop();
	assert visibleText(root) === "list 1", visibleText(root);
	assert mounts === "list;detail;", mounts;
	stack.dispose();
}

test "a tab keeps its component state across a switch away and back" {
	const pages = createChildPages<string, string>(
		{ items: ["feed", "inbox"], selectedIndex: 0 },
		named,
		instance,
	);
	const root = mounted(renderPages<string, string>(pages, screen));
	bump("feed");
	assert visibleText(root) === "feed 1", visibleText(root);
	pages.select(1);
	assert visibleText(root) === "inbox 0", visibleText(root);
	pages.select(0);
	assert visibleText(root) === "feed 1", visibleText(root);
	assert mounts === "feed;inbox;", mounts;
	pages.dispose();
}

test "a tab that was never selected is not mounted" {
	const pages = createChildPages<string, string>(
		{ items: ["feed", "inbox", "profile"], selectedIndex: 0 },
		named,
		instance,
	);
	const root = mounted(renderPages<string, string>(pages, screen));
	assert mounts === "feed;", mounts;
	pages.select(2);
	assert visibleText(root) === "profile 0", visibleText(root);
	assert mounts === "feed;profile;", mounts;
	assert !mockToString(root).includes("inbox"), mockToString(root);
	pages.dispose();
}
