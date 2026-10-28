import { sleepAsync } from "std/core/promise";
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { Host, HostNode, MockNode, mockHost, render, mockToString } from "../../src/render/host";
import { flush } from "../../src/core/runtime";
import { Loading } from "../../src/macros/ui/flow";
import { query, createAsync, revalidate, queryKey } from "../../src/navigation/index";
import { Gate, opened, release } from "../core/asyncClock";

interface User {
	name: string;
	n: int32;
}

const runs: string[] = [];

function ran(name: string): int32 {
	let n = 0;
	for (const r of runs) { if (r === name) { n += 1; } }
	return n;
}

async function fetchWith(gate: Gate, name: string, arg: string): Promise<User> {
	runs.push(name);
	const n = ran(name);
	await opened(gate);
	return { name: arg, n: n };
}

function label(u: User): string {
	return u.name + "#" + u.n.toString();
}

const waiting: NeonNode = el("b", [], [], text("loading"));

test "concurrent calls of one query and one argument run the function once and share its answer" {
	const gate = new Gate();
	const getUser = query((id: string): Promise<User> => fetchWith(gate, "dedupe", id), "dedupe");
	const first = getUser("a");
	const second = getUser("a");
	const other = getUser("b");
	await release(gate);
	assert label(await first) === "a#1", label(await first);
	assert label(await second) === "a#1", label(await second);
	assert label(await other) === "b#2", label(await other);
	assert ran("dedupe") === 2, "one run per argument: " + ran("dedupe").toString();
}

test "a settled answer is served from the cache within the preload timeout" {
	const gate = new Gate();
	gate.open = true;
	const getUser = query((id: string): Promise<User> => fetchWith(gate, "cached", id), "cached");
	assert label(await getUser("a")) === "a#1";
	assert label(await getUser("a")) === "a#1", "the second call is the cached answer";
	assert ran("cached") === 1, "one run: " + ran("cached").toString();
}

test "a query without arguments and one with two are keyed by name and argument list" {
	const gate = new Gate();
	gate.open = true;
	const none = query((): Promise<User> => fetchWith(gate, "none", ""), "none");
	const pair = query((a: string, b: int32): Promise<User> => fetchWith(gate, "pair", a + b.toString()), "pair");
	await none();
	await none();
	await pair("x", 1);
	await pair("x", 1);
	await pair("x", 2);
	assert ran("none") === 1 && ran("pair") === 2, ran("none").toString() + "/" + ran("pair").toString();
	assert queryKey("none") === "none[]", queryKey("none");
	assert queryKey("pair", "x", 1) === "pair[\"x\",1]", queryKey("pair", "x", 1);
}

test "revalidate with a key, a prefix or nothing runs the readers again" {
	const gate = new Gate();
	gate.open = true;
	const getUser = query((id: string): Promise<User> => fetchWith(gate, "reval", id), "reval");
	const host = mockHost();
	const root = host.createElement("root");
	const shown = (): string => mockToString(root as unknown as MockNode);
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const user = createAsync((): Promise<User> => getUser("a"));
		Loading({ children: el("p", [], [], dynText((): string => label(user()))), fallback: waiting })(h, parent, before);
	};
	const dispose = render(app, host, root);
	await sleepAsync(8);
	assert shown().includes("<p>a#1</p>"), shown();
	revalidate(queryKey("reval", "zzz"));
	flush();
	await sleepAsync(8);
	assert ran("reval") === 1, "an unmatched key leaves the reader: " + ran("reval").toString();
	revalidate(queryKey("reval", "a"));
	flush();
	await sleepAsync(8);
	assert shown().includes("<p>a#2</p>"), "the key re-ran the reader: " + shown();
	revalidate("reval");
	flush();
	await sleepAsync(8);
	assert shown().includes("<p>a#3</p>"), "the prefix re-ran the reader: " + shown();
	revalidate();
	flush();
	await sleepAsync(8);
	assert shown().includes("<p>a#4</p>"), "no key re-ran the reader: " + shown();
	dispose();
}

test "createAsync shows the fallback while its query is pending and the answer after" {
	const gate = new Gate();
	const getUser = query((id: string): Promise<User> => fetchWith(gate, "pending", id), "pending");
	const host = mockHost();
	const root = host.createElement("root");
	const shown = (): string => mockToString(root as unknown as MockNode);
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const user = createAsync((): Promise<User> => getUser("a"));
		Loading({ children: el("p", [], [], dynText((): string => label(user()))), fallback: waiting })(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown().includes("<b>loading</b>") && !shown().includes("<p>"), shown();
	await release(gate);
	assert shown().includes("<p>a#1</p>") && !shown().includes("loading"), shown();
	assert ran("pending") === 1, ran("pending").toString();
	dispose();
}
