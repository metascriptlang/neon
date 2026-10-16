import { sleepAsync } from "std/core/promise";
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { Host, HostNode } from "../../src/render/hostTypes";
import { Accessor } from "../../src/core/signal";
import { createAsyncMemo } from "../../src/core/memo";
import { Loading, Errored } from "../../src/macros/ui/flow";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createRoot, createUniqueId } from "../../src/core/owner";
import { View, Text } from "../../src/components/primitives";
import { renderToString, renderToStream, SafeError } from "../../src/render/ssr";

const waiting: NeonNode = el("b", [], [], text("loading"));
const fetches: string[] = [];

async function after(ms: int32, value: int32): Promise<int32> {
	await sleepAsync(ms);
	return value;
}

async function immediately(value: int32): Promise<int32> {
	return value;
}

async function afterStr(ms: int32, value: string): Promise<string> {
	await sleepAsync(ms);
	return value;
}

async function afterFail(ms: int32, failure: Error): Promise<int32> {
	await sleepAsync(ms);
	throw failure;
}

function reading(name: string, ms: int32, value: int32): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => {
			fetches.push(name);
			return after(ms, value);
		});
		el("p", [], [], dynText((): string => name + "=" + data().toString()))(host, parent, before);
	};
}

function fetched(name: string): int32 {
	let n = 0;
	for (const f of fetches) { if (f === name) { n += 1; } }
	return n;
}

test "a Loading over an async read writes the settled content and the record, and fetches once" {
	const view = Loading({ children: reading("a", 5, 9), fallback: waiting });
	const out = await renderToStream(view);
	assert out.html === "<p>a=9</p><!---->", out.html;
	assert out.records.startsWith("<script>(self._$HY||(self._$HY={r:{},e:{}})).r[\"") && out.records.endsWith("\"]=\"9\"</script>"), out.records;
	assert fetched("a") === 1, "the re-pass adopted the settled value without a second fetch: " + fetched("a").toString();
}

test "renderToString writes the fallback and no record for the same view" {
	const view = Loading({ children: reading("sync", 5, 9), fallback: waiting });
	const html = renderToString(view);
	assert html.includes("<b>loading</b>") && !html.includes("sync="), html;
	await sleepAsync(12);
}

test "a read nested in a second Loading settles in a later pass and each fetches once" {
	const inner: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		Loading({ children: reading("inner", 5, 2), fallback: el("i", [], [], text("inner waits")) })(host, parent, before);
	};
	const outer: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		reading("outer", 5, 1)(host, parent, before);
		inner(host, parent, before);
	};
	const out = await renderToStream(Loading({ children: outer, fallback: waiting }));
	assert out.html.includes("<p>outer=1</p>") && out.html.includes("<p>inner=2</p>"), out.html;
	assert !out.html.includes("waits") && !out.html.includes("loading"), out.html;
	assert fetched("outer") === 1 && fetched("inner") === 1, fetched("outer").toString() + "/" + fetched("inner").toString();
	assert out.records.split("<script>").length === 3, "two records: " + out.records;
}

test "sibling Loadings with different delays both settle and their records follow start order" {
	const app: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		Loading({ children: reading("slow", 25, 1), fallback: waiting })(host, parent, before);
		Loading({ children: reading("quick", 3, 2), fallback: waiting })(host, parent, before);
	};
	const out = await renderToStream(app);
	assert out.html === "<p>slow=1</p><!----><p>quick=2</p><!---->", out.html;
	const slow = out.records.indexOf("]=\"1\"");
	const quick = out.records.indexOf("]=\"2\"");
	assert slow > 0 && quick > slow, out.records;
	assert fetched("slow") === 1 && fetched("quick") === 1, "once each";
}

test "a rejected read under Errored writes the fallback with the sanitized message and an error record" {
	const failing: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => afterFail(4, new Error("db password=hunter2")));
		el("p", [], [], dynText((): string => data().toString()))(host, parent, before);
	};
	const view = Loading({
		children: Errored({
			children: failing,
			fallback: (err: Accessor<Error>, reset: () => void): NeonNode => el("em", [], [], text("caught " + err().message)),
		}),
		fallback: waiting,
	});
	const out = await renderToStream(view);
	when (debug) {
		assert out.html.includes("caught db password=hunter2"), out.html;
		assert out.records.includes(".e[\"") && out.records.includes("]=\"db password=hunter2\""), out.records;
	} else {
		assert out.html.includes("caught Internal Server Error") && !out.html.includes("hunter2"), out.html;
		assert out.records.includes("]=\"Internal Server Error\"") && !out.records.includes("hunter2"), out.records;
	}
}

