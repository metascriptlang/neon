import { el, text, regionNode } from "../../src/render/node";
import { Host, HostNode, MockNode, mockHost, renderToHost, renderNode } from "../../src/render/host";
import { mapArray } from "../../src/core/array";
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

test "region mounts a reactive list and reconciles on change" {
	createRoot((d) => {
		const [list, setList] = createSignal<number[]>([1, 2, 3]);
		const region = regionNode((h) => {
			const host = h as Host;
			return mapArray<number, HostNode>(() => list(), (v, i) => renderNode(el("li", [], [], [text("" + v)]), host));
		});
		const ul = el("ul", [], [], [region]);
		const host = mockHost();
		const root = host.createElement("root");
		renderToHost(ul, host, root);

		const ulNode = (root as unknown as MockNode).children[0];
		assert listText(ulNode) === "123", "initial list";
		setList([1, 2, 3, 4]);
		assert listText(ulNode) === "1234", "append 4";
		setList([2, 3]);
		assert listText(ulNode) === "23", "remove 1 and 4";
		setList([3, 2]);
		assert listText(ulNode) === "32", "reorder";
		setList([]);
		assert listText(ulNode) === "", "clear";
		d();
	});
}
