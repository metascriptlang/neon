import { el, text, dynText, NeonNode } from "../../src/render/node";
import { MockNode, mockHost, renderToHost, viewOf } from "../../src/render/host";
import { For, Index, Show } from "../../src/macros/ui/flow";
import { createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";

function listText(node: MockNode): string {
	let s = "";
	for (const c of node.children) {
		if (c.tag !== "") {
			for (const t of c.children) { s = s + t.text; }
		}
	}
	return s;
}

test "For reactive list reuses rows on reorder, creates only new" {
	createRoot((d) => {
		const [items, setItems] = createSignal<number[]>([1, 2, 3]);
		let creates = 0;
		const ul = el("ul", [], [], [
			For<number>({
				each: () => items(),
				children: (item, i) => { creates = creates + 1; return viewOf(el("li", [], [], [text("" + item)])); },
			}),
		]);
		const host = mockHost();
		const root = host.createElement("root");
		renderToHost(ul, host, root);
		const ulNode = (root as unknown as MockNode).children[0];
		assert listText(ulNode) === "123", "initial";
		assert creates === 3, "3 rows created";
		setItems([3, 1, 2]);
		assert listText(ulNode) === "312", "reordered";
		assert creates === 3, "no new creates on reorder";
		setItems([3, 1, 2, 4]);
		assert listText(ulNode) === "3124", "append";
		assert creates === 4, "one create for new item";
		setItems([2]);
		assert listText(ulNode) === "2", "shrink";
		assert creates === 4, "no creates on removal";
		d();
	});
}

test "For fallback shows when empty" {
	createRoot((d) => {
		const [items, setItems] = createSignal<number[]>([1]);
		const ul = el("ul", [], [], [
			For<number>({
				each: () => items(),
				children: (item, i) => viewOf(el("li", [], [], [text("" + item)])),
				fallback: viewOf(el("li", [], [], [text("empty")])),
			}),
		]);
		const host = mockHost();
		const root = host.createElement("root");
		renderToHost(ul, host, root);
		const ulNode = (root as unknown as MockNode).children[0];
		assert listText(ulNode) === "1", "has item";
		setItems([]);
		assert listText(ulNode) === "empty", "fallback shown";
		setItems([5]);
		assert listText(ulNode) === "5", "back to item";
		d();
	});
}

test "Index updates row value in place, no recreate" {
	createRoot((d) => {
		const [items, setItems] = createSignal<number[]>([1, 2, 3]);
		let creates = 0;
		const ul = el("ul", [], [], [
			Index<number>({
				each: () => items(),
				children: (item, i) => { creates = creates + 1; return viewOf(el("li", [], [], [dynText(() => "" + item())])); },
			}),
		]);
		const host = mockHost();
		const root = host.createElement("root");
		renderToHost(ul, host, root);
		const ulNode = (root as unknown as MockNode).children[0];
		assert listText(ulNode) === "123", "initial";
		assert creates === 3, "3 created";
		setItems([9, 2, 3]);
		assert listText(ulNode) === "923", "value updated in place";
		assert creates === 3, "no recreate on value change";
		d();
	});
}

test "Show swaps child/fallback and stays stable while true" {
	createRoot((d) => {
		const [n, setN] = createSignal(1);
		const div = el("div", [], [], [
			Show({
				when: () => n() > 0,
				children: viewOf(el("span", [], [], [text("on")])),
				fallback: viewOf(el("span", [], [], [text("off")])),
			}),
		]);
		const host = mockHost();
		const root = host.createElement("root");
		renderToHost(div, host, root);
		const divNode = (root as unknown as MockNode).children[0];

		assert divNode.children[0].children[0].text === "on", "initial on";
		const firstSpan = divNode.children[0];
		setN(2);
		assert divNode.children[0].children[0].text === "on", "still on";
		assert divNode.children[0] === firstSpan, "same node — not rebuilt while truthy";
		setN(0);
		assert divNode.children[0].children[0].text === "off", "fallback off";
		setN(5);
		assert divNode.children[0].children[0].text === "on", "on again";
		d();
	});
}

test "For fallback reactive scope is disposed when rows return" {
	createRoot((d) => {
		const [items, setItems] = createSignal<number[]>([]);
		const [label, setLabel] = createSignal("empty");
		let fbRuns = 0;
		const ul = el("ul", [], [], [
			For<number>({
				each: () => items(),
				children: (item, i) => viewOf(el("li", [], [], [text("" + item)])),
				fallback: viewOf(el("li", [], [], [dynText(() => { fbRuns = fbRuns + 1; return label(); })])),
			}),
		]);
		const host = mockHost();
		const root = host.createElement("root");
		renderToHost(ul, host, root);
		assert fbRuns === 1, "fallback effect ran once when empty";
		setLabel("none");
		assert fbRuns === 2, "fallback effect reactive while shown";
		setItems([1]);
		setLabel("ignored");
		assert fbRuns === 2, "fallback effect disposed once rows returned";
		d();
	});
}
