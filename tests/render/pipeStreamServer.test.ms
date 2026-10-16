import { sleepAsync } from "std/core/promise";
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { Host, HostNode } from "../../src/render/hostTypes";
import { Accessor } from "../../src/core/signal";
import { createAsyncMemo } from "../../src/core/memo";
import { Loading, Errored } from "../../src/macros/ui/flow";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { View, Text } from "../../src/components/primitives";
import { renderToStream, streamRender, StreamSink, SsrMarkup } from "../../src/render/ssr";

const waiting: NeonNode = el("b", [], [], text("loading"));

async function after(ms: int32, value: int32): Promise<int32> {
	await sleepAsync(ms);
	return value;
}

async function afterFail(ms: int32, failure: Error): Promise<int32> {
	await sleepAsync(ms);
	throw failure;
}

function reading(name: string, ms: int32, value: int32): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => after(ms, value));
		el("p", [], [], dynText((): string => name + "=" + data().toString()))(host, parent, before);
	};
}

class Flag {
	up: boolean;

	constructor(up: boolean) {
		this.up = up;
	}
}

// The slow sibling settles only after the quick one's fragment was written, so the order holds under any load.
async function afterFlag(flag: Flag, value: int32): Promise<int32> {
	while (!flag.up) { await sleepAsync(1); }
	return value;
}

function readingAfter(name: string, flag: Flag, value: int32): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => afterFlag(flag, value));
		el("p", [], [], dynText((): string => name + "=" + data().toString()))(host, parent, before);
	};
}

class Collected {
	chunks: string[] = [];
	ended: int32 = 0;
	quickWritten: Flag = new Flag(false);
}

function sinkOf(c: Collected): StreamSink {
	return {
		write: (chunk: string): void => {
			c.chunks.push(chunk);
			if (c.chunks.length >= 2) { c.quickWritten.up = true; }
		},
		end: (): void => { c.ended += 1; },
	};
}

function siblings(slowFirst: boolean, quickWritten: Flag): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		Loading({ children: slowFirst ? readingAfter("first", quickWritten, 1) : reading("first", 3, 1), fallback: waiting })(host, parent, before);
		Loading({ children: slowFirst ? reading("second", 3, 2) : readingAfter("second", quickWritten, 2), fallback: waiting })(host, parent, before);
	};
}

const OPEN = "<template id=\"pl-";
const CALL = "$df(\"";
const DEFINITION = "function $df";

function placeholders(shell: string): string[] {
	const ids: string[] = [];
	let at = shell.indexOf(OPEN);
	while (at >= 0) {
		const from = at + OPEN.length;
		ids.push(shell.slice(from, shell.indexOf("\"", from)));
		at = shell.indexOf(OPEN, from);
	}
	return ids;
}

function withoutStyle(chunk: string): string {
	return chunk.startsWith("<style>") ? chunk.slice(chunk.indexOf("</style>") + "</style>".length) : chunk;
}

function withoutRecords(chunk: string): string {
	const at = chunk.indexOf("<script>");
	return at < 0 ? chunk : chunk.slice(0, at);
}

function fragmentId(whole: string): string {
	const chunk = withoutStyle(whole);
	const open = "<template id=\"";
	if (!chunk.startsWith(open)) { return "no fragment: " + chunk; }
	return chunk.slice(open.length, chunk.indexOf("\"", open.length));
}

// What $df does to the page: the placeholder, its fallback and its closing comment give way to the template's content.
function swapped(page: string, whole: string): string {
	const chunk = withoutStyle(whole);
	const id = fragmentId(chunk);
	const content = chunk.slice(("<template id=\"" + id + "\">").length, chunk.lastIndexOf("</template>"));
	const open = OPEN + id + "\"></template>";
	const close = "<!--pl-" + id + "-->";
	const from = page.indexOf(open);
	return page.slice(0, from) + content + page.slice(page.indexOf(close, from) + close.length);
}

function applied(c: Collected): string {
	let page = withoutRecords(withoutStyle(c.chunks[0]));
	for (let i = 1; i < c.chunks.length; i += 1) { page = swapped(page, c.chunks[i]); }
	return page;
}

function count(whole: string, part: string): int32 {
	let n = 0;
	let at = whole.indexOf(part);
	while (at >= 0) {
		n += 1;
		at = whole.indexOf(part, at + part.length);
	}
	return n;
}

function joined(c: Collected): string {
	let all = "";
	for (const chunk of c.chunks) { all += chunk; }
	return all;
}

