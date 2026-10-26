import { Cleanup, Dispose } from "../../core/types";
import { createEffect } from "../../core/effect";
import { createRoot } from "../../core/owner";
import { Router } from "../../navigation/router";

when (js) {
	extern function pageTitle(): string from
		"(() => document.title || (document.querySelector('h1')?.innerText || document.querySelector('h1')?.textContent || ''))()";
	extern function announceText(message: string): void from
		"(m => { let a = document.getElementById('__neon-route-announcer__'); if (!a) { a = document.createElement('div'); a.id = '__neon-route-announcer__'; a.setAttribute('aria-live', 'assertive'); a.setAttribute('role', 'alert'); a.style.cssText = 'position:absolute;border:0;height:1px;margin:-1px;padding:0;width:1px;clip:rect(0 0 0 0);overflow:hidden;white-space:nowrap;word-wrap:normal'; document.body.appendChild(a); } a.textContent = m; })(#)";
	extern function removeAnnouncer(): void from
		"document.getElementById('__neon-route-announcer__')?.remove()";
}

export function followAnnouncements(router: Router): Dispose {
	when (js) {
		let previous: string | null = null;
		announceText("");
		const stop = createRoot((dispose: Dispose): Dispose => {
			createEffect<string>(
				(): string => router.location().pathname,
				(path: string, before: string | null): Cleanup | null => {
					setTimeout((): void => {
						const title = pageTitle();
						if (previous !== null && previous !== title) { announceText(title); }
						previous = title;
					}, 0);
					return null;
				},
			);
			return dispose;
		});
		return (): void => {
			stop();
			removeAnnouncer();
		};
	} else {
		throw new Error("routing: announcing navigation requires the JavaScript browser host");
	}
}
