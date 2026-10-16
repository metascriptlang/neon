import { el, text, NeonNode } from "../../src/render/node";
import { Host, HostNode } from "../../src/render/hostTypes";
import { Accessor } from "../../src/core/signal";
import { Errored } from "../../src/macros/ui/flow";
import { renderToString, SafeError } from "../../src/render/ssr";

// server/flow.ts:274 Errored over server/signals.ts:3584 createErrorBoundary: the fallback replaces what the children wrote
test "a server render swaps a throw while mounting for the fallback and takes back the partial output" {
	const leaking: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		text("partial")(host, parent, before);
		throw new Error("db password=hunter2");
	};
	const html = renderToString(Errored({
		children: leaking,
		fallback: (err: Accessor<Error>, reset: () => void): NeonNode => el("b", [], [], text("caught " + err().message)),
	}));
	assert !html.includes("partial"), "the children's output was taken back: " + html;
	when (debug) {
		assert html.includes("caught db password=hunter2"), "a dev build keeps the message: " + html;
	} else {
		assert html.includes("caught Internal Server Error") && !html.includes("hunter2"), "a build without debug sends the generic message: " + html;
	}
}

// server/signals.ts:3551 a branded error passes through
test "a server render keeps the message of a SafeError" {
	const safe: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		throw new SafeError("try again later");
	};
	const html = renderToString(Errored({
		children: safe,
		fallback: (err: Accessor<Error>, reset: () => void): NeonNode => el("b", [], [], text("caught " + err().message)),
	}));
	assert html.includes("caught try again later"), "the safe message reached the page: " + html;
}

test "a server render hands the fallback the same generic Error for every read" {
	let first: Error | null = null;
	let same = false;
	const boom: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => { throw new Error("secret"); };
	renderToString(Errored({
		children: boom,
		fallback: (err: Accessor<Error>, reset: () => void): NeonNode => {
			first = err();
			same = err() === first;
			return text("x");
		},
	}));
	assert same, "one wire value per caught error";
}
