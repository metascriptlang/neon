import { render } from "../../src/render/host";
import { HostNode, NeonNode } from "../../src/render/hostTypes";

when (js) {
	import { domHost } from "../../src/platform/browser/dom";
	import {
		imagesAtStart,
		linesApp,
		marksApp,
		mediaAtStart,
		primitivesApp,
		scrollViewApp,
		servedPart,
		styles,
		svgAtStart,
		switchesApp,
		textareasApp,
	} from "./servedApps";

	extern class MarkupElement {
		innerHTML: string;
		extern appendChild(node: MarkupElement): void;
		extern remove(): void;
	}
	extern class document {
		static body: MarkupElement;
		static extern createElement(tag: cstring): MarkupElement;
	}
	extern function normalized(root: MarkupElement): string from
		"(r => { const f=n=>n.nodeType===1?[n.localName,Array.from(n.attributes,a=>[a.name,a.name==='class'?a.value.split(/\\s+/).sort().join(' '):a.name==='style'?n.style.cssText:a.value]).filter(a=>a[0]!=='checked').concat(n.localName==='input'&&n.type==='checkbox'?[['checked property',String(n.checked)]]:[]).sort((a,b)=>a[0].localeCompare(b[0])),n.localName==='textarea'?[n.value]:Array.from(n.childNodes,f)]:n.nodeType===3?n.data:null;return JSON.stringify(Array.from(r.childNodes,f));})(#)";
	extern function parsedMarkup(html: cstring): MarkupElement from
		"(s => { const r=document.createElement('div');r.innerHTML=s;return r; })(#)";

	test "server primitive classes and attributes match actual DOM host" {
		assert styles.box.cssId !== null && styles.label.cssId !== null;
		const app: NeonNode = primitivesApp();
		const server = servedPart("primitives", "html");
		assert servedPart("primitives", "css").indexOf("white-space:pre-wrap") >= 0;
		const mount = document.createElement("div");
		document.body.appendChild(mount);
		const dispose = render(app, domHost(), mount as unknown as HostNode);
		try {
			assert normalized(parsedMarkup(server)) === normalized(mount),
				server + " vs " + mount.innerHTML;
		} finally { dispose(); mount.remove(); }
	}

	extern function parsedNodes(html: cstring): string from
		"(s => { const r=document.createElement('div');r.innerHTML=s;const f=n=>n.nodeType===1?[n.localName,Array.from(n.childNodes,f).filter(x=>x!==undefined)]:n.nodeType===3?n.data:n.data===''?'':n.data==='!'?undefined:'comment '+n.data;return JSON.stringify(Array.from(r.childNodes,f).filter(x=>x!==undefined));})(#)";
	extern function liveNodes(mount: MarkupElement): string from
		"(r => { const f=n=>n.nodeType===1?[n.localName,Array.from(n.childNodes,f)]:n.nodeType===3?n.data:'comment '+n.data;return JSON.stringify(Array.from(r.childNodes,f));})(#)";

	test "server text marks give a parsed page the node list the DOM host builds" {
		const app: NeonNode = marksApp();
		const server = servedPart("marks", "html");
		assert server.indexOf("<!---->") >= 0 && server.indexOf("<!--!-->") >= 0, server;
		const mount = document.createElement("div");
		document.body.appendChild(mount);
		const dispose = render(app, domHost(), mount as unknown as HostNode);
		try {
			assert parsedNodes(server) === liveNodes(mount), parsedNodes(server) + " vs " + liveNodes(mount);
		} finally { dispose(); mount.remove(); }
	}

	function serverAndDom(name: cstring, app: NeonNode): string[] {
		const server = servedPart(name, "html");
		const mount = document.createElement("div");
		document.body.appendChild(mount);
		const dispose = render(app, domHost(), mount as unknown as HostNode);
		const result = [server, mount.innerHTML, normalized(parsedMarkup(server)), normalized(mount)];
		dispose();
		mount.remove();
		return result;
	}

	test "server ScrollView is the element and classes the DOM host builds" {
		const [server, dom, servedShape, builtShape] = serverAndDom("scrollView", scrollViewApp());
		assert servedShape === builtShape, server + " vs " + dom;
	}

	test "server Text numberOfLines is the classes the DOM host builds" {
		const [server, dom, servedShape, builtShape] = serverAndDom("lines", linesApp());
		assert servedShape === builtShape, server + " vs " + dom;
		assert server.indexOf("numberOfLines") < 0, server;
		const css = servedPart("lines", "css");
		assert css.indexOf(".neon-lines-2{-webkit-line-clamp:2}") >= 0 && css.indexOf(".neon-lines{") >= 0, css;
	}

	test "server Switch and ActivityIndicator are the elements and classes the DOM host builds" {
		const [server, dom, servedShape, builtShape] = serverAndDom("switches", switchesApp());
		assert servedShape === builtShape, server + " vs " + dom;
		assert server.indexOf("<switch") < 0 && server.indexOf("<activityindicator") < 0, server;
		assert server.indexOf("checked") >= 0, "the served switch must show its state before hydrate: " + server;
		assert servedPart("switches", "css").indexOf(".neon-activity{") >= 0, servedPart("switches", "css");
	}

	test "server multiline TextInput is the textarea, class and text the DOM host builds" {
		const [server, dom, servedShape, builtShape] = serverAndDom("textareas", textareasApp());
		assert servedShape === builtShape, server + " vs " + dom;
		assert server.indexOf("<multilinetextinput") < 0 && server.indexOf("defaultValue") < 0, server;
		assert server.indexOf("<textarea") >= 0, server;
		assert servedPart("textareas", "css").indexOf(".neon-textarea{field-sizing:content;resize:none}") >= 0,
			servedPart("textareas", "css");
	}

	test "server Image is the img, classes and rules the DOM host builds" {
		const [server, dom, servedShape, builtShape] = serverAndDom("images", imagesAtStart());
		assert servedShape === builtShape, server + " vs " + dom;
		assert server.indexOf("<image") < 0 && server.indexOf("source=") < 0 && server.indexOf("<img") >= 0, server;
		const css = servedPart("images", "css");
		assert css.indexOf(".neon-image{object-fit:cover}") >= 0 && css.indexOf(".neon-blur-30{filter:blur(3px)}") >= 0 &&
			css.indexOf("background-repeat:repeat") >= 0, css;
	}

	test "server Svg is the svg, its prefix and the markup the DOM host draws from the display list" {
		const [server, dom, servedShape, builtShape] = serverAndDom("svg", svgAtStart());
		assert servedShape === builtShape, server + " vs " + dom;
		assert server.indexOf("displayList") < 0 && server.indexOf("<path") >= 0 && server.indexOf("viewBox=\"0 0 20 10\"") >= 0, server;
		assert server.indexOf("data-neon-svg=\"neon-svg1\"") >= 0 && server.indexOf("data-neon-svg=\"neon-svg2\"") >= 0, server;
	}

	test "server Video, WebView and CameraView are the elements, classes and attributes the DOM host builds" {
		const [server, dom, servedShape, builtShape] = serverAndDom("media", mediaAtStart());
		assert servedShape === builtShape, server + " vs " + dom;
		assert server.indexOf("<webview") < 0 && server.indexOf("<camera") < 0 && server.indexOf("source=") < 0, server;
		assert server.indexOf("<video") >= 0 && server.indexOf("<iframe") >= 0 && server.indexOf("srcdoc=") >= 0 && server.indexOf("sandbox=") >= 0, server;
		assert server.indexOf("neon-camera neon-camera-mirror") >= 0 || server.indexOf("neon-camera-mirror neon-camera") >= 0, server;
		const css = servedPart("media", "css");
		assert css.indexOf(".neon-video{") >= 0 && css.indexOf(".neon-webview{") >= 0 && css.indexOf(".neon-camera{") >= 0, css;
	}
}
