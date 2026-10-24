// chrome-args: --use-fake-device-for-media-stream --use-fake-ui-for-media-stream --autoplay-policy=no-user-gesture-required
import { render, hydrate } from "../../src/render/host";
import { Host, HostNode, NeonNode } from "../../src/render/hostTypes";
import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { OnLoadData, VideoResizeMode } from "../../src/components/video";
import { WebViewMessageEvent, WebViewNavigationEvent } from "../../src/components/webView";
import { CameraType, CameraMountError } from "../../src/components/cameraView";
import { sleepAsync } from "std/core/promise";

when (js) {
	import { domHost } from "../../src/platform/browser/dom";
	import { FRAME_PAGE, OTHER_PAGE, MediaHooks, mediaApp, servedPart } from "./servedApps";

	extern class Page {
		extern remove(): void;
	}
	extern function parsedPage(html: cstring): Page from
		"(s => { const r=document.createElement('div');r.innerHTML=s;document.body.appendChild(r);r.querySelectorAll('*').forEach(n=>{n.neonServed=true;});return r; })(#)";
	extern function emptyPage(): Page from "(() => { const r=document.createElement('div');document.body.appendChild(r);return r; })()";
	extern function pageNode(root: Page, selector: cstring): Page from "(#).querySelector(#)";
	extern function notServed(root: Page): number from
		"(r => Array.from(r.querySelectorAll('*')).filter(n=>n.neonServed!==true).length)(#)";
	extern function shape(root: Page): string from
		"(r => { const f=n=>n.nodeType===1?[n.localName,Array.from(n.attributes,a=>[a.name,a.name==='class'?a.value.split(/\\s+/).sort().join(' '):a.value]).sort((a,b)=>a[0].localeCompare(b[0])),Array.from(n.childNodes,f)]:n.nodeType===3?n.data:'comment '+n.data;return JSON.stringify(Array.from(r.childNodes,f)); })(#)";
	extern function hasClass(node: Page, name: cstring): boolean from "(#).classList.contains(#)";
	extern function propOf(node: Page, name: cstring): string from "((n, p) => String(n[p]))(#, #)";
	extern function fire(node: Page, type: cstring): void from "((n, t) => n.dispatchEvent(new Event(t)))(#, #)";
	extern function frameLoaded(node: Page): boolean from "(f => { try { return f.contentDocument.readyState === 'complete' && f.contentWindow.location.href === 'about:srcdoc'; } catch (e) { return false; } })(#)";
	extern function blankLoaded(node: Page): boolean from "(f => { try { return f.contentDocument.readyState === 'complete'; } catch (e) { return false; } })(#)";
	extern function framePost(node: Page, data: cstring): void from "((f, d) => f.contentWindow.ReactNativeWebView.postMessage(d))(#, #)";
	extern function markFrame(node: Page): void from "(f => { f.contentWindow.__kept = 1; })(#)";
	extern function frameMarked(node: Page): boolean from "(f => { try { return f.contentWindow.__kept === 1; } catch (e) { return false; } })(#)";
	extern function frameText(node: Page): string from "(f => { try { return f.contentDocument.getElementById('t').textContent; } catch (e) { return ''; } })(#)";
	extern function countEmptied(node: Page): void from "(v => { v.__emptied = 0; v.addEventListener('emptied', () => { v.__emptied += 1; }); })(#)";
	extern function emptied(node: Page): number from "(#).__emptied";
	extern function hasStream(node: Page): boolean from "(v => !!v.srcObject && v.videoWidth > 0)(#)";

	async function waitFor(what: string, ready: () => boolean, ms: number): Promise<void> {
		const end = performance.now() + ms;
		while (!ready()) {
			if (performance.now() > end) { throw new Error("timed out waiting for " + what); }
			await sleepAsync(20);
		}
	}

	class Seen {
		videoLoads: number = 0;
		ends: number = 0;
		messages: string[] = [];
		frameLoads: number = 0;
		back: boolean = false;
		ready: number = 0;
		errors: string = "";
	}

	function hooks(seen: Seen): MediaHooks {
		return {
			onVideoLoad: (d: OnLoadData): void => { seen.videoLoads += 1; },
			onVideoEnd: (): void => { seen.ends += 1; },
			onMessage: (e: WebViewMessageEvent): void => { seen.messages.push(e.nativeEvent.data); },
			onFrameLoad: (e: WebViewNavigationEvent): void => { seen.frameLoads += 1; seen.back = e.nativeEvent.canGoBack; },
			onCameraReady: (): void => { seen.ready += 1; },
			onCameraError: (e: CameraMountError): void => { seen.errors = e.message; },
		};
	}

	function rendered(app: NeonNode): string {
		const mount = emptyPage();
		const dispose = render(app, domHost(), mount as unknown as HostNode);
		const result = shape(mount);
		dispose();
		mount.remove();
		return result;
	}

	function countingHost(counter: int32[]): Host {
		const host: Host = domHost();
		const create = host.createElement;
		host.createElement = (tag: string): HostNode => { counter[0] += 1; return create(tag); };
		return host;
	}

	test "hydrate takes over a served Video, keeps its node and follows its signals" {
		const seen = new Seen();
		const [fit, setFit] = createSignal<VideoResizeMode>("cover");
		const [facing, _facing] = createSignal<CameraType>("front");
		const [page, _page] = createSignal(FRAME_PAGE);
		const mount = parsedPage(servedPart("media", "html"));
		const video = pageNode(mount, "video.neon-video");
		const fresh = rendered(mediaApp(fit, facing, page, hooks(new Seen())));
		countEmptied(video);
		const made = [0];
		const dispose = hydrate(mediaApp(fit, facing, page, hooks(seen)), countingHost(made), mount as unknown as HostNode);
		try {
			assert made[0] === 0, "the host created " + made[0].toString() + " elements";
			assert notServed(mount) === 0, notServed(mount).toString() + " elements are not the page's own";
			assert pageNode(mount, "video.neon-video") === video, "hydrate replaced the served video";
			assert shape(mount) === fresh, shape(mount) + " vs " + fresh;
			assert propOf(video, "muted") === "true" && propOf(video, "loop") === "true" && propOf(video, "controls") === "true",
				"the props did not reach the served video";
			await waitFor("the clip's metadata", (): boolean => seen.videoLoads > 0, 5000);
			await sleepAsync(150);
			assert emptied(video) === 0, "hydrate reloaded the served clip";
			assert seen.videoLoads === 1, "onLoad ran " + seen.videoLoads.toString() + " times";
			fire(video, "ended");
			assert seen.ends === 1, "onEnd ran " + seen.ends.toString() + " times";
			assert hasClass(video, "neon-video-cover"), "the served cover class is gone";
			setFit("stretch");
			flush();
			assert hasClass(video, "neon-video-stretch") && !hasClass(video, "neon-video-cover"), "resizeMode did not follow its signal";
			assert pageNode(mount, "video.neon-video") === video, "an update replaced the served video";
		} finally { dispose(); mount.remove(); }
	}

	test "hydrate takes over a served WebView before its page loads and the page reaches the app once" {
		const seen = new Seen();
		const [fit, _fit] = createSignal<VideoResizeMode>("cover");
		const [facing, _facing] = createSignal<CameraType>("front");
		const [page, _page] = createSignal(FRAME_PAGE);
		const mount = parsedPage(servedPart("media", "html"));
		const frame = pageNode(mount, "iframe.neon-webview");
		const dispose = hydrate(mediaApp(fit, facing, page, hooks(seen)), domHost(), mount as unknown as HostNode);
		try {
			assert pageNode(mount, "iframe.neon-webview") === frame, "hydrate replaced the served iframe";
			await waitFor("the page's message", (): boolean => seen.messages.length > 0, 5000);
			await sleepAsync(150);
			assert seen.messages.length === 1 && seen.messages[0] === "ready", "messages: " + seen.messages.join(",");
			assert seen.frameLoads === 1, "onLoad ran " + seen.frameLoads.toString() + " times";
			assert !seen.back, "the page that loaded after hydrate counts a page before it";
		} finally { dispose(); mount.remove(); }
	}

	test "hydrate takes over a served WebView that already loaded, keeps its page and follows its signal" {
		const seen = new Seen();
		const [fit, _fit] = createSignal<VideoResizeMode>("cover");
		const [facing, _facing] = createSignal<CameraType>("front");
		const [page, setPage] = createSignal(FRAME_PAGE);
		const mount = parsedPage(servedPart("media", "html"));
		const frame = pageNode(mount, "iframe.neon-webview");
		const blank = pageNode(mount, "iframe.neon-webview:not([sandbox])[src='about:blank']");
		await waitFor("the served page", (): boolean => frameLoaded(frame) && blankLoaded(blank), 5000);
		await sleepAsync(100);
		markFrame(frame);
		const dispose = hydrate(mediaApp(fit, facing, page, hooks(seen)), domHost(), mount as unknown as HostNode);
		try {
			await sleepAsync(200);
			assert pageNode(mount, "iframe.neon-webview") === frame, "hydrate replaced the served iframe";
			assert frameMarked(frame), "hydrate reloaded the served page";
			assert seen.messages.length === 0 && seen.frameLoads === 0, "the page was reported again: " + seen.messages.join(",");
			framePost(blank, "late");
			await waitFor("the served blank page's message", (): boolean => seen.messages.length > 0, 5000);
			assert seen.messages.length === 1 && seen.messages[0] === "late", "messages: " + seen.messages.join(",");
			setPage(OTHER_PAGE);
			flush();
			await waitFor("the next page", (): boolean => frameText(frame) === "other", 5000);
			await waitFor("its load", (): boolean => seen.frameLoads > 0, 5000);
			await sleepAsync(100);
			assert seen.frameLoads === 1, "onLoad ran " + seen.frameLoads.toString() + " times";
			assert seen.back, "the served page is not in the frame's history";
			assert pageNode(mount, "iframe.neon-webview") === frame, "an update replaced the served iframe";
		} finally { dispose(); mount.remove(); }
	}

	test "hydrate takes over a served CameraView, keeps its node and streams into it" {
		const seen = new Seen();
		const [fit, _fit] = createSignal<VideoResizeMode>("cover");
		const [facing, setFacing] = createSignal<CameraType>("front");
		const [page, _page] = createSignal(FRAME_PAGE);
		const mount = parsedPage(servedPart("media", "html"));
		const camera = pageNode(mount, "video.neon-camera");
		const dispose = hydrate(mediaApp(fit, facing, page, hooks(seen)), domHost(), mount as unknown as HostNode);
		try {
			assert pageNode(mount, "video.neon-camera") === camera, "hydrate replaced the served camera";
			await waitFor("the camera", (): boolean => seen.ready > 0 || seen.errors !== "", 8000);
			assert seen.errors === "" && seen.ready === 1, "ready " + seen.ready.toString() + ": " + seen.errors;
			assert hasStream(camera), "the stream did not reach the served element";
			assert hasClass(camera, "neon-camera-mirror"), "the served mirror class is gone";
			setFacing("back");
			flush();
			assert !hasClass(camera, "neon-camera-mirror"), "facing did not follow its signal";
			await waitFor("the restart", (): boolean => seen.ready > 1, 8000);
			assert seen.ready === 2 && pageNode(mount, "video.neon-camera") === camera, "ready " + seen.ready.toString();
		} finally { dispose(); mount.remove(); }
	}
}
