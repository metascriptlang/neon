import { NeonNode, el, text, dynText } from "../../src/render/node";
import { render, mockHost, mockToString, MockNode, Host, HostNode } from "../../src/render/host";
import { Errored, Loading } from "../../src/macros/ui/flow";
import { createAsyncMemo } from "../../src/core/memo";
import { Accessor } from "../../src/core/signal";
import { resetErrorHalt } from "../../src/core/runtime";
import { Gate, gated, release } from "../core/asyncClock";

const loadingB: NeonNode = el("b", [], [], text("loading"));

function readInBody(data: Accessor<int32>): NeonNode {
	return (h: Host, p: HostNode, b: HostNode | null): void => {
		const v = data();
		el("p", [], [], text("v" + v.toString()))(h, p, b);
	};
}

function readInChild(data: Accessor<int32>): NeonNode {
	const child: NeonNode = (h: Host, p: HostNode, b: HostNode | null): void => {
		const v = data();
		el("i", [], [], text("child " + v.toString()))(h, p, b);
	};
	return el("div", [], [], child);
}

test "a pending read in the body of an Errored's content waits under the Loading and mounts when it lands" {
	resetErrorHalt();
	const good = new Gate();
	const host = mockHost();
	const root = host.createElement("root");
	const shown = (): string => mockToString(root as unknown as MockNode);
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => gated(good, 9));
		Loading({
			fallback: loadingB,
			children: Errored({ children: readInBody(data), fallback: (err: Accessor<Error>, reset: () => void): NeonNode => el("em", [], [], text("caught")) }),
		})(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown() === "<root><b>loading</b></root>", "waiting: " + shown();
	await release(good);
	assert shown() === "<root><p>v9</p></root>", "landed: " + shown();
	dispose();
}

test "a pending read in a component under an Errored's content waits under the Loading and mounts when it lands" {
	resetErrorHalt();
	const good = new Gate();
	const host = mockHost();
	const root = host.createElement("root");
	const shown = (): string => mockToString(root as unknown as MockNode);
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => gated(good, 4));
		Loading({
			fallback: loadingB,
			children: Errored({ children: readInChild(data), fallback: (err: Accessor<Error>, reset: () => void): NeonNode => el("em", [], [], text("caught")) }),
		})(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown() === "<root><b>loading</b></root>", "waiting: " + shown();
	await release(good);
	assert shown() === "<root><div><i>child 4</i></div></root>", "landed: " + shown();
	dispose();
}

test "a reset that mounts the content into a pending read keeps what the Loading shows and mounts when the read lands" {
	resetErrorHalt();
	const good = new Gate();
	const attempts = [0];
	let again: () => void = (): void => {};
	const host = mockHost();
	const root = host.createElement("root");
	const shown = (): string => mockToString(root as unknown as MockNode);
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => gated(good, 9));
		const content: NeonNode = (ch: Host, cp: HostNode, cb: HostNode | null): void => {
			attempts[0] = attempts[0] + 1;
			if (attempts[0] === 1) { throw new Error("first"); }
			readInBody(data)(ch, cp, cb);
		};
		Loading({
			fallback: loadingB,
			children: Errored({
				children: content,
				fallback: (err: Accessor<Error>, reset: () => void): NeonNode => { again = reset; return el("em", [], [], dynText((): string => "caught " + err().message)); },
			}),
		})(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown() === "<root><em>caught first</em></root>", "failed once: " + shown();
	again();
	assert shown() === "<root><em>caught first</em></root>", "the Loading has shown content, so the reset's wait keeps it: " + shown();
	await release(good);
	assert shown() === "<root><p>v9</p></root>", "landed: " + shown();
	assert attempts[0] === 3, "the body ran for the first failure, the reset and the landing: " + attempts[0].toString();
	dispose();
}

test "a reset into a pending read in a nested component's body keeps what the Loading shows and mounts as well" {
	resetErrorHalt();
	const good = new Gate();
	const attempts = [0];
	let again: () => void = (): void => {};
	const host = mockHost();
	const root = host.createElement("root");
	const shown = (): string => mockToString(root as unknown as MockNode);
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => gated(good, 5));
		const content: NeonNode = (ch: Host, cp: HostNode, cb: HostNode | null): void => {
			attempts[0] = attempts[0] + 1;
			if (attempts[0] === 1) { throw new Error("first"); }
			readInChild(data)(ch, cp, cb);
		};
		Loading({
			fallback: loadingB,
			children: Errored({
				children: content,
				fallback: (err: Accessor<Error>, reset: () => void): NeonNode => { again = reset; return el("em", [], [], text("caught")); },
			}),
		})(h, parent, before);
	};
	const dispose = render(app, host, root);
	again();
	assert shown() === "<root><em>caught</em></root>", "the Loading has shown content, so the reset's wait keeps it: " + shown();
	await release(good);
	assert shown() === "<root><div><i>child 5</i></div></root>", "landed: " + shown();
	dispose();
}
