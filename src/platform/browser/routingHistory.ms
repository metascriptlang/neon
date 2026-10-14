import { Dispose } from "../../core/types";
import { RoutingHistory, RoutingHistoryEntry } from "../../navigation/routingHistory";

when (js) {
	interface BrowserRoutingState {
		__neonRouting: string;
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

	extern function readHistoryString(key: cstring): string from
		"(k => typeof history.state?.[k] === 'string' ? history.state[k] : '')(#)";

	extern class Event {
		extern preventDefault(): void;
	}

	extern function sameOriginLink(event: Event): string from
		"(e => { if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.altKey || e.ctrlKey || e.shiftKey) return ''; const a = e.composedPath().find(n => n instanceof Node && n.nodeName.toUpperCase() === 'A'); if (!a || a.target || !a.href || a.hasAttribute('download') || (a.getAttribute('rel') || '').split(/\\s+/).includes('external')) return ''; const u = new URL(a.href, document.baseURI); return u.origin === location.origin ? u.pathname + u.search + u.hash : ''; })(#)";
	extern function scrollToFragmentOrTop(url: string): void from
		"(u => { const at = u.indexOf('\\x23'); const el = at < 0 ? null : document.getElementById(decodeURIComponent(u.slice(at + 1))); if (el) el.scrollIntoView(); else window.scrollTo(0, 0); })(#)";

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
			push: (entry: RoutingHistoryEntry): void => {
				window.history.pushState({ __neonRouting: entry.state }, "", entry.url);
			},
			replace: (entry: RoutingHistoryEntry): void => {
				window.history.replaceState({ __neonRouting: entry.state }, "", entry.url);
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
