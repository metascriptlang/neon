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
	extern function offsetAt(offsets: Offsets, index: int32): number from
		"((o, i) => typeof o[i] === 'number' ? o[i] : -1)(#, #)";
	extern function reachable(y: number): boolean from
		"(y => document.documentElement.scrollHeight - window.innerHeight >= y)(#)";
	extern function scrollToOffset(y: number): void from "window.scrollTo(0, #)";
	extern function scrollToEntryHash(): void from
		"(() => { const el = location.hash && document.getElementById(decodeURIComponent(location.hash.slice(1))); if (el) el.scrollIntoView(); else window.scrollTo(0, 0); })()";
	extern class Growth {}
	extern function watchGrowth(changed: () => void): Growth from
		"(f => { const o = new ResizeObserver(f); o.observe(document.documentElement); return o; })(#)";
	extern function stopGrowth(growth: Growth): void from "#.disconnect()";
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
		let watching: Growth | null = null;
		const release = (): void => {
			const growth = watching;
			if (growth !== null) {
				watching = null;
				stopGrowth(growth as Growth);
			}
		};
		const restore = (index: int32): void => {
			release();
			const y = offsetAt(offsets, index);
			if (y < 0) { scrollToEntryHash(); return; }
			if (reachable(y)) { scrollToOffset(y); return; }
			watching = watchGrowth((): void => {
				if (!reachable(y)) { return; }
				release();
				scrollToOffset(y);
			});
		};
		const scroller: Scroller = {
			arrived: (address: string, replace: boolean, scroll: boolean): void => {
				release();
				const index = entries.index();
				forgetOffsets(offsets, index, replace ? index : 1000000000);
				const at = address.indexOf("#");
				scrollToHash(at < 0 ? "" : address.substring(at + 1), scroll);
			},
		};
		router.scrollWith(scroller);
		const recorded = (event: unknown): void => {
			if (watching === null) { recordOffset(offsets, entries.index()); }
		};
		const popped = (event: unknown): void => restore(entries.index());
		const leaving = (event: unknown): void => saveOffsets(offsets);
		const took = (event: unknown): void => release();
		window.addEventListener("scroll", recorded, false);
		window.addEventListener("popstate", popped, false);
		window.addEventListener("pagehide", leaving, false);
		window.addEventListener("wheel", took, false);
		window.addEventListener("touchstart", took, false);
		window.addEventListener("keydown", took, false);
		if ((opened === "" ? navigationType() : opened) !== "navigate") { restore(entries.index()); }
		return (): void => {
			release();
			window.removeEventListener("scroll", recorded, false);
			window.removeEventListener("popstate", popped, false);
			window.removeEventListener("pagehide", leaving, false);
			window.removeEventListener("wheel", took, false);
			window.removeEventListener("touchstart", took, false);
			window.removeEventListener("keydown", took, false);
			router.scrollWith(null);
			takeScrollRestoration(was);
		};
	} else {
		throw new Error("routing: following scroll requires the JavaScript browser host");
	}
}
