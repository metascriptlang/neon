import { onCleanup } from "../../src/core/cleanup";
import { Host, HostNode, NeonNode } from "../../src/render/hostTypes";
import { el } from "../../src/render/node";
import { renderToMarkup } from "../../src/render/ssr";
import { render, mockHost, mockNode, mockToString } from "../../src/render/host";
import { bindText } from "../../src/render/bind";
import { createUniqueId } from "../../src/core/owner";
import { createEffect } from "../../src/core/effect";
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

function labelled(label: string): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const id = createUniqueId();
		const text = host.createElement("label");
		host.setAttr(text, "for", id);
		const caption = host.createText("");
		bindText(host, caption, (): string => label);
		host.append(text, caption);
		const input = host.createElement("input");
		host.setAttr(input, "id", id);
		host.insertBefore(parent, text, before);
		host.insertBefore(parent, input, before);
	};
}

function form(): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		labelled("name")(host, parent, before);
		createEffect(() => { labelled("mail")(host, parent, before); });
	};
}

test "createUniqueId draws the same ids in every request for one tree" {
	const first = renderToMarkup(form()).html;
	assert first === "<label for=\"0\">name</label><input id=\"0\">" +
		"<label for=\"10\">mail</label><input id=\"10\">", first;
	assert renderToMarkup(classed("a", "one")).html === "<p class=\"a\">one</p>", "another tree in between";
	assert renderToMarkup(form()).html === first, "the second request drew different ids";
}

test "a client render outside a request draws ids that never repeat" {
	const host = mockHost();
	const a = mockNode("root");
	const b = mockNode("root");
	const disposeA = render(form(), host, a as unknown as HostNode);
	const disposeB = render(form(), host, b as unknown as HostNode);
	const htmlA = mockToString(a);
	const htmlB = mockToString(b);
	disposeA();
	disposeB();
	assert htmlA.includes("for=\"cl-") && htmlA !== htmlB, htmlA + " | " + htmlB;
}
