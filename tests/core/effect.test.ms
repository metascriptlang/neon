import { createSignal, batch } from "../../src/core/signal";
import { createEffect, createRenderEffect, onMount } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { mockHost, mockNode, render, hydrate, HostNode, MockNode } from "../../src/render/host";
import { NeonNode } from "../../src/render/node";
import { View, TextInput } from "../../src/components/primitives";

test "an effect outside any root runs at once" {
	let runs = 0;
	createEffect(() => { runs += 1; });
	assert runs === 1, "no root defers it";
}

test "an effect created in a root runs after the root body" {
	const log: string[] = [];
	createRoot((d) => {
		createEffect(() => { log.push("effect"); });
		createRenderEffect(() => { log.push("render"); });
		log.push("body");
	});
	assert log.join(",") === "render,body,effect", "got " + log.join(",");
}

test "deferred effects run in creation order after a nested root" {
	const log: string[] = [];
	createRoot((d) => {
		createEffect(() => { log.push("outer"); });
		createRoot((d2) => {
			createEffect(() => { log.push("inner"); });
		});
		log.push("body");
	});
	assert log.join(",") === "body,outer,inner", "got " + log.join(",");
}

test "an effect created in a batch runs when the batch ends" {
	const log: string[] = [];
	batch(() => {
		createEffect(() => { log.push("effect"); });
		log.push("body");
	});
	assert log.join(",") === "body,effect", "got " + log.join(",");
}

test "a render effect writing the host runs before an effect reading it back" {
	const [count, setCount] = createSignal(0);
	let host = -1;
	const seen: number[] = [];
	createRoot((d) => {
		createEffect(() => { count(); seen.push(host); });
		createRenderEffect(() => { host = count(); });
	});
	setCount(5);
	assert seen.join(",") === "0,5", "got " + seen.join(",");
}

test "a signal written in a root body does not run the root's deferred effects early" {
	const [count, setCount] = createSignal(0);
	const log: string[] = [];
	createRoot((d) => {
		createEffect(() => { log.push("effect " + count().toString()); });
		setCount(1);
		log.push("body");
	});
	assert log.join(",") === "body,effect 1", "got " + log.join(",");
}

test "a disposed root drops its pending effect" {
	let runs = 0;
	createRoot((d) => {
		createEffect(() => { runs += 1; });
		d();
	});
	assert runs === 0, "disposed before it ran";
}

interface FocusProps { log: string[]; }

function Focus(props: FocusProps): NeonNode {
	const log = props.log;
	let input: HostNode | null = null;
	onMount(() => { log.push(input === null ? "null" : "node"); });
	return <View><TextInput ref={(n: HostNode): void => { input = n; }} /></View>;
}

test "onMount sees a node its own subtree created" {
	const log: string[] = [];
	const root = mockNode("root");
	render(<Focus log={log} />, mockHost(), root as unknown as HostNode);
	assert log.join(",") === "node", "got " + log.join(",");
}

test "onMount runs once and does not track" {
	const [count, setCount] = createSignal(0);
	let runs = 0;
	createRoot((d) => {
		onMount(() => { count(); runs += 1; });
	});
	setCount(1);
	assert runs === 1, "ran " + runs.toString();
}

test "hydration runs onMount after the served nodes are claimed" {
	const log: string[] = [];
	const served = mockNode("root");
	render(<Focus log={[]} />, mockHost(), served as unknown as HostNode);
	hydrate(<Focus log={log} />, mockHost(), served as unknown as HostNode);
	assert log.join(",") === "node", "got " + log.join(",");
}
