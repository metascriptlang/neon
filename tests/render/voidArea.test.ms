import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { createContext, useContext } from "../../src/render/context";
import { Void, View, Text } from "../../src/components/primitives";
import { createVoidHost } from "../../src/platform/void/host";

test "Void mounts its children into the area the host opens" {
	const root: MockNode = mockNode("root");
	render(element(<Void><View><Text>hi</Text></View></Void>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><void><voidroot><view><text>hi</text></view></voidroot></void></root>", mockToString(root);
}

test "Void takes the same style as View" {
	const root: MockNode = mockNode("root");
	render(element(<Void style={{ flexGrow: 1, backgroundColor: "#102030" }}><View /></Void>), mockHost(), root as unknown as HostNode);
	const v = root.children[0];
	assert v.tag === "void", "outer element is the void tag";
	assert v.style !== null, "style reached the void element";
	assert v.style!.flexGrow === 1, "flexGrow";
	assert v.style!.backgroundColor === "#102030", "backgroundColor";
}

test "disposing the owner releases the area" {
	const root: MockNode = mockNode("root");
	const dispose = render(element(<Void><View /></Void>), mockHost(), root as unknown as HostNode);
	const v = root.children[0];
	assert mockToString(v).indexOf("released") < 0, "not released while mounted";
	dispose();
	assert mockToString(v).indexOf("released=\"true\"") >= 0, "released on dispose: " + mockToString(v);
}

interface Theme { accent: string; }

test "context and signals cross into the area" {
	const T = createContext<Theme>({ accent: "red" });
	const [n, setN] = createSignal(1);
	const root: MockNode = mockNode("root");
	render(element(
		<T.Provider value={{ accent: "blue" }}>
			<Void><Text>{useContext(T).accent}{n().toString()}</Text></Void>
		</T.Provider>
	), mockHost(), root as unknown as HostNode);
	assert mockToString(root).indexOf("<text>blue1</text>") >= 0, "context read inside: " + mockToString(root);
	setN(2);
	assert mockToString(root).indexOf("<text>blue2</text>") >= 0, "signal tracked inside: " + mockToString(root);
}

test "a host without voidArea refuses Void and names the capability" {
	const vh = createVoidHost();
	assert vh.host.voidArea === null, "the void host opens no nested area";
	let caught = "";
	try {
		render(element(<Void><View /></Void>), vh.host, vh.root as unknown as HostNode);
	} catch (e) { caught = e.toString(); }
	assert caught.includes("voidArea"), "error names the capability: " + caught;
}
