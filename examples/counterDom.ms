import { createSignal } from "../src/core/signal";
import { el, attr, evt, text, dynText } from "../src/render/node";
import { element } from "../src/macros/ui/element";
import { renderToHost } from "../src/render/host";
import { domHost, documentBody } from "../src/platform/browser/dom";

function main(): void {
	const [count, setCount] = createSignal(0);
	const app = element(
		<div>
			<p>Count: {count() + ""}</p>
			<button onClick={() => setCount(count() + 1)}>+</button>
		</div>
	);
	renderToHost(app, domHost(), documentBody());
}
main();
