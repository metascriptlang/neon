import { sleepAsync } from "std/core/promise";
import { createSignal } from "../../src/core/signal";
import { renderToStream } from "../../src/render/ssr";
import { NeonNode } from "../../src/render/hostTypes";
import { el, text } from "../../src/render/node";
import { Loading, Show } from "../../src/macros/ui/flow";
import { lazyModule } from "../../src/render/lazy";
import { createRequestRoutingHistory } from "../../src/navigation/routingHistory";
import { LayoutProps, RouterProvider, createRoutes, createRouter } from "../../src/navigation/router";

function Ownership(props: {}): NeonNode {
	return el("p", [], [], text("ownership"));
}

async function loadOwnership(): Promise<(props: {}) => NeonNode> {
	await sleepAsync(5);
	return Ownership;
}

const LazyOwnership = lazyModule<{}>("tests/navigation/routeLazyHoldServer/ownership", loadOwnership);
const LazyAlone = lazyModule<{}>("tests/navigation/routeLazyHoldServer/alone", loadOwnership);

const [open, setOpen] = createSignal<boolean>(true);

function SiteShell(props: LayoutProps): NeonNode {
	return <div>
		<header>top</header>
		<main><Loading fallback={el("b", [], [], text("loading"))}>{props.children}</Loading></main>
		<Show when={open()}><footer>end</footer></Show>
	</div>;
}

function BareShell(props: LayoutProps): NeonNode {
	return <main><Loading fallback={el("b", [], [], text("loading"))}>{props.children}</Loading></main>;
}

async function served(page: (props: {}) => NeonNode, shell: (props: LayoutProps) => NeonNode): Promise<string> {
	const made = createRouter(createRoutes([{ layout: shell, children: [{ path: "/ownership", component: page }] }]), createRequestRoutingHistory("/ownership"));
	if (!made.ok) { return "no router: " + made.error.toString(); }
	let html = "";
	try {
		const out = await renderToStream(<RouterProvider router={made.value} />);
		html = out.html;
	} catch (e) {
		html = "threw: " + e.message;
	}
	made.value.dispose();
	return html;
}

test "a Loading around a layout's outlet renders a lazy page on the server" {
	const html = await served(LazyOwnership, SiteShell);
	assert html.includes("<p>ownership</p>") && html.includes("<footer>end</footer>"), html;
	assert !html.includes("loading"), html;
}

test "a Loading that is the only child of the layout's main renders a lazy page on the server" {
	const html = await served(LazyAlone, BareShell);
	assert html.includes("<p>ownership</p>") && !html.includes("loading"), html;
}

test "a Loading around a layout's outlet renders an eager page on the server" {
	const html = await served(Ownership, BareShell);
	assert html.includes("<p>ownership</p>"), html;
}
