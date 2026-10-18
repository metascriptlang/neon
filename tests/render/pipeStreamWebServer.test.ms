when (js) {
	import { sleepAsync } from "std/core/promise";
	import { el, text, dynText, NeonNode } from "../../src/render/node";
	import { Host, HostNode } from "../../src/render/hostTypes";
	import { createAsyncMemo } from "../../src/core/memo";
	import { Loading } from "../../src/macros/ui/flow";
	import { renderToStream, pipeTo, readable } from "../../src/render/ssr";

	extern class WritableStream {}
	extern class ReadableStream {}
	extern class TransformStream {
		readable: ReadableStream;
		writable: WritableStream;
	}
	extern function newTransform(): TransformStream from "new TransformStream()";
	extern function readAll(stream: ReadableStream): Promise<string[]> from
		"(async (rs) => { const reader = rs.getReader(); const decoder = new TextDecoder(); const out = []; for (;;) { const { done, value } = await reader.read(); if (done) { break; } out.push(decoder.decode(value)); } return out; })(#)";
	extern function readFirst(stream: ReadableStream): Promise<string> from
		"(async (rs) => { const reader = rs.getReader(); const { value } = await reader.read(); reader.releaseLock(); return new TextDecoder().decode(value); })(#)";

	const waiting: NeonNode = el("b", [], [], text("loading"));
	let slowSettled = false;
	let shellRead = true;

	async function slowValue(ms: int32): Promise<int32> {
		await sleepAsync(ms);
		while (!shellRead) { await sleepAsync(1); }
		slowSettled = true;
		return 7;
	}

	function page(ms: int32): NeonNode {
		const content: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
			const data = createAsyncMemo((p: int32 | null): Promise<int32> => slowValue(ms));
			el("p", [], [], dynText((): string => "slow=" + data().toString()))(host, parent, before);
		};
		return Loading({ children: content, fallback: waiting });
	}

	class Collected {
		chunks: string[] = [];
		ended: int32 = 0;
	}

	async function piped(ms: int32): Promise<string[]> {
		const c = new Collected();
		const r = renderToStream(page(ms));
		r.pipe({ write: (chunk: string): void => { c.chunks.push(chunk); }, end: (): void => { c.ended += 1; } });
		await r;
		return c.chunks;
	}

	test "readable carries the chunks pipe delivers, as bytes of a web stream" {
		const expected = await piped(5);
		const r = renderToStream(page(5));
		const got = await readAll(readable(r));
		assert got.length === 2 && expected.length === 2, got.length.toString() + "/" + expected.length.toString();
		assert got[0] === expected[0] && got[1] === expected[1], got[0] + " | " + got[1];
	}

	test "the first chunk of the readable arrives before the slow read settles" {
		slowSettled = false;
		shellRead = false;
		const r = renderToStream(page(5));
		const first = await readFirst(readable(r));
		assert !slowSettled, "the slow read had settled before the shell arrived";
		shellRead = true;
		assert first.includes("<b>loading</b>") && !first.includes("slow="), first;
		await r;
		assert slowSettled, "the render finished";
	}

	test "pipeTo writes the same chunks to a writable and settles once it is closed" {
		const expected = await piped(5);
		const pair = newTransform();
		const r = renderToStream(page(5));
		const done = r.pipeTo(pair.writable);
		const got = await readAll(pair.readable);
		await done;
		assert got.length === 2 && got[0] === expected[0] && got[1] === expected[1], got.length.toString();
	}

	test "readable called twice is one stream, and a different consumer after it throws" {
		const r = renderToStream(page(5));
		const view = readable(r);
		assert readable(r) === view, "the second access made a second stream";
		let message = "";
		try {
			r.pipe({ write: (chunk: string): void => {}, end: (): void => {} });
		} catch (e) {
			message = (e as Error).message;
		}
		assert message === "renderToStream result was already consumed via `readable`; cannot also consume it via `pipe`. Use exactly one of `pipe`, `pipeTo`, or `readable`.", message;
		await readAll(view);
	}

	test "pipeTo after pipe throws and names pipe" {
		const r = renderToStream(page(5));
		r.pipe({ write: (chunk: string): void => {}, end: (): void => {} });
		let message = "";
		try {
			pipeTo(r, newTransform().writable);
		} catch (e) {
			message = (e as Error).message;
		}
		assert message.includes("already consumed via `pipe`; cannot also consume it via `pipeTo`"), message;
		await r;
	}
}
