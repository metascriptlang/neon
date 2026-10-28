import { execFileSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { startServer } from "./server.mjs";

const [, , playwrightPath] = process.argv;
execFileSync(process.env.MSC ?? "msc", ["build", "--target=js", "tests/browser/pressableActivation.ms", "--output=out/pressable-activation/app.js"], { stdio: "inherit" });
const { server, port } = await startServer(process.cwd());
const { chromium } = await import(pathToFileURL(playwrightPath).href);
const browser = await chromium.launch({ channel: process.env.NEON_CHROME_CHANNEL ?? "chrome" });
console.log(`Chrome ${browser.version()}`);
let failed = 0;
try {
	const page = await browser.newPage();
	page.on("pageerror", (e) => { failed++; console.log(`uncaught ${e}`); });
	await page.goto(`http://127.0.0.1:${port}/tests/browser/pressableActivation.html`);
	const gesture = page.locator('[aria-label="Gesture"]');
	await gesture.waitFor();
	const log = () => page.locator('#activation-log').textContent();
	async function check(action, expected, why) {
		await page.reload();
		await gesture.waitFor();
		await page.evaluate(() => document.addEventListener("click", (e) => console.log("click metadata " + JSON.stringify({ class: e.constructor.name, pointerType: e.pointerType ?? null, ownPointerType: Object.hasOwn(e, "pointerType"), detail: e.detail })), true));
		await action();
		await page.waitForTimeout(220);
		const got = await log();
		if (got === expected) console.log(`ok ${why}: ${got}`);
		else { failed++; console.log(`FAIL ${why}: expected ${expected}, got ${got}`); }
	}
	page.on("console", (msg) => { if (msg.text().startsWith("click metadata")) console.log(msg.text()); });
	await check(() => gesture.evaluate((e) => e.click()), "press;", "programmatic click");
	await check(async () => { await gesture.focus(); await page.keyboard.press("Enter"); }, "press;", "keyboard Enter");
	await check(async () => { await gesture.focus(); await page.keyboard.press("Space"); }, "press;", "keyboard Space");
	await check(() => gesture.click(), "in;press;out;", "physical short click once");
	await check(async () => {
		const b = await gesture.boundingBox();
		await page.mouse.move(b.x + 20, b.y + 20);
		await page.mouse.down(); await page.waitForTimeout(300); await page.mouse.up();
	}, "in;long;out;", "physical long click suppressed");
	await check(async () => {
		const b = await gesture.boundingBox();
		await page.mouse.move(b.x + 20, b.y + 20); await page.mouse.down();
		await page.mouse.move(b.x + 80, b.y + 20, { steps: 6 }); await page.mouse.up();
		await page.waitForTimeout(160);
		await gesture.focus(); await page.keyboard.press("Enter");
	}, "in;out;press;", "claimed drag then independent keyboard activation");
	await check(() => page.locator('[aria-label="Cheap"]').click(), "cheap;", "cheap physical control");
} finally {
	await browser.close(); server.kill();
}
console.log(`pressable activation real input: ${failed} failed`);
process.exit(failed ? 1 : 0);
