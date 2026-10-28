import { onSettled, createEffect, createRenderEffect } from "../../src/core/effect";
import { createSignal } from "../../src/core/signal";
import { Cleanup } from "../../src/core/types";
import { resetErrorHalt } from "../../src/core/runtime";
import { HostNode } from "../../src/render/host";
import { renderToString } from "../../src/render/ssr";
import { NeonNode } from "../../src/render/node";
import { View, TextInput } from "../../src/components/primitives";

interface FocusProps { log: string[]; }

function Focus(props: FocusProps): NeonNode {
	const log = props.log;
	let input: HostNode | null = null;
	onSettled(() => { log.push(input === null ? "null" : "node"); return null; });
	return <View><TextInput ref={(n: HostNode): void => { input = n; }} /></View>;
}

test "effects and onSettled do not run on the server" {
	const log: string[] = [];
	const html = renderToString(<Focus log={log} />);
	assert log.length === 0, "got " + log.join(",");
	assert html !== "", "the page still renders";
}

function EffectReads(props: FocusProps): NeonNode {
	const [value, setValue] = createSignal("typed");
	createEffect<string>(
		(prev: string | null): string => { props.log.push(value()); return value(); },
		(text: string, prev: string | null): Cleanup | null => null,
	);
	return <View />;
}

test "an effect's compute in a component body reads a signal on the server" {
	const log: string[] = [];
	const html = renderToString(<EffectReads log={log} />);
	assert log.join(",") === "typed", "got " + log.join(",");
	assert html !== "", "the page still renders";
}

function RenderEffectApplyReads(props: FocusProps): NeonNode {
	const [value, setValue] = createSignal("seen");
	createRenderEffect<int32>(
		(prev: int32 | null): int32 => 1,
		(n: int32, prev: int32 | null): Cleanup | null => { props.log.push(value()); return null; },
	);
	return <View />;
}

test "a render effect's apply in a component body reads a signal on the server" {
	const log: string[] = [];
	const html = renderToString(<RenderEffectApplyReads log={log} />);
	assert log.join(",") === "seen", "got " + log.join(",");
	assert html !== "", "the page still renders";
}

function readThrough(read: () => string): string {
	return read();
}

function ReadsAfterEffect(props: FocusProps): NeonNode {
	const [value, setValue] = createSignal("direct");
	createEffect<string>((prev: string | null): string => value(), (text: string, prev: string | null): Cleanup | null => null);
	props.log.push(readThrough((): string => value()));
	return <View />;
}

test "a read through a helper in a server component body after an effect still throws in debug only" {
	const log: string[] = [];
	let message = "";
	try { renderToString(<ReadsAfterEffect log={log} />); } catch (e) { message = e.message; }
	resetErrorHalt();
	when (debug) {
		assert message.indexOf("[STRICT_READ_UNTRACKED]") === 0, "got [" + message + "]";
	} else {
		assert message === "", "got [" + message + "]";
		assert log.join(",") === "direct", "got " + log.join(",");
	}
}
