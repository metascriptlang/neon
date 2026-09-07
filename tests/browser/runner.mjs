const [, , playwrightPath, port, label] = process.argv;
const { chromium } = await import(playwrightPath);

const browser = await chromium.launch();
const page = await browser.newPage();
const pageErrors = [];
page.on("pageerror", (e) => pageErrors.push(String(e)));

await page.goto(`http://localhost:${port}/neon-test.html`);
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