async function streamed(view: NeonNode, c: Collected): Promise<SsrMarkup> {
	const r = streamRender(view);
	r.pipe(sinkOf(c));
	return await r.markup();
}

test "siblings stream in the order their waits end, after one shell holding both fallbacks" {
	const c = new Collected();
	const out = await streamed(siblings(true, c.quickWritten), c);
	assert c.chunks.length === 3 && c.ended === 1, "shell and two fragments, ended once: " + c.chunks.length.toString() + "/" + c.ended.toString();
	const ids = placeholders(c.chunks[0]);
	assert ids.length === 2, c.chunks[0];
	assert count(c.chunks[0], "<b>loading</b>") === 2 && !c.chunks[0].includes("first=") && !c.chunks[0].includes("second="), "the shell shows both fallbacks: " + c.chunks[0];
	assert fragmentId(c.chunks[1]) === ids[1] && c.chunks[1].includes("<p>second=2</p>"), "the quick sibling streams first: " + c.chunks[1];
	assert fragmentId(c.chunks[2]) === ids[0] && c.chunks[2].includes("<p>first=1</p>"), "the slow sibling streams second: " + c.chunks[2];
	assert applied(c) === out.html, applied(c) + " | " + out.html;
}

test "the same siblings with their delays swapped stream in the swapped order" {
	const c = new Collected();
	const out = await streamed(siblings(false, c.quickWritten), c);
	const ids = placeholders(c.chunks[0]);
	assert c.chunks.length === 3, c.chunks.length.toString();
	assert fragmentId(c.chunks[1]) === ids[0] && fragmentId(c.chunks[2]) === ids[1], fragmentId(c.chunks[1]) + "," + fragmentId(c.chunks[2]) + " against " + ids.join(",");
	assert applied(c) === out.html, applied(c) + " | " + out.html;
}

function nested(outerMs: int32, innerMs: int32): NeonNode {
	const inner: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		Loading({ children: reading("inner", innerMs, 2), fallback: el("i", [], [], text("inner waits")) })(host, parent, before);
	};
	const outer: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		reading("outer", outerMs, 1)(host, parent, before);
		inner(host, parent, before);
	};
	return Loading({ children: outer, fallback: waiting });
}

test "a nested boundary streams after its parent's fragment, which still holds the nested placeholder" {
	const c = new Collected();
	const out = await streamed(nested(3, 20), c);
	assert c.chunks.length === 3, "shell, parent, nested: " + c.chunks.length.toString();
	const parent = placeholders(c.chunks[0])[0];
	assert placeholders(c.chunks[0]).length === 1 && c.chunks[0].includes("<b>loading</b>"), c.chunks[0];
	assert fragmentId(c.chunks[1]) === parent && c.chunks[1].includes("<p>outer=1</p>"), c.chunks[1];
	const child = placeholders(c.chunks[1]);
	assert child.length === 1 && c.chunks[1].includes("<i>inner waits</i>") && !c.chunks[1].includes("inner="), "the parent carries the nested placeholder and its fallback: " + c.chunks[1];
	assert fragmentId(c.chunks[2]) === child[0] && c.chunks[2].includes("<p>inner=2</p>"), c.chunks[2];
	assert applied(c) === out.html, applied(c) + " | " + out.html;
}

test "a nested boundary whose read is quicker than its parent's still follows the parent's fragment" {
	const c = new Collected();
	const out = await streamed(nested(20, 3), c);
	assert c.chunks.length === 3, c.chunks.length.toString();
	const parent = placeholders(c.chunks[0])[0];
	assert fragmentId(c.chunks[1]) === parent, "the parent first: " + c.chunks[1];
	assert fragmentId(c.chunks[2]) === placeholders(c.chunks[1])[0], c.chunks[2];
	assert applied(c) === out.html, applied(c) + " | " + out.html;
}

function bareThenLoading(): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		reading("bare", 3, 7)(host, parent, before);
		Loading({ children: reading("late", 20, 9), fallback: waiting })(host, parent, before);
	};
}

