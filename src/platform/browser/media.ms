import { HostNode } from "../../render/hostTypes";
import { NeonEvent, neonEvent } from "../../render/event";
import { registerCss } from "../../render/sheet";

extern class MediaClassList {
	extern add(name: cstring): void;
	extern remove(name: cstring): void;
}

extern class HTMLElement {
	src: cstring;
	srcdoc: cstring;
	muted: boolean;
	volume: number;
	playbackRate: number;
	defaultPlaybackRate: number;
	loop: boolean;
	controls: boolean;
	currentTime: number;
	duration: number;
	paused: boolean;
	ended: boolean;
	videoWidth: number;
	videoHeight: number;
	currentSrc: string;
	classList: MediaClassList;
	extern setAttribute(name: cstring, value: cstring): void;
	extern removeAttribute(name: cstring): void;
	extern addEventListener(name: cstring, handler: (e: Event) => void): void;
	extern pause(): void;
	extern focus(): void;
}

extern class Event {}

extern class document {
	static extern createElement(tag: cstring): HTMLElement;
}

extern class window {
	static extern addEventListener(name: cstring, handler: (e: Event) => void): void;
}

extern function queueMicrotask(callback: () => void): void;
extern function frameSameOrigin(frame: HTMLElement): boolean from "((f) => { try { return !!f.contentDocument; } catch (e) { return false; } })(#)";
extern function frameLocation(frame: HTMLElement): string from "#.contentWindow.location.href";
extern function frameTitle(frame: HTMLElement): string from "(#.contentDocument.title || '')";
extern function frameEval(frame: HTMLElement, script: cstring): void from "#.contentWindow.eval(#)";
extern function framePost(frame: HTMLElement, data: cstring): void from "#.contentWindow.postMessage(#, '*')";
extern function frameReload(frame: HTMLElement): void from "#.contentWindow.location.reload()";
extern function frameStop(frame: HTMLElement): void from "#.contentWindow.stop()";
extern function historyBack(unused: int32): void from "(#, history.back())";
extern function historyForward(unused: int32): void from "(#, history.forward())";
extern function messageFrom(e: Event, frame: HTMLElement): boolean from "(#.source === #.contentWindow)";
extern function messageLoadUrl(e: Event): string from "((d) => (typeof d === 'object' && d !== null && typeof d.__neonLoad === 'string') ? d.__neonLoad : '')(#.data)";
extern function messageText(e: Event): string from "String(#.data)";
extern function playVideo(video: HTMLElement, failed: (message: string) => void): void from "((v, f) => { const p = v.play(); if (p) p.catch((e) => f(String((e && e.message) || e))); })(#, #)";
extern function videoBuffered(video: HTMLElement): number from "((v) => v.buffered.length ? v.buffered.end(v.buffered.length - 1) : 0)(#)";
extern function videoErrorCode(video: HTMLElement): number from "((v) => v.error ? v.error.code : 0)(#)";
extern function videoErrorMessage(video: HTMLElement): string from "((v) => v.error ? (v.error.message || 'media error ' + v.error.code) : '')(#)";

interface MediaRoute {
	type: string;
	handler: (e: NeonEvent) => void;
}

const MEDIA_CSS = ".neon-webview{border:0;display:block;background:#ffffff}" +
	".neon-video{display:block;background:#000000;object-fit:contain}" +
	".neon-video-cover{object-fit:cover}.neon-video-stretch{object-fit:fill}";

// react-native-webview's page bridge: `window.ReactNativeWebView.postMessage(data)` reaches
// onMessage, and with `intercept` a link click asks onShouldStartLoadWithRequest first.
function bridgeScript(intercept: boolean): string {
	let script = "(function(){window.ReactNativeWebView={postMessage:function(d){parent.postMessage(String(d),'*');}};";
	if (intercept) {
		script += "document.addEventListener('click',function(e){var a=e.target&&e.target.closest?e.target.closest('a[href]'):null;" +
			"if(!a||(a.target&&a.target!=='_self'))return;var h=a.href;if(!h||h.indexOf('javascript:')===0)return;" +
			"if(a.getAttribute('href').charAt(0)==='#')return;e.preventDefault();parent.postMessage({__neonLoad:h},'*');},true);";
	}
	return script + "})();";
}

