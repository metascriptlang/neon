import { sleepAsync } from "std/core/promise";
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { Host, HostNode } from "../../src/render/hostTypes";
import { Accessor } from "../../src/core/signal";
import { createAsyncMemo, createMemo } from "../../src/core/memo";
import { onCleanup } from "../../src/core/cleanup";
import { Head } from "../../src/render/head";
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
			const read = data();
			el("p", [], [], text(read.toString()))(host, parent, before);
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

const bodies: string[] = [];

function counted(name: string, inner: NeonNode): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		bodies.push(name);
		inner(host, parent, before);
	};
}

function ran(name: string): int32 {
	let n = 0;
	for (const b of bodies) { if (b === name) { n += 1; } }
	return n;
}

test "a Loading whose content does not pend runs its body once beside a sibling that does" {
	const app: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		Loading({ children: counted("ready-a", el("p", [], [], text("ready"))), fallback: waiting })(host, parent, before);
		Loading({ children: counted("pends-a", reading("sibA", 8, 5)), fallback: waiting })(host, parent, before);
	};
	const out = await renderToStream(app);
	assert out.html === "<p>ready</p><!----><p>sibA=5</p><!---->", out.html;
	assert ran("ready-a") === 1, "the settled sibling ran " + ran("ready-a").toString() + " times";
	assert ran("pends-a") === 1, "the pending one ran " + ran("pends-a").toString() + " times";
}

test "two pending Loadings with a ready one between them run each body once" {
	const app: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		Loading({ children: counted("slow-b", reading("slowB", 20, 1)), fallback: waiting })(host, parent, before);
		Loading({ children: counted("ready-b", el("p", [], [], text("ready"))), fallback: waiting })(host, parent, before);
		Loading({ children: counted("quick-b", reading("quickB", 3, 2)), fallback: waiting })(host, parent, before);
	};
	const out = await renderToStream(app);
	assert out.html === "<p>slowB=1</p><!----><p>ready</p><!----><p>quickB=2</p><!---->", out.html;
	assert ran("ready-b") === 1 && ran("slow-b") === 1 && ran("quick-b") === 1, ran("slow-b").toString() + "/" + ran("ready-b").toString() + "/" + ran("quick-b").toString();
	assert fetched("slowB") === 1 && fetched("quickB") === 1, "once each";
}

test "a pending Loading inside a pending Loading runs each body once" {
	const inner: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		Loading({ children: counted("inner-c", reading("innerC", 5, 2)), fallback: el("i", [], [], text("inner waits")) })(host, parent, before);
	};
	const outer: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		reading("outerC", 5, 1)(host, parent, before);
		inner(host, parent, before);
	};
	const out = await renderToStream(Loading({ children: counted("outer-c", outer), fallback: waiting }));
	assert out.html === "<p>outerC=1</p><p>innerC=2</p><!----><!---->", out.html;
	assert ran("outer-c") === 1, "the outer body ran " + ran("outer-c").toString() + " times";
	assert ran("inner-c") === 1, "the inner body ran " + ran("inner-c").toString() + " times";
	assert fetched("outerC") === 1 && fetched("innerC") === 1, "once each";
}

test "a Loading inside a Loading that waits twice runs neither body again" {
	const inner: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		Loading({ children: counted("inner-d", reading("innerD", 4, 2)), fallback: waiting })(host, parent, before);
	};
	const outer: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		reading("firstD", 3, 1)(host, parent, before);
		inner(host, parent, before);
		reading("lastD", 12, 3)(host, parent, before);
	};
	const out = await renderToStream(Loading({ children: counted("outer-d", outer), fallback: waiting }));
	assert out.html.includes("<p>firstD=1</p><p>innerD=2</p><!----><p>lastD=3</p>"), out.html;
	assert ran("outer-d") === 1 && ran("inner-d") === 1, "outer " + ran("outer-d").toString() + ", inner " + ran("inner-d").toString();
	assert fetched("innerD") === 1 && fetched("lastD") === 1, "once each";
}

test "a settled Loading's owners stay alive until every boundary has settled" {
	const events: string[] = [];
	const ready: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		onCleanup((): void => { events.push("cleanup ready"); });
		el("p", [], [], text("ready"))(host, parent, before);
	};
	const slow: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => {
			events.push("fetch slow");
			return after(10, 1);
		});
		el("p", [], [], dynText((): string => { events.push("read slow"); return data().toString(); }))(host, parent, before);
	};
	const app: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		Loading({ children: ready, fallback: waiting })(host, parent, before);
		Loading({ children: slow, fallback: waiting })(host, parent, before);
	};
	const out = await renderToStream(app);
	assert out.html.includes("<p>ready</p>") && out.html.includes("<p>1</p>"), out.html;
	let lastRead = -1;
	for (let i = 0; i < events.length; i += 1) { if (events[i] === "read slow") { lastRead = i; } }
	const cleaned = events.indexOf("cleanup ready");
	assert cleaned > lastRead, "the settled sibling was cleaned up at " + cleaned.toString() + ", the slow read last ran at " + lastRead.toString() + ": " + events.join(",");
}

