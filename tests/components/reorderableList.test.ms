import { createRoot } from "../../src/core/owner";
import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { neonEvent } from "../../src/render/event";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render, fireEventWith, fireTouch } from "../../src/render/host";
import { Text, View } from "../../src/components/primitives";
import { ReorderableFlatList, ReorderableRenderItemInfo, reorderTarget } from "../../src/components/reorderableList";

interface Song {
	title: string;
}

function songs(n: number): Song[] {
	const out: Song[] = [];
	for (let i = 0; i < n; i += 1) { out.push({ title: "song " + i.toString() }); }
	return out;
}

function moveItem(list: Song[], from: int32, to: int32): Song[] {
	const rest: Song[] = [];
	for (let i = 0; i < list.length; i += 1) {
		if (i !== from) { rest.push(list[i]); }
	}
	const out: Song[] = [];
	for (let i = 0; i < rest.length; i += 1) {
		if (i === to) { out.push(list[from]); }
		out.push(rest[i]);
	}
	if (to >= rest.length) { out.push(list[from]); }
	return out;
}

function findRow(n: MockNode, title: string): MockNode | null {
	if (n.tag === "" && n.text === title) { return n; }
	for (const k of n.children) {
		const hit = findRow(k, title);
		if (hit !== null) { return hit; }
	}
	return null;
}

function rowOf(root: MockNode, title: string): MockNode {
	let at = findRow(root, title) as MockNode;
	while (at.parent !== null) {
		const p = at.parent as MockNode;
		for (const e of p.events) {
			if (e.name === "onTouchMove") { return p; }
		}
		at = p;
	}
	throw "no row for " + title;
}

function transformOf(n: MockNode): string {
	const s = n.style;
	if (s === null) { return "none"; }
	return s.transform ?? "none";
}

function order(root: MockNode): string {
	const titles: string[] = [];
	const walk = (n: MockNode): void => {
		if (n.tag === "" && n.text.startsWith("song")) { titles.push(n.text); }
		for (const k of n.children) { walk(k); }
	};
	walk(root);
	return titles.join(",");
}

function scrollEnabledOf(n: MockNode): string {
	for (const a of n.attrs) { if (a.name === "scrollEnabled") { return a.value ?? "null"; } }
	for (const c of n.children) {
		const found = scrollEnabledOf(c);
		if (found !== "") { return found; }
	}
	return "";
}

test "the midpoint rule picks the slot the dragged row's centre has crossed" {
	const h: number[] = [50, 50, 50, 50];
	assert reorderTarget(h, 1, 20) === 1, "20 px stays";
	assert reorderTarget(h, 1, 30) === 2, "past the next centre";
	assert reorderTarget(h, 1, 110) === 3, "two rows down";
	assert reorderTarget(h, 2, -60) === 1, "one row up";
	assert reorderTarget(h, 2, -500) === 0, "clamped at the top";
}

test "a long-press drag moves a row down, opens the gap, and reorders with the row's identity kept" {
	const [data, setData] = createSignal<Song[]>(songs(5));
	const drags: (() => void)[] = [];
	const log: string[] = [];
	let made = 0;
	const root = mockNode("root");
	createRoot((): void => {
		render(element(<ReorderableFlatList data={data()} dropDuration={0}
			onReorder={(from: number, to: number): void => {
				log.push(`${from}->${to}`);
				setData(moveItem(data(), from as int32, to as int32));
			}}
			renderItem={(info: ReorderableRenderItemInfo<Song>): NeonNode => {
				made += 1;
				drags.push(info.drag);
				return element(<View><Text>{info.item.title}</Text></View>);
			}} />), mockHost(), root as unknown as HostNode);
	});
	for (let i = 0; i < 5; i += 1) {
		const e = neonEvent("layout");
		e.height = 50;
		fireEventWith(rowOf(root, "song " + i.toString()), "onLayout", e);
	}
	const target = rowOf(root, "song 1");
	assert scrollEnabledOf(root) === "true", "the list scrolls before a drag: " + scrollEnabledOf(root);
	fireTouch(target.children[0], "onTouchStart", 10, 75, 1);
	drags[1]();
	assert scrollEnabledOf(root) === "false", "drag() stops the list scrolling before the first move, so a native scroll view cannot take the gesture";
	fireTouch(target.children[0], "onTouchMove", 10, 80, 2);
	fireTouch(target.children[0], "onTouchMove", 10, 140, 3);
	assert transformOf(target) === "translateY(60px)", "the row follows the touch: " + transformOf(target);
	assert transformOf(rowOf(root, "song 2")) === "translateY(-50px)", "the next row opens the gap: " + transformOf(rowOf(root, "song 2"));
	assert transformOf(rowOf(root, "song 3")) === "translateY(0px)", "the row after stays";
	const before = made;
	fireTouch(target.children[0], "onTouchEnd", 10, 140, 4);
	assert log.join(",") === "1->2", "reported: " + log.join(",");
	assert order(root) === "song 0,song 2,song 1,song 3,song 4", "reordered: " + order(root);
	assert made === before, "no row was rendered again";
	assert transformOf(rowOf(root, "song 1")) === "translateY(0px)", "the dropped row rests";
	assert scrollEnabledOf(root) === "true", "the drop lets the list scroll again";
}

