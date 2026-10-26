import { Dispose } from "../../core/types";
import { Router } from "../../navigation/router";
import { Scroller } from "../../navigation/scroll";
import { createBrowserRoutingHistory } from "./routingHistory";

when (js) {
	extern class Offsets {}

	extern class window {
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

	extern function loadOffsets(): Offsets from
		"(() => { try { return JSON.parse(sessionStorage.getItem('neon:scroll') || '{}'); } catch { return {}; } })()";
	extern function saveOffsets(offsets: Offsets): void from
		"(o => { try { sessionStorage.setItem('neon:scroll', JSON.stringify(o)); } catch {} })(#)";
	extern function recordOffset(offsets: Offsets, index: int32): void from
		"((o, i) => { o[i] = window.scrollY; })(#, #)";
	extern function forgetOffsets(offsets: Offsets, from: int32, to: int32): void from
		"((o, a, b) => { for (const k in o) if (+k >= a && +k <= b) delete o[k]; })(#, #, #)";
	extern function restoreOffset(offsets: Offsets, index: int32): void from
		"((o, i) => { if (typeof o[i] === 'number') window.scrollTo(0, o[i]); else { const el = location.hash && document.getElementById(decodeURIComponent(location.hash.slice(1))); if (el) el.scrollIntoView(); else window.scrollTo(0, 0); } })(#, #)";
	extern function scrollToHash(hash: string, fallbackTop: boolean): void from
		"((h, top) => { const el = h && document.getElementById(decodeURIComponent(h)); if (el) el.scrollIntoView(); else if (top) window.scrollTo(0, 0); })(#, #)";
	extern function takeScrollRestoration(mode: string): string from
		"(m => { const was = history.scrollRestoration; history.scrollRestoration = m; return was; })(#)";
	extern function navigationType(): string from
		"(() => { const [n] = performance.getEntriesByType('navigation'); return n ? n.type : 'navigate'; })()";
}

export function followScroll(router: Router, opened: string = ""): Dispose {
	when (js) {
		const entries = createBrowserRoutingHistory();
		const offsets = loadOffsets();
		const was = takeScrollRestoration("manual");
		const scroller: Scroller = {
			arrived: (address: string, replace: boolean, scroll: boolean): void => {
				const index = entries.index();
				forgetOffsets(offsets, index, replace ? index : 1000000000);
				const at = address.indexOf("#");
				scrollToHash(at < 0 ? "" : address.substring(at + 1), scroll);
			},
		};
		router.scrollWith(scroller);
		const recorded = (event: unknown): void => recordOffset(offsets, entries.index());
		const popped = (event: unknown): void => restoreOffset(offsets, entries.index());
		const leaving = (event: unknown): void => saveOffsets(offsets);
		window.addEventListener("scroll", recorded, false);
		window.addEventListener("popstate", popped, false);
		window.addEventListener("pagehide", leaving, false);
		if ((opened === "" ? navigationType() : opened) !== "navigate") { restoreOffset(offsets, entries.index()); }
		return (): void => {
			window.removeEventListener("scroll", recorded, false);
			window.removeEventListener("popstate", popped, false);
			window.removeEventListener("pagehide", leaving, false);
			router.scrollWith(null);
			takeScrollRestoration(was);
		};
	} else {
		throw new Error("routing: following scroll requires the JavaScript browser host");
	}
}
