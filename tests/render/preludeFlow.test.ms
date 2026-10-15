import { NeonNode } from "../../src/render/node";
import { render, mockHost, mockNode, mockToString, HostNode } from "../../src/render/host";

function orNone(maybe: NeonNode | null): NeonNode {
	return <div>{maybe ?? <i>none</i>}</div>;
}

test "bare JSX lowers ?? over a nullable node" {
	const a = mockNode("root");
	render(orNone(null), mockHost(), a as unknown as HostNode);
	assert mockToString(a) === "<root><div><i>none</i></div></root>", "null: " + mockToString(a);
	const b = mockNode("root");
	render(orNone(<b>x</b>), mockHost(), b as unknown as HostNode);
	assert mockToString(b) === "<root><div><b>x</b></div></root>", "present: " + mockToString(b);
}
