import { NeonEvent } from "../render/event";
import { Style, layerStyles } from "../render/style";
import { Accessor } from "../core/signal";
import { onCleanup } from "../core/cleanup";
import { Host, HostNode } from "../render/hostTypes";
import { NeonNode, VAttr, VEvent, hostElement, evt, dynAttr } from "../render/node";
import { appServices, hasAppServices } from "../api/services";

export interface WebViewSource {
	uri?: string | null;
	html?: string | null;
	baseUrl?: string | null;
}

export struct WebViewNavigation {
	url: string;
	title: string;
	loading: boolean;
	canGoBack: boolean;
	canGoForward: boolean;
}

export struct WebViewNavigationEvent {
	nativeEvent: WebViewNavigation;
}

export struct WebViewMessage {
	url: string;
	title: string;
	loading: boolean;
	canGoBack: boolean;
	canGoForward: boolean;
	data: string;
}

export struct WebViewMessageEvent {
	nativeEvent: WebViewMessage;
}

export struct WebViewError {
	url: string;
	title: string;
	loading: boolean;
	canGoBack: boolean;
	canGoForward: boolean;
	code: int32;
	description: string;
}

export struct WebViewErrorEvent {
	nativeEvent: WebViewError;
}

export struct ShouldStartLoadRequest {
	url: string;
	title: string;
	loading: boolean;
	canGoBack: boolean;
	canGoForward: boolean;
	navigationType: string;
	isTopFrame: boolean;
}

export interface WebViewProps {
	source?: Accessor<WebViewSource> | null;
	javaScriptEnabled?: Accessor<boolean> | null;
	originWhitelist?: Accessor<string[]> | null;
	injectedJavaScript?: Accessor<string> | null;
	style?: Accessor<Style> | null;
	ref?: ((handle: WebViewHandle) => void) | null;
	onLoadStart?: ((event: WebViewNavigationEvent) => void) | null;
	onLoad?: ((event: WebViewNavigationEvent) => void) | null;
	onLoadEnd?: ((event: WebViewNavigationEvent) => void) | null;
	onError?: ((event: WebViewErrorEvent) => void) | null;
	onMessage?: ((event: WebViewMessageEvent) => void) | null;
	onNavigationStateChange?: ((navigation: WebViewNavigation) => void) | null;
	onShouldStartLoadWithRequest?: ((request: ShouldStartLoadRequest) => boolean) | null;
	onLayout?: ((e: NeonEvent) => void) | null;
}

class WebViewSlot {
	host: Host | null = null;
	node: HostNode | null = null;
	mounted: boolean = false;
	state: WebViewNavigation = { url: "", title: "", loading: false, canGoBack: false, canGoForward: false };

	command(name: string, argument: string): void {
		if (!this.mounted || this.host === null || this.node === null) {
			throw new Error(`WebView.${name} was called while the WebView is not mounted`);
		}
		(this.host as Host).setAttr(this.node as HostNode, "command", name + "\x1f" + argument);
	}

	answer(allow: boolean): void {
		if (this.host === null || this.node === null) { return; }
		(this.host as Host).setAttr(this.node as HostNode, "loadDecision", allow ? "allow" : "block");
	}
}

export class WebViewHandle {
	private slot: WebViewSlot;

	constructor(slot: WebViewSlot) {
		this.slot = slot;
	}

	goBack(): void { this.slot.command("goBack", ""); }
	goForward(): void { this.slot.command("goForward", ""); }
	reload(): void { this.slot.command("reload", ""); }
	stopLoading(): void { this.slot.command("stopLoading", ""); }
	injectJavaScript(script: string): void { this.slot.command("injectJavaScript", script); }
	postMessage(data: string): void { this.slot.command("postMessage", data); }
	requestFocus(): void { this.slot.command("requestFocus", ""); }
}

// The wire form of a source: "uri\x1f<url>" or "html\x1f<html>\x1f<baseUrl>".
export function webViewSourceAttr(source: WebViewSource): string {
	const html = source.html ?? "";
	const uri = source.uri ?? "";
	if (html !== "" && uri !== "") { throw new Error("WebView: a source takes either uri or html, not both"); }
	if (html !== "") { return "html\x1f" + html + "\x1f" + (source.baseUrl ?? ""); }
	return "uri\x1f" + uri;
}

