import { sleepAsync } from "std/core/promise";
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { Host, HostNode, MockNode, mockHost, render, mockToString } from "../../src/render/host";
import { flush } from "../../src/core/runtime";
import { Loading } from "../../src/macros/ui/flow";
import { query, createAsync, action, useAction, useSubmission, useSubmissions, Submission } from "../../src/navigation/index";
import { Gate, opened, release } from "../core/asyncClock";

const runs: string[] = [];

function ran(name: string): int32 {
	let n = 0;
	for (const r of runs) { if (r === name) { n += 1; } }
	return n;
}

async function save(gate: Gate, name: string, input: string): Promise<string> {
	runs.push(name);
	await opened(gate);
	return input + "!";
}

async function failingSave(gate: Gate, name: string, input: string): Promise<string> {
	runs.push(name);
	await opened(gate);
	if (ran(name) === 1) { throw new Error("denied " + input); }
	return input + "!";
}

function stateOf(sub: Submission<string, string> | null): string {
	if (sub === null) { return "none"; }
	if (sub.pending()) { return "pending:" + sub.input; }
	const error = sub.error();
	if (error !== null) { return "error:" + error.message; }
	return "result:" + (sub.result() ?? "");
}

test "an action call runs its function once and its submission goes from pending to result" {
	const gate = new Gate();
	const save1 = action((input: string): Promise<string> => save(gate, "once", input), "once");
	const host = mockHost();
	const root = host.createElement("root");
	const shown = (): string => mockToString(root as unknown as MockNode);
	let call: ((input: string) => Promise<string>) | null = null;
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		call = useAction(save1);
		const sub = useSubmission(save1);
		el("p", [], [], dynText((): string => stateOf(sub())))(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown().includes("<p>none</p>"), shown();
	const answer = call!("a");
	flush();
	assert shown().includes("<p>pending:a</p>"), shown();
	await release(gate);
	assert (await answer) === "a!";
	flush();
	assert shown().includes("<p>result:a!</p>"), shown();
	assert ran("once") === 1, ran("once").toString();
	dispose();
}

test "an error lands in the submission, rejects the call, and retry runs the function again" {
	const gate = new Gate();
	gate.open = true;
	const save2 = action((input: string): Promise<string> => failingSave(gate, "retry", input), "retry");
	const subs = useSubmissions(save2);
	let message = "";
	try { await useAction(save2)("b"); } catch (error) { message = error.message; }
	flush();
	assert message === "denied b", message;
	const list = subs();
	assert list.length === 1 && stateOf(list[0]) === "error:denied b", list.length.toString();
	assert (await list[0].retry()) === "b!";
	flush();
	assert stateOf(list[0]) === "result:b!", stateOf(list[0]);
	assert ran("retry") === 2, ran("retry").toString();
}

interface Note {
	text: string;
}

async function fetchNote(name: string): Promise<Note> {
	runs.push(name);
	return { text: "note#" + ran(name).toString() };
}

test "settling an action revalidates a query a reader holds, and a failing action does not" {
	const getNote = query((): Promise<Note> => fetchNote("note"), "note");
	const gate = new Gate();
	gate.open = true;
	const edit = action((input: string): Promise<string> => failingSave(gate, "edit", input), "edit");
	const host = mockHost();
	const root = host.createElement("root");
	const shown = (): string => mockToString(root as unknown as MockNode);
	const waiting: NeonNode = el("b", [], [], text("loading"));
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const note = createAsync((): Promise<Note> => getNote());
		Loading({ children: el("p", [], [], dynText((): string => note().text)), fallback: waiting })(h, parent, before);
	};
	const dispose = render(app, host, root);
	await sleepAsync(8);
	assert shown().includes("<p>note#1</p>"), shown();
	let message = "";
	try { await useAction(edit)("x"); } catch (error) { message = error.message; }
	flush();
	await sleepAsync(8);
	assert message === "denied x" && ran("note") === 1, "an error leaves the query: " + ran("note").toString();
	assert (await useAction(edit)("y")) === "y!";
	flush();
	await sleepAsync(8);
	assert ran("note") === 2 && shown().includes("<p>note#2</p>"), "one rerun after the settle: " + shown();
	dispose();
}

test "useSubmissions lists the submissions of one action, narrowed by a filter, and clear drops one" {
	const gate = new Gate();
	gate.open = true;
	const first = action((input: string): Promise<string> => save(gate, "list", input), "list");
	const other = action((input: string): Promise<string> => save(gate, "list-other", input), "list-other");
	const all = useSubmissions(first);
	const onlyB = useSubmissions(first, (input: string): boolean => input === "b");
	const latest = useSubmission(first);
	assert all().length === 0 && latest() === null;
	await useAction(first)("a");
	await useAction(first)("b");
	await useAction(other)("c");
	flush();
	assert all().length === 2 && onlyB().length === 1, all().length.toString();
	assert stateOf(latest()) === "result:b!", stateOf(latest());
	all()[1].clear();
	flush();
	assert all().length === 1 && stateOf(latest()) === "result:a!", all().length.toString();
}

async function nothing(input: string): Promise<string | null> {
	runs.push("nothing");
	// Parked on ~/metascript/.inbox/compiler/2026-10-08-async-return-null-literal-refused.md: `return null;` in place of this typed constant.
	const none: string | null = null;
	return none;
}

test "an action that answers null leaves no submission behind" {
	const quiet = action(nothing, "quiet");
	await useAction(quiet)("a");
	flush();
	assert useSubmissions(quiet)().length === 0;
}
