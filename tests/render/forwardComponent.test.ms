import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { mockHost, mockNode, mockToString, HostNode } from "../../src/render/host";

function App(): NeonNode {
	return element(<div><Header title="hi" /></div>);
}

function Header(props: { title: string }): NeonNode {
	return element(<p>{props.title}</p>);
}

test "a component used above its declaration is checked and mounts" {
	const root = mockNode("root");
	App()(mockHost(), root as unknown as HostNode, null);
	assert mockToString(root) === "<root><div><p>hi</p></div></root>", mockToString(root);
}
