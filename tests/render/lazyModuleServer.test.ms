import { el, text, NeonNode } from "../../src/render/node";
import { Host, HostNode } from "../../src/render/hostTypes";
import { lazyModule, createComponent } from "../../src/render/component";
import { serverContext } from "../../src/core/serverContext";
import { renderToStream } from "../../src/render/ssr";
import { Loading } from "../../src/macros/ui/flow";
import { Gate, gated, release } from "../core/asyncClock";

function Greeting(props: { label: string }): NeonNode {
	return el("p", [], [], text("hello " + props.label));
}

function shell(Page: (props: { label: string }) => NeonNode): NeonNode {
	return el("div", [], [], Loading({ children: createComponent(Page, { label: "ssr" }), fallback: el("b", [], [], text("loading")) }));
}

function loaderOf(gate: Gate): () => Promise<(props: { label: string }) => NeonNode> {
	return (): Promise<(props: { label: string }) => NeonNode> => gated(gate, Greeting);
}

test "a keyed lazy rendered on the server records its memo id and key on the server context" {
	const seen: string[] = [];
	const probe: NeonNode = (h: Host, p: HostNode, b: HostNode | null): void => {
		const ctx = serverContext();
		if (ctx !== null) { for (const key of ctx.modules.values()) { seen.push(key); } }
	};
	const gate = new Gate();
	const Served = lazyModule("tests/render/lazyPreload/ssr2", loaderOf(gate));
	const done = renderToStream((h: Host, p: HostNode, b: HostNode | null): void => { shell(Served)(h, p, b); probe(h, p, b); });
	await release(gate);
	const out = await done;
	assert seen.includes("tests/render/lazyPreload/ssr2"), "keys seen: " + seen.join(",");
	assert out.html.includes("hello ssr"), out.html;
}
