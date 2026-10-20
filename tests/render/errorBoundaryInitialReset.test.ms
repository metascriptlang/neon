import { Errored } from "../../src/macros/ui/flow";
import { el, text, NeonNode } from "../../src/render/node";
import { createSignal, Accessor } from "../../src/core/signal";
import { createRenderEffect } from "../../src/core/effect";
import { flush } from "../../src/core/runtime";
import { Cleanup } from "../../src/core/types";
import { onCleanup } from "../../src/core/cleanup";
import { mockHost, mockNode, mockToString, render } from "../../src/render/host";
import { Host, HostNode } from "../../src/render/hostTypes";

test "reset after an initial mount throw removes the fallback before remount" {
	let first = true;
	const resets: (() => void)[] = [];
	const risky: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		if (first) { first = false; throw new Error("first mount"); }
		text("good")(host, parent, before);
	};
	const root = mockNode("root");
	const dispose = render(Errored({ children: risky,
		fallback: (error: Accessor<Error>, reset: () => void): NeonNode => {
			resets.push(reset);
			return text("fallback");
		},
	}), mockHost(), root);
	try {
		assert mockToString(root) === "<root>fallback</root>";
		resets[0]();
		assert mockToString(root) === "<root>good</root>";
	} finally { dispose(); }
}

test "nested initial reset preserves siblings and cleans repeated failure lifetimes" {
	let first = true;
	let childCleanups = 0;
	let fallbackCleanups = 0;
	const [broken, setBroken] = createSignal(false);
	const resets: (() => void)[] = [];
	const risky: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		onCleanup((): void => { childCleanups += 1; });
		if (first) { first = false; throw new Error("first mount"); }
		createRenderEffect<boolean>(
			(prev: boolean | null): boolean => broken(),
			(value: boolean, prev: boolean | null): Cleanup | null => {
				if (value) { throw new Error("later failure"); }
				return null;
			},
		);
		text("good")(host, parent, before);
	};
	const boundary = Errored({ children: risky,
		fallback: (error: Accessor<Error>, reset: () => void): NeonNode => {
			resets.push(reset);
			return (host: Host, parent: HostNode, before: HostNode | null): void => {
				onCleanup((): void => { fallbackCleanups += 1; });
				text("fallback")(host, parent, before);
			};
		},
	});
	const children: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		text("left")(host, parent, before);
		boundary(host, parent, before);
		text("right")(host, parent, before);
	};
	const root = mockNode("root");
	const dispose = render(el("panel", [], [], children), mockHost(), root);
	try {
		assert mockToString(root) === "<root><panel>leftfallbackright</panel></root>";
		assert childCleanups === 1 && fallbackCleanups === 0;
		resets[0]();
		assert mockToString(root) === "<root><panel>leftgoodright</panel></root>";
		assert childCleanups === 1 && fallbackCleanups === 1;
		setBroken(true);
		flush();
		assert mockToString(root) === "<root><panel>leftfallbackright</panel></root>";
		assert childCleanups === 1 && fallbackCleanups === 1;
		setBroken(false);
		flush();
		resets[1]();
		assert mockToString(root) === "<root><panel>leftgoodright</panel></root>";
		assert childCleanups === 1 && fallbackCleanups === 2;
	} finally { dispose(); }
	assert childCleanups === 2 && fallbackCleanups === 2;
}
