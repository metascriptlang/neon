import { createSignal } from "../../src/core/signal";
import { onSettled } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { resetErrorHalt } from "../../src/core/runtime";
import { Cleanup } from "../../src/core/types";
import { mockHost, mockNode, render, hydrate, HostNode, MockNode } from "../../src/render/host";
import { renderToString } from "../../src/render/ssr";
import { NeonNode } from "../../src/render/node";
import { View, TextInput } from "../../src/components/primitives";

test "onSettled runs after the owner's body" {
	const log: string[] = [];
	createRoot((d) => {
		log.push("sync");
		onSettled(() => { log.push("settled"); return null; });
		log.push("after onSettled call");
		assert log.join(",") === "sync,after onSettled call", "nothing ran inside the body: " + log.join(",");
		return 0;
	});
	assert log.join(",") === "sync,after onSettled call,settled", "got " + log.join(",");
}

test "onSettled without an owner runs at once" {
	const log: string[] = [];
	onSettled(() => { log.push("settled"); return null; });
	assert log.join(",") === "settled", "got " + log.join(",");
}

test "nested onSettled callbacks without an owner run outer then inner" {
	const log: string[] = [];
	onSettled(() => {
		log.push("outer");
		onSettled(() => { log.push("inner"); return null; });
		return null;
	});
	assert log.join(",") === "outer,inner", "got " + log.join(",");
}

test "nested onSettled callbacks inside an owner run outer then inner" {
	const log: string[] = [];
	createRoot((d) => {
		onSettled(() => {
			log.push("outer");
			onSettled(() => { log.push("inner"); return null; });
			return null;
		});
		return 0;
	});
	assert log.join(",") === "outer,inner", "got " + log.join(",");
}

test "the cleanup an onSettled returns runs when its owner is disposed" {
	let cleaned = 0;
	let dispose: (() => void) | null = null;
	createRoot((d) => {
		dispose = d;
		onSettled((): Cleanup | null => () => { cleaned += 1; });
		return 0;
	});
	assert cleaned === 0, "alive until disposed";
	(dispose as () => void)();
	assert cleaned === 1, "disposal ran it once: " + cleaned.toString();
	(dispose as () => void)();
	assert cleaned === 1, "and not twice: " + cleaned.toString();
}

test "an onSettled with no owner rejects a returned cleanup" {
	let cleaned = 0;
	let message = "";
	try {
		onSettled((): Cleanup | null => () => { cleaned += 1; });
	} catch (e) {
		message = e.message;
	}
	resetErrorHalt();
	assert message.indexOf("[SETTLED_CLEANUP_UNOWNED]") === 0, "got [" + message + "]";
	assert cleaned === 0, "the cleanup is never run";
}

test "a nested onSettled rejects a returned cleanup even under an owner" {
	let cleaned = 0;
	let message = "";
	try {
		createRoot((d) => {
			onSettled(() => {
				onSettled((): Cleanup | null => () => { cleaned += 1; });
				return null;
			});
			return 0;
		});
	} catch (e) {
		message = e.message;
	}
	resetErrorHalt();
	assert message.indexOf("[SETTLED_CLEANUP_UNOWNED]") === 0, "got [" + message + "]";
	assert cleaned === 0, "the cleanup is never run";
}

test "onSettled runs once and does not track" {
	const [x, setX] = createSignal(0);
	const seen: number[] = [];
	createRoot((d) => {
		onSettled(() => { seen.push(x()); return null; });
		return 0;
	});
	assert seen.join(",") === "0", "got " + seen.join(",");
	setX(1);
	assert seen.join(",") === "0", "a write does not rerun it: " + seen.join(",");
}

interface FocusProps { log: string[]; }

function Focus(props: FocusProps): NeonNode {
	const log = props.log;
	let input: HostNode | null = null;
	onSettled(() => { log.push(input === null ? "null" : "node"); return null; });
	return <View><TextInput ref={(n: HostNode): void => { input = n; }} /></View>;
}

test "onSettled sees a node its own subtree created" {
	const log: string[] = [];
	const root = mockNode("root");
	render(<Focus log={log} />, mockHost(), root as unknown as HostNode);
	assert log.join(",") === "node", "got " + log.join(",");
}

test "onSettled does not run on the server" {
	const log: string[] = [];
	const html = renderToString(<Focus log={log} />);
	assert log.length === 0, "got " + log.join(",");
	assert html !== "", "the page still renders";
}

test "hydration runs onSettled after the served nodes are claimed" {
	const log: string[] = [];
	const served = mockNode("root");
	render(<Focus log={[]} />, mockHost(), served as unknown as HostNode);
	hydrate(<Focus log={log} />, mockHost(), served as unknown as HostNode);
	assert log.join(",") === "node", "got " + log.join(",");
}
