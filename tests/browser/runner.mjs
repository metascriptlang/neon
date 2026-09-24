import { pathToFileURL } from "node:url";

const [, , playwrightPath, port, label, pagePath] = process.argv;
const { chromium } = await import(pathToFileURL(playwrightPath).href);

const browser = await chromium.launch({ channel: process.env.NEON_CHROME_CHANNEL ?? "chrome" });
const page = await browser.newPage();
const pageErrors = [];
page.on("pageerror", (e) => pageErrors.push(String(e)));

const url = `http://127.0.0.1:${port}/${pagePath}`;
for (let attempt = 0; ; attempt++) {
	try {
		await page.goto(url);
		break;
	} catch (e) {
		if (attempt >= 50) throw e;
		await new Promise((r) => setTimeout(r, 100));
	}
}
await page.waitForFunction("globalThis.__neonDone !== undefined", { timeout: 60000 });
const done = await page.evaluate("globalThis.__neonDone");
await browser.close();

console.log(done.lines.join("\n"));
if (done.crashed) {
	console.log(`\n== ${label}: the page threw before the suite finished\n${done.error}`);
	process.exit(1);
}
for (const e of pageErrors) console.log(`== uncaught: ${e}`);
process.exit(done.exitCode === 0 && pageErrors.length === 0 ? 0 : 1);
