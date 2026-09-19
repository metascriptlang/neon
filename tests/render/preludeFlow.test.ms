import { NeonNode } from "../../src/render/node";
import { renderToString } from "../../src/render/ssr";
import { element } from "../../src/macros/ui/element";
import { createSignal, Accessor } from "../../src/core/signal";

test "a lowered && needs no flow import" {
	const [on, _s] = createSignal(true);
	const v: NeonNode = element(<div>{on() && <b>yes</b>}</div>);
	assert renderToString(v) === "<div><b>yes</b></div>", "Show came from the prelude";
}

test "a lowered ternary needs no flow import" {
	const [on, _s] = createSignal(false);
	const v: NeonNode = element(<div>{on() ? <b>y</b> : <i>n</i>}</div>);
	assert renderToString(v) === "<div><i>n</i></div>", "both arms came from the prelude";
}

test "a lowered map needs no flow import" {
	const [xs, _s] = createSignal<number[]>([1, 2]);
	const v: NeonNode = element(<ul>{xs.map((n: number): NeonNode => element(<li>{n.toString()}</li>))}</ul>);
	assert renderToString(v) === "<ul><li>1</li><li>2</li></ul>", "For came from the prelude";
}

test "the flow tags are in scope without an import" {
	const [on, _o] = createSignal(true);
	const [xs, _x] = createSignal<number[]>([1]);
	const shown: NeonNode = element(<div><Show when={on()}><b>y</b></Show></div>);
	assert renderToString(shown) === "<div><b>y</b></div>", "Show tag";
	const each: NeonNode = element(<ul><For each={xs()}>{(n: number, i: Accessor<number>): NeonNode => element(<li>{n.toString()}</li>)}</For></ul>);
	assert renderToString(each) === "<ul><li>1</li></ul>", "For tag";
}
