import { render, hydrate } from "../../src/render/host";
import { Host, HostNode, NeonNode } from "../../src/render/hostTypes";
import { NeonEvent } from "../../src/render/event";
import { View } from "../../src/components/primitives";
import { createSignal, Accessor } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";

when (js) {
	import { domHost } from "../../src/platform/browser/dom";
	import {
		clampedApp,
		docs,
		plainTextareaApp,
		scrollApp,
		servedPart,
		switchApp,
		textareaApp,
	} from "./servedApps";

	extern class Page {
		textContent: string;
		extern remove(): void;
		extern click(): void;
	}
	extern function parsedPage(html: cstring): Page from
		"(s => { const r=document.createElement('div');r.innerHTML=s;document.body.appendChild(r);r.querySelectorAll('*').forEach(n=>{n.neonServed=true;});return r; })(#)";
	extern function emptyPage(tag: cstring): Page from "(t => { const r=document.createElement(t);document.body.appendChild(r);return r; })(#)";
	extern function pageNode(root: Page, selector: cstring): Page from "(#).querySelector(#)";
	extern function addForeignChild(node: Page): void from "(n => { const f=document.createElement('i');f.id='foreign';n.appendChild(f); })(#)";
	extern function notServed(root: Page): number from
		"(r => Array.from(r.querySelectorAll('*')).filter(n=>n.neonServed!==true&&n.id!=='foreign').length)(#)";
	extern function fireScroll(node: Page): void from "(n => n.dispatchEvent(new Event('scroll')))(#)";
	extern function isChecked(node: Page): boolean from "(#).checked";
	extern function toggle(node: Page): void from "(n => { n.checked = !n.checked; n.dispatchEvent(new Event('change')); })(#)";
	extern function fieldValue(node: Page): string from "(#).value";
	extern function typeInto(node: Page, text: cstring): void from
		"((n, t) => { n.value = t; n.dispatchEvent(new Event('input')); })(#, #)";
	extern function shape(root: Page): string from
		"(r => { const f=n=>n.nodeType===1?[n.localName,Array.from(n.attributes,a=>[a.name,a.name==='class'?a.value.split(/\\s+/).sort().join(' '):a.value]).sort((a,b)=>a[0].localeCompare(b[0])),n.id==='mech'?[]:Array.from(n.childNodes,f)]:n.nodeType===3?n.data:'comment '+n.data;return JSON.stringify(Array.from(r.childNodes,f)); })(#)";

	function freshShape(name: string, open: boolean, rows: string[]): string {
		const [n, _n] = createSignal(name);
		const [b, _b] = createSignal("");
		const [o, _o] = createSignal(open);
		const [r, _r] = createSignal<string[]>(rows);
		const mount = emptyPage("div");
		const dispose = render(docs(n, b, o, r, (e: NeonEvent): void => {}, (node: HostNode): void => {}), domHost(), mount as unknown as HostNode);
		const s = shape(mount);
		dispose();
		mount.remove();
		return s;
	}

	test "hydrate attaches a tree to a parsed page without creating an element" {
		const sent = servedPart("docs", "html");
		assert sent.indexOf("<!---->") >= 0 && sent.indexOf("<!--!-->") >= 0, sent;

		const mount = parsedPage(sent);
		addForeignChild(pageNode(mount, "#mech"));
		const [name, setName] = createSignal("Ann");
		const [blank, setBlank] = createSignal("");
		const [open, setOpen] = createSignal(true);
		const [rows, setRows] = createSignal<string[]>(["a", "b", "c"]);
		let pressed = 0;
		let mech: HostNode | null = null;
		let made = 0;
		const host: Host = domHost();
		const create = host.createElement;
		host.createElement = (tag: string): HostNode => { made += 1; return create(tag); };

		const dispose = hydrate(
			docs(name, blank, open, rows, (e: NeonEvent): void => { pressed += 1; }, (node: HostNode): void => { mech = node; }),
			host, mount as unknown as HostNode);
		try {
			assert made === 0, "the host created " + made.toString() + " elements";
			assert notServed(mount) === 0, notServed(mount).toString() + " elements are not the page's own";
			assert shape(mount) === freshShape("Ann", true, ["a", "b", "c"]), shape(mount);
			assert mech === (pageNode(mount, "#mech") as unknown as HostNode), "the ref received the page's canvas";
			assert pageNode(mount, "#mech #foreign") !== null, "the canvas lost the child it was given";

			pageNode(mount, "[aria-label=Copy]").click();
			assert pressed === 1, "pressed " + pressed.toString();

			setName("Bob");
			flush();
			setBlank("now");
			flush();
			setOpen(false);
			flush();
			setRows(["c", "a"]);
			flush();
			assert notServed(mount) === 0, "an update replaced a served element";
			const [n2, _n2] = createSignal("Bob");
			assert pageNode(mount, "span").textContent === "Hi Bob", pageNode(mount, "span").textContent;
			setBlank("");
			flush();
			assert shape(mount) === freshShape("Bob", false, ["c", "a"]), shape(mount);

			setOpen(true);
			flush();
			setRows(["a", "d", "c"]);
			flush();
			assert shape(mount) === freshShape("Bob", true, ["a", "d", "c"]), shape(mount);
			assert made === 4, "one new row, the reopened branch and the detached holder each of the two regions builds its later rows in are the only elements created: " + made.toString();
		} finally { dispose(); mount.remove(); }
	}

	test "hydrate on a page from another tree fails before the page is shown wrong" {
		const mount = parsedPage("<div class=\"neon-view\"><p>b</p></div>");
		let said = "";
		try {
			hydrate(<View><h1>b</h1></View>, domHost(), mount as unknown as HostNode);
		} catch (e) { said = e.toString(); }
		mount.remove();
		assert said.indexOf("<h1>") >= 0 && said.indexOf("child 1 of view") >= 0, said;
	}

	function rendered(app: NeonNode): string {
		const mount = emptyPage("div");
		const dispose = render(app, domHost(), mount as unknown as HostNode);
		const result = shape(mount);
		dispose();
		mount.remove();
		return result;
	}

	test "hydrate takes over a served ScrollView and leaves it scrollable" {
		let scrolls = 0;
		const app: NeonNode = scrollApp((e: NeonEvent): void => { scrolls += 1; });
		const mount = parsedPage(servedPart("scroll", "html"));
		let made = 0;
		const host: Host = domHost();
		const create = host.createElement;
		host.createElement = (tag: string): HostNode => { made += 1; return create(tag); };
		const dispose = hydrate(app, host, mount as unknown as HostNode);
		try {
			assert made === 0, "the host created " + made.toString() + " elements";
			assert notServed(mount) === 0, notServed(mount).toString() + " elements are not the page's own";
			fireScroll(pageNode(mount, ".neon-scrollview"));
			assert scrolls === 1, "onScroll ran " + scrolls.toString() + " times";
			assert shape(mount) === rendered(app), shape(mount);
		} finally { dispose(); mount.remove(); }
	}

	test "hydrate takes over a clamped Text without an attribute left behind" {
		const app: NeonNode = clampedApp();
		const mount = parsedPage(servedPart("clamped", "html"));
		const dispose = hydrate(app, domHost(), mount as unknown as HostNode);
		try {
			assert notServed(mount) === 0, notServed(mount).toString() + " elements are not the page's own";
			assert shape(mount) === rendered(app), shape(mount) + " vs " + rendered(app);
		} finally { dispose(); mount.remove(); }
	}

	test "hydrate takes over a served Switch and ActivityIndicator" {
		const [on, setOn] = createSignal(true);
		let changes = "";
		const app: NeonNode = switchApp(on, (v: boolean): void => { changes = changes + v.toString(); });
		const mount = parsedPage(servedPart("switch", "html"));
		let made = 0;
		const host: Host = domHost();
		const create = host.createElement;
		host.createElement = (tag: string): HostNode => { made += 1; return create(tag); };
		const dispose = hydrate(app, host, mount as unknown as HostNode);
		try {
			assert made === 0, "the host created " + made.toString() + " elements";
			assert notServed(mount) === 0, notServed(mount).toString() + " elements are not the page's own";
			assert shape(mount) === rendered(app), shape(mount) + " vs " + rendered(app);
			assert isChecked(pageNode(mount, "input")), "the served switch lost its state";
			toggle(pageNode(mount, "input"));
			assert changes === "false", "onValueChange saw '" + changes + "'";
			setOn(false);
			flush();
			assert isChecked(pageNode(mount, "input")) === false, "the switch did not follow its signal";
		} finally { dispose(); mount.remove(); }
	}

	test "hydrate takes over a served multiline TextInput and keeps what was typed before it" {
		let heard = "";
		const app: NeonNode = textareaApp((t: string): void => { heard = t; });
		const mount = parsedPage(servedPart("textarea", "html"));
		const field = pageNode(mount, "textarea");
		assert fieldValue(field) === "note", "the served textarea shows its default: " + fieldValue(field);
		typeInto(field, "typed early");
		let made = 0;
		const host: Host = domHost();
		const create = host.createElement;
		host.createElement = (tag: string): HostNode => { made += 1; return create(tag); };
		const dispose = hydrate(app, host, mount as unknown as HostNode);
		try {
			assert made === 0, "the host created " + made.toString() + " elements";
			assert notServed(mount) === 0, notServed(mount).toString() + " elements are not the page's own";
			assert fieldValue(field) === "typed early", "hydrate replaced the typed text: " + fieldValue(field);
			typeInto(field, "after");
			assert heard === "after", "onChangeText heard '" + heard + "'";
		} finally { dispose(); mount.remove(); }
	}

	test "hydrate leaves a served multiline TextInput shaped like a fresh render" {
		const app: NeonNode = plainTextareaApp();
		const mount = parsedPage(servedPart("plainTextarea", "html"));
		const dispose = hydrate(app, domHost(), mount as unknown as HostNode);
		try {
			assert shape(mount) === rendered(app), shape(mount) + " vs " + rendered(app);
			assert fieldValue(pageNode(mount, "textarea")) === "note", "the default is lost";
		} finally { dispose(); mount.remove(); }
	}
}
