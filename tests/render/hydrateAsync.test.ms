import { NeonNode, el, text, dynText } from "../../src/render/node";
import { render, hydrate, mockHost, mockNode, mockToString, MockNode, Host, HostNode } from "../../src/render/host";
import { createSignal, Accessor } from "../../src/core/signal";
import { createAsyncMemo } from "../../src/render/hydrateMemo";
import { flush } from "../../src/core/runtime";
import { Errored, Loading } from "../../src/macros/ui/flow";
import { unclaimed } from "../../src/render/claim";
import { putRecord, putError, hasRecord, clearRecords } from "../../src/render/hydrationRecords";
import { Gate, release, opened } from "../core/asyncClock";

interface Note {
	text: string;
	n: int32;
}

interface Basket {
	items: string[];
	total: float64;
}

let sent: int32 = 0;

when (js) {
	extern function spyFetch(): void from
		"(() => { const spy = () => { globalThis.neonFetchCalls++; return Promise.resolve(new Response('')); }; globalThis.neonFetchCalls = 0; globalThis.neonRealFetch = globalThis.fetch; globalThis.fetch = spy; })()";
	extern function unspyFetch(): void from "(() => { globalThis.fetch = globalThis.neonRealFetch; })()";
	extern function callFetch(url: cstring): void from "(u => { fetch(u); })(#)";
	extern function fetchCalls(): int32 from "(globalThis.neonFetchCalls)";
}

function startCounting(): void {
	sent = 0;
	when (js) { spyFetch(); }
}

function stopCounting(): void {
	when (js) { unspyFetch(); }
}

function request(): void {
	when (js) { callFetch("/note"); } else { sent += 1; }
}

function requestsSent(): int32 {
	when (js) { return fetchCalls(); } else { return sent; }
}

async function loadNote(gate: Gate, n: int32): Promise<Note> {
	request();
	await opened(gate);
	return { text: "live", n: n };
}

async function loadFrom(gate: Gate, dep: Accessor<int32>): Promise<Note> {
	const n = dep();
	request();
	await opened(gate);
	return { text: "live", n: n };
}

async function loadBasket(gate: Gate, n: int32): Promise<Basket> {
	request();
	await opened(gate);
	return { items: ["live"], total: n as float64 };
}

function silence(n: MockNode): void {
	n.events = [];
	for (const k of n.children) { silence(k); }
}

function served(tree: NeonNode): MockNode {
	const root = mockNode("root");
	const dispose = render(tree, mockHost(), root as unknown as HostNode, "");
	dispose();
	silence(root);
	return root;
}

function readNow(read: () => string): string {
	try {
		return read();
	} catch (e) {
		return "pending";
	}
}

function line(read: () => string): NeonNode {
	return el("p", [], [], dynText(read));
}

test "a hydrating async memo with a record reads it at creation and sends no request, and a dependency change recomputes it" {
	clearRecords();
	startCounting();
	try {
		putRecord("0", JSON.stringify<Note>({ text: "srv", n: 7 }));
		const root = served(line((): string => "srv=7"));
		const before = mockToString(root);
		const gate = new Gate();
		const [dep, setDep] = createSignal<int32>(1);
		let first = "";
		const page = (): NeonNode => (host: Host, parent: HostNode, before: HostNode | null): void => {
			const data = createAsyncMemo((p: Note | null): Promise<Note> => loadNote(gate, dep()));
			first = readNow((): string => data().text + "=" + data().n.toString());
			line((): string => data().text + "=" + data().n.toString())(host, parent, before);
		};
		const dispose = hydrate(page(), mockHost(), root as unknown as HostNode);
		try {
			assert first === "srv=7", "the first read was the record's value: " + first;
			assert mockToString(root) === before, mockToString(root);
			when (js) {
				assert requestsSent() === 0, "the trace run swapped fetch: " + requestsSent().toString();
			} else {
				assert requestsSent() === 1, "one discarded trace run: " + requestsSent().toString();
			}
			const traced = requestsSent();
			setDep(2);
			flush();
			assert requestsSent() === traced + 1, "a dependency change ran the compute for real: " + requestsSent().toString();
			await release(gate);
			assert mockToString(root) === "<root><p>live=2</p></root>", mockToString(root);
		} finally {
			dispose();
		}
	} finally {
		stopCounting();
		clearRecords();
	}
}

test "a record of an array and a number is adopted the same way, and a second memo keeps its own record" {
	clearRecords();
	startCounting();
	try {
		putRecord("0", JSON.stringify<Basket>({ items: ["a", "b"], total: 2.5 }));
		putRecord("1", JSON.stringify<Note>({ text: "two", n: 2 }));
		let both = "";
		const pair = (): NeonNode => (host: Host, parent: HostNode, before: HostNode | null): void => {
			const gate = new Gate();
			const basket = createAsyncMemo((p: Basket | null): Promise<Basket> => loadBasket(gate, 1));
			const note = createAsyncMemo((p: Note | null): Promise<Note> => loadNote(gate, 2));
			both = readNow((): string => basket().items.join("+") + "/" + basket().total.toString() + "/" + note().text);
			line((): string => both)(host, parent, before);
		};
		const root = served(line((): string => "a+b/2.5/two"));
		const before = mockToString(root);
		const dispose = hydrate(pair(), mockHost(), root as unknown as HostNode);
		try {
			assert both === "a+b/2.5/two", "both memos read their own record: " + both;
			assert mockToString(root) === before, mockToString(root);
		} finally {
			dispose();
		}
	} finally {
		stopCounting();
		clearRecords();
	}
}