// A navigation record on the wire: url, title, loading, canGoBack, canGoForward.
export function parseNavigation(value: string): WebViewNavigation {
	const fields = value.split("\x1f");
	const at = (i: int32): string => (i < fields.length ? fields[i] : "");
	return {
		url: at(0),
		title: at(1),
		loading: at(2) === "true",
		canGoBack: at(3) === "true",
		canGoForward: at(4) === "true",
	};
}

// RN WebViewShared.tsx extractOrigin: /^[A-Za-z][A-Za-z0-9+\-.]+:(\/\/)?[^/]*/.
export function originOf(url: string): string {
	if (url.length === 0 || !isLetter(url.charCodeAt(0))) { return ""; }
	let at: int32 = 1;
	while (at < url.length && schemeChar(url.charCodeAt(at))) { at += 1; }
	if (at < 2 || at >= url.length || url.charCodeAt(at) !== 58) { return ""; }
	at += 1;
	if (url.substring(at, at + 2) === "//") { at += 2; }
	while (at < url.length && url.charCodeAt(at) !== 47) { at += 1; }
	return url.substring(0, at);
}

function isLetter(code: int32): boolean {
	return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
}

function schemeChar(code: int32): boolean {
	return isLetter(code) || (code >= 48 && code <= 57) || code === 43 || code === 45 || code === 46;
}

// RN's whitelist entry is a regex `^entry` with `*` as `.*`: a prefix match of the origin.
function globPrefix(pattern: string, p: int32, text: string, t: int32): boolean {
	if (p === pattern.length) { return true; }
	if (pattern.charCodeAt(p) === 42) {
		for (let k = t; k <= text.length; k += 1) {
			if (globPrefix(pattern, p + 1, text, k)) { return true; }
		}
		return false;
	}
	if (t >= text.length || pattern.charCodeAt(p) !== text.charCodeAt(t)) { return false; }
	return globPrefix(pattern, p + 1, text, t + 1);
}

// RN passesWhitelist: `about:blank` always passes, then every entry against the url's origin.
export function passesWhitelist(whitelist: string[], url: string): boolean {
	const origin = originOf(url);
	if (origin === "") { return false; }
	if (globPrefix("about:blank", 0, origin, 0)) { return true; }
	for (const entry of whitelist) {
		if (globPrefix(entry, 0, origin, 0)) { return true; }
	}
	return false;
}

// RN's default originWhitelist.
const DEFAULT_WHITELIST: string[] = ["http://*", "https://*"];

// A url the whitelist refuses goes to the system, as RN does.
async function openOutside(url: string): Promise<void> {
	const services = appServices("WebView.originWhitelist");
	if (await services.canOpenURL(url)) {
		const opened = await services.openURL(url);
		if (!opened) { console.log(`WebView: the system did not open ${url}`); }
	}
}

function navigationEvent(state: WebViewNavigation): WebViewNavigationEvent {
	return { nativeEvent: state };
}

// RN WebView's default style: it fills its parent, white under the page.
const WEBVIEW_BASE: Style = { flexGrow: 1, flexShrink: 1, flexBasis: 0, backgroundColor: "#ffffff", overflow: "hidden" };

