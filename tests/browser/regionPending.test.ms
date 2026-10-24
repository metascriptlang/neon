import { domHost } from "../../src/platform/browser/dom";
import { HostNode, NeonNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { el, text } from "../../src/render/node";
import { Loading, Show } from "../../src/macros/ui/flow";
import { createAsyncMemo } from "../../src/core/memo";
import { flush } from "../../src/core/runtime";
import { createSignal } from "../../src/core/signal";
import { sleepAsync } from "std/core/promise";

extern function js(code: cstring): string from "String((0, eval)(#))";

extern class HTMLElement {
	innerHTML: string;
	extern remove(): void;
}

extern class document {
	static body: HTMLElement;
	static extern createElement(tag: cstring): HTMLElement;
}

async function later(): Promise<boolean> {
	await sleepAsync(20);
	return true;
}

test "a Show whose condition is pending, at the top of a Loading's content, settles in the DOM" {
	const root = document.createElement("div");
	const node: NeonNode = Loading({
		children: (h, p, b): void => {
			const ready = createAsyncMemo((prev: boolean | null): Promise<boolean> => later());
			Show({ when: ready, children: el("p", [], [], text("shown")) })(h, p, b);
		},
		fallback: el("b", [], [], text("wait")),
	});
	const dispose = render(node, domHost(), root as unknown as HostNode);
	flush();
	await sleepAsync(60);
	flush();
	assert root.innerHTML.indexOf("<p>shown</p>") >= 0, root.innerHTML;
	dispose();
}

test "a Show whose condition is pending, built in a region row swapped in later, settles in the DOM" {
	const root = document.createElement("div");
	const [on, setOn] = createSignal<boolean>(false);
	const node: NeonNode = Loading({
		children: Show({
			when: on,
			children: (h, p, b): void => {
				const ready = createAsyncMemo((prev: boolean | null): Promise<boolean> => later());
				Show({ when: ready, children: el("p", [], [], text("shown")) })(h, p, b);
			},
			fallback: el("i", [], [], text("home")),
		}),
		fallback: el("b", [], [], text("wait")),
	});
	const dispose = render(node, domHost(), root as unknown as HostNode);
	flush();
	setOn(true);
	flush();
	await sleepAsync(60);
	flush();
	assert root.innerHTML.indexOf("<p>shown</p>") >= 0, root.innerHTML;
	dispose();
}
