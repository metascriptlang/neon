// Real Chrome: builds examples/svg/web, samples the pixels each <Svg> draws (the svg element
// rasterised onto a canvas) and runs the Animated progress ring with a real click.
// Usage: node tests/browser/svg.mjs <playwright index.mjs> [screenshot.png]
import { execFileSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { startServer } from "./server.mjs";

const [, , playwrightPath, shotPath] = process.argv;
execFileSync(process.env.MSC ?? "msc", ["build", "--target=js", "examples/svg/web/app.ms", "--output=out/svg-web/app.js"], { stdio: "ignore" });
const { server, port } = await startServer(process.cwd());
const { chromium } = await import(pathToFileURL(playwrightPath).href);
const browser = await chromium.launch({ channel: process.env.NEON_CHROME_CHANNEL ?? "chrome" });
const page = await browser.newPage({ viewport: { width: 420, height: 860 } });
const errors = [];
page.on("pageerror", (e) => errors.push(String(e)));
let failed = 0;

for (let attempt = 0; ; attempt++) {
	try {
		await page.goto(`http://127.0.0.1:${port}/examples/svg/web/index.html`);
		break;
	} catch (e) {
		if (attempt > 50) throw e;
		await new Promise((r) => setTimeout(r, 100));
	}
}
await page.getByText("Neon SVG", { exact: true }).waitFor();

// The colour at (x, y) inside the <svg> labelled `label`, rasterised at its own size.
const pixel = (label, x, y) => page.evaluate(async ([label, x, y]) => {
	const svg = document.querySelector(`svg[aria-label="${label}"]`);
	const box = svg.getBoundingClientRect();
	const copy = svg.cloneNode(true);
	copy.setAttribute("width", String(box.width));
	copy.setAttribute("height", String(box.height));
	copy.setAttribute("xmlns", "http://www.w3.org/2000/svg");
	const image = new Image();
	image.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(new XMLSerializer().serializeToString(copy));
	await image.decode();
	const canvas = document.createElement("canvas");
	canvas.width = box.width;
	canvas.height = box.height;
	const ctx = canvas.getContext("2d");
	ctx.fillStyle = "#ffffff";
	ctx.fillRect(0, 0, canvas.width, canvas.height);
	ctx.drawImage(image, 0, 0);
	const d = ctx.getImageData(x, y, 1, 1).data;
	return [d[0], d[1], d[2]];
}, [label, x, y]);

async function expectColor(label, x, y, test, why) {
	const c = await pixel(label, x, y);
	if (test(c)) { console.log(`ok   ${why}: rgb(${c.join(",")})`); return; }
	failed++;
	console.log(`FAIL ${why}: rgb(${c.join(",")}) at ${label} (${x}, ${y})`);
}

const near = (want, tolerance = 40) => (c) => c.every((v, i) => Math.abs(v - want[i]) <= tolerance);
const white = near([255, 255, 255], 10);

await expectColor("icon heart", 20, 20, near([229, 57, 53]), "the heart icon is red in its middle");
await expectColor("icon heart", 2, 38, white, "and empty in its corner");
await expectColor("icon check", 11, 25, near([67, 160, 71]), "the check mark is green");
await expectColor("donut chart", 120, 70, near([229, 57, 53]), "the first slice (40%) covers three o'clock");
await expectColor("donut chart", 70, 120, near([30, 136, 229]), "the second slice covers six o'clock");
await expectColor("donut chart", 20, 70, near([67, 160, 71]), "the third slice covers nine o'clock");
await expectColor("donut chart", 55, 23, near([251, 192, 45]), "the fourth slice sits before twelve o'clock");
await expectColor("donut chart", 70, 70, white, "the hole is empty");
await expectColor("progress ring", 70, 120, near([224, 224, 224]), "the ring track shows before the animation");
await expectColor("line chart", 375, 116, (c) => c[2] > c[0] + 20 && c[0] > 150, "the gradient area fades to a light blue at the bottom");
await expectColor("line chart", 300, 20, white, "and leaves the sky above the line white");
await expectColor("logo", 15, 30, (c) => c[0] > 200 && c[2] < 100, "the logo starts orange");
await expectColor("logo", 190, 30, (c) => c[2] > c[1] + 40, "and ends purple");
await expectColor("logo", 100, 28, white, "with white text in the middle");

await page.getByText("animate", { exact: true }).click();
for (let i = 0; i < 40; i++) {
	const s = await page.evaluate(() => [...document.querySelectorAll("*")].map((e) => e.firstChild && e.firstChild.nodeType === 3 ? e.firstChild.textContent : "").find((t) => t.startsWith("status ")) ?? "");
	if (s === "status progress 75%") break;
	await page.waitForTimeout(100);
}
await expectColor("progress ring", 70, 120, near([142, 36, 170]), "the Animated ring reaches six o'clock");
await expectColor("progress ring", 35, 35, near([224, 224, 224]), "and stops short of the last quarter");
const label = await page.evaluate(() => document.querySelector('svg[aria-label="progress ring"] text').textContent);
if (label !== "75%") { failed++; console.log(`FAIL ring label: ${label}`); } else { console.log("ok   ring label 75%"); }
if (shotPath) await page.screenshot({ path: shotPath });

await browser.close();
server.kill();
for (const e of errors) { failed++; console.log(`FAIL page error: ${e}`); }
console.log(failed === 0 ? "svg: all checks passed" : `svg: ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
