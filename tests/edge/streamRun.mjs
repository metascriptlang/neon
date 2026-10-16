import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { createServer as createHttpServer } from "node:http";
import { createServer } from "node:net";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const [, , workerd, playwright] = process.argv;
if (!existsSync(playwright)) {
	console.error(`playwright-core not found at ${playwright} — run: npm install --prefix tests/browser`);
	process.exit(2);
}

function freePort() {
	return new Promise((found) => {
		const probe = createServer().listen(0, "127.0.0.1", () => {
			const free = probe.address().port;
			probe.close(() => found(free));
		});
	});
}

const origin = `http://127.0.0.1:${await freePort()}`;

// The worker's slow read is a subrequest to this server, which answers it only once the test has the shell.
let shellRead = () => {};
const shellSeen = new Promise((seen) => { shellRead = seen; });
const gate = createHttpServer(async (_request, answer) => {
	await shellSeen;
	answer.end("1");
});
await new Promise((listening) => gate.listen(0, "127.0.0.1", listening));
const gateUrl = `http://127.0.0.1:${gate.address().port}/`;

const server = spawn(workerd, [
	"serve", join(here, "streamConfig.capnp"),
	"--socket-addr", `http=${new URL(origin).host}`,
], { stdio: ["ignore", "inherit", "inherit"] });

async function started() {
	for (let attempt = 0; attempt < 100; attempt += 1) {
		if (server.exitCode !== null) { throw new Error(`workerd exited with ${server.exitCode}`); }
		try {
			const response = await fetch(origin + "/awaited");
			return await response.text();
		} catch { await new Promise((wake) => setTimeout(wake, 50)); }
	}
	throw new Error(`workerd did not answer on ${origin}`);
}

// The text a browser shows for a page: its scripts run, so every $df swaps its placeholder.
async function shownText(chrome, html) {
	const page = await chrome.newPage();
	try {
		await page.setContent("<!doctype html><meta charset=\"utf-8\"><body>" + html + "</body>");
		return { text: await page.locator("body").innerText(), templates: await page.locator("template").count() };
	} finally {
		await page.close();
	}
}

async function streaming() {
	const awaited = await started();
	assert.match(awaited, /slow=1/);
	assert.match(awaited, /after the wait/);

	const response = await fetch(origin + "/stream?gate=" + encodeURIComponent(gateUrl));
	assert.equal(response.status, 200);
	const reader = response.body.getReader();
	const decoder = new TextDecoder();
	let stalled;
	const first = await Promise.race([reader.read(), new Promise((_, fail) => { stalled = setTimeout(() => fail(new Error("no shell within 30 s while the slow read is held: the stream does not send its shell before a pending read settles")), 30000); })]);
	clearTimeout(stalled);
	assert.equal(first.done, false);
	const shell = decoder.decode(first.value);
	assert.match(shell, /waiting/, "the first chunk is the shell, with the fallback");
	assert.doesNotMatch(shell, /slow=/, "the first chunk holds no content of the slow read");
	assert.doesNotMatch(shell, /\$df\(/, "the first chunk holds no swap");

	shellRead();
	let body = shell;
	for (;;) {
		const next = await reader.read();
		if (next.done) { break; }
		body += decoder.decode(next.value, { stream: true });
	}
	assert.equal(body.split("function $df").length - 1, 1, "the swap function is sent once");
	assert.equal(body.split("$df(\"").length - 1, 1, "one swap call for the one boundary");
	assert.match(body, /<template id="\d+">.*slow=1.*<\/template>/s);

	const { chromium } = await import(pathToFileURL(playwright).href);
	const chrome = await chromium.launch({ channel: process.env.NEON_CHROME_CHANNEL ?? "chrome" });
	try {
		const streamed = await shownText(chrome, body);
		const whole = await shownText(chrome, awaited);
		assert.match(streamed.text, /slow=1/);
		assert.doesNotMatch(streamed.text, /waiting/, "the fallback was left in the page");
		assert.equal(streamed.templates, 0, "a template was left in the page");
		assert.equal(streamed.text, whole.text, "the streamed page shows other text than the awaited page");
	} finally {
		await chrome.close();
	}
	console.log("PASS: workerd streams the shell before the slow read is answered, and the page the stream builds shows the awaited page's text");
}

try {
	await streaming();
} finally {
	server.kill();
	gate.close();
}
