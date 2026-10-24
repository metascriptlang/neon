import { sleepAsync } from "std/core/promise";
import { NeonNode } from "../../src/render/hostTypes";
import { MockNode, mockHost, mockToString, render } from "../../src/render/host";
import { el, text } from "../../src/render/node";
import { Loading, Show } from "../../src/macros/ui/flow";
import { createAsyncMemo } from "../../src/core/memo";
import { flush } from "../../src/core/runtime";
import { createSignal } from "../../src/core/signal";

async function later(): Promise<boolean> {
	await sleepAsync(20);
	return true;
}

function pendingShow(): NeonNode {
	return (h, p, b): void => {
		const ready = createAsyncMemo((prev: boolean | null): Promise<boolean> => later());
		Show({ when: ready, children: el("p", [], [], text("shown")) })(h, p, b);
	};
}

test "a Show whose condition is pending, at the top of a Loading's content, settles where the content moved" {
	const host = mockHost();
	const root = host.createElement("root");
	const dispose = render(Loading({ children: pendingShow(), fallback: el("b", [], [], text("wait")) }), host, root);
	flush();
	assert mockToString(root as unknown as MockNode).includes("<b>wait</b>"), mockToString(root as unknown as MockNode);
	await sleepAsync(60);
	flush();
	const out = mockToString(root as unknown as MockNode);
	assert out.includes("<p>shown</p>") && !out.includes("wait"), out;
	dispose();
}

test "a Show whose condition is pending, built in a region row swapped in later, settles where the content moved" {
	const host = mockHost();
	const root = host.createElement("root");
	const [on, setOn] = createSignal<boolean>(false);
	const node: NeonNode = Loading({
		children: Show({ when: on, children: pendingShow(), fallback: el("i", [], [], text("home")) }),
		fallback: el("b", [], [], text("wait")),
	});
	const dispose = render(node, host, root);
	flush();
	setOn(true);
	flush();
	await sleepAsync(60);
	flush();
	const out = mockToString(root as unknown as MockNode);
	assert out.includes("<p>shown</p>") && !out.includes("home") && !out.includes("wait"), out;
	dispose();
}