test "releasing a long press without moving cancels the drag" {
	const [data, setData] = createSignal<Song[]>(songs(3));
	const drags: (() => void)[] = [];
	const log: string[] = [];
	const root = mockNode("root");
	createRoot((): void => {
		render(element(<ReorderableFlatList data={data()} dropDuration={0}
			onReorder={(from: number, to: number): void => { log.push(`${from}->${to}`); }}
			renderItem={(info: ReorderableRenderItemInfo<Song>): NeonNode => {
				drags.push(info.drag);
				return element(<Text>{info.item.title}</Text>);
			}} />), mockHost(), root as unknown as HostNode);
	});
	const target = rowOf(root, "song 0");
	fireTouch(target, "onTouchStart", 10, 10, 1);
	drags[0]();
	fireTouch(target, "onTouchEnd", 10, 10, 2);
	fireTouch(target, "onTouchStart", 10, 10, 3);
	fireTouch(target, "onTouchMove", 10, 90, 4);
	fireTouch(target, "onTouchEnd", 10, 90, 5);
	assert log.length === 0, "a later drag without drag() does not reorder: " + log.join(",");
	assert transformOf(target) === "translateY(0px)", "rests: " + transformOf(target);
}

test "dragging a row past the bottom edge scrolls the list and the row stays under the touch" {
	const [data, setData] = createSignal<Song[]>(songs(8));
	const drags: (() => void)[] = [];
	const log: string[] = [];
	const root = mockNode("root");
	createRoot((): void => {
		render(element(<ReorderableFlatList data={data()} dropDuration={0}
			onReorder={(from: number, to: number): void => { log.push(`${from}->${to}`); }}
			renderItem={(info: ReorderableRenderItemInfo<Song>): NeonNode => {
				drags.push(info.drag);
				return element(<Text>{info.item.title}</Text>);
			}} />), mockHost(), root as unknown as HostNode);
	});
	for (let i = 0; i < 8; i += 1) {
		const e = neonEvent("layout");
		e.height = 50;
		fireEventWith(rowOf(root, "song " + i.toString()), "onLayout", e);
	}
	const scroll = root.children[0];
	const viewport = neonEvent("scroll");
	viewport.height = 200;
	fireEventWith(scroll, "onScroll", viewport);
	const target = rowOf(root, "song 1");
	fireTouch(target, "onTouchStart", 10, 75, 1);
	drags[1]();
	fireTouch(target, "onTouchMove", 10, 80, 2);
	fireTouch(target, "onTouchMove", 10, 280, 3);
	const scrolled = scroll.scrollY;
	const moved = transformOf(target);
	fireTouch(target, "onTouchEnd", 10, 280, 4);
	assert scrolled === 20, "one autoscroll step of 20: " + scrolled.toString();
	assert moved === "translateY(220px)", "the row follows the touch and the scroll: " + moved;
	assert log.join(",") === "1->5", "dropped past song 5: " + log.join(",");
}
