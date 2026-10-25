import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
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

	const tagged = await get(site + "/docs/routing?utm=1");
	assert.equal(tagged.status, 200, "a query the site does not read made a page a no-match");
	assert.match(tagged.body, /<h1>Docs: routing<\/h1>/);

	for (const path of ["/docs/missing", "/nowhere", "/docs/missing?utm=1"]) {
		const missing = await get(site + path);
		assert.equal(missing.status, 404, path);
		assert.match(missing.body, /<meta name="robots" content="noindex"/, path);
		assert.match(missing.body, /<h1>Not found<\/h1>/, path);
	}
	const slashed = await fetch(site + "/docs/start/?utm=1", { redirect: "manual" });
	assert.equal(slashed.status, 308, "an address ending in a slash is not redirected for good");
	assert.equal(slashed.headers.get("location"), "/docs/start?utm=1");
	assert.deepEqual(await get(site + "/"), home, "the home page changed after other requests");
	assert.match(home.body.slice(0, 60), /^<!doctype html><html>/);
	assert.equal(slashed.headers.get("content-type"), null, "a redirect carries a body type");
	const headed = await fetch(site + "/", { method: "HEAD" });
	assert.deepEqual([headed.status, await headed.text(), headed.headers.get("content-type")], [200, "", "text/html; charset=utf-8"]);
	const posted = await fetch(site + "/", { method: "POST" });
	assert.deepEqual([posted.status, posted.headers.get("allow")], [405, "GET, HEAD"]);
	console.log("PASS: workerd routes each request through its own router, answers a no-match with 404 and a trailing slash with 308");
}

async function notes() {
	const alpha = await get(site + "/notes/alpha");
	assert.equal(alpha.status, 200);
	assert.match(alpha.body, /<p id="note">Note alpha read at render<\/p>/, "the served page lacks the data the request read");
	assert.doesNotMatch(alpha.body, /Loading note/, "the served page holds the fallback of a read that settled");
	const records = alpha.body.match(/<script>\(self\._\$HY[^<]*<\/script>/g) ?? [];
	assert.equal(records.length, 1, "the served page holds " + records.length + " record scripts");
	assert.ok(alpha.body.indexOf(records[0]) > alpha.body.indexOf("</div>"), "the record does not follow the markup");
	assert.ok(alpha.body.indexOf(records[0]) < alpha.body.indexOf("/client.js"), "the record comes after the client script");
	assert.match(records[0], /\.r\["\d+"\]="\{\\"slug\\":\\"alpha\\",\\"text\\":\\"Note alpha read at render\\"\}"/);

	const beta = await get(site + "/notes/beta?utm=1");
	assert.match(beta.body, /<p id="note">Note beta read at render<\/p>/, "a second slug did not read its own data");
	assert.doesNotMatch(beta.body, /Note alpha/);
	assert.equal((beta.body.match(/<script>\(self\._\$HY/g) ?? []).length, 1);
	assert.equal((await get(site + "/notes/gamma")).status, 404);

	for (const path of ["/", "/docs/start"]) {
		assert.doesNotMatch((await get(site + path)).body, /_\$HY/, "a route with no async read carries a record: " + path);
	}
	const api = await get(site + "/api/note/beta");
	assert.equal(api.status, 200);
	assert.deepEqual(JSON.parse(api.body), { slug: "beta", text: "Note beta read from the api" });
	console.log("PASS: workerd renders the async read of /notes/:slug into the page with one record, and no other route carries one");
}

async function prerender() {
	const { staticPaths } = await import(pathToFileURL(join(here, "out/site.js")).href);
	const out = join(here, "out/static");
	rmSync(out, { recursive: true, force: true });
	const paths = staticPaths();
	assert.deepEqual(paths, ["/", "/docs/start", "/docs/routing"]);
	for (const path of paths) {
		const page = await get(site + path);
		assert.equal(page.status, 200, path);
		assert.deepEqual(await get(site + path + "?utm=1"), page, "a static page differs by its query: " + path);
		const file = join(out, (path === "/" ? "/index" : path) + ".html");
		mkdirSync(dirname(file), { recursive: true });
		writeFileSync(file, page.body);
	}
	const missing = await get(site + "/nowhere");
	assert.equal(missing.status, 404);
	writeFileSync(join(out, "404.html"), missing.body);
	console.log("PASS: every static path renders 200 the same for any query and is written to out/static, with 404.html");
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
					if (!(record.target instanceof Element) || record.target.closest("#app") === null) { continue; }
					for (const node of [...record.addedNodes, ...record.removedNodes]) {
						if (node.nodeType === 1) { globalThis.neonSiteChanged.push(node.localName); }
					}
				}
			});
			document.addEventListener("readystatechange", () => {
				if (document.readyState === "interactive") { changes.observe(document, { childList: true, subtree: true }); }
			});
		});
		await page.goto(site + "/docs/start?utm=1#notes");
		await page.waitForFunction("globalThis.neonSiteHydrated === 1", { timeout: 20000 });
		assert.equal(new URL(page.url()).search + new URL(page.url()).hash, "?utm=1#notes", "opening the session rewrote the address");
		const landed = await page.evaluate("window.scrollY");
		assert.ok(landed > 1000, "the browser's own scroll to the fragment was lost: " + landed);
		assert.deepEqual(errors, []);
		assert.equal(await page.evaluate("document.querySelectorAll('#app *').length"), 14);
		assert.deepEqual(await page.evaluate("globalThis.neonSiteChanged"), [], "hydrate added or removed an element of the served page");
		await page.evaluate(() => { document.querySelector("nav").served = true; });
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
		assert.equal(await page.evaluate("document.querySelector('nav').served"), true, "a navigation replaced the layout");
		assert.equal(await page.getByRole("link", { name: "Routing", exact: true }).getAttribute("aria-current"), "page");
		assert.equal(await page.getByRole("link", { name: "Start", exact: true }).getAttribute("aria-current"), null);
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

		await page.getByRole("link", { name: "Home", exact: true }).click();
		await page.waitForFunction("document.querySelector('h1').textContent === 'Neon site'");
		await page.getByRole("link", { name: "Notes", exact: true }).click();
		await page.waitForFunction("document.querySelector('h1').textContent === 'Docs: routing'");
		assert.equal(new URL(page.url()).pathname + new URL(page.url()).hash, "/docs/routing#notes");
		const atNotes = await page.evaluate("[window.scrollY, document.getElementById('notes').getBoundingClientRect().top, window.innerHeight]");
		assert.ok(atNotes[0] > 1000 && atNotes[1] >= 0 && atNotes[1] < atNotes[2], "a followed link did not scroll to its fragment: " + atNotes);
		assert.equal(documents, 1, "a link with a fragment went through the server");

		await page.getByRole("link", { name: "Missing", exact: true }).click();
		await page.waitForFunction("document.querySelector('h1').textContent === 'Not found'");
		assert.equal(new URL(page.url()).pathname, "/docs/missing");
		assert.equal(await page.title(), "Not found · Neon site");
		assert.equal(await page.evaluate("document.querySelector('nav').served"), true, "a page with no route replaced the layout");
		assert.equal(documents, 1, "a link to no page went through the server");
		assert.deepEqual(errors, []);
	} finally {
		await chrome.close();
	}
	console.log("PASS: Chrome hydrates the served route, follows links without a reload and renders a no-match in the layout");
}