function sameIdsPage(slow: boolean): NeonNode {
	const content: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		Identified()(host, parent, before);
		if (slow) {
			reading("ids", 4, 9)(host, parent, before);
		} else {
			const data = createMemo((p: int32 | null): int32 => 9);
			el("p", [], [], dynText((): string => "ids=" + data().toString()))(host, parent, before);
		}
		Identified()(host, parent, before);
	};
	const fallback: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		Identified()(host, parent, before);
		Identified()(host, parent, before);
		Identified()(host, parent, before);
	};
	return <View>
		<Identified />
		<Loading fallback={fallback}>{content}</Loading>
		<Identified />
	</View>;
}

test "a Loading that waited gives its content and its next sibling the ids a single pass gives" {
	const waited = await renderToStream(sameIdsPage(true));
	const single = await renderToStream(sameIdsPage(false));
	assert waited.html === single.html, waited.html + " | " + single.html;
	assert waited.html.includes("ids=9"), waited.html;
}

test "a bare read after a pending Loading settles both, and each fetches once" {
	const app: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		Loading({ children: counted("loading-e", reading("loadingE", 25, 1)), fallback: waiting })(host, parent, before);
		reading("bareE", 3, 2)(host, parent, before);
	};
	const out = await renderToStream(app);
	assert out.html === "<p>loadingE=1</p><!----><p>bareE=2</p>", out.html;
	assert ran("loading-e") === 1, "one root pass: the bare read is a hole, not a reason to mount the page again: " + ran("loading-e").toString();
	assert fetched("loadingE") === 1 && fetched("bareE") === 1, fetched("loadingE").toString() + "/" + fetched("bareE").toString();
}

function hostilePage(spelled: string, inFallback: string): NeonNode {
	return <View>
		<Text>before</Text>
		<Loading fallback={<View><script>{inFallback}</script><Text>{inFallback}</Text></View>}>
			<Text>{spelled}</Text>
			<script>{spelled}</script>
			<style>{spelled}</style>
			<a title={spelled}>x</a>
			{reading("hostile", 3, 1)}
		</Loading>
		<Text>after</Text>
	</View>;
}

test "author content that spells a boundary's placeholder is written as author content" {
	const probe = await renderToStream(hostilePage("plain", "plain"));
	assert probe.records.includes("r[\"0000\"]"), "the boundary this test spells is owner id 0: " + probe.records;
	const open = "<template id=\"pl-0\"></template>";
	const close = "<!--pl-0-->";
	const spelled = "a" + open + "FAKE" + close + "b";
	const out = await renderToStream(hostilePage(spelled, "f" + close + "FALLBACK" + open));
	const b = "\\";
	assert out.html.includes("&lt;template id=\"pl-0\"&gt;&lt;/template&gt;FAKE&lt;!--pl-0--&gt;b"), "text: " + out.html;
	assert out.html.includes("<script>a" + b + "u003ctemplate id=\"pl-0\"></template>FAKE" + b + "u003c!--pl-0-->b</script>"), "script: " + out.html;
	assert out.html.includes("<style>a" + b + "3c template id=\"pl-0\"></template>FAKE" + b + "3c !--pl-0-->b</style>"), "style: " + out.html;
	assert out.html.includes("title=\"a&lt;template id=&quot;pl-0&quot;&gt;&lt;/template&gt;FAKE&lt;!--pl-0--&gt;b\""), "attribute: " + out.html;
	assert out.html.includes("<p>hostile=1</p><!----><span class=\"neon-text\">after</span>") && !out.html.includes("FALLBACK"), "structure: " + out.html;
	assert !out.html.includes("<template") && !out.html.includes("<!--pl-"), "a placeholder survived: " + out.html;
}

function readOf(name: string, slow: boolean, value: int32): NeonNode {
	if (slow) { return reading(name, 3, value); }
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createMemo((p: int32 | null): int32 => value);
		el("p", [], [], dynText((): string => name + "=" + data().toString()))(host, parent, before);
	};
}

