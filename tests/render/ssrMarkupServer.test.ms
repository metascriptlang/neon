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

test "SSR writes accessibilityState as the aria attributes the DOM host writes" {
	const all = renderToString(el("view", [attr("accessibilityState", "checked,selected,disabled,busy,expanded")], [], null));
	assert all === "<div aria-checked=\"true\" aria-selected=\"true\" aria-disabled=\"true\" aria-busy=\"true\" aria-expanded=\"true\" class=\"neon-view\"></div>", all;
	const button = renderToString(el("pressable", [attr("accessibilityState", "selected,disabled")], [], null));
	assert button === "<button aria-disabled=\"true\" aria-pressed=\"true\" class=\"neon-view\"></button>", button;
	const toggle = renderToString(el("pressable", [attr("accessibilityState", ""), attr("accessibilityRole", "togglebutton")], [], null));
	assert toggle === "<button aria-pressed=\"false\" role=\"button\" class=\"neon-view\"></button>", toggle;
	const tab = renderToString(el("pressable", [attr("accessibilityState", "selected"), attr("role", "tab")], [], null));
	assert tab === "<button aria-selected=\"true\" role=\"tab\" class=\"neon-view\"></button>", tab;
	const box = renderToString(el("pressable", [attr("role", "checkbox"), attr("accessibilityState", "checked")], [], null));
	assert box === "<button role=\"checkbox\" aria-checked=\"true\" class=\"neon-view\"></button>", box;
	const off = renderToString(el("view", [attr("accessibilityState", "unchecked,collapsed")], [], null));
	assert off === "<div aria-checked=\"false\" aria-expanded=\"false\" class=\"neon-view\"></div>", off;
	const mixed = renderToString(el("view", [attr("accessibilityState", "mixed")], [], null));
	assert mixed === "<div aria-checked=\"mixed\" class=\"neon-view\"></div>", mixed;
	const none = renderToString(el("view", [attr("accessibilityState", "")], [], null));
	assert none === "<div class=\"neon-view\"></div>", none;
}

test "SSR writes the RN accessibility props as react-native-web writes them" {
	const value = renderToString(el("view", [attr("accessibilityValue", ",10,3,three, of ten")], [], null));
	assert value === "<div aria-valuemax=\"10\" aria-valuenow=\"3\" aria-valuetext=\"three, of ten\" class=\"neon-view\"></div>", value;
	const live = renderToString(el("view", [attr("accessibilityLiveRegion", "none"), attr("accessibilityViewIsModal", "true"),
		attr("accessibilityLabelledBy", "a,b"), attr("focusable", "false")], [], null));
	assert live === "<div aria-live=\"off\" aria-modal=\"true\" aria-labelledby=\"a b\" tabindex=\"-1\" class=\"neon-view\"></div>", live;
	const hidden = renderToString(el("view", [attr("importantForAccessibility", "no-hide-descendants"), attr("focusable", "true")], [], null));
	assert hidden === "<div aria-hidden=\"true\" tabindex=\"0\" class=\"neon-view\"></div>", hidden;
	const shown = renderToString(el("view", [attr("accessibilityElementsHidden", "false"), attr("importantForAccessibility", "yes"),
		attr("accessibilityActions", "magicTap"), attr("role", "none")], [], null));
	assert shown === "<div role=\"presentation\" class=\"neon-view\"></div>", shown;
}