test "the shell carries the records already settled after its markup, and a fragment carries its own" {
	const c = new Collected();
	await streamed(bareThenLoading(), c);
	assert c.chunks.length === 2, c.chunks.length.toString();
	const shell = c.chunks[0];
	assert shell.includes("<p>bare=7</p>") && shell.includes("]=\"7\"</script>"), "the settled read is in the shell: " + shell;
	assert shell.indexOf("]=\"7\"") > shell.lastIndexOf("<!--pl-"), "the record follows the markup: " + shell;
	assert !shell.includes("]=\"9\""), "the pending read has no record yet: " + shell;
	assert c.chunks[1].includes("]=\"9\"</script>") && !c.chunks[1].includes("]=\"7\""), "the fragment carries its own record only: " + c.chunks[1];
	assert c.chunks[1].indexOf("</template>") < c.chunks[1].indexOf("]=\"9\"") && c.chunks[1].indexOf("]=\"9\"") < c.chunks[1].indexOf(CALL), "template, record, then the swap: " + c.chunks[1];
}

test "a page with no pending boundary is one chunk with no swap script, and the sink ends once" {
	const c = new Collected();
	const out = await streamed(el("p", [], [], text("static")), c);
	assert c.chunks.length === 1 && c.ended === 1, c.chunks.length.toString() + "/" + c.ended.toString();
	assert c.chunks[0] === "<p>static</p>" && out.html === "<p>static</p>", c.chunks[0];
}

test "the swap function is sent once, before the first call, however many boundaries stream" {
	const c = new Collected();
	const app: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		Loading({ children: reading("a", 3, 1), fallback: waiting })(host, parent, before);
		Loading({ children: reading("b", 12, 2), fallback: waiting })(host, parent, before);
		Loading({ children: reading("c", 24, 3), fallback: waiting })(host, parent, before);
	};
	await streamed(app, c);
	assert c.chunks.length === 4, c.chunks.length.toString();
	const definitions = count(joined(c), DEFINITION);
	const calls = count(joined(c), CALL);
	assert definitions === 1, "the definition: " + definitions.toString();
	assert calls === 3, "one call per boundary: " + calls.toString();
	const first = c.chunks[1];
	assert first.indexOf(DEFINITION) >= 0 && first.indexOf(DEFINITION) < first.indexOf(CALL), "the definition comes first in the first script: " + first;
	assert !c.chunks[2].includes(DEFINITION) && !c.chunks[3].includes(DEFINITION), "later scripts only call it";
}

