import { createSignal } from "../../src/core/signal";
import { createRenderEffect } from "../../src/core/effect";
import { Cleanup } from "../../src/core/types";
import { onCleanup } from "../../src/core/cleanup";
import { Host, HostNode, NeonNode } from "../../src/render/hostTypes";
import { el, attr, text, dynText } from "../../src/render/node";
import { renderToString, renderToMarkup } from "../../src/render/ssr";

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

test "SSR writes a scrollview as the div, classes and scroll style the DOM host builds" {
	const page = renderToMarkup(el("scrollview", [attr("horizontal", "true"),
		attr("showsHorizontalScrollIndicator", "false")], [], null));
	assert page.html === "<div horizontal=\"true\" showsHorizontalScrollIndicator=\"false\" " +
		"class=\"neon-view neon-scrollview neon-hide-horizontal\" " +
		"style=\"overflow-x:auto;overflow-y:hidden;touch-action:pan-x;scrollbar-width:auto;\"></div>", page.html;
	assert page.css.indexOf(".neon-scrollview{overflow-x:hidden;overflow-y:auto}") >= 0, page.css;
	assert page.css.indexOf(".neon-view)") >= 0, page.css;
	const plain = renderToString(el("scrollview", [], [], null));
	assert plain === "<div class=\"neon-view neon-scrollview\" " +
		"style=\"overflow-x:hidden;overflow-y:auto;touch-action:pan-y;scrollbar-width:auto;\"></div>", plain;
}

test "SSR writes Text numberOfLines as the clamp classes and their rules" {
	const page = renderToMarkup(el("text", [attr("numberOfLines", "2")], [], null));
	assert page.html === "<span class=\"neon-text neon-lines neon-lines-2\"></span>", page.html;
	assert page.css.indexOf(".neon-lines-2{-webkit-line-clamp:2}") >= 0, page.css;
	assert page.css.indexOf(".neon-lines{display:-webkit-box") >= 0, page.css;
	const free = renderToString(el("text", [attr("numberOfLines", "0")], [], null));
	assert free === "<span class=\"neon-text\"></span>", free;
	const marked = renderToString(el("text", [attr("class", "x&y"), attr("numberOfLines", "2\"")], [], null));
	assert marked === "<span class=\"x&amp;y neon-text neon-lines neon-lines-2&quot;\"></span>", "each class escaped once: " + marked;
}

test "SSR writes Switch and ActivityIndicator as the elements, classes and rules the DOM host builds" {
	const on = renderToMarkup(el("switch", [attr("value", "true"), attr("disabled", "false"),
		attr("thumbColor", "#fff")], [], null));
	assert on.html === "<input type=\"checkbox\" role=\"switch\" checked=\"\">", on.html;
	const off = renderToString(el("switch", [attr("value", "false"), attr("disabled", "true"),
		attr("accessibilityRole", "button")], [], null));
	assert off === "<input type=\"checkbox\" role=\"button\" disabled=\"\">", off;
	const spinner = renderToMarkup(el("activityindicator", [attr("animating", "false"),
		attr("hidesWhenStopped", "false"), attr("accessibilityRole", "progressbar")], [], null));
	assert spinner.html === "<div data-animating=\"false\" data-hides=\"false\" role=\"progressbar\" " +
		"class=\"neon-activity\"></div>", spinner.html;
	assert spinner.css.indexOf(".neon-activity[data-animating=false]{animation:none}") >= 0, spinner.css;
	assert on.css.indexOf(".neon-activity{") >= 0, on.css;
}

test "SSR writes a multiline TextInput as a textarea holding its value" {
	const fresh = renderToMarkup(el("multilinetextinput", [attr("defaultValue", "note"),
		attr("multiline", "true"), attr("placeholder", "Write")], [], null));
	assert fresh.html === "<textarea placeholder=\"Write\" class=\"neon-textarea\">note</textarea>", fresh.html;
	assert fresh.css.indexOf(".neon-textarea{field-sizing:content;resize:none}") >= 0, fresh.css;
	const value = renderToString(el("multilinetextinput", [attr("value", "\n<b> & co"),
		attr("defaultValue", "ignored")], [], null));
	assert value === "<textarea class=\"neon-textarea\">\n\n&lt;b&gt; &amp; co</textarea>", value;
	const empty = renderToString(el("multilinetextinput", [attr("value", ""), attr("defaultValue", "kept")], [], null));
	assert empty === "<textarea class=\"neon-textarea\">kept</textarea>", empty;
}

test "a throwing SSR mount disposes effects and cleanup" {
	const [read, write] = createSignal<int32>(0);
	let runs: int32 = 0;
	let cleaned: int32 = 0;
	const failing: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		createRenderEffect<int32>(
			(p: int32 | null): int32 => read(),
			(v: int32, p: int32 | null): Cleanup | null => { runs += 1; return null; },
		);
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