function textShape(slow: boolean): NeonNode {
	return <Text>
		{"lead"}
		<Loading fallback={<Text>wait</Text>}>{"x"}{readOf("t", slow, 4)}{"y"}</Loading>
		{"tail"}
	</Text>;
}

function rowsShape(slow: boolean): NeonNode {
	return <View>
		<For each={[1, 2, 3]}>{(n: number, i: Accessor<number>): NeonNode =>
			<View>
				<Identified />
				<Loading fallback={<Identified />}>{readOf("row" + n.toString(), slow, n as int32)}<Identified /></Loading>
				<Identified />
			</View>}</For>
		<Identified />
	</View>;
}

function regionsShape(slow: boolean): NeonNode {
	return <View>
		<Loading fallback={<Text>wait</Text>}>
			<Show when={true}><Text>on</Text><Identified /></Show>
			<For each={[1, 2]} fallback={<Text>none</Text>}>{(n: number, i: Accessor<number>): NeonNode => <Text>{n.toString()}</Text>}</For>
			{readOf("reg", slow, 6)}
			<Show when={false} fallback={<Identified />}><Text>off</Text></Show>
		</Loading>
		<Identified />
	</View>;
}

test "a Loading that waited writes the bytes a single pass writes, whatever its content holds" {
	const a = await renderToStream(textShape(true));
	const b = await renderToStream(textShape(false));
	assert a.html === b.html && a.html.includes("<!--!-->"), "text: " + a.html + " | " + b.html;
	const c = await renderToStream(rowsShape(true));
	const d = await renderToStream(rowsShape(false));
	assert c.html === d.html && c.html.includes("row3=3"), "rows: " + c.html + " | " + d.html;
	const e = await renderToStream(regionsShape(true));
	const f = await renderToStream(regionsShape(false));
	assert e.html === f.html && e.html.includes("reg=6"), "regions: " + e.html + " | " + f.html;
}

function headShape(slow: boolean): NeonNode {
	return <View>
		<Head><title>first</title><meta name="description" content="first" /></Head>
		<Loading fallback={<Text>wait</Text>}>
			<Head><title>inside</title><meta name="robots" content="inside" /></Head>
			<Head><meta name="robots" content="inside again" /></Head>
			{readOf("head", slow, 1)}
		</Loading>
		<Loading fallback={<Text>wait</Text>}>
			<Head><meta name="author" content="second loading" /></Head>
			{readOf("head2", slow, 2)}
		</Loading>
		<Head><title>last</title></Head>
	</View>;
}

test "a Head inside a Loading that waited takes the place in the head it takes in a single pass" {
	const waited = await renderToStream(headShape(true));
	const single = await renderToStream(headShape(false));
	assert waited.head === single.head, waited.head + " | " + single.head;
}

function chained(name: string, first: int32, second: int32, a: int32, b: int32): NeonNode {
	const inner: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		Loading({ children: reading(name + "2", second, b), fallback: waiting })(host, parent, before);
	};
	const outer: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		reading(name + "1", first, a)(host, parent, before);
		inner(host, parent, before);
	};
	return Loading({ children: outer, fallback: waiting });
}

test "records follow the order of the page, not the order the waits ended in" {
	const app: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		chained("ordA", 24, 3, 1, 2)(host, parent, before);
		chained("ordB", 3, 3, 3, 4)(host, parent, before);
	};
	const out = await renderToStream(app);
	const at1 = out.records.indexOf("]=\"1\"");
	const at2 = out.records.indexOf("]=\"2\"");
	const at3 = out.records.indexOf("]=\"3\"");
	const at4 = out.records.indexOf("]=\"4\"");
	assert at1 > 0 && at2 > at1 && at3 > at2 && at4 > at3, out.records;
}

async function lateFailure(): Promise<string> {
	const content: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		reading("late", 3, 1)(host, parent, before);
		throw new Error("thrown after the wait");
	};
	let message = "";
	try {
		await renderToStream(Loading({ children: content, fallback: waiting }));
	} catch (e) {
		message = e.message;
	}
	return message;
}

test "content that throws after its Loading waited fails the render with that error" {
	const message = await lateFailure();
	assert message === "thrown after the wait", "[" + message + "]";
}

test "a Loading without a fallback is replaced by its settled content" {
	const app: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		el("i", [], [], text("first"))(host, parent, before);
		Loading({ children: reading("bare", 3, 5) })(host, parent, before);
		el("i", [], [], text("last"))(host, parent, before);
	};
	const out = await renderToStream(app);
	assert out.html === "<i>first</i><p>bare=5</p><!----><i>last</i>", out.html;
}
