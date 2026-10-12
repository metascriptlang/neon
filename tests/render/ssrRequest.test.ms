import { onCleanup } from "../../src/core/cleanup";
import { Host, HostNode, NeonNode } from "../../src/render/hostTypes";
import { el } from "../../src/render/node";
import { renderToMarkup } from "../../src/render/ssr";
import { cssRuleCount, registerCss, resetCss } from "../../src/render/sheet";
import { RN_WEB_BASE_CSS } from "../../src/render/web";

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
