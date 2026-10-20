import { spawn } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const here = import.meta.dirname;
const repo = resolve(here, "../..");
const work = resolve(process.env.REFRESH_ROOT ?? join(repo, "out/refreshVite"));
const port = Number(process.env.REFRESH_PORT ?? 5197);
const previewPort = Number(process.env.REFRESH_PREVIEW_PORT ?? 5196);
const playwright = process.env.NEON_PLAYWRIGHT ?? join(repo, "tests/browser/node_modules/playwright-core/index.mjs");
const viteBin = join(here, "node_modules/vite/bin/vite.js");
const sources = ["build.ms", "main.ms", "counter.ms", "sibling.ms", "words.ms", "entry.js", "index.html"];

if (!existsSync(playwright)) throw new Error(`playwright-core not found at ${playwright}; set NEON_PLAYWRIGHT`);
if (!existsSync(viteBin)) throw new Error(`vite not installed at ${viteBin}; run run.sh`);

function copyPristine() {
	mkdirSync(work, { recursive: true });
	for (const f of sources) cpSync(join(here, f), join(work, f));
}

const results = [];
function check(scenario, name, ok, observed) {
	results.push(ok);
	console.log(`${ok ? "PASS" : "FAIL"} ${scenario} ${name} :: ${observed}`);
}

