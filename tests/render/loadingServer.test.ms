import { el, text, dynText, NeonNode } from "../../src/render/node";
import { Host, HostNode } from "../../src/render/hostTypes";
import { createAsyncMemo } from "../../src/core/memo";
import { Loading, Errored } from "../../src/macros/ui/flow";
import { renderToString } from "../../src/render/ssr";
import { Gate, gated, release } from "../core/asyncClock";

const waiting: NeonNode = el("b", [], [], text("loading"));

// server/hydration.ts:58 createLoadingBoundary: with no hydration context a synchronous render is the core boundary
test "a synchronous server render writes the content of a Loading whose reads are ready" {
	const html = renderToString(Loading({ children: el("p", [], [], text("ready")), fallback: waiting }));
	assert html.includes("<p>ready</p>") && !html.includes("loading"), html;
}

test "a synchronous server render writes the fallback of a Loading with a pending read and none of its content" {
	const gate = new Gate();
	const app: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, 9));
		const content: NeonNode = (h: Host, p: HostNode, b: HostNode | null): void => {
			text("partial")(h, p, b);
			el("p", [], [], dynText((): string => data().toString()))(h, p, b);
		};
		Loading({ children: content, fallback: waiting })(host, parent, before);
	};
	const html = renderToString(app);
	assert html.includes("<b>loading</b>") && !html.includes("partial") && !html.includes("<p>"), html;
	await release(gate);
}

test "a Loading without a fallback writes nothing of its pending content" {
	const gate = new Gate();
	const app: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, 9));
		Loading({ children: el("p", [], [], dynText((): string => data().toString())) })(host, parent, before);
	};
	const html = renderToString(app);
	assert !html.includes("<p>"), html;
	await release(gate);
}

test "a pending read inside an Errored inside a Loading reaches the Loading" {
	const gate = new Gate();
	const app: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, 9));
		const inner = Errored({
			children: el("p", [], [], dynText((): string => data().toString())),
			fallback: (err, reset): NeonNode => el("i", [], [], text("failed")),
		});
		Loading({ children: inner, fallback: waiting })(host, parent, before);
	};
	const html = renderToString(app);
	assert html.includes("<b>loading</b>") && !html.includes("failed"), html;
	await release(gate);
}

test "an Errored and a Loading each end in the one marker their region writes on the client" {
	const errored = renderToString(Errored({ children: el("p", [], [], text("x")), fallback: (err, reset): NeonNode => text("f") }));
	const loading = renderToString(Loading({ children: el("p", [], [], text("x")), fallback: waiting }));
	assert errored === loading && errored === "<p>x</p><!---->", "[" + errored + "][" + loading + "]";
}
