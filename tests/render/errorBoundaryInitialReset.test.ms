import { ErrorBoundary } from "../../src/macros/ui/flow";
import { text, NeonNode } from "../../src/render/node";
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
	const dispose = render(ErrorBoundary({ children: risky,
		fallback: (error: Error, reset: () => void): NeonNode => {
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