test "a dependency read inside the async function before its first await is kept from the trace run" {
	clearRecords();
	startCounting();
	try {
		putRecord("0", JSON.stringify<Note>({ text: "srv", n: 7 }));
		const gate = new Gate();
		const [dep, setDep] = createSignal<int32>(1);
		let first = "";
		const page: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
			const data = createAsyncMemo((p: Note | null): Promise<Note> => loadFrom(gate, dep));
			first = readNow((): string => data().text + "=" + data().n.toString());
			line((): string => data().text + "=" + data().n.toString())(host, parent, before);
		};
		const root = served(line((): string => "srv=7"));
		const dispose = hydrate(page, mockHost(), root as unknown as HostNode);
		try {
			assert first === "srv=7", first;
			const traced = requestsSent();
			setDep(4);
			flush();
			assert requestsSent() === traced + 1, "the write reached the memo through the trace run's read: " + requestsSent().toString();
			await release(gate);
			assert mockToString(root) === "<root><p>live=4</p></root>", mockToString(root);
		} finally {
			dispose();
		}
	} finally {
		stopCounting();
		clearRecords();
	}
}

test "a hydrating async memo with no record computes fresh and is pending until it lands" {
	clearRecords();
	startCounting();
	try {
		const gate = new Gate();
		let pending = false;
		let data: Accessor<Note> | null = null;
		const root = mockNode("root");
		const node: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
			const m = createAsyncMemo((p: Note | null): Promise<Note> => loadNote(gate, 5));
			data = m;
			try {
				m();
			} catch (e) {
				pending = true;
			}
		};
		const dispose = hydrate(node, mockHost(), root as unknown as HostNode);
		try {
			assert pending, "no record, so the read waits for the compute";
			assert requestsSent() === 1, "one request: " + requestsSent().toString();
			await release(gate);
			assert (data as Accessor<Note>)().n === 5, "the live answer landed";
		} finally {
			dispose();
		}
	} finally {
		stopCounting();
		clearRecords();
	}
}

test "an async memo created after hydration ignores a record with its id and computes fresh" {
	clearRecords();
	startCounting();
	try {
		putRecord("0", JSON.stringify<Note>({ text: "srv", n: 7 }));
		const gate = new Gate();
		const root = mockNode("root");
		const empty: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {};
		hydrate(empty, mockHost(), root as unknown as HostNode)();
		let pending = false;
		const dispose = render((host: Host, parent: HostNode, before: HostNode | null): void => {
			const m = createAsyncMemo((p: Note | null): Promise<Note> => loadNote(gate, 5));
			try {
				m();
			} catch (e) {
				pending = true;
			}
		}, mockHost(), root as unknown as HostNode, "");
		try {
			assert !hasRecord("0"), "hydration is over";
			assert pending && requestsSent() === 1, "a fresh compute, not the record";
		} finally {
			dispose();
		}
	} finally {
		stopCounting();
		clearRecords();
	}
}

function failure(run: () => void): string {
	try {
		run();
	} catch (e) {
		return (e as Error).message;
	}
	return "";
}

test "a record that does not decode fails the hydrate with the id and the decoder's text" {
	clearRecords();
	try {
		putRecord("0", "{\"text\":5}");
		const gate = new Gate();
		const node: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
			const data = createAsyncMemo((p: Note | null): Promise<Note> => loadNote(gate, 1));
			data();
		};
		const said = failure((): void => { hydrate(node, mockHost(), mockNode("root") as unknown as HostNode)(); });
		assert said.indexOf("\"0\"") >= 0 || said.indexOf(" 0 ") >= 0, "names the id: " + said;
		assert said.indexOf("field 'text': expected string") >= 0, "carries the decoder's text: " + said;
	} finally {
		clearRecords();
	}
}

let resetFallback: () => void = (): void => {};

function guarded(source: () => Accessor<Note>): NeonNode {
	const inner: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		unclaimed(host, (): void => {
			Loading({
				children: Errored({
					children: (h: Host, p: HostNode, b: HostNode | null): void => {
						const data = source();
						line((): string => data().text + "=" + data().n.toString())(h, p, b);
					},
					fallback: (err: Accessor<Error>, reset: () => void): NeonNode => {
						resetFallback = reset;
						return el("em", [], [], dynText((): string => "caught " + err().message));
					},
				}),
				fallback: el("b", [], [], text("loading")),
			})(host, parent, before);
		});
	};
	return el("div", [], [], inner);
}

test "an error record shows the server's message in the nearest Errored and a reset recomputes on the client" {
	clearRecords();
	startCounting();
	try {
		putError("000010", "the server failed");
		const retried = new Gate();
		const live = (): Accessor<Note> => createAsyncMemo((q: Note | null): Promise<Note> => loadNote(retried, 3));
		const root = served(el("div", [], [], text("")));
		const dispose = hydrate(guarded(live), mockHost(), root as unknown as HostNode);
		try {
			assert mockToString(root) === "<root><div><em>caught the server failed</em></div></root>", "the fallback carries the server's message: " + mockToString(root);
			const traced = requestsSent();
			resetFallback();
			flush();
			assert requestsSent() === traced + 1, "reset recomputed on the client: " + requestsSent().toString();
			await release(retried);
			assert mockToString(root) === "<root><div><p>live=3</p></div></root>", mockToString(root);
		} finally {
			dispose();
		}
	} finally {
		stopCounting();
		clearRecords();
	}
}
