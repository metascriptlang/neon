// Solid's server lazy waits for the module before the render settles (packages/solid/src/server/component.ts:269); here the async memo's server slot carries that wait.
import { sleepAsync } from "std/core/promise";
import { el, text, NeonNode } from "../../src/render/node";
import { createComponent } from "../../src/render/component";
import { lazyModule } from "../../src/render/lazy";
import { Loading } from "../../src/macros/ui/flow";
import { renderToString, renderToStream } from "../../src/render/ssr";

const waiting: NeonNode = el("b", [], [], text("loading"));
const loads = [0];

function Greeting(props: { label: string }): NeonNode {
	return el("p", [], [], text("hello " + props.label));
}

async function loadGreeting(): Promise<(props: { label: string }) => NeonNode> {
	loads[0] = loads[0] + 1;
	await sleepAsync(5);
	return Greeting;
}

test "renderToStream waits for the lazy module and writes the page, loading it once" {
	const Lazy = lazyModule("tests/render/lazy/greeting", loadGreeting);
	const out = await renderToStream(Loading({ children: createComponent(Lazy, { label: "ssr" }), fallback: waiting }));
	assert out.html === "<p>hello ssr</p><!---->", out.html;
	assert loads[0] === 1, "one load: " + loads[0].toString();
}

test "renderToString writes the fallback for a module that has not loaded" {
	const Lazy = lazyModule("tests/render/lazyServer/sync", loadGreeting);
	const html = renderToString(Loading({ children: createComponent(Lazy, { label: "sync" }), fallback: waiting }));
	assert html.includes("<b>loading</b>") && !html.includes("hello"), html;
	await sleepAsync(12);
}
