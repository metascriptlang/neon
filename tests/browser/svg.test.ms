import { domHost } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { createSignal } from "../../src/core/signal";
import {
	Svg,
	G,
	Path,
	Rect,
	Circle,
	Text as SvgText,
	Defs,
	LinearGradient,
	Stop,
	ClipPath,
} from "../../src/components/svg/elements";
import { SvgXml } from "../../src/components/svg/xml";

extern class HTMLElement {
	extern appendChild(child: HTMLElement): void;
	extern setAttribute(name: cstring, value: cstring): void;
}

extern class window {
	static extern eval(code: cstring): string;
}

extern class document {
	static body: HTMLElement;
	static extern createElement(tag: cstring): HTMLElement;
}

function mountPoint(id: string): HostNode {
	const mount = document.createElement("div");
	mount.setAttribute("id", id);
	mount.setAttribute("style", "position:absolute;left:0;top:0");
	document.body.appendChild(mount);
	return mount as unknown as HostNode;
}

function js(code: string): string {
	return window.eval(`String((() => { ${code} })())`);
}

test "an Svg is a real <svg> element whose shapes have the encoded geometry" {
	const [r, setR] = createSignal<float64>(40);
	render(element(<Svg width={100} height={100} accessibilityLabel="ring">
		<Circle cx={50} cy={50} r={r()} fill="#ff0000" />
	</Svg>), domHost(), mountPoint("svg-a"));
	const shape = js("const s = document.querySelector('#svg-a svg'); return s.namespaceURI + ' ' + s.getAttribute('aria-label') + ' ' + s.getBoundingClientRect().width;");
	assert shape === "http://www.w3.org/2000/svg ring 100", shape;
	const box = js("const b = document.querySelector('#svg-a path').getBBox(); return [b.x, b.y, b.width, b.height].map(Math.round).join(',');");
	assert box === "10,10,80,80", "bbox: " + box;
	const hits = js("const p = document.querySelector('#svg-a path'); return [document.elementFromPoint(50, 50) === p, document.elementFromPoint(12, 12) === p].join(',');");
	assert hits === "true,false", "hit test: " + hits;
	setR(20);
	const smaller = js("const b = document.querySelector('#svg-a path').getBBox(); return Math.round(b.width);");
	assert smaller === "40", "reactive radius: " + smaller;
}

test "viewBox scales, a gradient fills, a clip cuts and text is drawn" {
	render(element(<Svg width={200} height={100} viewBox="0 0 20 10">
		<Defs>
			<LinearGradient id="fade" x1="0" y1="0" x2="1" y2="0">
				<Stop offset={0} stopColor="#00ff00" />
				<Stop offset={1} stopColor="#0000ff" />
			</LinearGradient>
			<ClipPath id="left"><Rect width={10} height={10} /></ClipPath>
		</Defs>
		<Rect width={20} height={10} fill="url(#fade)" clipPath="url(#left)" />
		<G transform="translate(12, 8)"><SvgText fontSize={4} fill="black">Hi</SvgText></G>
	</Svg>), domHost(), mountPoint("svg-b"));
	const view = js("return document.querySelector('#svg-b svg').getAttribute('viewBox');");
	assert view === "0 0 20 10", view;
	const fill = js("const p = document.querySelector('#svg-b g[clip-path] path'); return p.getAttribute('fill').startsWith('url(#') && document.querySelector('#svg-b linearGradient stop').getAttribute('stop-color');");
	assert fill === "rgb(0,255,0)", "gradient: " + fill;
	const clip = js("const p = document.querySelector('#svg-b g[clip-path] path'); return [document.elementFromPoint(50, 50) === p, document.elementFromPoint(150, 50) === p].join(',');");
	assert clip === "true,false", "clip: " + clip;
	const text = js("const t = document.querySelector('#svg-b text'); const b = t.getBoundingClientRect(); return t.textContent + ' ' + (b.left > 115 && b.left < 125);");
	assert text === "Hi true", "text: " + text;
}

test "SvgXml draws a parsed SVG document" {
	render(element(<SvgXml width={64} height={64} xml={"<svg viewBox=\"0 0 32 32\"><path d=\"M4 4h24v24H4z\" fill=\"#336699\" stroke-width=\"2\"/></svg>"} />), domHost(), mountPoint("svg-c"));
	const box = js("const p = document.querySelector('#svg-c path'); const b = p.getBoundingClientRect(); return p.getAttribute('fill') + ' ' + Math.round(b.width);");
	assert box === "rgb(51,102,153) 48", "xml: " + box;
}