test "SSR writes nativeID as the DOM id, as react-native-web createDOMProps does" {
	const view = renderToString(el("view", [attr("nativeID", "title")], [], null));
	assert view === "<div id=\"title\" class=\"neon-view\"></div>", view;
	const scroll = renderToString(el("scrollview", [attr("nativeID", "feed")], [], null));
	assert scroll.startsWith("<div id=\"feed\" "), scroll;
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

test "SSR writes Image as the img, classes and rules the DOM host builds" {
	const page = renderToMarkup(el("image", [attr("source", "/a.png"), attr("resizeMode", "repeat"),
		attr("blurRadius", "2.5"), attr("accessibilityRole", "image"), attr("accessibilityLabel", "a\"b")], [], null));
	assert page.html.startsWith("<img src=\"/a.png\" data-resize=\"repeat\" role=\"img\" alt=\"a&quot;b\" aria-label=\"a&quot;b\" class=\"neon-image neon-tile-"), page.html;
	assert page.html.indexOf(" neon-blur-25\">") > 0 && page.html.indexOf("<image") < 0, page.html;
	assert page.css.indexOf(".neon-image{object-fit:cover}") >= 0 && page.css.indexOf(".neon-blur-25{filter:blur(2.5px)}") >= 0, page.css;
	assert page.css.indexOf("{background-image:url(\"/a.png\");background-repeat:repeat;") >= 0, page.css;
	const plain = renderToString(el("image", [], [], null));
	assert plain === "<img class=\"neon-image\">", plain;
	const still = renderToString(el("image", [attr("source", "/a.png"), attr("resizeMode", "contain"), attr("blurRadius", "0")], [], null));
	assert still === "<img src=\"/a.png\" data-resize=\"contain\" class=\"neon-image\">", still;
}

test "SSR keeps a tiled source from leaving the style element or its string" {
	const page = renderToMarkup(el("image", [attr("source", "/a\"</style><b>\n.png"), attr("resizeMode", "repeat")], [], null));
	assert page.css.indexOf("url(\"/a\\\"\\3c /style>\\3c b>\\a .png\")") >= 0, page.css;
	assert page.css.indexOf("</style><b>") < 0, page.css;
}

test "SSR writes Svg with the prefix, viewBox and markup the DOM host draws from its display list" {
	const list = "V 0 0 20 10 5 0 M 0 0 L 5 0 L 5 5 L 0 5 Z F c 255 0 0 1 S n E 0 O";
	const page = renderToString(el("view", [], [], el("svg", [attr("displayList", list), attr("accessibilityLabel", "box")], [], null)));
	assert page.indexOf("<svg data-neon-svg=\"neon-svg1\" viewBox=\"0 0 20 10\" preserveAspectRatio=\"xMidYMid meet\" aria-label=\"box\" class=\"neon-view\">") >= 0, page;
	assert page.indexOf("<path d=\"M 0 0 L 5 0 L 5 5 L 0 5 Z\"") >= 0 && page.indexOf("displayList") < 0, page;
	const twice = renderToString(el("view", [], [], el("svg", [], [], null)));
	assert twice.indexOf("data-neon-svg=\"neon-svg1\"") >= 0, "the numbering starts again with each render: " + twice;
}

test "SSR writes Video as the video, classes and attributes the DOM host builds" {
	const page = renderToMarkup(el("video", [attr("source", "/a.mp4"), attr("muted", "true"), attr("repeat", "true"),
		attr("controls", "false"), attr("volume", "0.5"), attr("resizeMode", "cover"), attr("command", "pause")], [], null));
	assert page.html === "<video playsinline=\"\" src=\"/a.mp4\" loop=\"\" class=\"neon-video neon-video-cover\"></video>", page.html;
	assert page.css.indexOf(".neon-video{display:block") >= 0 && page.css.indexOf(".neon-webview{") >= 0, page.css;
	const again = renderToString(el("video", [attr("resizeMode", "cover"), attr("resizeMode", "contain")], [], null));
	assert again === "<video playsinline=\"\" class=\"neon-video\"></video>", again;
}

test "SSR writes WebView as the iframe whose document is the one the DOM host sets" {
	const html = renderToString(el("webview", [attr("interceptLoads", "true"), attr("javaScriptEnabled", "false"),
		attr("source", "html\x1f<p>a</p><script>x</" + "script>\x1fhttps://b.test/")], [], null));
	assert html.startsWith("<iframe sandbox=\"allow-same-origin allow-forms allow-popups\" srcdoc=\"&lt;base href=&quot;https://b.test/&quot;&gt;&lt;script&gt;(function(){window.ReactNativeWebView="), html;
	assert html.indexOf("&lt;/script&gt;&lt;p&gt;a&lt;/p&gt;&lt;script&gt;x&lt;/script&gt;\"") > 0 && html.endsWith(" class=\"neon-webview\"></iframe>") && html.indexOf("interceptLoads") < 0, html;
	const plain = renderToString(el("webview", [attr("source", "html\x1fa"), attr("source", "uri\x1f/x.html")], [], null));
	assert plain === "<iframe src=\"/x.html\" class=\"neon-webview\"></iframe>", plain;
	const quiet = renderToString(el("webview", [attr("source", "html\x1fa")], [], null));
	assert quiet.indexOf("addEventListener") < 0 && quiet.indexOf("ReactNativeWebView") > 0, quiet;
}

test "SSR writes CameraView as the video the DOM host creates, mirrored when it faces front" {
	const front = renderToString(el("camera", [attr("facing", "front"), attr("flash", "off"), attr("active", "true"), attr("mirror", "false")], [], null));
	assert front === "<video playsinline=\"\" muted=\"\" autoplay=\"\" class=\"neon-camera neon-camera-mirror\"></video>", front;
	const back = renderToString(el("camera", [attr("facing", "front"), attr("facing", "back")], [], null));
	assert back === "<video playsinline=\"\" muted=\"\" autoplay=\"\" class=\"neon-camera\"></video>", back;
	const mirrored = renderToString(el("camera", [attr("facing", "back"), attr("mirror", "true")], [], null));
	assert mirrored.indexOf("neon-camera-mirror") > 0, mirrored;
}
