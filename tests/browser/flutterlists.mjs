// Real Chrome, real mouse: builds examples/flutterlists/web and drives it with playwright's
// mouse the way a user drags. Usage: node tests/browser/flutterlists.mjs <playwright index.mjs>
import { execFileSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { startServer } from "./server.mjs";

const [, , playwrightPath] = process.argv;
execFileSync(process.env.MSC ?? "msc", ["build", "--target=js", "examples/flutterlists/web/app.ms", "--output=out/flutterlists-web/app.js"], { stdio: "ignore" });
const { server, port } = await startServer(process.cwd());
const { chromium } = await import(pathToFileURL(playwrightPath).href);
const browser = await chromium.launch({ channel: process.env.NEON_CHROME_CHANNEL ?? "chrome" });
const page = await browser.newPage({ viewport: { width: 420, height: 860 } });
const errors = [];
page.on("pageerror", (e) => errors.push(String(e)));
let failed = 0;

async function open() {
	for (let attempt = 0; ; attempt++) {
		try {
			await page.goto(`http://127.0.0.1:${port}/examples/flutterlists/web/index.html`);
			break;
		} catch (e) {
			if (attempt > 50) throw e;
			await new Promise((r) => setTimeout(r, 100));
		}
	}
	await page.getByText("Mail 2", { exact: true }).waitFor();
}

const status = () => page.evaluate(() => [...document.querySelectorAll("*")].map((e) => e.firstChild && e.firstChild.nodeType === 3 ? e.firstChild.textContent : "").find((t) => t.startsWith("status ")) ?? "");
async function box(text) {
	const b = await page.getByText(text, { exact: true }).first().boundingBox();
	if (!b) throw new Error(`no box for ${text}`);
	return b;
}
async function drag(x1, y1, x2, y2, { hold = 0, steps = 12 } = {}) {
	await page.mouse.move(x1, y1);
	await page.mouse.down();
	if (hold) await page.waitForTimeout(hold);
	await page.mouse.move(x2, y2, { steps });
	await page.mouse.up();
}
async function expectStatus(prefix, why) {
	for (let i = 0; i < 40; i++) {
		if ((await status()).startsWith(prefix)) { console.log(`ok   ${why}: ${await status()}`); return; }
		await page.waitForTimeout(100);
	}
	failed++;
	console.log(`FAIL ${why}: expected ${prefix}, got ${await status()}`);
}
function check(ok, why) {
	if (ok) console.log(`ok   ${why}`); else { failed++; console.log(`FAIL ${why}`); }
}

await open();
let m = await box("Mail 2");
await drag(120, m.y + m.height / 2, 360, m.y + m.height / 2);
await expectStatus("status archived Mail 2", "a right mouse drag archives Mail 2");
await page.waitForTimeout(600);
check(await page.getByText("Mail 2", { exact: true }).count() === 0, "the archived row left the list");

m = await box("Mail 3");
await drag(300, m.y + m.height / 2, 60, m.y + m.height / 2);
await expectStatus("status deleted Mail 3", "a left mouse drag deletes Mail 3");
await page.waitForTimeout(600);

await page.getByText("Mail 4", { exact: true }).click();
await expectStatus("status opened Mail 4", "a click on a swipeable row presses it");

m = await box("Mail 5");
await drag(120, m.y + m.height / 2, 170, m.y + m.height / 2);
await page.waitForTimeout(400);
check(await page.getByText("Mail 5", { exact: true }).count() === 1 && (await status()) === "status opened Mail 4", "a short drag springs back without pressing");

await page.getByText("playlist", { exact: true }).click();
await expectStatus("status order 1 2 3 4", "the playlist opens");
const h = await box("drag 1");
await drag(h.x + h.width / 2, h.y + h.height / 2, h.x + h.width / 2, h.y + h.height / 2 + 130, { hold: 600, steps: 20 });
await expectStatus("status order 2 3 1 4 moved 0 to 2", "a long-press mouse drag reorders");

await page.getByText("photos", { exact: true }).click();
await expectStatus("status grid width", "the max-extent grid derives its item width");
const p1 = await box("P1"), p3 = await box("P3");
check(Math.abs(p1.y - p3.y) < 2, `three photos share the first row (${p1.y} ${p3.y})`);
await page.getByText("show masonry", { exact: true }).click();
await page.getByText("P1 c0", { exact: true }).waitFor();
check(true, "masonry places P1 in the first column");

await page.getByText("header", { exact: true }).click();
await expectStatus("status header 200", "the header starts expanded");
const r = await box("Row 3");
await page.mouse.move(r.x + 40, r.y + r.height / 2);
await page.mouse.wheel(0, 400);
await expectStatus("status header 64", "the pinned header collapses on scroll");

await page.getByText("slivers", { exact: true }).click();
await page.getByText("Albums", { exact: true }).waitFor();
const before = await box("Albums");
const a4 = await box("Album 4");
await page.mouse.move(a4.x + 10, a4.y + 10);
await page.mouse.wheel(0, 300);
await page.waitForTimeout(400);
const after = await box("Albums");
check(after.y < before.y, `the banner scrolls away under the pinned header (${before.y} -> ${after.y})`);

await page.getByText("wheel", { exact: true }).click();
await page.getByText("hour 1", { exact: true }).waitFor();
const w = await box("hour 1");
await page.mouse.move(w.x + 10, w.y + 10);
await page.mouse.wheel(0, 3 * 44 + 10);
await expectStatus("status picked hour 4", "scrolling the wheel three items picks hour 4");
await page.waitForTimeout(800);
const centred = await box("hour 4");
const wheelBox = await page.getByText("hour 4", { exact: true }).evaluate((el) => { let at = el; while (at && getComputedStyle(at).overflowY !== "auto" && getComputedStyle(at).overflowY !== "scroll") at = at.parentElement; const r = at.getBoundingClientRect(); return { top: r.top, height: r.height }; });
check(Math.abs(centred.y + centred.height / 2 - (wheelBox.top + wheelBox.height / 2)) < 6, `the wheel snaps hour 4 to its centre (${centred.y + centred.height / 2} vs ${wheelBox.top + wheelBox.height / 2})`);

for (const e of errors) { failed++; console.log(`uncaught ${e}`); }
await browser.close();
server.kill();
console.log(failed === 0 ? "flutterlists browser lane: all passed" : `flutterlists browser lane: ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
