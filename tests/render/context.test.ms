import { createSignal, accessor, Accessor } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonNode, text } from "../../src/render/node";
import { renderToString } from "../../src/render/ssr";
import { Host, HostNode, MockNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { createContext, useContext } from "../../src/render/context";
import { onCleanup } from "../../src/core/cleanup";
import { createRoot } from "../../src/core/owner";
import { catchError } from "../../src/core/error";
import { Dispose } from "../../src/core/types";
import { For, Index, Show } from "../../src/macros/ui/flow";

interface Theme { accent: string; }

test "a provider feeds a consumer nested in its subtree" {
	const T = createContext<Theme>({ accent: "red" });
	const root: MockNode = mockNode("root");
	const app: NeonNode = element(
		<T.Provider value={{ accent: "blue" }}>
			<div>{useContext(T).accent}</div>
		</T.Provider>
	);
	render(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div>blue</div></root>", "consumer saw the provided value: " + mockToString(root);
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
	render(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div>green</div></root>", "inner provider won: " + mockToString(root);
}

test "a consumer without a provider reads the default" {
	const T = createContext<Theme>({ accent: "red" });
	const root: MockNode = mockNode("root");
	const app: NeonNode = element(<div>{useContext(T).accent}</div>);
	render(app, mockHost(), root as unknown as HostNode);
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
	render(app, mockHost(), root as unknown as HostNode);
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
	render(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div><span>x</span><p>red</p></div></root>", "sibling outside saw the default: " + mockToString(root);
}

test "a consumer sees through a component boundary" {
	const T = createContext<Theme>({ accent: "red" });
	function Chip(props: { label: Accessor<string> }): NeonNode {
		const c = useContext(T);
		return element(<div>{props.label + ":" + c.accent}</div>);
	}
	const root: MockNode = mockNode("root");
	const app: NeonNode = element(
		<T.Provider value={{ accent: "blue" }}>
			<Chip label="go" />
		</T.Provider>
	);
	render(app, mockHost(), root as unknown as HostNode);
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
	render(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div>blue</div></root>", "initial read: " + mockToString(root);
	setAccent("green");
	assert mockToString(root) === "<root><div>green</div></root>", "signal change reached the consumer: " + mockToString(root);
}

test "a For row reads the provider above the list" {
	const T = createContext<Theme>({ accent: "red" });
	const [items, setItems] = createSignal<number[]>([1]);
	const root: MockNode = mockNode("root");
	const app: NeonNode = T.Provider({
		value: accessor((): Theme => ({ accent: "blue" })),
		children: element(<ul>{For<number>({
			each: () => items(),
			children: (n: number, i: Accessor<number>): NeonNode => <li>{useContext(T).accent + n.toString()}</li>,
		})}</ul>),
	});
	render(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><ul><li>blue1</li></ul></root>", "first row saw the provider: " + mockToString(root);
	setItems([1, 2]);
	assert mockToString(root) === "<root><ul><li>blue1</li><li>blue2</li></ul></root>", "a row added later saw the provider: " + mockToString(root);
}

test "an Index row reads the provider above the list" {
	const T = createContext<Theme>({ accent: "red" });
	const [items, setItems] = createSignal<number[]>([1, 2]);
	const root: MockNode = mockNode("root");
	const app: NeonNode = T.Provider({
		value: accessor((): Theme => ({ accent: "blue" })),
		children: element(<ul>{Index<number>({
			each: () => items(),
			children: (n: Accessor<number>, i: number): NeonNode => <li>{useContext(T).accent + n().toString()}</li>,
		})}</ul>),
	});
	render(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><ul><li>blue1</li><li>blue2</li></ul></root>", "every row saw the provider: " + mockToString(root);
}

test "a For fallback reads the provider above the list" {
	const T = createContext<Theme>({ accent: "red" });
	const [items, setItems] = createSignal<number[]>([]);
	const root: MockNode = mockNode("root");
	const app: NeonNode = T.Provider({
		value: accessor((): Theme => ({ accent: "blue" })),
		children: element(<ul>{For<number>({
			each: () => items(),
			children: (n: number, i: Accessor<number>): NeonNode => <li>{n.toString()}</li>,
			fallback: (h: Host, p: HostNode, b: HostNode | null): void => {
				const row: NeonNode = <li>{useContext(T).accent}</li>;
				row(h, p, b);
			},
		})}</ul>),
	});
	render(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><ul><li>blue</li></ul></root>", "fallback saw the provider: " + mockToString(root);
	setItems([7]);
	setItems([]);
	assert mockToString(root) === "<root><ul><li>blue</li></ul></root>", "a rebuilt fallback saw the provider: " + mockToString(root);
}

test "disposing the mount leaves later consumers on the default" {
	const T = createContext<Theme>({ accent: "red" });
	const root: MockNode = mockNode("root");
	const app: NeonNode = element(
		<T.Provider value={{ accent: "blue" }}>
			<div>{useContext(T).accent}</div>
		</T.Provider>
	);
	const dispose = render(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div>blue</div></root>", "mounted under the provider: " + mockToString(root);
	dispose();
	const after: MockNode = mockNode("after");
	render(element(<div>{useContext(T).accent}</div>), mockHost(), after as unknown as HostNode);
	assert mockToString(after) === "<after><div>red</div></after>", "a consumer mounted later reads the default: " + mockToString(after);
}

test "a provider that a Show drops and brings back feeds its child each time" {
	const T = createContext<Theme>({ accent: "red" });
	const [on, setOn] = createSignal(true);
	const root: MockNode = mockNode("root");
	const app: NeonNode = element(
		<Show when={on()}>
			<T.Provider value={{ accent: "blue" }}><span>{useContext(T).accent}</span></T.Provider>
		</Show>
	);
	render(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><span>blue</span></root>", "mounted: " + mockToString(root);
	setOn(false);
	assert mockToString(root) === "<root></root>", "dropped: " + mockToString(root);
	setOn(true);
	assert mockToString(root) === "<root><span>blue</span></root>", "back: " + mockToString(root);
	setOn(false);
	assert mockToString(root) === "<root></root>", "dropped again: " + mockToString(root);
}

test "dropping the first of two sibling providers keeps the second one readable" {
	const T = createContext<Theme>({ accent: "red" });
	const [showA, setShowA] = createSignal(true);
	const [items, setItems] = createSignal<number[]>([]);
	const root: MockNode = mockNode("root");
	const app: NeonNode = element(
		<div>
			<Show when={showA()}>
				<T.Provider value={{ accent: "A" }}><span>a</span></T.Provider>
			</Show>
			{T.Provider({
				value: accessor((): Theme => ({ accent: "B" })),
				children: element(<ul>{For<number>({
					each: () => items(),
					children: (n: number, i: Accessor<number>): NeonNode => <li>{useContext(T).accent + n.toString()}</li>,
				})}</ul>),
			})}
		</div>
	);
	render(app, mockHost(), root as unknown as HostNode);
	setShowA(false);
	setItems([1]);
	assert mockToString(root) === "<root><div><ul><li>B1</li></ul></div></root>", "a row mounted after the removal found the surviving provider: " + mockToString(root);
}

test "a nested provider that goes leaves the outer provider readable" {
	const T = createContext<Theme>({ accent: "red" });
	const [inner, setInner] = createSignal(true);
	const [items, setItems] = createSignal<number[]>([]);
	const root: MockNode = mockNode("root");
	const app: NeonNode = T.Provider({
		value: accessor((): Theme => ({ accent: "outer" })),
		children: element(
			<div>
				<Show when={inner()}>
					<T.Provider value={{ accent: "inner" }}><span>i</span></T.Provider>
				</Show>
				<ul>{For<number>({
					each: () => items(),
					children: (n: number, i: Accessor<number>): NeonNode => <li>{useContext(T).accent + n.toString()}</li>,
				})}</ul>
			</div>
		),
	});
	render(app, mockHost(), root as unknown as HostNode);
	setInner(false);
	setItems([1]);
	assert mockToString(root) === "<root><div><ul><li>outer1</li></ul></div></root>", "the outer provider still answers: " + mockToString(root);
}

test "a consumer's cleanup runs once when its provider's mount is disposed" {
	const T = createContext<Theme>({ accent: "red" });
	let cleanups = 0;
	function Probe(props: { tag: string }): NeonNode {
		onCleanup((): void => {
			cleanups = cleanups + 1;
		});
		return element(<b>{props.tag}</b>);
	}
	const root: MockNode = mockNode("root");
	const app: NeonNode = element(
		<T.Provider value={{ accent: "blue" }}>
			<Probe tag="p" />
		</T.Provider>
	);
	const dispose = render(app, mockHost(), root as unknown as HostNode);
	dispose();
	assert cleanups === 1, "the child's cleanup ran once: " + cleanups.toString();
}

test "a root created under a provider reads it" {
	const T = createContext<Theme>({ accent: "red" });
	let seen = "";
	const consumer: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		createRoot((dispose: Dispose): number => {
			seen = useContext(T).accent;
			return 0;
		});
	};
	const app: NeonNode = T.Provider({ value: accessor((): Theme => ({ accent: "blue" })), children: consumer });
	render(app, mockHost(), mockNode("root") as unknown as HostNode);
	assert seen === "blue", "the root saw the provider: " + seen;
}

test "a catchError scope under a provider reads it" {
	const T = createContext<Theme>({ accent: "red" });
	let seen = "";
	const consumer: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		catchError((): void => {
			seen = useContext(T).accent;
		}, (err: Error): void => {});
	};
	const app: NeonNode = T.Provider({ value: accessor((): Theme => ({ accent: "blue" })), children: consumer });
	render(app, mockHost(), mockNode("root") as unknown as HostNode);
	assert seen === "blue", "the catchError scope saw the provider: " + seen;
}

test "a provider of another context between does not hide the outer one" {
	const A = createContext<Theme>({ accent: "red" });
	const B = createContext<number>(0);
	let seen = "";
	let inner: number = -1;
	const consumer: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		seen = useContext(A).accent;
		inner = useContext(B);
	};
	const middle: NeonNode = B.Provider({ value: accessor((): number => 7), children: consumer });
	const app: NeonNode = A.Provider({ value: accessor((): Theme => ({ accent: "blue" })), children: middle });
	render(app, mockHost(), mockNode("root") as unknown as HostNode);
	assert seen === "blue" && inner === 7, "both providers answered: " + seen + " " + inner.toString();
}
