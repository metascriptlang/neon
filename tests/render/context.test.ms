import { createSignal, accessor, Accessor } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonNode, text } from "../../src/render/node";
import { renderToString } from "../../src/render/ssr";
import { Host, HostNode, MockNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { Context, createContext, useContext, ContextNotFoundError, NoOwnerError } from "../../src/render/context";
import { onCleanup } from "../../src/core/cleanup";
import { createRoot } from "../../src/core/owner";
import { resetErrorHalt } from "../../src/core/runtime";
import { Dispose } from "../../src/core/types";
import { Errored, For, ForUnkeyed, Show } from "../../src/macros/ui/flow";

interface Theme { accent: string; }

test "a provider feeds a consumer nested in its subtree" {
	const T = createContext<Theme>({ accent: "red" });
	const root: MockNode = mockNode("root");
	const app: NeonNode = element(
		<T value={{ accent: "blue" }}>
			<div>{useContext(T).accent}</div>
		</T>
	);
	render(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div>blue</div></root>", "consumer saw the provided value: " + mockToString(root);
}

test "the nearest provider wins when providers nest" {
	const T = createContext<Theme>({ accent: "red" });
	const root: MockNode = mockNode("root");
	const app: NeonNode = element(
		<T value={{ accent: "blue" }}>
			<T value={{ accent: "green" }}>
				<div>{useContext(T).accent}</div>
			</T>
		</T>
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
		<A value={{ accent: "A!" }}>
			<div>{useContext(B).accent}</div>
		</A>
	);
	render(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div>b</div></root>", "same shape, different object: no bleed: " + mockToString(root);
}

test "the scope ends at the closing tag" {
	const T = createContext<Theme>({ accent: "red" });
	const root: MockNode = mockNode("root");
	const app: NeonNode = element(
		<div>
			<T value={{ accent: "blue" }}><span>x</span></T>
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
		<T value={{ accent: "blue" }}>
			<Chip label="go" />
		</T>
	);
	render(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div>go:blue</div></root>", "component body mounted inside the scope: " + mockToString(root);
}

test "renderToString sees through a provider" {
	const T = createContext<Theme>({ accent: "red" });
	const app: NeonNode = element(
		<T value={{ accent: "blue" }}>
			<div>{useContext(T).accent}</div>
		</T>
	);
	assert renderToString(app) === "<div>blue</div>", "ssr saw the provided value: " + renderToString(app);
}

test "the value is read once when the provider mounts, so a signal in it does not reach the consumer" {
	const T = createContext<Theme>({ accent: "red" });
	const [accent, setAccent] = createSignal("blue");
	let reads = 0;
	function pick(): string {
		reads = reads + 1;
		return accent();
	}
	const root: MockNode = mockNode("root");
	const app: NeonNode = element(
		<T value={{ accent: pick() }}>
			<div>{useContext(T).accent}</div>
		</T>
	);
	render(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div>blue</div></root>", "initial read: " + mockToString(root);
	setAccent("green");
	assert mockToString(root) === "<root><div>blue</div></root>", "the provided value stayed the mount-time one: " + mockToString(root);
	assert reads === 1, "the value expression ran once: " + reads.toString();
}

test "a provider mounted inside an effect does not subscribe the effect to the value" {
	const T = createContext<Theme>({ accent: "red" });
	const [accent, setAccent] = createSignal("blue");
	const [on, setOn] = createSignal(true);
	const root: MockNode = mockNode("root");
	const app: NeonNode = element(
		<Show when={on()}>
			<T value={{ accent: accent() }}><span>{useContext(T).accent}</span></T>
		</Show>
	);
	render(app, mockHost(), root as unknown as HostNode);
	setAccent("green");
	assert mockToString(root) === "<root><span>blue</span></root>", "the signal read in the value did not re-mount the provider: " + mockToString(root);
	setOn(false);
	setOn(true);
	assert mockToString(root) === "<root><span>green</span></root>", "a new mount reads the signal again: " + mockToString(root);
}

test "a For row reads the provider above the list" {
	const T = createContext<Theme>({ accent: "red" });
	const [items, setItems] = createSignal<number[]>([1]);
	const root: MockNode = mockNode("root");
	const app: NeonNode = T.provider({
		value: accessor((): Theme => ({ accent: "blue" })),
		children: element(<ul>{For<number>({
			each: items,
			children: (n: number, i: Accessor<number>): NeonNode => <li>{useContext(T).accent + n.toString()}</li>,
		})}</ul>),
	});
	render(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><ul><li>blue1</li></ul></root>", "first row saw the provider: " + mockToString(root);
	setItems([1, 2]);
	assert mockToString(root) === "<root><ul><li>blue1</li><li>blue2</li></ul></root>", "a row added later saw the provider: " + mockToString(root);
}

test "a position-keyed For row reads the provider above the list" {
	const T = createContext<Theme>({ accent: "red" });
	const [items, setItems] = createSignal<number[]>([1, 2]);
	const root: MockNode = mockNode("root");
	const app: NeonNode = T.provider({
		value: accessor((): Theme => ({ accent: "blue" })),
		children: element(<ul>{ForUnkeyed<number>({
			each: items,
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
	const app: NeonNode = T.provider({
		value: accessor((): Theme => ({ accent: "blue" })),
		children: element(<ul>{For<number>({
			each: items,
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
		<T value={{ accent: "blue" }}>
			<div>{useContext(T).accent}</div>
		</T>
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
			<T value={{ accent: "blue" }}><span>{useContext(T).accent}</span></T>
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
				<T value={{ accent: "A" }}><span>a</span></T>
			</Show>
			{T.provider({
				value: accessor((): Theme => ({ accent: "B" })),
				children: element(<ul>{For<number>({
					each: items,
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
	const app: NeonNode = T.provider({
		value: accessor((): Theme => ({ accent: "outer" })),
		children: element(
			<div>
				<Show when={inner()}>
					<T value={{ accent: "inner" }}><span>i</span></T>
				</Show>
				<ul>{For<number>({
					each: items,
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
		<T value={{ accent: "blue" }}>
			<Probe tag="p" />
		</T>
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
	const app: NeonNode = T.provider({ value: accessor((): Theme => ({ accent: "blue" })), children: consumer });
	render(app, mockHost(), mockNode("root") as unknown as HostNode);
	assert seen === "blue", "the root saw the provider: " + seen;
}

test "an Errored scope under a provider reads it" {
	const T = createContext<Theme>({ accent: "red" });
	let seen = "";
	const consumer: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		Errored({ children: (h: Host, p: HostNode, b: HostNode | null): void => { seen = useContext(T).accent; }, fallback: (err: Accessor<Error>, reset: () => void): NeonNode => (h: Host, p: HostNode, b: HostNode | null): void => {} })(host, parent, before);
	};
	const app: NeonNode = T.provider({ value: accessor((): Theme => ({ accent: "blue" })), children: consumer });
	render(app, mockHost(), mockNode("root") as unknown as HostNode);
	assert seen === "blue", "the Errored scope saw the provider: " + seen;
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
	const middle: NeonNode = B.provider({ value: accessor((): number => 7), children: consumer });
	const app: NeonNode = A.provider({ value: accessor((): Theme => ({ accent: "blue" })), children: middle });
	render(app, mockHost(), mockNode("root") as unknown as HostNode);
	assert seen === "blue" && inner === 7, "both providers answered: " + seen + " " + inner.toString();
}

interface Where { here: Accessor<string>; }
const [nowhere, _nowhere] = createSignal("none");
const WhereContext = createContext<Where>({ here: nowhere });

function WhereReader(): NeonNode {
	const where = useContext(WhereContext);
	return <p>{where.here()}</p>;
}

test "a signal reaches a reader through a context as a field of the value" {
	const [place, setPlace] = createSignal("a");
	const root = mockNode("root");
	render(<WhereContext value={{ here: place }}><WhereReader /></WhereContext>, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><p>a</p></root>", mockToString(root);
	setPlace("b");
	assert mockToString(root) === "<root><p>b</p></root>", mockToString(root);
}

const ThemeContext = createContext<Theme>({ accent: "light" });

function ThemeText(): NeonNode {
	return element(<div>{useContext(ThemeContext).accent}</div>);
}

function ThemeShow(): NeonNode {
	return element(<Show when={true}><div>{useContext(ThemeContext).accent}</div></Show>);
}

test "a provider with a component child feeds it" {
	const root = mockNode("root");
	render(element(<ThemeContext value={{ accent: "dark" }}><ThemeText /></ThemeContext>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div>dark</div></root>", mockToString(root);
}

test "a provider with a component whose body is a Show feeds it" {
	const root = mockNode("root");
	render(element(<ThemeContext value={{ accent: "dark" }}><ThemeShow /></ThemeContext>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div>dark</div></root>", mockToString(root);
}

test "a provider with several children feeds the component among them" {
	const root = mockNode("root");
	render(element(<ThemeContext value={{ accent: "dark" }}><div>Hi</div><ThemeText /></ThemeContext>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div>Hi</div><div>dark</div></root>", mockToString(root);
}

test "a provider with several children feeds a Show among them" {
	const root = mockNode("root");
	render(element(<ThemeContext value={{ accent: "dark" }}><div>Hi</div><ThemeShow /></ThemeContext>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div>Hi</div><div>dark</div></root>", mockToString(root);
}

test "a provider with a child built in an expression feeds it" {
	const child: NeonNode = element(<ThemeText />);
	const root = mockNode("root");
	render(element(<ThemeContext value={{ accent: "dark" }}><div>Hi</div>{child}</ThemeContext>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div>Hi</div><div>dark</div></root>", mockToString(root);
}

test "a provider with a Show child feeds a row that appears after the mount" {
	const [on, setOn] = createSignal(false);
	const root = mockNode("root");
	render(element(<ThemeContext value={{ accent: "dark" }}><Show when={on()}><ThemeText /></Show></ThemeContext>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root></root>", mockToString(root);
	setOn(true);
	assert mockToString(root) === "<root><div>dark</div></root>", "a row mounted later still sits under the provider: " + mockToString(root);
}

test "roots nested under a provider forward the value" {
	const T = createContext<Theme>({ accent: "red" });
	let outer = "";
	let inner = "";
	const consumer: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		createRoot((dispose: Dispose): number => {
			outer = useContext(T).accent;
			createRoot((disposeInner: Dispose): number => {
				inner = useContext(T).accent;
				return 0;
			});
			return 0;
		});
	};
	render(T.provider({ value: accessor((): Theme => ({ accent: "blue" })), children: consumer }), mockHost(), mockNode("root") as unknown as HostNode);
	assert outer === "blue" && inner === "blue", "both roots saw it: " + outer + " " + inner;
}

test "a provider mounted by a consumer is not seen by the consumer's own owner" {
	const T = createContext<Theme>({ accent: "red" });
	let after = "";
	const leaf: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {};
	const consumer: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		T.provider({ value: accessor((): Theme => ({ accent: "inner" })), children: leaf })(host, parent, before);
		after = useContext(T).accent;
	};
	render(T.provider({ value: accessor((): Theme => ({ accent: "outer" })), children: consumer }), mockHost(), mockNode("root") as unknown as HostNode);
	assert after === "outer", "the reader above the inner provider still saw the outer one: " + after;
}

test "a default-form context read under a bare root returns the default, inferred from the argument" {
	const tone = createContext("light");
	const size = createContext(14);
	let seen = "";
	let px = 0;
	createRoot((dispose: Dispose): number => {
		seen = useContext(tone);
		px = useContext(size);
		return 0;
	});
	assert seen === "light" && px === 14, "defaults came back: " + seen + " " + px.toString();
}

test "a null default is a value, not an absent one" {
	const T = createContext<Theme | null>(null);
	let seen: Theme | null = { accent: "x" };
	createRoot((dispose: Dispose): number => {
		seen = useContext(T);
		return 0;
	});
	assert seen === null, "the null default came back instead of throwing";
}

test "a default-less context read without a provider throws ContextNotFoundError" {
	const T = createContext<Theme>();
	let caught: Error | null = null;
	try {
		createRoot((dispose: Dispose): Theme => useContext(T));
	} catch (e) {
		caught = e;
	}
	assert caught !== null, "the read did not throw";
	assert (caught as Error) instanceof ContextNotFoundError, "the error is ContextNotFoundError: " + (caught as Error).message;
}

test "a default-less context of a scalar throws the same way" {
	const T = createContext<number>();
	let caught: Error | null = null;
	try {
		createRoot((dispose: Dispose): number => useContext(T));
	} catch (e) {
		caught = e;
	}
	assert caught !== null && caught instanceof ContextNotFoundError, "a number context without a provider throws ContextNotFoundError";
}

test "a nullable default-less context still throws, where an explicit null default does not" {
	const absent = createContext<Theme | null>();
	const present = createContext<Theme | null>(null);
	let thrown = false;
	let value: Theme | null = { accent: "x" };
	try {
		createRoot((dispose: Dispose): Theme | null => useContext(absent));
	} catch (e) {
		thrown = e instanceof ContextNotFoundError;
	}
	createRoot((dispose: Dispose): number => {
		value = useContext(present);
		return 0;
	});
	assert thrown, "no default reads as absent even when T admits null";
	assert value === null, "createContext(null) is a default";
}

test "a provider of null feeds a nullable default-less context" {
	const T = createContext<Theme | null>();
	let seen: Theme | null = { accent: "x" };
	const consumer: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		seen = useContext(T);
	};
	render(T.provider({ value: accessor((): Theme | null => null), children: consumer }), mockHost(), mockNode("root") as unknown as HostNode);
	assert seen === null, "a provided null is a value";
}

interface Todos { count: number; }

test "a default-less context reads as T under its provider" {
	const T = createContext<Todos>();
	const root = mockNode("root");
	render(element(<T value={{ count: 3 }}><b>{useContext(T).count.toString()}</b></T>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><b>3</b></root>", mockToString(root);
}

test "a component under a default-less provider throws ContextNotFoundError when mounted without it" {
	const T = createContext<Todos>();
	function Need(): NeonNode {
		return element(<b>{useContext(T).count.toString()}</b>);
	}
	let caught: Error | null = null;
	try {
		render(element(<Need />), mockHost(), mockNode("root") as unknown as HostNode);
	} catch (e) {
		caught = e;
	}
	resetErrorHalt();
	assert caught !== null && caught instanceof ContextNotFoundError, "mounting the reader without its provider throws ContextNotFoundError";
}

test "a read outside any owner throws NoOwnerError, with or without a default" {
	const withDefault = createContext<Theme>({ accent: "red" });
	const without = createContext<Theme>();
	let first: Error | null = null;
	let second: Error | null = null;
	try { useContext(withDefault); } catch (e) { first = e; }
	try { useContext(without); } catch (e) { second = e; }
	assert first !== null && first instanceof NoOwnerError, "a default does not stand in for an owner";
	assert second !== null && second instanceof NoOwnerError, "no default and no owner: the owner is what is missing";
}

test "renderToString reads the default and throws without a provider when there is none" {
	const withDefault = createContext<Theme>({ accent: "red" });
	const without = createContext<Theme>();
	assert renderToString(element(<div>{useContext(withDefault).accent}</div>)) === "<div>red</div>", "ssr read the default";
	let caught: Error | null = null;
	try {
		renderToString(element(<div>{useContext(without).accent}</div>));
	} catch (e) {
		caught = e;
	}
	assert caught !== null && caught instanceof ContextNotFoundError, "ssr threw ContextNotFoundError for the default-less read";
}

test "renderToString nests providers and the inner one wins" {
	const T = createContext<Theme>();
	const app: NeonNode = element(
		<T value={{ accent: "outer" }}>
			<p>{useContext(T).accent}</p>
			<T value={{ accent: "inner" }}><p>{useContext(T).accent}</p></T>
		</T>
	);
	assert renderToString(app) === "<p>outer</p><p>inner</p>", renderToString(app);
}

test "what the value expression registers is owned by the provider and cleaned with its mount" {
	const T = createContext<Theme>({ accent: "red" });
	let cleanups = 0;
	function made(): Theme {
		onCleanup((): void => {
			cleanups = cleanups + 1;
		});
		return { accent: "made" };
	}
	const root = mockNode("root");
	const dispose = render(element(<T value={made()}><div>{useContext(T).accent}</div></T>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div>made</div></root>", mockToString(root);
	assert cleanups === 0, "alive while mounted";
	dispose();
	assert cleanups === 1, "the provider's mount disposed it: " + cleanups.toString();
}

test "a provider a Show drops disposes its value and builds a new one when it returns" {
	const T = createContext<Theme>({ accent: "red" });
	const [on, setOn] = createSignal(true);
	let built = 0;
	let cleanups = 0;
	function made(): Theme {
		built = built + 1;
		onCleanup((): void => {
			cleanups = cleanups + 1;
		});
		return { accent: "v" + built.toString() };
	}
	const root = mockNode("root");
	render(element(<Show when={on()}><T value={made()}><span>{useContext(T).accent}</span></T></Show>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><span>v1</span></root>", mockToString(root);
	setOn(false);
	assert cleanups === 1, "dropping the provider disposed the value: " + cleanups.toString();
	setOn(true);
	assert mockToString(root) === "<root><span>v2</span></root>", "the return built a fresh value: " + mockToString(root);
	assert built === 2 && cleanups === 1, "built " + built.toString() + " cleaned " + cleanups.toString();
}

test "the value expression sees the provider above it, not its own" {
	const T = createContext<Theme>({ accent: "red" });
	const root = mockNode("root");
	const app: NeonNode = element(
		<T value={{ accent: "outer" }}>
			<T value={{ accent: useContext(T).accent + "+inner" }}><div>{useContext(T).accent}</div></T>
		</T>
	);
	render(app, mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div>outer+inner</div></root>", mockToString(root);
}

interface Palette { tone: Context<Theme>; }
const Palettes: Palette = { tone: createContext<Theme>() };

test "a context held in a field is a tag through the dotted path" {
	const root = mockNode("root");
	render(element(<Palettes.tone value={{ accent: "held" }}><b>{useContext(Palettes.tone).accent}</b></Palettes.tone>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><b>held</b></root>", mockToString(root);
}