test "a second consumer of the same render throws and the first keeps its stream" {
	const c = new Collected();
	const r = streamRender(siblings(true, c.quickWritten));
	r.pipe(sinkOf(c));
	let message = "";
	try {
		r.pipe(sinkOf(new Collected()));
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "streamRender result was already consumed via `pipe`; cannot also consume it via `pipe`. Use exactly one of `pipe`, `pipeTo`, or `readable`.", message;
	const out = await r.markup();
	assert c.chunks.length === 3 && c.ended === 1, "the first sink still got the whole stream: " + c.chunks.length.toString();
	assert out.html.includes("first=1") && out.html.includes("second=2"), out.html;
}

test "awaiting the render beside a pipe gives the awaited form of renderToStream" {
	const c = new Collected();
	const beside = await streamed(siblings(true, c.quickWritten), c);
	const alone = await renderToStream(siblings(true, new Flag(true)));
	assert beside.html === alone.html && beside.css === alone.css && beside.head === alone.head, beside.html + " | " + alone.html;
	assert beside.records === alone.records, beside.records + " | " + alone.records;
}

test "a sink attached after the boundaries settled receives the chunks an early sink received" {
	const early = new Collected();
	await streamed(nested(3, 8), early);
	const late = new Collected();
	const r = streamRender(nested(3, 8));
	await r.markup();
	r.pipe(sinkOf(late));
	assert late.chunks.length === early.chunks.length && late.ended === 1, late.chunks.length.toString() + "/" + early.chunks.length.toString();
	for (let i = 0; i < early.chunks.length; i += 1) {
		assert late.chunks[i] === early.chunks[i], "chunk " + i.toString() + ": " + late.chunks[i] + " | " + early.chunks[i];
	}
}

const looks = createStyles({
	shellLook: { padding: 3 },
	lateLook: { padding: 9, backgroundColor: "#eee" },
});

function styledPage(): NeonNode {
	return <View style={looks.shellLook}>
		<Loading fallback={<Text>wait</Text>}>
			{reading("styled", 4, 5)}
			<View style={looks.lateLook}><Text>{"styled"}</Text></View>
			<View style={looks.shellLook}><Text>{"again"}</Text></View>
		</Loading>
	</View>;
}

test "a rule only a fragment needs travels in front of that fragment, once, and the shell's rule is not repeated" {
	const c = new Collected();
	const out = await streamed(styledPage(), c);
	assert c.chunks.length === 2, c.chunks.length.toString();
	assert c.chunks[0].startsWith("<style>") && c.chunks[0].includes("padding:3px") && !c.chunks[0].includes("padding:9px"), "the shell holds its own rule: " + c.chunks[0];
	assert c.chunks[1].startsWith("<style>") && c.chunks[1].includes("padding:9px") && !c.chunks[1].includes("padding:3px"), "the fragment brings the rule only it uses: " + c.chunks[1];
	assert out.css.includes("padding:3px") && out.css.includes("padding:9px"), out.css;
}

function sharedRulePage(): NeonNode {
	return <View style={looks.shellLook}>
		<Loading fallback={<Text>wait</Text>}>
			{reading("shared", 4, 5)}
			<View style={looks.lateLook}><Text>{"in"}</Text></View>
		</Loading>
		<View style={looks.lateLook}><Text>{"shell"}</Text></View>
	</View>;
}

test "a rule a fragment and a later element of the shell both use is written with the shell and not repeated" {
	const c = new Collected();
	await streamed(sharedRulePage(), c);
	assert c.chunks.length === 2, c.chunks.length.toString();
	assert c.chunks[0].includes("padding:9px"), "the shell holds the rule its own element uses: " + c.chunks[0];
	assert !c.chunks[1].includes("padding:9px"), "the fragment does not repeat it: " + c.chunks[1];
}

test "a rejected read under Errored streams the caught fallback and its error record" {
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
	const c = new Collected();
	const out = await streamed(view, c);
	assert c.chunks.length === 2, c.chunks.length.toString();
	assert c.chunks[1].includes("<em>caught ") && c.chunks[1].includes(".e[\""), c.chunks[1];
	when (debug) {
		assert c.chunks[1].includes("db password=hunter2"), c.chunks[1];
	} else {
		assert !joined(c).includes("hunter2") && c.chunks[1].includes("Internal Server Error"), joined(c);
	}
	assert applied(c) === out.html, applied(c) + " | " + out.html;
}

async function lateFailure(c: Collected, inSpot: boolean): Promise<string> {
	const thrown = new Flag(false);
	const content: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => after(3, 1));
		const fail = (): string => {
			const v = data();
			thrown.up = true;
			throw new Error("thrown after the wait");
		};
		if (inSpot) {
			el("p", [], [], dynText(fail))(host, parent, before);
		} else {
			fail();
		}
	};
	const app: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		Loading({ children: content, fallback: waiting })(host, parent, before);
		Loading({ children: readingAfter("other", thrown, 2), fallback: waiting })(host, parent, before);
	};
	const r = streamRender(app);
	r.pipe(sinkOf(c));
	let message = "";
	try {
		await r.markup();
	} catch (e) {
		message = e.message;
	}
	return message;
}

test "a boundary that fails after the shell ends the stream with the shell alone, and the awaited form rejects" {
	const c = new Collected();
	const message = await lateFailure(c, false);
	assert message === "thrown after the wait", "[" + message + "]";
	assert c.chunks.length === 1 && c.ended === 1, "the shell, then the end: " + c.chunks.length.toString() + "/" + c.ended.toString();
	assert count(c.chunks[0], "<b>loading</b>") === 2, c.chunks[0];
}

test "a text spot that fails once its source settled ends the stream the same way: the shell alone, and the awaited form rejects" {
	const c = new Collected();
	const message = await lateFailure(c, true);
	assert message === "thrown after the wait", "[" + message + "]";
	assert c.chunks.length === 1 && c.ended === 1, "the shell, then the end: " + c.chunks.length.toString() + "/" + c.ended.toString();
	assert count(c.chunks[0], "<b>loading</b>") === 2, c.chunks[0];
}

async function firstPassFailure(c: Collected): Promise<string> {
	const broken: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		throw new Error("broken before the shell");
	};
	const r = streamRender(broken);
	r.pipe(sinkOf(c));
	let message = "";
	try {
		await r.markup();
	} catch (e) {
		message = e.message;
	}
	return message;
}

test "a render that throws before its shell writes nothing and ends the sink" {
	const c = new Collected();
	const message = await firstPassFailure(c);
	assert message === "broken before the shell", "[" + message + "]";
	assert c.chunks.length === 0 && c.ended === 1, c.chunks.length.toString() + "/" + c.ended.toString();
}