test "a SafeError rejection keeps its message in the page and in the record" {
	const failing: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => afterFail(4, new SafeError("try again later")));
		el("p", [], [], dynText((): string => data().toString()))(host, parent, before);
	};
	const view = Loading({
		children: Errored({
			children: failing,
			fallback: (err: Accessor<Error>, reset: () => void): NeonNode => el("em", [], [], text("caught " + err().message)),
		}),
		fallback: waiting,
	});
	const out = await renderToStream(view);
	assert out.html.includes("caught try again later"), out.html;
	assert out.records.includes("]=\"try again later\""), out.records;
}

test "a read with no Loading above it still settles" {
	const out = await renderToStream(reading("bare", 4, 7));
	assert out.html === "<p>bare=7</p>", out.html;
	assert fetched("bare") === 1, "once";
}

test "a record is written as a script string a parser cannot cut short" {
	const tricky = "</script><!-- \"q\" \\ é \u2028 \u2029 \n";
	const view: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: string | null): Promise<string> => afterStr(3, tricky));
		el("p", [], [], dynText((): string => data().length.toString()))(host, parent, before);
	};
	const out = await renderToStream(Loading({ children: view, fallback: waiting }));
	const b = "\\";
	const body = b + "\"" + b + "u003c/script>" + b + "u003c!-- " + b + b + b + "\"q" + b + b + b + "\" " + b + b + b + b + " é " + b + "u2028 " + b + "u2029 " + b + b + "n" + b + "\"";
	assert out.records.endsWith("]=\"" + body + "\"</script>"), out.records;
	assert out.records.split("</script>").length === 2, "one script element: " + out.records;
}

const looks = createStyles({
	quick: { padding: 3, backgroundColor: "#111" },
	slow: { padding: 9, backgroundColor: "#eee" },
});

function Identified(): NeonNode {
	const id = createUniqueId();
	return <Text>{id}</Text>;
}

function pageOf(name: string, ms: int32, value: int32, slow: boolean): NeonNode {
	return <View style={slow ? looks.slow : looks.quick}>
		<Identified />
		<Loading fallback={<Text>wait</Text>}>{reading(name, ms, value)}</Loading>
		<Identified />
	</View>;
}

test "two renders started together keep their own ids, records and css" {
	const slow = pageOf("slow", 30, 1, true);
	const quick = pageOf("quick", 3, 2, false);
	const slowBeside = renderToStream(slow);
	const quickBeside = renderToStream(quick);
	const quickOut = await quickBeside;
	const slowOut = await slowBeside;
	const slowAlone = await renderToStream(slow);
	const quickAlone = await renderToStream(quick);
	assert slowOut.html === slowAlone.html && quickOut.html === quickAlone.html, slowOut.html + " | " + quickOut.html;
	assert slowOut.records === slowAlone.records && quickOut.records === quickAlone.records, slowOut.records + " | " + quickOut.records;
	assert slowOut.css === slowAlone.css && quickOut.css === quickAlone.css, slowOut.css + " | " + quickOut.css;
	assert slowOut.css !== quickOut.css && slowOut.records.includes("]=\"1\"") && quickOut.records.includes("]=\"2\""), "the pages differ";
}

// Parked on ~/metascript/.inbox/compiler/2026-10-08-test-block-awaiting-a-rejected-nullable-promise-segfaults.md (struct payload sighting): a test block awaiting a rejected Promise<struct> kills the C binary, so the await is inside this helper.
async function budgetFailure(): Promise<string> {
	let burn = 0;
	const unstable: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		burn += 1;
		createRoot((dispose: () => void): number => {
			const data = createAsyncMemo((p: int32 | null): Promise<int32> => immediately(1));
			el("p", [], [], dynText((): string => data().toString()))(host, parent, before);
			return 0;
		}, "u" + burn.toString());
	};
	let message = "";
	try {
		await renderToStream(Loading({ children: unstable, fallback: waiting }));
	} catch (e) {
		message = e.message;
	}
	return message + " (rendered " + burn.toString() + " times)";
}

test "a render that never converges names its Loading and fails" {
	const message = await budgetFailure();
	assert message.includes("<Loading> at owner id \"") && message.includes("did not converge after 10000 passes"), "[" + message + "]";
	assert message.endsWith("(rendered 10000 times)"), message;
}
