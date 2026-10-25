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

function between(s: string, open: string, close: string): string {
	const at = s.indexOf(open);
	if (at < 0) { return "absent: " + open; }
	return s.slice(at + open.length, s.indexOf(close, at + open.length));
}

test "the records of a served lazy list its key in the page's module table under the lazy's hydration id" {
	const gate = new Gate();
	const Served = lazyModule("tests/render/lazyModuleServer/table", loaderOf(gate));
	const done = renderToStream(shell(Served));
	await release(gate);
	const out = await done;
	const id = between(out.records, ".r[\"", "\"]=\"true\"");
	assert out.records.includes("(self._$HY||(self._$HY={r:{},e:{},m:{}})).m[\"" + id + "\"]=\"tests/render/lazyModuleServer/table\"</script>"), out.records;
}

test "a streamed page writes each lazy's module entry once, in the first piece written after the lazy rendered" {
	const gate = new Gate();
	const Served = lazyModule("tests/render/lazyModuleServer/streamed", loaderOf(gate));
	const chunks: string[] = [];
	const r = renderToStream(shell(Served));
	r.pipe({ write: (chunk: string): void => { chunks.push(chunk); }, end: (): void => {} });
	await release(gate);
	await r;
	const entry = ".m[\"";
	let written = 0;
	for (const c of chunks) { written += c.split("\"]=\"tests/render/lazyModuleServer/streamed\"").length - 1; }
	assert written === 1, "one entry: " + chunks.join(" || ");
	assert chunks[0].includes(entry), "the shell's records carry it: " + chunks.join(" || ");
}
