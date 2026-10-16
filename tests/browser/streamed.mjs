// Real Chrome: a streamed render over HTTP, not hydrated. The slow read settles only when this script
// releases it, after Chrome shows the fallback; then the page must hold the awaited form's markup.
// Usage: node tests/browser/streamed.mjs <playwright index.mjs>
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createServer } from "node:http";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [, , playwrightPath] = process.argv;
execFileSync(process.env.MSC ?? "msc", ["build", "--target=js", "-d:server", "tests/browser/streamedPage.ms", "--output=tests/browser/out/streamedPage.mjs"], { stdio: "ignore" });
const { slowStream, slowAwaited, nestedStream, nestedAwaited } = await import(pathToFileURL(resolve("tests/browser/out/streamedPage.mjs")).href);

let release = () => {};
let releaseInner = () => {};
const server = createServer(async (req, res) => {
	res.setHeader("content-type", "text/html; charset=utf-8");
	if (req.url === "/awaited") {
		res.end("<!doctype html><body>" + await slowAwaited(Promise.resolve(1)) + "</body>");
		return;
	}
	if (req.url === "/nestedAwaited") {
		res.end("<!doctype html><body>" + await nestedAwaited(Promise.resolve(1), Promise.resolve(2)) + "</body>");
		return;
	}
	const sink = { write: (chunk) => { res.write(chunk); }, end: () => { res.end("</body>"); } };
	res.write("<!doctype html><meta charset=\"utf-8\"><body>");
	if (req.url === "/nested") {
		nestedStream(new Promise((open) => { release = open; }), new Promise((open) => { releaseInner = open; }), sink);
		return;
	}
	slowStream(new Promise((open) => { release = open; }), sink);
});
await new Promise((listening) => server.listen(0, "127.0.0.1", listening));
const origin = `http://127.0.0.1:${server.address().port}`;

const { chromium } = await import(pathToFileURL(playwrightPath).href);
const chrome = await chromium.launch({ channel: process.env.NEON_CHROME_CHANNEL ?? "chrome" });
let failed = 0;
try {
	const page = await chrome.newPage();
	const errors = [];
	page.on("pageerror", (e) => errors.push(String(e)));

	await page.goto(origin + "/page", { waitUntil: "commit" });
	await page.getByText("waiting", { exact: true }).waitFor();
	assert.equal(await page.getByText("slow=1").count(), 0, "the content showed before the read settled");
	assert.equal(await page.locator("template[id^=pl-]").count(), 1, "the shell holds the boundary's placeholder");

	release(1);
	await page.getByText("slow=1", { exact: true }).waitFor();
	await page.waitForLoadState("load");
	assert.equal(await page.getByText("waiting", { exact: true }).count(), 0, "the fallback stayed after the swap");
	assert.equal(await page.locator("template").count(), 0, "a template stayed after the swap");

	const markup = (p) => p.evaluate(() => {
		const body = document.body.cloneNode(true);
		for (const extra of body.querySelectorAll("script, style, template")) { extra.remove(); }
		return body.innerHTML;
	});
	const reference = await chrome.newPage();
	await reference.goto(origin + "/awaited");
	const streamed = await markup(page);
	const awaited = await markup(reference);
	assert.equal(streamed, awaited, "the streamed page's markup is not the awaited form's");
	assert.match(streamed, /slow=1/);

	const inner = await chrome.newPage();
	inner.on("pageerror", (e) => errors.push(String(e)));
	await inner.goto(origin + "/nested", { waitUntil: "commit" });
	await inner.getByText("outer waits", { exact: true }).waitFor();
	release(1);
	await inner.getByText("slow=1", { exact: true }).waitFor();
	assert.equal(await inner.getByText("outer waits", { exact: true }).count(), 0, "the outer fallback stayed after its swap");
	assert.equal(await inner.getByText("inner waits", { exact: true }).count(), 1, "the nested fallback shows after the parent's swap");
	assert.equal(await inner.getByText("inner content").count(), 0, "the nested content showed before its read settled");
	releaseInner(2);
	await inner.getByText("slow=2", { exact: true }).waitFor();
	await inner.waitForLoadState("load");
	assert.equal(await inner.locator("template").count(), 0, "a template stayed after the nested swap");
	const nestedReference = await chrome.newPage();
	await nestedReference.goto(origin + "/nestedAwaited");
	assert.equal(await markup(inner), await markup(nestedReference), "the nested streamed page's markup is not the awaited form's");
	assert.deepEqual(errors, []);
} catch (e) {
	failed = 1;
	console.error(e);
} finally {
	await chrome.close();
	server.close();
}
if (failed === 0) { console.log("PASS: Chrome shows each fallback first, then the content after $df, for a boundary and a nested one, with the awaited form's markup"); }
process.exit(failed);