export function WebView(props: WebViewProps): NeonNode {
	const slot = new WebViewSlot();
	const attrs: VAttr[] = [];
	attrs.push(dynAttr("interceptLoads", (): string | null => "true"));
	const scripts = props.javaScriptEnabled;
	if (scripts !== null) {
		const read = scripts as Accessor<boolean>;
		attrs.push(dynAttr("javaScriptEnabled", (): string | null => read() ? "true" : "false"));
	}
	const source = props.source;
	if (source !== null) {
		const read = source as Accessor<WebViewSource>;
		attrs.push(dynAttr("source", (): string | null => webViewSourceAttr(read())));
	}
	const whitelist = props.originWhitelist;
	const decide = props.onShouldStartLoadWithRequest;
	const injected = props.injectedJavaScript;
	const loadStart = props.onLoadStart;
	const load = props.onLoad;
	const loadEnd = props.onLoadEnd;
	const fail = props.onError;
	const message = props.onMessage;
	const navigation = props.onNavigationStateChange;
	const changed = (state: WebViewNavigation): void => {
		slot.state = state;
		if (navigation !== null) { (navigation as (n: WebViewNavigation) => void)(state); }
	};
	const evts: VEvent[] = [];
	evts.push(evt("onLoadStart", (e: NeonEvent): void => {
		const state = parseNavigation(e.value);
		if (loadStart !== null) { (loadStart as (x: WebViewNavigationEvent) => void)(navigationEvent(state)); }
		changed(state);
	}));
	evts.push(evt("onLoad", (e: NeonEvent): void => {
		const state = parseNavigation(e.value);
		if (injected !== null) {
			const script = (injected as Accessor<string>)();
			if (script !== "") { slot.command("injectJavaScript", script); }
		}
		if (load !== null) { (load as (x: WebViewNavigationEvent) => void)(navigationEvent(state)); }
		if (loadEnd !== null) { (loadEnd as (x: WebViewNavigationEvent) => void)(navigationEvent(state)); }
		changed(state);
	}));
	evts.push(evt("onError", (e: NeonEvent): void => {
		const fields = e.value.split("\x1f");
		const state = slot.state;
		const error: WebViewError = {
			url: fields.length > 2 ? fields[2] : state.url,
			title: state.title,
			loading: false,
			canGoBack: state.canGoBack,
			canGoForward: state.canGoForward,
			code: fields.length > 0 ? parseInt(fields[0]) as int32 : 0,
			description: fields.length > 1 ? fields[1] : "",
		};
		if (loadEnd !== null) {
			(loadEnd as (x: WebViewNavigationEvent) => void)(navigationEvent({ ...state, url: error.url, loading: false }));
		}
		if (fail !== null) { (fail as (x: WebViewErrorEvent) => void)({ nativeEvent: error }); }
	}));
	if (message !== null) {
		evts.push(evt("onMessage", (e: NeonEvent): void => {
			const state = slot.state;
			(message as (x: WebViewMessageEvent) => void)({
				nativeEvent: {
					url: state.url,
					title: state.title,
					loading: state.loading,
					canGoBack: state.canGoBack,
					canGoForward: state.canGoForward,
					data: e.value,
				},
			});
		}));
	}
	evts.push(evt("onShouldStartLoad", (e: NeonEvent): void => {
		const fields = e.value.split("\x1f");
		const url = fields[0];
		const allowed = whitelist === null ? DEFAULT_WHITELIST : (whitelist as Accessor<string[]>)();
		if (!passesWhitelist(allowed, url)) {
			slot.answer(false);
			if (hasAppServices()) { openOutside(url); }
			return;
		}
		if (decide === null) {
			slot.answer(true);
			return;
		}
		const state = slot.state;
		const request: ShouldStartLoadRequest = {
			url,
			title: state.title,
			loading: true,
			canGoBack: state.canGoBack,
			canGoForward: state.canGoForward,
			navigationType: fields.length > 1 ? fields[1] : "other",
			isTopFrame: fields.length > 2 ? fields[2] !== "false" : true,
		};
		slot.answer((decide as (r: ShouldStartLoadRequest) => boolean)(request));
	}));
	if (props.onLayout !== null) { evts.push(evt("onLayout", props.onLayout as (e: NeonEvent) => void)); }
	const userStyle = props.style;
	const style = (): Style => userStyle === null ? WEBVIEW_BASE : layerStyles([WEBVIEW_BASE, (userStyle as () => Style)()]);
	const userRef = props.ref;
	const inner = hostElement("webview", attrs, evts, null, style, (node: HostNode): void => {
		slot.node = node;
		slot.mounted = true;
		onCleanup((): void => { slot.mounted = false; });
		if (userRef !== null) { (userRef as (h: WebViewHandle) => void)(new WebViewHandle(slot)); }
	});
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		slot.host = host;
		inner(host, parent, before);
	};
}
