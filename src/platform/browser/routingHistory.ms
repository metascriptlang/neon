import { Dispose } from "../../core/types";
import { RoutingHistory, RoutingHistoryEntry } from "../../navigation/routingHistory";
import { ACTION_URL, FormData } from "../../navigation/action";

when (js) {
	interface BrowserRoutingState {
		__neonRouting: string;
		__neonIndex: int32;
	}

	extern class BrowserLocation {
		pathname: string;
		search: string;
		hash: string;
	}

	extern class BrowserHistory {
		extern pushState(state: BrowserRoutingState, title: string, url: string): void;
		extern replaceState(state: BrowserRoutingState, title: string, url: string): void;
		extern go(delta: int32): void;
	}

	extern class window {
		static location: BrowserLocation;
		static history: BrowserHistory;
		static extern addEventListener(
			name: string,
			listener: (event: unknown) => void,
			capture: boolean,
		): void;
		static extern removeEventListener(
			name: string,
			listener: (event: unknown) => void,
			capture: boolean,
		): void;
	}

	extern function readHistoryString(key: string): string from
		"(k => typeof history.state?.[k] === 'string' ? history.state[k] : '')(#)";
	extern function readHistoryIndex(key: string): int32 from
		"(k => Number.isInteger(history.state?.[k]) ? history.state[k] : 0)(#)";

	extern class Event {
		extern preventDefault(): void;
	}

	extern function sameOriginLink(event: Event): string from
		"(e => { if (e.defaultPrevented || e.button > 0 || e.metaKey || e.altKey || e.ctrlKey || e.shiftKey) return ''; const a = e.composedPath().find(n => n instanceof Node && n.nodeName.toUpperCase() === 'A'); if (!a || a.target || !a.href || a.hasAttribute('download') || (a.getAttribute('rel') || '').split(/\\s+/).includes('external')) return ''; const u = new URL(a.href, document.baseURI); return u.origin === location.origin ? u.pathname + u.search + u.hash : ''; })(#)";
	extern class Anchor {}
	extern function eventAnchor(event: Event): Anchor from
		"(e => e.composedPath().find(n => n instanceof Node && n.nodeName.toUpperCase() === 'A'))(#)";
	extern function preloadDisabled(anchor: Anchor): boolean from
		"(a => a.getAttribute('preload') === 'false')(#)";
	extern function listenPassive(name: string, listener: (event: unknown) => void): void from
		"window.addEventListener(#, #, { passive: true })";
	extern function scrollToFragmentOrTop(url: string): void from
		"(u => { const at = u.indexOf('\\x23'); const el = at < 0 ? null : document.getElementById(decodeURIComponent(u.slice(at + 1))); if (el) el.scrollIntoView(); else window.scrollTo(0, 0); })(#)";

	extern function submitUrl(event: Event): string from
		"(e => { if (e.defaultPrevented) return ''; const s = e.submitter; return (s && s.hasAttribute('formaction') ? s.getAttribute('formaction') : e.target.getAttribute('action')) || ''; })(#)";
	extern function submitMethod(event: Event): string from
		"(e => e.target.method.toUpperCase())(#)";
	extern function submitEntries(event: Event, add: (name: string, value: string) => void): void from
		"((e, add) => { for (const [k, v] of new globalThis.FormData(e.target, e.submitter)) { if (typeof v !== 'string') throw new Error('an action form takes text fields only: ' + k); add(k, v); } })(#, #)";
	extern function listenDocument(name: string, listener: (event: unknown) => void): void from
		"document.addEventListener(#, #)";
	extern function unlistenDocument(name: string, listener: (event: unknown) => void): void from
		"document.removeEventListener(#, #)";

	function readBrowserEntry(): RoutingHistoryEntry {
		return {
			url: window.location.pathname + window.location.search + window.location.hash,
			state: readHistoryString("__neonRouting"),
		};
	}
}

export function createBrowserRoutingHistory(): RoutingHistory {
	when (js) {
		return {
			writable: true,
			read: readBrowserEntry,
			index: (): int32 => readHistoryIndex("__neonIndex"),
			push: (entry: RoutingHistoryEntry): void => {
				window.history.pushState({
					__neonRouting: entry.state,
					__neonIndex: readHistoryIndex("__neonIndex") + 1,
				}, "", entry.url);
			},
			replace: (entry: RoutingHistoryEntry): void => {
				window.history.replaceState({
					__neonRouting: entry.state,
					__neonIndex: readHistoryIndex("__neonIndex"),
				}, "", entry.url);
			},
			go: (delta: int32): boolean => {
				if (delta === 0) { return false; }
				window.history.go(delta);
				return true;
			},
			listen: (listener: (entry: RoutingHistoryEntry) => void): Dispose => {
				const handler = (event: unknown): void => listener(readBrowserEntry());
				window.addEventListener("popstate", handler, false);
				let removed = false;
				return (): void => {
					if (removed) { return; }
					removed = true;
					window.removeEventListener("popstate", handler, false);
				};
			},
		};
	} else {
		throw new Error("routing: browser history requires the JavaScript browser host");
	}
}

export function followLinks(navigate: (url: string) => boolean): Dispose {
	when (js) {
		const handler = (event: unknown): void => {
			const click = event as Event;
			const url = sameOriginLink(click);
			if (url === "" || !navigate(url)) { return; }
			click.preventDefault();
			scrollToFragmentOrTop(url);
		};
		window.addEventListener("click", handler, false);
		return (): void => window.removeEventListener("click", handler, false);
	} else {
		throw new Error("routing: following links requires the JavaScript browser host");
	}
}

export function followPreloads(preload: (url: string) => void): Dispose {
	when (js) {
		let pending: number = 0;
		let last: Anchor | null = null;
		const preloadEvent = (event: unknown): void => {
			const url = sameOriginLink(event as Event);
			if (url === "" || preloadDisabled(eventAnchor(event as Event))) { return; }
			preload(url);
		};
		const move = (event: unknown): void => {
			clearTimeout(pending);
			const url = sameOriginLink(event as Event);
			if (url === "") { last = null; return; }
			const anchor = eventAnchor(event as Event);
			if (anchor === last) { return; }
			pending = setTimeout((): void => {
				last = anchor;
				if (!preloadDisabled(anchor)) { preload(url); }
			}, 20);
		};
		listenPassive("mousemove", move);
		listenPassive("focusin", preloadEvent);
		listenPassive("touchstart", preloadEvent);
		return (): void => {
			clearTimeout(pending);
			window.removeEventListener("mousemove", move, false);
			window.removeEventListener("focusin", preloadEvent, false);
			window.removeEventListener("touchstart", preloadEvent, false);
		};
	} else {
		throw new Error("routing: preloading links requires the JavaScript browser host");
	}
}

export function followSubmits(submit: (url: string, data: FormData) => boolean): Dispose {
	when (js) {
		const handler = (event: unknown): void => {
			const sent = event as Event;
			const url = submitUrl(sent);
			if (url === "") { return; }
			if (url.startsWith(ACTION_URL) && submitMethod(sent) !== "POST") {
				throw new Error("Only POST forms are supported for Actions");
			}
			const data = new FormData();
			submitEntries(sent, (name: string, value: string): void => data.append(name, value));
			if (submit(url, data)) { sent.preventDefault(); }
		};
		listenDocument("submit", handler);
		return (): void => unlistenDocument("submit", handler);
	} else {
		throw new Error("routing: following form submits requires the JavaScript browser host");
	}
}