async function hydratedNotes() {
	const { chromium } = await import(pathToFileURL(playwright).href);
	const chrome = await chromium.launch({ channel: process.env.NEON_CHROME_CHANNEL ?? "chrome" });
	try {
		const page = await chrome.newPage();
		const errors = [];
		const reads = [];
		let documents = 0;
		page.on("pageerror", (e) => errors.push(String(e)));
		page.on("request", (r) => {
			if (r.resourceType() === "document") { documents += 1; }
			if (new URL(r.url()).pathname.startsWith("/api/")) { reads.push(new URL(r.url()).pathname); }
		});
		await page.addInitScript(() => {
			globalThis.neonSiteChanged = [];
			globalThis.neonSiteFallback = 0;
			const changes = new MutationObserver((records) => {
				for (const record of records) {
					if (!(record.target instanceof Element) || record.target.closest("#app") === null) { continue; }
					for (const node of [...record.addedNodes, ...record.removedNodes]) {
						if (node.nodeType === 1) { globalThis.neonSiteChanged.push(node.localName); }
					}
					if (record.target.textContent.includes("Loading note")) { globalThis.neonSiteFallback += 1; }
				}
			});
			document.addEventListener("readystatechange", () => {
				if (document.readyState === "interactive") { changes.observe(document, { childList: true, subtree: true, characterData: true }); }
			});
		});
		await page.goto(site + "/notes/alpha");
		await page.waitForFunction("globalThis.neonSiteHydrated === 1", { timeout: 20000 });
		await new Promise((wake) => setTimeout(wake, 500));
		assert.deepEqual(reads, [], "hydrate sent data requests: " + reads);
		assert.equal(await page.locator("#note").innerText(), "Note alpha read at render");
		assert.deepEqual(await page.evaluate("globalThis.neonSiteChanged"), [], "hydrate added or removed an element of the served page");
		assert.equal(await page.evaluate("globalThis.neonSiteFallback"), 0, "the page showed the fallback");
		assert.deepEqual(errors, []);

		await page.getByRole("link", { name: "Home", exact: true }).click();
		await page.waitForFunction("document.querySelector('h1').textContent === 'Neon site'");
		assert.deepEqual(reads, []);
		await page.goBack();
		await page.waitForFunction("document.querySelector('#note')?.textContent === 'Note alpha read from the api'");
		assert.deepEqual(reads, ["/api/note/alpha"], "a client navigation to the route did not load its data once");

		await page.evaluate(() => {
			const link = document.createElement("a");
			link.href = "/notes/beta";
			link.textContent = "Beta";
			document.querySelector("nav").append(link);
		});
		await page.getByRole("link", { name: "Beta", exact: true }).click();
		await page.waitForFunction("document.querySelector('#note')?.textContent === 'Note beta read from the api'");
		assert.deepEqual(reads, ["/api/note/alpha", "/api/note/beta"]);
		assert.equal(documents, 1, "a link reloaded the page");
		assert.deepEqual(errors, []);
	} finally {
		await chrome.close();
	}
	console.log("PASS: Chrome hydrates the page that holds the async read with no data request and no fallback, and a client navigation to the route still loads its data");
}

try {
	await pages();
	await routes();
	await notes();
	await prerender();
	await browser();
	await hydratedNotes();
} finally {
	server.kill();
}
