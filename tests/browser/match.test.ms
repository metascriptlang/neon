import { render } from "../../src/render/host";
import { HostNode, NeonNode } from "../../src/render/hostTypes";
import { createSignal, Accessor } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";

when (js) {
	import { domHost } from "../../src/platform/browser/dom";

	extern class Mount {
		extern remove(): void;
	}
	extern function matchPage(unused: int32): Mount from "(#, (() => { const r = document.createElement('div'); document.body.appendChild(r); return r; })())";
	extern function htmlOf(m: Mount): string from "#.innerHTML";
	extern class Elem {
		textContent: string;
	}
	extern function firstOf(m: Mount): Elem from "#.firstElementChild";

	class User {
		name: string;
		constructor(name: string) { this.name = name; }
	}

	test "a browser shows the first matching case, keeps its element while it stays selected, and swaps it when the index changes" {
		const mount = matchPage(0);
		const [n, setN] = createSignal(2);
		const dispose = render(<Match fallback={<i>none</i>}>
			<Case when={n() === 1}><b>one</b></Case>
			<Case when={n() >= 2}><span>{n().toString()}</span></Case>
			<Case when={n() >= 2}><u>never</u></Case>
		</Match>, domHost(), mount as unknown as HostNode);
		try {
			assert htmlOf(mount).indexOf("<span>2</span>") >= 0 && htmlOf(mount).indexOf("never") < 0, htmlOf(mount);
			const span = firstOf(mount);
			setN(3);
			flush();
			assert htmlOf(mount).indexOf("<span>3</span>") >= 0 && firstOf(mount) === span, "the same element: " + htmlOf(mount);
			setN(1);
			flush();
			assert htmlOf(mount).indexOf("<b>one</b>") >= 0 && htmlOf(mount).indexOf("span") < 0, htmlOf(mount);
			setN(0);
			flush();
			assert htmlOf(mount).indexOf("<i>none</i>") >= 0, htmlOf(mount);
		} finally { dispose(); mount.remove(); }
	}

	test "a browser mounts a keyed case again for each new value and follows a plain callback in place" {
		const mount = matchPage(0);
		const [user, setUser] = createSignal<User | null>(null);
		const dispose = render(<div>
			<Match><Case when={user()} keyed>{(u: User): NeonNode => <s>{u.name}</s>}</Case></Match>
			<Match><Case when={user()}>{(u: Accessor<User>): NeonNode => <em>{u().name}</em>}</Case></Match>
		</div>, domHost(), mount as unknown as HostNode);
		try {
			setUser(new User("ann"));
			flush();
			assert htmlOf(mount).indexOf("<s>ann</s>") >= 0 && htmlOf(mount).indexOf("<em>ann</em>") >= 0, htmlOf(mount);
			setUser(new User("bob"));
			flush();
			assert htmlOf(mount).indexOf("<s>bob</s>") >= 0 && htmlOf(mount).indexOf("<em>bob</em>") >= 0, htmlOf(mount);
			setUser(null);
			flush();
			assert htmlOf(mount).indexOf("<s>") < 0 && htmlOf(mount).indexOf("<em>") < 0, htmlOf(mount);
		} finally { dispose(); mount.remove(); }
	}
}
