import { el, evt, text, attr } from "../src/render/node";
import { element } from "../src/macros/ui/element";

test "A: element with NO attrs" {
	const v = element(<p>hi</p>);
	assert v.tag === "p", "tag p";
	assert v.children.length === 1, "one child";
}

test "B: element with a NON-event attr" {
	const v = element(<p class="box">hi</p>);
	assert v.tag === "p", "tag p";
	assert v.attrs.length === 1, "one attr";
}

test "C: element with an EVENT attr" {
	const inc = () => {};
	const v = element(<button onClick={inc}>+</button>);
	assert v.tag === "button", "tag button";
	assert v.events.length === 1, "one event";
}