function escapeScriptEnd(script: string): string {
	return script.split("</").join("<\\/");
}

class MediaState {
	el: HTMLElement;
	kind: string;
	routes: MediaRoute[] = [];
	released: boolean = false;
	source: string = "";
	baseUrl: string = "";
	html: boolean = false;
	intercept: boolean = false;
	decision: string = "";
	index: int32 = -1;
	length: int32 = 0;
	traverse: int32 = 0;
	reloading: boolean = false;
	started: boolean = false;
	loading: boolean = false;
	progressEvery: number = 250;
	timer: number = -1;
	paused: boolean = false;

	constructor(el: HTMLElement, kind: string) {
		this.el = el;
		this.kind = kind;
	}

	fire(type: string, value: string, width: number, height: number): void {
		if (this.released) { return; }
		for (const route of this.routes) {
			if (route.type !== type) { continue; }
			const e = neonEvent(type);
			e.timeStamp = performance.now();
			e.value = value;
			e.width = width;
			e.height = height;
			route.handler(e);
		}
	}

	pageUrl(): string {
		if (frameSameOrigin(this.el)) {
			const href = frameLocation(this.el);
			if (href !== "about:srcdoc") { return href; }
			return this.baseUrl !== "" ? this.baseUrl : "about:blank";
		}
		return this.source;
	}

	navigation(): string {
		const title = frameSameOrigin(this.el) ? frameTitle(this.el) : "";
		const back = this.index > 0;
		const forward = this.index < this.length - 1;
		return `${this.pageUrl()}\x1f${title}\x1f${this.loading}\x1f${back}\x1f${forward}`;
	}

	startLoad(url: string): void {
		this.loading = true;
		this.started = true;
		const at = url;
		queueMicrotask((): void => {
			this.fire("loadstart", `${at}\x1f\x1ftrue\x1f${this.index > 0}\x1f${this.index < this.length - 1}`, 0, 0);
		});
	}
}

const states = new Map<HTMLElement, MediaState>();
let cssDone = false;
let listening = false;

function onWindowMessage(e: Event): void {
	for (const state of states.values()) {
		if (state.kind !== "webview" || state.released || !messageFrom(e, state.el)) { continue; }
		const url = messageLoadUrl(e);
		if (url === "") {
			state.fire("message", messageText(e), 0, 0);
			return;
		}
		state.decision = "allow";
		state.fire("shouldstartload", url + "\x1fclick\x1ftrue", 0, 0);
		if (state.decision === "allow") { navigateFrame(state, url); }
		return;
	}
}

function navigateFrame(state: MediaState, url: string): void {
	state.source = url;
	state.html = false;
	state.el.removeAttribute("srcdoc");
	state.startLoad(url);
	state.el.src = url;
}

function onFrameLoad(state: MediaState): void {
	if (state.traverse !== 0) {
		state.index += state.traverse;
		state.traverse = 0;
	} else if (state.reloading) {
		state.reloading = false;
	} else {
		state.index += 1;
		state.length = state.index + 1;
	}
	if (!state.html && frameSameOrigin(state.el)) { frameEval(state.el, bridgeScript(state.intercept)); }
	if (!state.started) {
		state.loading = true;
		state.fire("loadstart", state.navigation(), 0, 0);
	}
	state.started = false;
	state.loading = false;
	state.fire("load", state.navigation(), 0, 0);
}

