import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { renderToString } from "../../src/render/ssr";
import { ContextNotFoundError, createContext, useContext } from "../../src/render/context";

interface Theme { accent: string; }

test "renderToString sees through a provider" {
	const T = createContext<Theme>({ accent: "red" });
	const app: NeonNode = element(
		<T value={{ accent: "blue" }}>
			<div>{useContext(T).accent}</div>
		</T>
	);
	assert renderToString(app) === "<div>blue</div>", "ssr saw the provided value: " + renderToString(app);
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
