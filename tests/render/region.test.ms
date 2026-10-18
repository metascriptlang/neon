import { regionNode, builtRow } from "../../src/render/node";
import { element } from "../../src/macros/ui/element";
import { MockNode, mockHost, render } from "../../src/render/host";
import { Row } from "../../src/render/reconcile";
import { mapArray } from "../../src/core/array";
import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";

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
	const [list, setList] = createSignal<number[]>([1, 2, 3]);
	const region = regionNode((h, home) => {
		return mapArray<number, Row>(() => list(), (v, i) => builtRow(h, home, <li>{"" + v}</li>));
	});
	const ul = element(<ul>{region}</ul>);
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);

	const ulNode = (root as unknown as MockNode).children[0];
	assert listText(ulNode) === "123", "initial list";
	setList([1, 2, 3, 4]);
	flush();
	assert listText(ulNode) === "1234", "append 4";
	setList([2, 3]);
	flush();
	assert listText(ulNode) === "23", "remove 1 and 4";
	setList([3, 2]);
	flush();
	assert listText(ulNode) === "32", "reorder";
	setList([]);
	flush();
	assert listText(ulNode) === "", "clear";
	d();
}