function writeFrameSource(state: MediaState, value: string): void {
	const fields = value.split("\x1f");
	if (fields[0] === "html") {
		state.html = true;
		state.baseUrl = fields.length > 2 ? fields[2] : "";
		state.source = state.baseUrl !== "" ? state.baseUrl : "about:blank";
		const base = state.baseUrl !== "" ? `<base href="${state.baseUrl}">` : "";
		const html = fields.length > 1 ? fields[1] : "";
		state.startLoad(state.source);
		state.el.srcdoc = `${base}<script>${escapeScriptEnd(bridgeScript(state.intercept))}</script>${html}`;
		return;
	}
	const url = fields.length > 1 ? fields[1] : "";
	state.html = false;
	state.source = url;
	state.el.removeAttribute("srcdoc");
	state.startLoad(url);
	state.el.src = url;
}

function frameCommand(state: MediaState, name: string, argument: string): void {
	const el = state.el;
	if (name === "postMessage") {
		framePost(el, argument);
		return;
	}
	if (name === "goBack") {
		if (state.index <= 0) { return; }
		state.traverse = -1;
		state.startLoad("");
		historyBack(0);
		return;
	}
	if (name === "goForward") {
		if (state.index >= state.length - 1) { return; }
		state.traverse = 1;
		state.startLoad("");
		historyForward(0);
		return;
	}
	if (name === "reload") {
		state.reloading = true;
		state.startLoad(state.pageUrl());
		if (frameSameOrigin(el)) { frameReload(el); } else { el.src = state.source; }
		return;
	}
	if (name === "stopLoading") {
		if (frameSameOrigin(el)) { frameStop(el); }
		return;
	}
	if (name === "requestFocus") {
		el.focus();
		return;
	}
	if (name === "injectJavaScript") {
		if (!frameSameOrigin(el)) {
			throw new Error(`WebView.injectJavaScript: the page at ${state.source} is cross-origin, and the browser runs script only in a same-origin frame`);
		}
		frameEval(el, argument);
		return;
	}
	throw new Error(`WebView: the browser host has no command "${name}"`);
}

function writeFrameAttr(state: MediaState, name: string, value: string): boolean {
	if (name === "source") {
		writeFrameSource(state, value);
		return true;
	}
	if (name === "javaScriptEnabled") {
		if (value === "false") { state.el.setAttribute("sandbox", "allow-same-origin allow-forms allow-popups"); }
		else { state.el.removeAttribute("sandbox"); }
		return true;
	}
	if (name === "interceptLoads") {
		state.intercept = value === "true";
		return true;
	}
	if (name === "loadDecision") {
		state.decision = value;
		return true;
	}
	if (name === "command") {
		const cut = value.indexOf("\x1f");
		frameCommand(state, cut < 0 ? value : value.substring(0, cut), cut < 0 ? "" : value.substring(cut + 1, value.length));
		return true;
	}
	return false;
}

function progressRecord(el: HTMLElement): string {
	return `${el.currentTime}\x1f${videoBuffered(el)}\x1f${el.duration}`;
}

function stopProgress(state: MediaState): void {
	if (state.timer < 0) { return; }
	clearInterval(state.timer);
	state.timer = -1;
}

function startProgress(state: MediaState): void {
	stopProgress(state);
	state.timer = setInterval((): void => {
		if (state.released) {
			stopProgress(state);
			return;
		}
		state.fire("progress", progressRecord(state.el), 0, 0);
	}, state.progressEvery);
}

function play(state: MediaState): void {
	playVideo(state.el, (message: string): void => { state.fire("error", "0\x1f" + message, 0, 0); });
}

