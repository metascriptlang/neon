// Real Chrome: builds examples/media/web and drives the WebView bridge, the https WebView and the
// Video player the way a user does.
// Usage: node tests/browser/media.mjs <playwright index.mjs> [screenshot dir]
import { execFileSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { startServer } from "./server.mjs";

const [, , playwrightPath, shots] = process.argv;
execFileSync(process.env.MSC ?? "msc", ["build", "--target=js", "examples/media/web/app.ms", "--output=out/media-web/app.js"], { stdio: "ignore" });
const { server, port } = await startServer(process.cwd());
const { chromium } = await import(pathToFileURL(playwrightPath).href);
const browser = await chromium.launch({ channel: process.env.NEON_CHROME_CHANNEL ?? "chrome" });
const page = await browser.newPage({ viewport: { width: 420, height: 860 } });
const errors = [];
page.on("pageerror", (e) => errors.push(String(e)));
let failed = 0;

for (let attempt = 0; ; attempt++) {
	try {
		await page.goto(`http://127.0.0.1:${port}/examples/media/web/index.html`);
		break;
	} catch (e) {
		if (attempt > 50) throw e;
		await new Promise((r) => setTimeout(r, 100));
	}
}

const status = () => page.evaluate(() => [...document.querySelectorAll("*")].map((e) => e.firstChild && e.firstChild.nodeType === 3 ? e.firstChild.textContent : "").find((t) => t.startsWith("status ")) ?? "");
const textStarting = (prefix) => page.evaluate((p) => [...document.querySelectorAll("*")].map((e) => e.firstChild && e.firstChild.nodeType === 3 ? e.firstChild.textContent : "").find((t) => t.startsWith(p)) ?? "", prefix);
async function expectStatus(prefix, why, tries = 60) {
	for (let i = 0; i < tries; i++) {
		if ((await status()).startsWith(prefix)) { console.log(`ok   ${why}: ${await status()}`); return; }
		await page.waitForTimeout(100);
	}
	failed++;
	console.log(`FAIL ${why}: expected ${prefix}, got ${await status()}`);
}
function check(ok, why) {
	if (ok) console.log(`ok   ${why}`); else { failed++; console.log(`FAIL ${why}`); }
}
const shot = async (name) => { if (shots) await page.screenshot({ path: `${shots}/${name}.png` }); };
const press = (text) => page.getByText(text, { exact: true }).first().click();

await expectStatus("status page ready", "the local page posts on load");
const frame = page.frameLocator("iframe");
await frame.getByText("Send to app").click();
await expectStatus("status hello from the page", "a button in the page reaches onMessage");
await press("send to page");
await expectStatus("status page got hello from the app", "postMessage reaches the page and it answers");
check((await frame.locator("#inbox").textContent()) === "got hello from the app", "the page shows the app's message");
await press("inject");
await expectStatus("status title Neon bridge", "injectJavaScript runs in the page");
await shot("bridge");

await press("browser");
await expectStatus("status loaded https://example.com/", "an https page loads in the WebView", 150);
await shot("browser");

await press("video");
await expectStatus("status video 3s 160x90", "the bundled clip reports its duration and size");
await press("play");
await expectStatus("status playing", "play");
await page.waitForTimeout(800);
const t = Number((await textStarting("time ")).slice(5));
check(t > 0.2, `progress advances: time ${t}`);
await press("seek 2");
await expectStatus("status video ended", "seek 2 then the clip ends");
await shot("video");

check(errors.length === 0, `no page errors ${errors.join(" | ")}`);
await browser.close();
server.kill();
console.log(failed === 0 ? "media: all passed" : `media: ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
