// A shared sheet entry becomes a CSS rule + class on a host with a stylesheet,
// and stays a field-by-field write everywhere else (docs/STYLE.md §5).
//
// Both lanes run this file: the js lane exercises the class route, the native
// lane pins that none of the CSS metadata exists there — the macro must not
// spend bytes on rules a native binary can never use.
//
// The rule text is asserted literally. That is deliberate: the macro spells CSS
// (kebab-case, px) independently of applyCss in platform/browser/dom.ms, so
// this assertion is the thing that catches the two drifting apart.

import { el, withStyle } from "../../src/render/node";
import { mockHost, renderNode, MockNode, Host, HostNode } from "../../src/render/host";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { registerCss, collectCss, resetCss, cssRuleCount } from "../../src/render/sheet";

const sheet = createStyles({
	btn: { padding: 8, backgroundColor: "#334" },
});

// A host that speaks CSS — the mock's browser-shaped sibling. mockHost() itself
// stays native-like so every existing test keeps measuring the setStyle path.
function cssHost(): Host {
	const h = mockHost();
	h.setStyleClass = (node: HostNode, id: string, css: string): void => {
		registerCss(id, css);
		(node as unknown as MockNode).className = id;
	};
	return h;
}

test "a static sheet entry becomes one class instead of inline style" {
	when (js) {
		resetCss();
		const m = renderNode(withStyle(el("div", [], [], []), sheet.btn), cssHost()) as unknown as MockNode;
		assert sheet.btn.cssId !== null, "the entry carries a class id on the browser lane";
		assert m.className === (sheet.btn.cssId as string), "the node carries that class";
		assert m.style === null, "no inline style once a class applies";
		assert cssRuleCount() === 1, "exactly one rule for one entry";
		assert collectCss() === "." + (sheet.btn.cssId as string) + "{padding:8px;background-color:#334;}", "rule text";
	} else {
		const m = renderNode(withStyle(el("div", [], [], []), sheet.btn), mockHost()) as unknown as MockNode;
		assert sheet.btn.cssId === null, "no css metadata off the browser lane";
		assert sheet.btn.css === null, "and no rule text";
		assert m.style !== null, "a native host still receives the fields through setStyle";
		assert m.className === "", "and carries no class";
	}
}

test "the style values survive on both lanes" {
	assert sheet.btn.padding === 8, "a sheet entry is still readable as a Style";
	assert sheet.btn.backgroundColor === "#334", "including string fields";
}
