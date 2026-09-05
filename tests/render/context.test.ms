// context — createContext/useContext: a provider pushes a value onto the
// nearest-owner walk, consumers read it wherever they mount. Identity is the
// context object itself; reactivity flows through signals inside the value.

import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { direct } from "../../src/macros/ui/direct";
import { NeonNode, renderToString } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, renderToHost, mockToString } from "../../src/render/host";
import { createContext, useContext } from "../../src/render/context";

interface Theme { accent: string; }

test "a provider feeds a consumer nested in its subtree — tree emission" {
	const T = createContext<Theme>({ accent: "red" });
	const root: MockNode = mockNode("root");
	const app: NeonNode = element(
		<T.Provider value={{ accent: "blue" }}>
			<div>{useContext(T).accent}</div>
		</T.Provider>
	);
	renderToHost(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div>blue</div></root>", "consumer saw the provided value: " + mockToString(root);
}

test "a provider feeds a consumer nested in its subtree — direct emission" {
	const T = createContext<Theme>({ accent: "red" });
	const host = mockHost();
	const root: MockNode = mockNode("root");
	const mount = direct(
		<T.Provider value={{ accent: "blue" }}>
			<div>{useContext(T).accent}</div>
		</T.Provider>
	);
	host.append(root as unknown as HostNode, mount(host));
	assert mockToString(root) === "<root><div>blue</div></root>", "direct lane saw the same value: " + mockToString(root);
}

test "the nearest provider wins when providers nest" {
	const T = createContext<Theme>({ accent: "red" });
	const root: MockNode = mockNode("root");
	const app: NeonNode = element(
		<T.Provider value={{ accent: "blue" }}>
			<T.Provider value={{ accent: "green" }}>
				<div>{useContext(T).accent}</div>
			</T.Provider>
		</T.Provider>
	);
	renderToHost(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div>green</div></root>", "inner provider won: " + mockToString(root);
}

test "a consumer without a provider reads the default" {
	const T = createContext<Theme>({ accent: "red" });
	const root: MockNode = mockNode("root");
	const app: NeonNode = element(<div>{useContext(T).accent}</div>);
	renderToHost(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div>red</div></root>", "default came back: " + mockToString(root);
}

test "identity is the context object, not the shape" {
	const A = createContext<Theme>({ accent: "a" });
	const B = createContext<Theme>({ accent: "b" });
	const root: MockNode = mockNode("root");
	const app: NeonNode = element(
		<A.Provider value={{ accent: "A!" }}>
			<div>{useContext(B).accent}</div>
		</A.Provider>
	);
	renderToHost(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div>b</div></root>", "same shape, different object: no bleed: " + mockToString(root);
}

test "the scope ends at the closing tag" {
	const T = createContext<Theme>({ accent: "red" });
	const root: MockNode = mockNode("root");
	const app: NeonNode = element(
		<div>
			<T.Provider value={{ accent: "blue" }}><span>x</span></T.Provider>
			<p>{useContext(T).accent}</p>
		</div>
	);
	renderToHost(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div><span>x</span><p>red</p></div></root>", "sibling outside saw the default: " + mockToString(root);
}

test "a consumer sees through a component boundary" {
	const T = createContext<Theme>({ accent: "red" });
	function Chip(props: { label: string }): NeonNode {
		const c = useContext(T);
		return element(<div>{props.label + ":" + c.accent}</div>);
	}
	const root: MockNode = mockNode("root");
	const app: NeonNode = element(
		<T.Provider value={{ accent: "blue" }}>
			<Chip label="go" />
		</T.Provider>
	);
	renderToHost(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div>go:blue</div></root>", "component body mounted inside the scope: " + mockToString(root);
}

test "renderToString sees through a provider" {
	const T = createContext<Theme>({ accent: "red" });
	const app: NeonNode = element(
		<T.Provider value={{ accent: "blue" }}>
			<div>{useContext(T).accent}</div>
		</T.Provider>
	);
	assert renderToString(app) === "<div>blue</div>", "ssr saw the provided value: " + renderToString(app);
}

test "a signal inside the value keeps the consumer reactive" {
	const T = createContext<Theme>({ accent: "red" });
	const [accent, setAccent] = createSignal("blue");
	const root: MockNode = mockNode("root");
	const app: NeonNode = element(
		<T.Provider value={{ accent: accent() }}>
			<div>{useContext(T).accent}</div>
		</T.Provider>
	);
	renderToHost(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div>blue</div></root>", "initial read: " + mockToString(root);
	setAccent("green");
	assert mockToString(root) === "<root><div>green</div></root>", "signal change reached the consumer: " + mockToString(root);
}
