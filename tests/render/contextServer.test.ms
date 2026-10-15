import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { renderToString } from "../../src/render/ssr";
import { createContext, useContext } from "../../src/render/context";

interface Theme { accent: string; }

test "renderToString sees through a provider" {
	const T = createContext<Theme>({ accent: "red" });
	const app: NeonNode = element(
		<T.Provider value={{ accent: "blue" }}>
			<div>{useContext(T).accent}</div>
		</T.Provider>
	);
	assert renderToString(app) === "<div>blue</div>", "ssr saw the provided value: " + renderToString(app);
}
