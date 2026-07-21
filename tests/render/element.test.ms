import { createSignal } from "../../src/core/signal";
import { el, text, dynText, renderToString } from "../../src/render/node";
import { element } from "../../src/macros/ui/element";

test "reactive element renders and updates on signal change" {
	const [name, setName] = createSignal("world");
	const node = element(<p>Hi {name()}</p>);
	assert renderToString(node) === "<p>Hi world</p>", "initial render";
	setName("neon");
	assert renderToString(node) === "<p>Hi neon</p>", "render updates after set";
}

test "JSX bound to a const is consumed by element()" {
	const [name, setName] = createSignal("world");
	const view = <p>Hi {name()}</p>;
	const node = element(view);
	assert renderToString(node) === "<p>Hi world</p>", "const-form initial render";
	setName("neon");
	assert renderToString(node) === "<p>Hi neon</p>", "const-form updates after set";
}

test "the same JSX const consumed twice yields independent trees" {
	const [a, setA] = createSignal("x");
	const view = <p>{a()}</p>;
	const one = element(view);
	const two = element(view);
	setA("y");
	assert renderToString(one) === "<p>y</p>", "first tree reactive";
	assert renderToString(two) === "<p>y</p>", "second tree reactive";
}
