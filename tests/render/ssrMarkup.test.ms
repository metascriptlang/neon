import { createSignal } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { onCleanup } from "../../src/core/cleanup";
import { Host, HostNode, NeonNode } from "../../src/render/hostTypes";
import { el, attr, text, dynText } from "../../src/render/node";
import { renderToString } from "../../src/render/ssr";

test "SSR emits HTML void elements without end tags" {
	const tags = ["area", "base", "br", "col", "embed", "hr", "img", "input",
		"link", "meta", "param", "source", "track", "wbr"];
	for (const tag of tags) {
		assert renderToString(el(tag, [attr("id", "one")], [], null)) ===
			"<" + tag + " id=\"one\">";
	}
	assert renderToString(el("div", [], [], null)) === "<div></div>";
}

test "SSR writes input attributes with the values the DOM host writes" {
	const open = renderToString(el("textinput", [attr("editable", "true"), attr("autoFocus", "false"),
		attr("secureTextEntry", "true"), attr("keyboardType", "number-pad"),
		attr("autoCorrect", "false"), attr("maxLength", "4"), attr("blurOnSubmit", "true")], [], null));
	assert open === "<input type=\"password\" inputmode=\"numeric\" autocorrect=\"off\" maxlength=\"4\">", open;
	const locked = renderToString(el("textinput", [attr("editable", "false"), attr("autoFocus", "true"),
		attr("secureTextEntry", "false"), attr("accessibilityRole", "text")], [], null));
	assert locked === "<input readonly=\"\" autofocus=\"\" type=\"text\">", locked;
}

test "a throwing SSR mount disposes effects and cleanup" {
	const [read, write] = createSignal<int32>(0);
	let runs: int32 = 0;
	let cleaned: int32 = 0;
	const failing: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		createEffect((): void => { read(); runs += 1; });
		onCleanup((): void => { cleaned += 1; });
		throw new Error("SSR mount failed");
	};
	let message = "";
	try { renderToString(failing); }
	catch (error) { message = (error as Error).message; }
	assert message === "SSR mount failed";
	write(1);
	assert runs === 1 && cleaned === 1;
	assert renderToString(el("p", [], [], text("next"))) === "<p>next</p>";
}

test "a void element with children fails and disposes mounted resources" {
	let cleaned: int32 = 0;
	const invalid: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		onCleanup((): void => { cleaned += 1; });
		el("input", [], [], text("invalid"))(host, parent, before);
	};
	let message = "";
	try { renderToString(invalid); }
	catch (error) { message = (error as Error).message; }
	assert message.indexOf("input") >= 0;
	assert cleaned === 1;
}

function both(a: NeonNode, b: NeonNode): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		a(host, parent, before);
		b(host, parent, before);
	};
}

test "SSR marks the text nodes an HTML parse would drop or merge" {
	assert renderToString(el("p", [], [], dynText((): string => ""))) === "<p><!----></p>", "an empty text node";
	assert renderToString(el("p", [], [], both(text("a"), dynText((): string => "b")))) ===
		"<p>a<!--!-->b</p>", "two text nodes in a row";
	assert renderToString(el("p", [], [], both(text("a"), both(dynText((): string => ""), text("b"))))) ===
		"<p>a<!---->b</p>", "an empty one between two";
	assert renderToString(el("p", [], [], both(text("a"), both(el("b", [], [], null), text("c"))))) ===
		"<p>a<b></b>c</p>", "an element between two needs no mark";
}

test "SSR writes no marks where the parser reads comments as text" {
	for (const tag of ["title", "textarea", "style", "script"]) {
		const html = renderToString(el(tag, [], [], both(text("a"), both(dynText((): string => ""), dynText((): string => "b")))));
		assert html === "<" + tag + ">ab</" + tag + ">", html;
	}
}
