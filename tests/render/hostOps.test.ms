import { mockHost, mockToString, MockNode, HostNode } from "../../src/render/host";

test "insertBefore positions, nextSibling navigates, removeChild detaches" {
	const h = mockHost();
	const root = h.createElement("ul");
	const a = h.createElement("a");
	const b = h.createElement("b");
	const c = h.createElement("c");
	h.append(root, a);
	h.append(root, c);
	h.insertBefore(root, b, c);
	assert mockToString(root as unknown as MockNode) === "<ul><a></a><b></b><c></c></ul>", "insertBefore before c";

	const ns = h.nextSibling(a);
	assert ns !== null, "a has a next sibling";
	assert (ns as unknown as MockNode).tag === "b", "next sibling of a is b";
	assert h.nextSibling(c) === null, "c is last → null";

	h.removeChild(root, b);
	assert mockToString(root as unknown as MockNode) === "<ul><a></a><c></c></ul>", "after remove b";

	h.insertBefore(root, b, null as unknown as HostNode);
	assert mockToString(root as unknown as MockNode) === "<ul><a></a><c></c><b></b></ul>", "null ref appends at end";
}
