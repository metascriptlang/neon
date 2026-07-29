import { createSignal } from "../src/core/signal";
import { el, attr, evt, text, dynText, withStyle } from "../src/render/node";
import { element } from "../src/macros/ui/element";
import { renderToHost } from "../src/render/host";
import { domHost, documentBody } from "../src/platform/browser/dom";

function main(): void {
	const [count, setCount] = createSignal(0);
	const app = element(
		<div style={{ padding: 16, backgroundColor: "#1e1e2e", color: "#cdd6f4", borderRadius: 8 }}>
			<p>Count: {count() + ""}</p>
			<button onClick={() => setCount(count() + 1)}>+</button>
		</div>
	);
	renderToHost(app, domHost(), documentBody());
}
main();
