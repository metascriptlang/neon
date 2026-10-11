// Real Chrome: builds examples/capture/web and drives the photo picker, the camera, the bundled
// chime and a recording the way a user does, with Chrome's fake camera and a Web Audio microphone.
// Usage: node tests/browser/capture.mjs <playwright index.mjs> [screenshot dir]
import { execFileSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { startServer } from "./server.mjs";

const [, , playwrightPath, shots] = process.argv;
execFileSync(process.env.MSC ?? "msc", ["build", "--target=js", "examples/capture/web/app.ms", "--output=out/capture-web/app.js"], { stdio: "ignore" });
const { server, port } = await startServer(process.cwd());
const { chromium } = await import(pathToFileURL(playwrightPath).href);
const browser = await chromium.launch({
	channel: process.env.NEON_CHROME_CHANNEL ?? "chrome",
	args: ["--use-fake-device-for-media-stream", "--use-fake-ui-for-media-stream", "--autoplay-policy=no-user-gesture-required"],
});
const page = await browser.newPage({ viewport: { width: 420, height: 860 } });
// Headless Chrome on macOS never settles getUserMedia({ audio }) even with the fake device, so the
// microphone is a Web Audio oscillator behind the same API.
await page.addInitScript(() => {
	const real = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
	navigator.mediaDevices.getUserMedia = (c) => {
		if (c && c.audio && !c.video) {
			const ctx = new AudioContext();
			const o = ctx.createOscillator();
			const d = ctx.createMediaStreamDestination();
			o.connect(d);
			o.start();
			return Promise.resolve(d.stream);
		}
		return real(c);
	};
});
const errors = [];
page.on("pageerror", (e) => errors.push(String(e)));
let failed = 0;

for (let attempt = 0; ; attempt++) {
	try {
		await page.goto(`http://127.0.0.1:${port}/examples/capture/web/index.html`);
		break;
	} catch (e) {
		if (attempt > 50) throw e;
		await new Promise((r) => setTimeout(r, 100));
	}
}

const status = () => page.evaluate(() => [...document.querySelectorAll("*")].map((e) => e.firstChild && e.firstChild.nodeType === 3 ? e.firstChild.textContent : "").find((t) => t.startsWith("status ")) ?? "");
async function expectStatus(prefix, why, tries = 80) {
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
const shot = async (name) => { if (shots) await page.screenshot({ path: `${shots}/capture-${name}.png` }); };
const press = (text) => page.getByText(text, { exact: true }).first().click();
const shownImages = () => page.evaluate(() => [...document.querySelectorAll("img")].filter((i) => i.complete && i.naturalWidth > 0).map((i) => `${i.naturalWidth}x${i.naturalHeight}`));

await expectStatus("status ready", "the demo starts");
let chooser = page.waitForEvent("filechooser");
await press("pick photo");
let picker = await chooser;
check(!picker.isMultiple() && (await picker.element().getAttribute("capture")) === null, "the library picker is a single file input without capture");
await picker.setFiles("examples/capture/assets/swatch.png");
await expectStatus("status picked image 64x48", "a chosen png comes back as a 64x48 image asset");
check((await shownImages()).includes("64x48"), "the picked photo shows in an Image");
await shot("picked");

chooser = page.waitForEvent("filechooser");
await press("system camera");
picker = await chooser;
check((await picker.element().getAttribute("capture")) === "environment", "the camera picker asks the input to capture from the back camera");
await picker.setFiles("examples/capture/assets/swatch.png");
await expectStatus("status shot image 64x48", "a captured file comes back as an image asset");

await press("camera");
await press("open camera");
await expectStatus("status camera ready back", "the CameraView streams the fake camera");
check(await page.evaluate(() => { const v = document.querySelector("video.neon-camera"); return !!v && v.videoWidth > 0 && !v.paused; }), "the preview video plays");
await shot("camera");
await press("take picture");
await expectStatus("status picture 640x480", "takePictureAsync returns the fake camera's 640x480 frame");
check((await shownImages()).includes("640x480"), "the picture shows in an Image");
await shot("picture");
await press("flip");
await expectStatus("status camera ready front", "flipping restarts the stream on the front camera");
check(await page.evaluate(() => document.querySelector("video.neon-camera").classList.contains("neon-camera-mirror")), "the front preview is mirrored");
await press("close");
await expectStatus("status camera closed", "closing unmounts the camera");
check(await page.evaluate(() => !document.querySelector("video.neon-camera")), "the camera element is gone");

await press("audio");
await press("play clip");
await expectStatus("status clip finished", "the bundled chime plays to its end");
await press("record");
await expectStatus("status recording", "recording starts");
await page.waitForTimeout(1200);
await shot("recording");
await press("stop");
await expectStatus("status recorded 500+ms", "the recording stops with its duration");
await press("play recording");
await expectStatus("status recording finished", "the recording plays back to its end", 150);
await shot("audio");

check(errors.length === 0, `no page errors ${errors.join(" | ")}`);
await browser.close();
server.kill();
console.log(failed === 0 ? "capture: all passed" : `capture: ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