const stripAnsi = (s) => s.replace(/\x1b\[[0-9;]*m/g, "");

function startVite(args, env, readyPattern) {
	const child = spawn(process.execPath, [viteBin, ...args, "--config", join(here, "vite.config.mjs")], {
		cwd: work,
		env: { ...process.env, REFRESH_ROOT: work, REFRESH_PORT: String(port), REFRESH_PREVIEW_PORT: String(previewPort), ...env },
	});
	const lines = [];
	const onData = (b) => { for (const l of stripAnsi(b.toString()).split(/\r?\n/)) if (l.trim()) lines.push(l.trim()); };
	child.stdout.on("data", onData);
	child.stderr.on("data", onData);
	const ready = readyPattern === null ? null : new Promise((res, rej) => {
		const t = setInterval(() => {
			if (lines.some((l) => readyPattern.test(l))) { clearInterval(t); res(); }
			if (child.exitCode !== null) { clearInterval(t); rej(new Error(`vite exited ${child.exitCode}:\n${lines.join("\n")}`)); }
		}, 100);
	});
	const exited = new Promise((res) => child.on("exit", (code) => res(code)));
	return { child, lines, ready, exited };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

copyPristine();
const { chromium } = await import(pathToFileURL(playwright).href);
const browser = await chromium.launch({ channel: "chrome", headless: true });

// ---- dev server with -d:refresh
const dev = startVite([], {}, /Local:/);
await dev.ready;
const page = await browser.newPage();
const consoleLines = [];
page.on("console", (m) => consoleLines.push(`[${m.type()}] ${m.text()}`));
page.on("pageerror", (e) => consoleLines.push(`[pageerror] ${e.message}`));
let navigations = 0;
page.on("framenavigated", (f) => { if (f === page.mainFrame()) navigations++; });
await page.goto(`http://localhost:${port}/`);
await page.waitForSelector("#out", { timeout: 60000 }).catch((e) => {
	console.log(`the page never showed #out:\nvite:\n${dev.lines.join("\n")}\npage:\n${consoleLines.join("\n")}`);
	throw e;
});
const session = await page.evaluate(() => globalThis.__session);
const loadNavs = navigations;

await page.evaluate(() => { document.querySelector("#tallyOut").__mark = "tally"; });
await page.fill("#notes", "hello");
for (let i = 0; i < 3; i++) await page.click("#tallyInc");

const snap = () => page.evaluate(() => {
	const title = document.querySelector("#title");
	const overlay = document.querySelector("vite-error-overlay");
	return {
		session: globalThis.__session,
		out: [...document.querySelectorAll("#out")].map((n) => n.textContent).join(" | "),
		title: title?.textContent ?? null,
		color: title ? getComputedStyle(title).color : null,
		counters: document.querySelectorAll("#counter").length,
		incs: document.querySelectorAll("#inc").length,
		tally: document.querySelector("#tallyOut")?.textContent ?? null,
		tallySame: document.querySelector("#tallyOut")?.__mark === "tally",
		notes: document.querySelector("#notes")?.value ?? null,
		overlay: overlay ? (() => {
			const text = (overlay.shadowRoot?.textContent ?? overlay.textContent).replace(/\x1b?\[[0-9;]*m/g, "").replace(/\s+/g, " ");
			const at = text.indexOf("error:");
			return text.slice(0, 45) + " ... " + text.slice(at, at + 100);
		})() : null,
	};
});
const waitText = (sel, text, timeout = 60000) => page.waitForFunction(
	([s, t]) => document.querySelector(s)?.textContent === t, [sel, text], { timeout },
).then(() => true, () => false);
const countOf = (out) => Number(/: (\d+) /.exec(out)?.[1] ?? NaN);
const clicks = async (n) => { for (let i = 0; i < n; i++) await page.click("#inc"); };

const files = {};
function edit(file, from, to) {
	const path = join(work, file);
	const text = files[file] ?? readFileSync(path, "utf8");
	if (!text.includes(from)) throw new Error(`'${from}' not found in ${file}`);
	files[file] = text.replace(from, to);
	writeFileSync(path, files[file]);
}
const markOut = () => page.evaluate(() => { document.querySelector("#out").__old = true; });
const remounted = () => page.waitForFunction(() => {
	const out = document.querySelector("#out");
	return out !== null && out.__old !== true;
}, null, { timeout: 60000 }).then(() => true, () => false);
const viteSince = (mark) => dev.lines.slice(mark).filter((l) => /hmr|reload|error|fail/i.test(l)).map((l) => l.replace(/^\d+:\d+:\d+ [AP]M /, "")).join(" ; ") || "(none)";
const kept = (s) => s.session === session && navigations === loadNavs && s.tallySame && s.tally === "tally: 3" && s.notes === "hello";
const keptText = (s) => `session=${s.session === session ? "same" : s.session} navs=${navigations - loadNavs} tallyNode=${s.tallySame ? "same" : "new"} tally="${s.tally}" notes="${s.notes}"`;

// ---- 1. template-only edit keeps setup state
await clicks(8);
let s = await snap();
check("S1", "baseline", s.out === "clicks: 8 apples" && s.title === "Counter v1", `out="${s.out}" title="${s.title}" color=${s.color}`);
let mark = dev.lines.length;
edit("counter.ms", `style={{ color: "#205080" }}>Counter v1<`, `style={{ color: "#802050" }}>Counter v2<`);
let shown = await waitText("#title", "Counter v2");
s = await snap();
check("S1", "template edit applied, count kept, no reload", shown && s.out === "clicks: 8 apples" && s.color === "rgb(128, 32, 80)" && s.counters === 1 && kept(s),
	`title="${s.title}" color=${s.color} out="${s.out}" counters=${s.counters} ${keptText(s)} vite: ${viteSince(mark)}`);
await clicks(1);
s = await snap();
check("S1", "one click after edit adds exactly 1", s.out === "clicks: 9 apples", `out="${s.out}"`);

// ---- 2. setup edit remounts the boundary
mark = dev.lines.length;
await markOut();
edit("counter.ms", "setCount(count() + 1)", "setCount(count() + 2)");
shown = await remounted();
s = await snap();
check("S2", "handler edit remounts Counter with its count kept, sibling kept", shown && s.out === "clicks: 9 apples" && s.counters === 1 && s.title === "Counter v2" && kept(s),
	`out="${s.out}" counters=${s.counters} ${keptText(s)} vite: ${viteSince(mark)}`);
await clicks(1);
s = await snap();
check("S2", "new handler adds 2", s.out === "clicks: 11 apples", `out="${s.out}"`);

// ---- 3. four consecutive template edits
mark = dev.lines.length;
let all = true;
for (const v of [3, 4, 5, 6]) {
	edit("counter.ms", `>Counter v${v - 1}<`, `>Counter v${v}<`);
	all = (await waitText("#title", `Counter v${v}`)) && all;
}
s = await snap();
check("S3", "four template edits applied, one view, count kept", all && s.counters === 1 && s.incs === 1 && s.out === "clicks: 11 apples" && kept(s),
	`title="${s.title}" counters=${s.counters} incButtons=${s.incs} out="${s.out}" ${keptText(s)} vite: ${viteSince(mark)}`);
await clicks(1);
s = await snap();
check("S3", "one click adds exactly 2 (single handler)", s.out === "clicks: 13 apples", `out="${s.out}"`);

// ---- 4. dependency edit
mark = dev.lines.length;
edit("words.ms", `"apples"`, `"pears"`);
shown = await page.waitForFunction(() => document.querySelector("#out")?.textContent.endsWith(" pears"), null, { timeout: 60000 }).then(() => true, () => false);
s = await snap();
check("S4", "words.ms edit shows new word, sibling kept, no reload", shown && s.counters === 1 && kept(s),
	`out="${s.out}" counters=${s.counters} ${keptText(s)} vite: ${viteSince(mark)}`);
const countKept = s.out === "clicks: 13 pears";
check("S4", "Counter count kept across the dependency edit", countKept, `out="${s.out}" (was "clicks: 13 apples")`);
let n = countOf(s.out);
await clicks(1);
s = await snap();
check("S4", "click after dependency edit adds 2", countOf(s.out) === n + 2, `out="${s.out}"`);
n = countOf(s.out);

// ---- 5. compile errors
const lastGood = files["counter.ms"];
const brokenLine = `const [count, setCount] = createSignal(0);\n\tconst broken: int32 = "oops";`;
const waitOverlay = (present) => page.waitForFunction((p) => !!document.querySelector("vite-error-overlay") === p, present, { timeout: 60000 }).then(() => true, () => false);
mark = dev.lines.length;
edit("counter.ms", "const [count, setCount] = createSignal(0);", brokenLine);
let overlay = await waitOverlay(true);
s = await snap();
check("S5", "compile error shows overlay, page not reloaded", overlay && kept(s) && countOf(s.out) === n && /not assignable/.test(s.overlay ?? ""),
	`overlay="${s.overlay}" out="${s.out}" ${keptText(s)} vite: ${viteSince(mark)}`);
await page.evaluate(() => document.querySelector("#inc").click());
s = await snap();
check("S5", "old UI still clickable under the error (+2)", countOf(s.out) === n + 2, `out="${s.out}"`);
n = countOf(s.out);
mark = dev.lines.length;
files["counter.ms"] = lastGood;
writeFileSync(join(work, "counter.ms"), lastGood);
overlay = await waitOverlay(false);
await sleep(1500);
s = await snap();
check("S5", "restoring exact last-good source clears overlay, state kept", overlay && countOf(s.out) === n && s.title === "Counter v6" && kept(s),
	`overlay=${s.overlay === null ? "gone" : s.overlay} out="${s.out}" ${keptText(s)} vite: ${viteSince(mark)}`);
mark = dev.lines.length;
edit("counter.ms", "const [count, setCount] = createSignal(0);", brokenLine);
overlay = await waitOverlay(true);
check("S5", "second error shows overlay", overlay, `vite: ${viteSince(mark)}`);
mark = dev.lines.length;
files["counter.ms"] = lastGood;
edit("counter.ms", ">Counter v6<", ">Counter v7<");
shown = await waitText("#title", "Counter v7");
overlay = await waitOverlay(false);
s = await snap();
check("S5", "fix with a new template edit applies without reload, count kept", shown && overlay && countOf(s.out) === n && kept(s),
	`title="${s.title}" out="${s.out}" overlay=${s.overlay === null ? "gone" : s.overlay} ${keptText(s)} vite: ${viteSince(mark)}`);
await clicks(1);
s = await snap();
check("S5", "click after recovery adds 2", countOf(s.out) === n + 2, `out="${s.out}"`);

n = countOf(s.out);
const throwLine = `
	if (count() >= 0) { throw new Error("setup failed"); }`;
const failureText = () => page.evaluate(() => [...document.querySelectorAll("span")].map((x) => x.textContent).find((t) => t.includes("did not mount")) ?? null);
mark = dev.lines.length;
edit("counter.ms", "const [count, setCount] = createSignal(0);", "const [count, setCount] = createSignal(0);" + throwLine);
const threw = await page.waitForFunction(() => document.body.textContent.includes("did not mount: setup failed"), null, { timeout: 60000 }).then(() => true, () => false);
s = await snap();
check("S7", "setup that throws shows the error where Counter was, sibling kept, no reload", threw && s.counters === 0 && kept(s),
	`shown="${await failureText()}" counters=${s.counters} ${keptText(s)} vite: ${viteSince(mark)}`);
mark = dev.lines.length;
files["counter.ms"] = files["counter.ms"].replace(throwLine, "");
edit("counter.ms", ">Counter v7<", ">Counter v8<");
shown = await waitText("#title", "Counter v8");
s = await snap();
const cleared = await failureText();
check("S7", "the fix mounts Counter again with its count, error gone", shown && countOf(s.out) === n && s.counters === 1 && cleared === null && kept(s),
	`out="${s.out}" (was ${n}) counters=${s.counters} shown=${cleared} ${keptText(s)} vite: ${viteSince(mark)}`);

// ---- 8. an edit that adds a generic instance (a boolean signal read by the template)
n = countOf(s.out);
mark = dev.lines.length;
edit("counter.ms", "const [count, setCount] = createSignal(0);", "const [count, setCount] = createSignal(0);\n\tconst [flag, setFlag] = createSignal(false);");
edit("counter.ms", ">Counter v8<", `>{"Counter v9" + (flag() ? "!" : "")}<`);
shown = await waitText("#title", "Counter v9");
s = await snap();
check("S8", "a new generic instance applies without reload, count kept", shown && countOf(s.out) === n && s.counters === 1 && kept(s),
	`title="${s.title}" out="${s.out}" (was ${n}) ${keptText(s)} vite: ${viteSince(mark)}`);

const errors = consoleLines.filter((l) => /^\[(error|pageerror)\]/.test(l) && !/404/.test(l));
check("dev", "no page errors in the console", errors.length === 0, errors.join(" ; ") || "(none)");
await page.close();
dev.child.kill();
await dev.exited;

// ---- 6. production build without -d:refresh
copyPristine();
const build = startVite(["build"], {}, null);
const code = await build.exited;
const assets = join(work, "dist/assets");
const js = existsSync(assets) ? readdirSync(assets).filter((f) => f.endsWith(".js")) : [];
const bundle = js.map((f) => readFileSync(join(assets, f), "utf8")).join("\n");
const leaks = ["refreshModuleEval", "import.meta.hot", "__refreshBody", "refreshBoundary", "refreshState"].filter((w) => bundle.includes(w));
check("S6", "vite build without -d:refresh has no refresh hooks", code === 0 && js.length > 0 && leaks.length === 0,
	`exit=${code} bundles=${js.join(",")} bytes=${bundle.length} leaks=[${leaks.join(",")}] vite: ${build.lines.filter((l) => /built in|error/i.test(l)).join(" ; ")}`);
const preview = startVite(["preview"], {}, /Local:/);
await preview.ready;
const prod = await browser.newPage();
const prodErrors = [];
prod.on("pageerror", (e) => prodErrors.push(e.message));
await prod.goto(`http://localhost:${previewPort}/`);
const prodShown = await prod.waitForSelector("#out", { timeout: 30000 }).then(() => true, () => false);
for (let i = 0; i < 3; i++) if (prodShown) await prod.click("#inc");
const prodOut = prodShown ? await prod.textContent("#out") : null;
const prodTitle = prodShown ? await prod.textContent("#title") : null;
check("S6", "static production bundle works", prodOut === "clicks: 3 apples" && prodTitle === "Counter v1" && prodErrors.length === 0,
	`out="${prodOut}" title="${prodTitle}" errors=${prodErrors.join(";") || "none"}`);
preview.child.kill();
await preview.exited;
await browser.close();

const failed = results.filter((r) => !r).length;
console.log(`${failed === 0 ? "ALL PASS" : `${failed} FAIL`} (${results.length} checks)`);
process.exit(failed === 0 ? 0 : 1);
