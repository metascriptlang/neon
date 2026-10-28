import { sleepAsync } from "std/core/promise";
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { flush } from "../../src/core/runtime";
import { createRoot } from "../../src/core/owner";
import { Dispose } from "../../src/core/types";
import { createMemoryRoutingHistory } from "../../src/navigation/routingHistory";
import { Router, RouterProvider, createRoutes, createRouter } from "../../src/navigation/router";
import { FormData, formAction, submitForm, useSubmission, useSubmissions, Submission } from "../../src/navigation/index";

let inside: (() => NeonNode) | null = null;

function Probe(): NeonNode {
	return inside!();
}

function mount(body: () => NeonNode): Router {
	inside = body;
	const routes = createRoutes([{ path: "/", component: Probe }]);
	const made = createRouter(routes, createMemoryRoutingHistory({ url: "/", state: "" }));
	if (!made.ok) { throw new Error("router: " + made.error.toString()); }
	render(element(<RouterProvider router={made.value} />), mockHost(), mockNode("root") as unknown as HostNode);
	return made.value;
}

function fields(): FormData {
	const data = new FormData();
	data.append("title", "milk");
	data.append("tag", "a");
	data.append("tag", "b");
	return data;
}

const seen: string[] = [];

async function add(data: FormData): Promise<string> {
	seen.push((data.get("title") ?? "none") + "/" + data.getAll("tag").join("+"));
	return "saved " + (data.get("title") ?? "none");
}

async function refuse(data: FormData): Promise<string> {
	throw new Error("denied " + (data.get("title") ?? "none"));
}

function stateOf(sub: Submission<FormData, string> | null): string {
	if (sub === null) { return "none"; }
	if (sub.pending()) { return "pending"; }
	const error = sub.error();
	if (error !== null) { return "error:" + error.message; }
	return "result:" + (sub.result() ?? "");
}

test "FormData keeps every value of a name in order, get answers the first, and a missing name is null" {
	const data = fields();
	assert data.get("title") === "milk";
	assert data.getAll("tag").join("+") === "a+b";
	assert data.get("tag") === "a";
	assert data.get("none") === null;
	assert data.has("tag") && !data.has("none");
}

test "submitForm runs the action registered under a url with the form's fields and records its submission" {
	const addNote = formAction(add, "formAdd");
	let sub: (() => Submission<FormData, string> | null) | null = null;
	const router = mount((): NeonNode => {
		sub = useSubmission(addNote);
		return el("p", [], [], dynText((): string => stateOf(sub!())));
	});
	assert addNote.url === "https://action/formAdd", addNote.url;
	assert submitForm(router, addNote.url, fields());
	flush();
	assert seen.join("|") === "milk/a+b", seen.join("|");
	assert stateOf(sub!()).startsWith("pending") || stateOf(sub!()) === "result:saved milk", stateOf(sub!());
	await sleepAsync(10);
	flush();
	assert stateOf(sub!()) === "result:saved milk", stateOf(sub!());
	assert seen.length === 1;
	router.dispose();
}

test "submitForm answers false and runs nothing for a url no action owns" {
	const router = mount((): NeonNode => el("p", [], [], text("x")));
	assert !submitForm(router, "https://action/nobody", fields());
	assert !submitForm(router, "/_server/other", fields());
	router.dispose();
}

test "a form action that fails keeps its error in the submission and rejects nobody" {
	const refused = formAction(refuse, "formRefuse");
	let subs: (() => Submission<FormData, string>[]) | null = null;
	const router = mount((): NeonNode => {
		subs = useSubmissions(refused);
		return el("p", [], [], text("x"));
	});
	assert submitForm(router, refused.url, fields());
	await sleepAsync(10);
	flush();
	const list = subs!();
	assert list.length === 1 && stateOf(list[0]) === "error:denied milk", list.length.toString();
	router.dispose();
}

test "an action made under an owner leaves the registry when the owner is disposed, and a newer one under the same name replaces it" {
	const router = mount((): NeonNode => el("p", [], [], text("x")));
	let dispose: Dispose | null = null;
	createRoot((d: Dispose): number => {
		dispose = d;
		formAction(add, "formOwned");
		return 0;
	});
	assert submitForm(router, "https://action/formOwned", fields());
	dispose!();
	seen.length = 0;
	assert !submitForm(router, "https://action/formOwned", fields());
	assert seen.length === 0;
	formAction(add, "formSame");
	const newer = formAction(refuse, "formSame");
	assert submitForm(router, newer.url, fields());
	await sleepAsync(10);
	assert seen.length === 0, seen.join("|");
	router.dispose();
}
