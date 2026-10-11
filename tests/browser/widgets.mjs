// Real Chrome, real mouse: builds examples/widgets/web and drives the pager, tabs, carousel,
// accordion, data table and chips the way a user does.
// Usage: node tests/browser/widgets.mjs <playwright index.mjs>
import { execFileSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { startServer } from "./server.mjs";

const [, , playwrightPath] = process.argv;
execFileSync(process.env.MSC ?? "msc", ["build", "--target=js", "examples/widgets/web/app.ms", "--output=out/widgets-web/app.js"], { stdio: "ignore" });
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
			await page.goto(`http://127.0.0.1:${port}/examples/widgets/web/index.html`);
			break;
		} catch (e) {
			if (attempt > 50) throw e;
			await new Promise((r) => setTimeout(r, 100));
		}
	}
	await page.getByText("Welcome", { exact: true }).waitFor();
}

const status = () => page.evaluate(() => [...document.querySelectorAll("*")].map((e) => e.firstChild && e.firstChild.nodeType === 3 ? e.firstChild.textContent : "").find((t) => t.startsWith("status ")) ?? "");
async function box(text) {
	const b = await page.getByText(text, { exact: true }).first().boundingBox();
	if (!b) throw new Error(`no box for ${text}`);
	return b;
}
async function drag(x1, y1, x2, y2, { steps = 12, hold = 0 } = {}) {
	await page.mouse.move(x1, y1);
	await page.mouse.down();
	await page.mouse.move(x2, y2, { steps });
	if (hold) await page.waitForTimeout(hold);
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
const visibleX = async (text) => (await box(text)).x;

await open();
// Onboarding pager: a left mouse drag turns the page, a short drag springs back.
let w = await box("Welcome");
await drag(340, w.y, 80, w.y);
await expectStatus("status page 2", "a left mouse drag turns the onboarding page");
await page.waitForTimeout(600);
const sync = await box("Sync");
check(Math.abs(sync.x + sync.width / 2 - 210) < 4, `the second page settles centred (${sync.x + sync.width / 2})`);
await drag(200, sync.y, 230, sync.y, { hold: 300 });
await page.waitForTimeout(600);
check((await status()) === "status page 2" && Math.abs((await box("Sync")).x - sync.x) < 2, "a short slow drag springs back");
await page.getByText("next", { exact: true }).click();
await expectStatus("status page 3", "next turns to the last page");
await page.getByLabel("page 1 of 3").click();
await expectStatus("status page 1", "a dot jumps back to the first page");

// Tabs: a swipe moves the indicator, a tab press switches, the lazy scene renders.
await page.getByText("tabs", { exact: true }).click();
await page.getByText("Chats 1", { exact: true }).waitFor();
const chats1 = await box("Chats 1");
await drag(360, chats1.y + 100, 60, chats1.y + 100);
await expectStatus("status tab Status", "a swipe changes to the Status tab");
await page.getByText("Status 1", { exact: true }).waitFor();
const indicator = async () => page.evaluate(() => {
	const tab = [...document.querySelectorAll("[role=tab]")].find((t) => t.textContent === "Status");
	const bar = tab.parentElement;
	const line = [...bar.children].find((c) => c.getBoundingClientRect().height === 2);
	const l = line.getBoundingClientRect(), t = tab.getBoundingClientRect();
	return { lineX: l.x, lineW: l.width, tabX: t.x, tabW: t.width };
});
await page.waitForTimeout(500);
const ind = await indicator();
check(Math.abs(ind.lineX - ind.tabX) < 2 && Math.abs(ind.lineW - ind.tabW) < 2, `the indicator sits under Status (${ind.lineX},${ind.lineW} vs ${ind.tabX},${ind.tabW})`);
await page.getByText("Calls", { exact: true }).click();
await expectStatus("status tab Calls", "a tab press selects Calls");
await page.getByText("Calls 1", { exact: true }).waitFor();
await page.waitForTimeout(500);
const callsScroll = await box("Calls 3");
await page.mouse.move(callsScroll.x + 40, callsScroll.y);
await page.mouse.wheel(0, 200);
await page.waitForTimeout(300);
check((await box("Calls 3")).y < callsScroll.y, "a scene's vertical ScrollView still scrolls inside the pager");

// Carousel: auto-play advances, pause holds it, a drag moves it with peeking neighbours.
await page.getByText("carousel", { exact: true }).click();
await page.getByText("Slide A", { exact: true }).waitFor();
const a = await box("Slide A");
const b = await box("Slide B");
const spacing = (b.x + b.width / 2) - (a.x + a.width / 2);
check(Math.abs(spacing - 336) < 3, `slides sit 80% of the width apart, so the next one peeks (${spacing})`);
await expectStatus("status slide Slide B", "auto-play moves to Slide B");
await page.getByText("pause", { exact: true }).click();
await expectStatus("status autoplay off", "pause stops auto-play");
const held = await box("Slide B");
await drag(300, held.y + held.height / 2, 80, held.y + held.height / 2);
await expectStatus("status slide Slide C", "a mouse drag moves to Slide C");
await page.waitForTimeout(3000);
check((await status()) === "status slide Slide C", "paused auto-play does not move on");

// FAQ: the accordion opens one section, the expansion tile animates.
await page.getByText("faq", { exact: true }).click();
await page.getByText("Which platforms?", { exact: true }).click();
await expectStatus("status faq open 1", "a question opens");
await page.getByText("iOS, Android, the browser and the terminal.", { exact: true }).waitFor();
await page.waitForTimeout(500);
const answer = await box("iOS, Android, the browser and the terminal.");
check(answer.height > 10, `the answer is shown (${answer.height})`);
await page.getByText("Is it open source?", { exact: true }).click();
await expectStatus("status faq open 2", "another question closes the first");
await page.waitForTimeout(600);
const closed = await page.getByText("iOS, Android, the browser and the terminal.", { exact: true }).isVisible();
check(!closed, "the first answer collapsed out of view");
await page.getByText("Shipping", { exact: true }).click();
await expectStatus("status shipping open", "the expansion tile opens");

// Data table: sort by calories, flip it, select a row.
await page.getByText("table", { exact: true }).click();
await page.getByText("Eclair", { exact: true }).waitFor();
await page.getByText("Calories", { exact: true }).click();
await expectStatus("status sorted calories up", "a header press sorts by calories");
const order = async () => page.evaluate(() => ["Frozen yogurt", "Ice cream", "Eclair", "Cupcake", "Gingerbread"].map((n) => [n, [...document.querySelectorAll("*")].find((e) => e.firstChild && e.firstChild.nodeType === 3 && e.textContent === n).getBoundingClientRect().y]).sort((p, q) => p[1] - q[1]).map((p) => p[0]).join("|"));
check((await order()) === "Frozen yogurt|Ice cream|Eclair|Cupcake|Gingerbread", `ascending calories (${await order()})`);
await page.getByText("Calories", { exact: true }).click();
await expectStatus("status sorted calories down", "a second press flips the order");
check((await order()) === "Gingerbread|Cupcake|Eclair|Ice cream|Frozen yogurt", `descending calories (${await order()})`);
await page.getByText("Eclair", { exact: true }).click();
await expectStatus("status selected Eclair", "a row press selects it");
const columnsAligned = await page.evaluate(() => {
	const cell = (t) => [...document.querySelectorAll("*")].find((e) => e.firstChild && e.firstChild.nodeType === 3 && e.textContent === t).getBoundingClientRect();
	return Math.abs(cell("Eclair").y - cell("262").y) < 2 && Math.abs(cell("Gingerbread").y - cell("356").y) < 2;
});
check(columnsAligned, "the cells of a row line up across columns");

// Chips: the Wrap flows chips onto several rows with its spacing.
await page.getByText("chips", { exact: true }).click();
await page.getByText("Flexbox", { exact: true }).waitFor();
const neon = await box("Neon"), flexbox = await box("Flexbox");
check(flexbox.y > neon.y + 20, `the chips wrap onto more rows (${neon.y} -> ${flexbox.y})`);
await page.getByText("Yoga", { exact: true }).click();
await expectStatus("status chips Neon|Yoga", "a chip press selects it");

for (const e of errors) { failed++; console.log(`uncaught ${e}`); }
await browser.close();
server.kill();
console.log(failed === 0 ? "widgets browser lane: all passed" : `widgets browser lane: ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
