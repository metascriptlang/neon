import { mockHost, mockNode, mockToString, MockNode, HostNode } from "../../src/render/host";
import { Host } from "../../src/render/hostTypes";
import { openGuest, loadGuest, callGuest, openSlot, closeSlot, hostValue, boxBool } from "../../src/platform/raiser/native";

test "an editor whose Show hides its place notifies onPlaceGone before the node is released" {
	const opened = openGuest({ projectRoot: "." });
	if (!opened.ok) { throw new Error(opened.error); }
	const editor = opened.value;
	assert loadGuest(editor, "tests/platform/raiser/editor.ms").ok, "the editor compiles";
	const log: string[] = [];
	let place: MockNode | null = null;
	editor.onPlace = (name: string, host: Host, node: HostNode): void => {
		log.push(`place ${name}`);
		place = node as unknown as MockNode;
	};
	editor.onPlaceGone = (name: string): void => {
		log.push(`gone ${name} ${(place as MockNode).parent !== null ? "attached" : "detached"}`);
	};
	const root = mockNode("root");
	const slot = openSlot(editor, "editor", [], mockHost(), root as unknown as HostNode, null);
	const hidden = callGuest(editor, "showPlace", [hostValue(boxBool(false))]);
	assert hidden.ok, hidden.ok ? "" : hidden.error;
	assert log.join("; ") === "place preview; gone preview attached", log.join("; ");
	const again = callGuest(editor, "showPlace", [hostValue(boxBool(true))]);
	assert again.ok, again.ok ? "" : again.error;
	assert log.join("; ") === "place preview; gone preview attached; place preview", log.join("; ");
	closeSlot(slot);
	assert root.children.length === 0, mockToString(root);
}
