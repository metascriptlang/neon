import { domHost } from "../../src/platform/browser/dom";
import { createBrowserRoutingHistory, followSubmits } from "../../src/platform/browser/routingHistory";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { sleepAsync } from "std/core/promise";
import { NeonNode } from "../../src/render/node";
import { FormData, Submission, formAction, submitForm, useSubmission } from "../../src/navigation/index";
import { RouterProvider, createRouter, createRoutes } from "../../src/navigation/router";

extern function js(code: cstring): string from "String((0, eval)(#))";

extern class HTMLElement {
	extern appendChild(child: HTMLElement): void;
	extern remove(): void;
}

extern class document {
	static body: HTMLElement;
	static extern createElement(tag: cstring): HTMLElement;
}

const calls: string[] = [];

async function add(data: FormData): Promise<string> {
	calls.push("add " + (data.get("title") ?? "none") + " " + (data.get("how") ?? "none") + " " + data.getAll("tag").join("+"));
	return "saved " + (data.get("title") ?? "none");
}

async function other(data: FormData): Promise<string> {
	calls.push("other " + (data.get("how") ?? "none"));
	return "other";
}

const addNote = formAction(add, "browserAdd");
const otherNote = formAction(other, "browserOther");

function stateOf(sub: Submission<FormData, string> | null): string {
	if (sub === null) { return "none"; }
	if (sub.pending()) { return "pending"; }
	return "result:" + (sub.result() ?? "");
}

function Compose(): NeonNode {
	const sub = useSubmission(addNote);
	return <div>
		<p id="state">{stateOf(sub())}</p>
		<form id="add" action={addNote.url} method="post">
			<input name="title" value="milk" />
			<input name="tag" value="a" />
			<input name="tag" value="b" />
			<button id="plain" type="submit" name="how" value="plain">Add</button>
			<button id="alt" type="submit" name="how" value="alt" formaction={otherNote.url}>Other</button>
		</form>
		<form id="foreign" action="/elsewhere" method="post"><button id="foreignGo" type="submit">Go</button></form>
		<form id="get" action={addNote.url}><button id="getGo" type="submit">Go</button></form>
	</div>;
}

const probe = "window.__seen = []; window.__errors = []; window.addEventListener('submit', e => { window.__seen.push(e.defaultPrevented); e.preventDefault(); }); window.addEventListener('error', e => { window.__errors.push(String(e.error && e.error.message || e.message)); e.preventDefault(); }); 1";

function submit(form: string, submitter: string): void {
	js("document.getElementById('" + form + "').requestSubmit(document.getElementById('" + submitter + "'))");
}

test "a form bound to an action submits through it on the client, with the form's fields and the submitter's" {
	const history = createBrowserRoutingHistory();
	const original = history.read();
	history.replace({ url: "/form", state: "" });
	const routes = createRoutes([{ path: "/form", component: Compose }]);
	const created = createRouter(routes, history);
	assert created.ok;
	if (!created.ok) { return; }
	const router = created.value;
	const mount = document.createElement("div");
	document.body.appendChild(mount);
	const dispose = render(<RouterProvider router={router} />, domHost(), mount as unknown as HostNode);
	const stop = followSubmits((url: string, data: FormData): boolean => submitForm(router, url, data));
	js(probe);
	try {
		submit("add", "plain");
		await sleepAsync(30);
		assert calls.join("|") === "add milk plain a+b", calls.join("|");
		assert js("document.getElementById('state').textContent") === "result:saved milk", js("document.getElementById('state').textContent");
		assert js("window.__seen.join()") === "true", "a handled submit is prevented before the browser's own: " + js("window.__seen.join()");
		assert history.read().url === "/form", history.read().url;
		calls.length = 0;
		js("window.__seen = []");
		submit("add", "alt");
		await sleepAsync(30);
		assert calls.join("|") === "other alt", "formaction of the submitter wins: " + calls.join("|");
		calls.length = 0;
		js("window.__seen = []");
		submit("foreign", "foreignGo");
		await sleepAsync(30);
		assert calls.length === 0;
		assert js("window.__seen.join()") === "false", "an action no one owns is left to the browser";
		submit("get", "getGo");
		await sleepAsync(30);
		assert calls.length === 0, "a GET form of an action is refused: " + calls.join("|");
		assert js("window.__errors.join()") === "Only POST forms are supported for Actions", js("window.__errors.join()");
		js("document.getElementById('add').addEventListener('submit', e => e.preventDefault(), true)");
		submit("add", "plain");
		await sleepAsync(30);
		assert calls.length === 0, "a submit someone already prevented is left alone: " + calls.join("|");
		stop();
		js("window.__seen = []");
		submit("add", "plain");
		await sleepAsync(30);
		assert calls.length === 0, "after dispose: " + calls.join("|");
	} finally {
		stop();
		dispose();
		router.dispose();
		mount.remove();
		history.replace(original);
	}
}
