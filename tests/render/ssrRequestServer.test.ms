import { onCleanup } from "../../src/core/cleanup";
import { Host, HostNode, NeonNode } from "../../src/render/hostTypes";
import { el } from "../../src/render/node";
import { renderToMarkup } from "../../src/render/ssr";
import { render, mockHost, mockNode } from "../../src/render/host";
import { createUniqueId } from "../../src/core/owner";
import { cssRuleCount, registerCss, resetCss } from "../../src/render/sheet";
import { RN_WEB_BASE_CSS } from "../../src/render/web";
import { isServer } from "../../src/render/environment";
import { View, ViewHandle } from "../../src/components/primitives";
import { createSignal, Accessor } from "../../src/core/signal";
import { createList } from "../../src/core/list";
import { form } from "./requestForm";

function classed(id: string, label: string): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const node = host.createElement("p");
		const setClass = host.setStyleClass as (node: HostNode, id: string, css: string) => void;
		setClass(node, id, "." + id + "{color:red}");
		host.append(node, host.createText(label));
		host.insertBefore(parent, node, before);
	};
}

test "each request carries only the rules its own tree mounted" {
	resetCss();
	const first = renderToMarkup(classed("a", "one"));
	const second = renderToMarkup(classed("b", "two"));
	assert first.html === "<p class=\"a\">one</p>" && first.css === ".a{color:red}", first.css;
	assert second.html === "<p class=\"b\">two</p>" && second.css === ".b{color:red}", second.css;
	assert cssRuleCount() === 0, "the process-wide registry stays untouched";
}

test "a rule shared by several nodes is written once" {
	resetCss();
	const twice: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		classed("a", "one")(host, parent, before);
		classed("a", "two")(host, parent, before);
	};
	assert renderToMarkup(twice).css === ".a{color:red}";
}

test "rules registered outside a render reach every request" {
	resetCss();
	registerCss(":root", ":root{--gap:4px}");
	const first = renderToMarkup(classed("a", "one"));
	const second = renderToMarkup(classed("b", "two"));
	resetCss();
	assert first.css === ":root{--gap:4px}.a{color:red}", first.css;
	assert second.css === ":root{--gap:4px}.b{color:red}", second.css;
}

test "the base rule arrives with every request that renders a primitive" {
	resetCss();
	const first = renderToMarkup(el("view", [], [], null));
	const second = renderToMarkup(el("view", [], [], null));
	assert first.css === RN_WEB_BASE_CSS && second.css === RN_WEB_BASE_CSS, second.css;
	assert renderToMarkup(el("p", [], [], null)).css === "";
}

test "a render that throws leaves nothing in the next request" {
	resetCss();
	let cleaned: int32 = 0;
	const failing: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		classed("bad", "x")(host, parent, before);
		onCleanup((): void => { cleaned += 1; });
		throw new Error("request failed");
	};
	let message = "";
	try { renderToMarkup(failing); }
	catch (error) { message = (error as Error).message; }
	assert message === "request failed" && cleaned === 1;
	const next = renderToMarkup(classed("b", "two"));
	assert next.html === "<p class=\"b\">two</p>" && next.css === ".b{color:red}", next.css;
}

test "the top layer of one request is empty in the next" {
	let found: int32 = 0;
	const portal: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const top = (host.overlayRoot as (node: HostNode) => HostNode)(parent);
		if (host.firstChild(top) !== null) { found += 1; }
		host.append(top, host.createElement("div"));
	};
	renderToMarkup(portal);
	renderToMarkup(portal);
	assert found === 0;
}

test "createUniqueId draws the same ids in every request for one tree" {
	const first = renderToMarkup(form()).html;
	assert first === "<label for=\"0\">name</label><input id=\"0\">" +
		"<label for=\"10\">mail</label><input id=\"10\">", first;
	assert renderToMarkup(classed("a", "one")).html === "<p class=\"a\">one</p>", "another tree in between";
	assert renderToMarkup(form()).html === first, "the second request drew different ids";
}

test "a server render runs no ref" {
	let refs = 0;
	const count = (n: HostNode): void => { refs += 1; };
	const countView = (h: ViewHandle): void => { refs += 1; };
	const tree = (): NeonNode => <View><canvas ref={count}></canvas><View ref={countView}><p>x</p></View></View>;
	const html = renderToMarkup(tree()).html;
	assert html.indexOf("<canvas>") >= 0, html;
	assert refs === 0, "the server render ran " + refs.toString() + " refs";
}

test "isServer holds during a server render and not after one, thrown or not" {
	let during = false;
	const probe: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => { during = isServer(); };
	assert !isServer(), "before any render";
	renderToMarkup(probe);
	assert during && !isServer(), "during and after";
	const broken: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => { throw "broken page"; };
	let threw = false;
	try { renderToMarkup(broken); } catch (e) { threw = true; }
	assert threw && !isServer(), "after a render that threw";
}

const drawn: string[] = [];

function Drawn(): NeonNode {
	drawn.push(createUniqueId());
	return <p>x</p>;
}

function regions(): NeonNode {
	const [on, setOn] = createSignal(true);
	const list = createList<number>([7, 8]);
	return <View>
		<Drawn />
		<For each={[1, 2]}>{(n: number, i: Accessor<number>): NeonNode => <View><Drawn /><Show when={on}><Drawn /></Show></View>}</For>
		<Drawn />
		<For each={[3, 4]} keyed={false}>{(v: Accessor<number>, i: number): NeonNode => <Drawn />}</For>
		<ForList each={list}>{(v: Accessor<number>): NeonNode => <Drawn />}</ForList>
		<Errored fallback={(err: Accessor<Error>, reset: () => void): NeonNode => <Drawn />}>
			<Drawn />
			{failing}
		</Errored>
		<Drawn />
	</View>;
}

const failing: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
	throw new Error("fails while it mounts");
};

function drawnBy(paint: () => void): string {
	drawn.length = 0;
	paint();
	return drawn.join(" ");
}

test "the server draws the ids the client draws, inside every kind of region" {
	const server = drawnBy((): void => { renderToMarkup(regions()); });
	const client = drawnBy((): void => {
		const root = mockNode("root");
		const dispose = render(regions(), mockHost(), root as unknown as HostNode, "");
		dispose();
	});
	assert server === client, "server " + server + " | client " + client;
}
