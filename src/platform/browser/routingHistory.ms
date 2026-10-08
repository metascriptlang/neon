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
