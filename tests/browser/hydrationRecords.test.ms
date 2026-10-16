import { NeonNode } from "../../src/render/node";
import { hydrate, HostNode, Host } from "../../src/render/host";
import { createSignal } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { Cleanup } from "../../src/core/types";
import { hasRecord, takeRecord, takeError, clearRecords, scriptLiteral } from "../../src/render/hydrationRecords";
import { traceRun } from "../../src/render/traceRun";

when (js) {
	import { domHost } from "../../src/platform/browser/dom";

	extern class Page {
		extern remove(): void;
	}
	extern function emptyPage(): Page from "(() => { const r=document.createElement('div');document.body.appendChild(r);return r; })()";
	extern function parseScripts(html: cstring): void from
		"(h => { document.body.appendChild(document.createRange().createContextualFragment(h)); })(#)";
	extern function spyFetch(): void from
		"(() => { const spy = () => { globalThis.neonFetchCalls++; return Promise.resolve(new Response('')); }; spy.neonSpy = true; globalThis.neonFetchCalls = 0; globalThis.neonRealFetch = globalThis.fetch; globalThis.fetch = spy; })()";
	extern function unspyFetch(): void from "(() => { globalThis.fetch = globalThis.neonRealFetch; })()";
	extern function callFetch(url: cstring): void from "(u => { fetch(u); })(#)";
	extern function fetchCalls(): int32 from "(globalThis.neonFetchCalls)";
	extern function fetchIsSpy(): boolean from "(globalThis.fetch.neonSpy === true)";
	extern function promiseIsNative(): boolean from "(globalThis.Promise.name === 'Promise')";

	interface Note {
		text: string;
		n: int32;
	}

	interface Basket {
		items: Note[];
		total: float64;
	}

	function valueScript(id: string, json: string): string {
		return "<script>(self._$HY||(self._$HY={r:{},e:{}})).r[\"" + id + "\"]=\"" + scriptLiteral(json) + "\"</script>";
	}

	function errorScript(id: string, message: string): string {
		return "<script>(self._$HY||(self._$HY={r:{},e:{}})).e[\"" + id + "\"]=\"" + scriptLiteral(message) + "\"</script>";
	}

	function whileHydrating(body: () => void): void {
		const mount = emptyPage();
		const node: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => { body(); };
		const dispose = hydrate(node, domHost(), mount as unknown as HostNode);
		dispose();
		mount.remove();
	}

	const awkward: Note = { text: "a</script><!--\"q\"\\     é 漢 \n\t", n: -3 };

	test "a record the browser parsed from the page's script reads back as the value it was written from" {
		clearRecords();
		parseScripts(valueScript("w1", JSON.stringify<Note>(awkward)));
		whileHydrating((): void => {
			assert hasRecord("w1"), "the script's record is the client's";
			const back = takeRecord<Note>("w1");
			assert back.text === awkward.text && back.n === awkward.n, back.text;
		});
		clearRecords();
	}

	test "a nested record and an error message survive the same script form" {
		clearRecords();
		const basket: Basket = { items: [awkward, { text: "plain", n: 2 }], total: 0.1 };
		parseScripts(valueScript("w2", JSON.stringify<Basket>(basket)) + errorScript("w3", "the \"server\" </script> failed\nline two  "));
		whileHydrating((): void => {
			const back = takeRecord<Basket>("w2");
			assert back.items.length === 2 && back.items[0].text === awkward.text && back.items[1].n === 2 && back.total === 0.1, back.items[0].text;
			assert takeError("w3") === "the \"server\" </script> failed\nline two  ", "the error message came back unchanged";
		});
		clearRecords();
	}

	test "traceRun sends no request and keeps the signal read it makes" {
		spyFetch();
		const [n, setN] = createSignal(1);
		let traced = true;
		let insideSpy = true;
		let insideNative = true;
		createRoot((dispose) => {
			createEffect<int32>(
				(p: int32 | null): int32 => {
					if (traced) {
						traced = false;
						traceRun((): void => {
							insideSpy = fetchIsSpy();
							insideNative = promiseIsNative();
							n();
							callFetch("/trace");
						});
					} else {
						n();
						callFetch("/live");
					}
					return 0;
				},
				(v: int32, p: int32 | null): Cleanup | null => null);
			return dispose;
		});
		try {
			assert fetchCalls() === 0, "the trace run sent " + fetchCalls().toString() + " requests";
			assert !insideSpy && !insideNative, "fetch and Promise were swapped during the run";
			assert fetchIsSpy() && promiseIsNative(), "fetch and Promise were restored after it";
			setN(2);
			assert fetchCalls() === 1, "a write to the traced signal re-ran the computation, which really fetched";
		} finally {
			unspyFetch();
		}
	}

	async function rejects(): Promise<int32> {
		throw new Error("a rejected trace run");
	}

	test "traceRun restores fetch when the function throws, and observes a rejected promise" {
		spyFetch();
		let thrown = "";
		try {
			traceRun((): void => { callFetch("/x"); throw new Error("trace threw"); });
		} catch (e) {
			thrown = (e as Error).message;
		}
		try {
			assert thrown === "trace threw", thrown;
			assert fetchCalls() === 0 && fetchIsSpy() && promiseIsNative(), "restored after a throw with no request sent";
			traceRun((): Promise<int32> => rejects());
		} finally {
			unspyFetch();
		}
	}
}
