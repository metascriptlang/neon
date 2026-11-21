import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { startServer } from "./server.mjs";

const [, , playwrightPath] = process.argv;
execFileSync(process.env.MSC ?? "msc", ["build", "--target=js", "tests/browser/documentLoad.ms", "--output=out/document-load/app.js"], { stdio: "inherit" });
const { server, port } = await startServer(process.cwd());
const { chromium } = await import(pathToFileURL(playwrightPath).href);
const chrome = await chromium.launch({ channel: process.env.NEON_CHROME_CHANNEL ?? "chrome" });
let failed = 0;
try {
	const page = await chrome.newPage();
	const errors = [];
	page.on("pageerror", (e) => errors.push(String(e)));
	let loads = 0;
	page.on("load", () => { loads++; });
	const showing = (text) => page.locator("#at", { hasText: text }).waitFor();
	const mark = () => page.evaluate(() => { globalThis.neonBooted = "kept"; });
	const state = () => page.evaluate(() => globalThis.neonBooted ?? "reset");

	await page.goto(`http://127.0.0.1:${port}/tests/browser/documentLoad.html`);
	await showing("n=none");
	await mark();
	await page.click("#next");
	await showing("n=2");
	assert.equal(await state(), "kept", "a link before the update reloaded the document");
	assert.equal(loads, 1, "a link before the update fired a load");

	await page.evaluate(() => globalThis.neonUpdate());
	await page.locator("#version", { hasText: "new version" }).waitFor();
	await mark();
	await page.click("#later");
	await showing("n=3");
	assert.equal(await state(), "reset", "a link after the update stayed a client transition");
	assert.equal(loads, 2, `a link after the update fired ${loads - 1} loads`);

	const entries = await page.evaluate(() => history.length);
	await page.evaluate(() => globalThis.neonUpdate());
	await mark();
	await Promise.all([page.waitForEvent("load"), page.evaluate(() => { setTimeout(() => globalThis.neonNavigate("?n=4", true)); })]);
	await showing("n=4");
	assert.equal(await state(), "reset", "a navigate after the update stayed a client transition");
	assert.equal(await page.evaluate(() => history.length), entries, "a replace navigate added a history entry");
	assert.deepEqual(errors, []);
} catch (e) {
	failed = 1;
	console.error(e);
} finally {
	await chrome.close();
	server.kill();
}
if (failed === 0) { console.log("PASS: after the router is updated, a link and a navigate load the document; before it a link is a client transition"); }
process.exit(failed);