function writeVideoAttr(state: MediaState, name: string, value: string): boolean {
	const el = state.el;
	if (name === "source") {
		el.src = value;
		if (!state.paused) { play(state); }
		return true;
	}
	if (name === "paused") {
		state.paused = value === "true";
		if (state.paused) { el.pause(); } else { play(state); }
		return true;
	}
	if (name === "muted") { el.muted = value === "true"; return true; }
	if (name === "volume") { el.volume = Math.min(Math.max(parseFloat(value), 0), 1); return true; }
	if (name === "rate") {
		el.defaultPlaybackRate = parseFloat(value);
		el.playbackRate = parseFloat(value);
		return true;
	}
	if (name === "repeat") { el.loop = value === "true"; return true; }
	if (name === "controls") { el.controls = value === "true"; return true; }
	if (name === "progressUpdateInterval") {
		state.progressEvery = parseFloat(value);
		if (state.timer >= 0) { startProgress(state); }
		return true;
	}
	if (name === "resizeMode") {
		el.classList.remove("neon-video-cover");
		el.classList.remove("neon-video-stretch");
		if (value === "cover") { el.classList.add("neon-video-cover"); }
		if (value === "stretch") { el.classList.add("neon-video-stretch"); }
		return true;
	}
	if (name === "command") {
		const cut = value.indexOf("\x1f");
		const command = cut < 0 ? value : value.substring(0, cut);
		if (command === "seek") { el.currentTime = parseFloat(value.substring(cut + 1, value.length)); }
		else if (command === "pause") { el.pause(); }
		else if (command === "resume") { play(state); }
		else { throw new Error(`Video: the browser host has no command "${command}"`); }
		return true;
	}
	return false;
}

function listenVideo(state: MediaState): void {
	const el = state.el;
	el.addEventListener("loadstart", (e: Event): void => { state.fire("loadstart", el.currentSrc, 0, 0); });
	el.addEventListener("loadedmetadata", (e: Event): void => {
		state.fire("load", `${el.duration}\x1f${el.currentTime}`, el.videoWidth, el.videoHeight);
	});
	el.addEventListener("play", (e: Event): void => { startProgress(state); });
	el.addEventListener("pause", (e: Event): void => {
		stopProgress(state);
		state.fire("progress", progressRecord(el), 0, 0);
	});
	el.addEventListener("seeked", (e: Event): void => { state.fire("progress", progressRecord(el), 0, 0); });
	el.addEventListener("ended", (e: Event): void => {
		stopProgress(state);
		state.fire("end", "", 0, 0);
	});
	el.addEventListener("error", (e: Event): void => {
		state.fire("error", `${videoErrorCode(el)}\x1f${videoErrorMessage(el)}`, 0, 0);
	});
}

export function isMediaTag(tag: string): boolean {
	return tag === "webview" || tag === "video";
}

export function createMediaNode(tag: string): HostNode {
	if (!cssDone) {
		registerCss("neon-media", MEDIA_CSS);
		cssDone = true;
	}
	const el = document.createElement(tag === "webview" ? "iframe" : "video");
	const state = new MediaState(el, tag);
	states.set(el, state);
	if (tag === "webview") {
		el.classList.add("neon-webview");
		el.addEventListener("load", (e: Event): void => { onFrameLoad(state); });
		if (!listening) {
			window.addEventListener("message", onWindowMessage);
			listening = true;
		}
	} else {
		el.classList.add("neon-video");
		el.setAttribute("playsinline", "");
		listenVideo(state);
	}
	return el as unknown as HostNode;
}

export function isMediaNode(node: HostNode): boolean {
	return states.has(node as unknown as HTMLElement);
}

export function writeMediaAttr(node: HostNode, name: string, value: string): boolean {
	const el = node as unknown as HTMLElement;
	if (!states.has(el)) { return false; }
	const state = states.get(el) as MediaState;
	return state.kind === "webview" ? writeFrameAttr(state, name, value) : writeVideoAttr(state, name, value);
}

export function addMediaEvent(node: HostNode, type: string, handler: (e: NeonEvent) => void): boolean {
	const el = node as unknown as HTMLElement;
	if (!states.has(el) || type === "layout") { return false; }
	(states.get(el) as MediaState).routes.push({ type, handler });
	return true;
}

export function releaseMedia(node: HostNode): void {
	const el = node as unknown as HTMLElement;
	if (!states.has(el)) { return; }
	const state = states.get(el) as MediaState;
	state.released = true;
	stopProgress(state);
	if (state.kind === "video") { el.pause(); }
	states.delete(el);
}
