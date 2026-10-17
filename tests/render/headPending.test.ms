// A Head's content mounts inside the mount that places the Head, so a row that reads a pending value there is the pending status of the
// compute that built the Head's row, as for any element child (packages/solid/src/client/flow.ts:226).
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { Host, HostNode, MockNode, mockHost, render, mockToString } from "../../src/render/host";
import { Accessor, createSignal } from "../../src/core/signal";
import { createAsyncMemo } from "../../src/core/memo";
import { Head } from "../../src/render/head";
import { Loading, Show } from "../../src/macros/ui/flow";
import { Gate, gatedStr, release } from "../core/asyncClock";

const loadingB: NeonNode = el("b", [], [], text("loading"));

function pendingNote(gate: Gate, tag: Accessor<string>): Accessor<string> {
	return createAsyncMemo((p: string | null): Promise<string> => gatedStr(gate, "note" + tag()));
}

function titleReading(note: () => string, tail: () => string): NeonNode {
	return (h: Host, parent: HostNode, before: HostNode | null): void => {
		const v = note();
		el("title", [], [], dynText((): string => v + tail()))(h, parent, before);
	};
}

test "a Head whose content reads a pending value shows the fallback, then the title, and stays reactive" {
	const gate = new Gate();
	const [tag, setTag] = createSignal("");
	const [tail, setTail] = createSignal("!");
	const [on, setOn] = createSignal(true);
	const host = mockHost();
	const root = host.createElement("root");
	const shown = (): string => mockToString(root as unknown as MockNode);
	const head = (): string => mockToString((host.headRoot as (n: HostNode) => HostNode)(root) as unknown as MockNode);
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const note = pendingNote(gate, tag);
		const page = (ch: Host, cp: HostNode, cb: HostNode | null): void => {
			Head({ children: titleReading(note, tail) })(ch, cp, cb);
			el("p", [], [], text("body"))(ch, cp, cb);
		};
		Loading({ children: Show({ when: on, children: page }), fallback: loadingB })(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown() === "<root><b>loading</b></root>", "the fallback shows while pending: " + shown();
	assert head() === "<head></head>", "no title yet: " + head();
	await release(gate);
	assert shown() === "<root><p>body</p></root>", "the body shows once it landed: " + shown();
	assert head() === "<head><title>note!</title></head>", "the title is in the head: " + head();
	setTail("?");
	assert head() === "<head><title>note?</title></head>", "a later write still updates the title: " + head();
	setOn(false);
	assert head() === "<head></head>", "the title leaves with its row: " + head();
	gate.open = false;
	setTag("2");
	setOn(true);
	assert shown() === "<root></root>" && head() === "<head></head>", "a Head built while pending waits: " + shown() + head();
	await release(gate);
	assert head() === "<head><title>note2?</title></head>" && shown() === "<root><p>body</p></root>", "and lands: " + head();
	dispose();
}
