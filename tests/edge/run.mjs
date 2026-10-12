import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
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
const site = `http://127.0.0.1:${await freePort()}`;
const server = spawn(workerd, [
	"serve", join(here, "config.capnp"),
	"--socket-addr", `http=${new URL(origin).host}`,
	"--socket-addr", `site=${new URL(site).host}`,
], { stdio: ["ignore", "inherit", "inherit"] });

async function get(url) {
	const response = await fetch(url);
	return { status: response.status, body: await response.text() };
}

async function started() {
	for (let attempt = 0; attempt < 100; attempt += 1) {
		if (server.exitCode !== null) { throw new Error(`workerd exited with ${server.exitCode}`); }
		try { return await get(origin + "/"); } catch { await new Promise((wake) => setTimeout(wake, 50)); }
	}
	throw new Error(`workerd did not answer on ${origin}`);
}

async function pages() {
	const home = await started();
	const guide = await get(origin + "/guide");
	assert.equal(home.status, 200);
	assert.match(home.body, /home page/);
	assert.match(home.body, /padding:24px/);
	assert.doesNotMatch(home.body, /margin:12px/, "the first page carries the second page's rule");
	assert.match(guide.body, /guide page/);
	assert.match(guide.body, /margin:12px/);
	assert.doesNotMatch(guide.body, /padding:24px/, "the second page carries the first page's rule");
	assert.match(guide.body, /white-space:pre-wrap/, "the second page lost the base rule");

	const broken = await get(origin + "/broken");
	assert.equal(broken.status, 500);
	assert.deepEqual(await get(origin + "/"), home, "a page changed after other requests");
	assert.deepEqual(await get(origin + "/guide"), guide, "a page changed after a failed request");
	console.log("PASS: workerd answers each path with its own page and rules, with no browser globals");
}

async function routes() {
	const home = await get(site + "/");
	assert.equal(home.status, 200);
	assert.match(home.body, /<title data-neon-head="">Neon site<\/title>/);
	assert.match(home.body, /<meta name="description" content="A Neon site served from the edge"/);
	assert.match(home.body, /<h1>Neon site<\/h1>/);

	const doc = await get(site + "/docs/routing");
	assert.equal(doc.status, 200);
	assert.match(doc.body, /<title data-neon-head="">routing · Neon site<\/title>/);
	assert.match(doc.body, /<h1>Docs: routing<\/h1>/);
	assert.doesNotMatch(doc.body, /padding:24px/, "a docs page carries the home page's rule");

	for (const path of ["/docs/missing", "/nowhere", "/docs/start/"]) {
		const missing = await get(site + path);
		assert.equal(missing.status, 404, path);
		assert.match(missing.body, /<meta name="robots" content="noindex"/, path);
		assert.match(missing.body, /<h1>Not found<\/h1>/, path);
	}
	assert.deepEqual(await get(site + "/"), home, "the home page changed after other requests");
	console.log("PASS: workerd routes each request through its own registry and answers a no-match with 404");
}

async function browser() {
	const { chromium } = await import(pathToFileURL(playwright).href);
	const chrome = await chromium.launch({ channel: process.env.NEON_CHROME_CHANNEL ?? "chrome" });
	try {
		const page = await chrome.newPage();
		const errors = [];
		page.on("pageerror", (e) => errors.push(String(e)));
		let documents = 0;
		page.on("request", (r) => { if (r.resourceType() === "document") { documents += 1; } });

		await page.addInitScript(() => {
			globalThis.neonSiteChanged = [];
			const changes = new MutationObserver((records) => {
				for (const record of records) {
					if (!(record.target instanceof Element) || record.target.closest("#site") === null) { continue; }
					for (const node of [...record.addedNodes, ...record.removedNodes]) {
						if (node.nodeType === 1) { globalThis.neonSiteChanged.push(node.localName); }
					}
				}
			});
			document.addEventListener("readystatechange", () => {
				if (document.readyState === "interactive") { changes.observe(document, { childList: true, subtree: true }); }
			});
		});
		await page.goto(site + "/docs/start");
		await page.waitForFunction("globalThis.neonSiteHydrated === 1", { timeout: 20000 });
		assert.deepEqual(errors, []);
		assert.equal(await page.evaluate("document.querySelectorAll('#site *').length"), 12);
		assert.deepEqual(await page.evaluate("globalThis.neonSiteChanged"), [], "hydrate added or removed an element of the served page");
		await page.evaluate(() => { document.querySelector("h1").served = true; });
		assert.equal(await page.title(), "start · Neon site");
		assert.equal(await page.locator("head [data-neon-head]").count(), 0, "served head tags stayed beside the client's");
		assert.equal(await page.locator("head title").count(), 1);

		await page.getByLabel("Mark read").click();
		assert.equal(await page.getByLabel("Mark read").innerText(), "Read 1");

		await page.evaluate(() => window.scrollTo(0, 1500));
		await page.getByRole("link", { name: "Routing", exact: true }).click();
		await page.waitForFunction("document.querySelector('h1').textContent === 'Docs: routing'");
		assert.equal(new URL(page.url()).pathname, "/docs/routing");
		assert.equal(await page.title(), "routing · Neon site");
		assert.equal(await page.locator("meta[name=description]").getAttribute("content"), "Docs: routing");
		assert.equal(await page.evaluate("document.querySelector('h1').served"), true, "a navigation replaced the heading");
		assert.equal(await page.evaluate("window.scrollY"), 0, "a followed link left the page scrolled");
		assert.equal(documents, 1, "a link reloaded the page");

		await page.getByRole("link", { name: "Home", exact: true }).click();
		await page.waitForFunction("document.querySelector('h1').textContent === 'Neon site'");
		assert.equal(new URL(page.url()).pathname, "/");
		assert.equal(await page.title(), "Neon site");
		await page.goBack();
		await page.waitForFunction("document.querySelector('h1').textContent === 'Docs: routing'");
		assert.equal(await page.title(), "routing · Neon site");
		assert.equal(documents, 1, "history went through the server");

		const answered = page.waitForResponse((r) => r.url() === site + "/docs/missing");
		await page.getByRole("link", { name: "Missing", exact: true }).click();
		assert.equal((await answered).status(), 404, "a link to no route is the server's to answer");
		await page.waitForFunction("document.querySelector('h1').textContent === 'Not found'");
		assert.equal(documents, 2);
		assert.deepEqual(errors, []);
	} finally {
		await chrome.close();
	}
	console.log("PASS: Chrome hydrates the served route, follows links without a reload and leaves a no-match to the server");
}

try {
	await pages();
	await routes();
	await browser();
} finally {
	server.kill();
}
