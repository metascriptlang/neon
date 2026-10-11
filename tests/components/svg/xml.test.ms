import { createSignal } from "../../../src/core/signal";
import { element } from "../../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../../src/render/host";
import { Style } from "../../../src/render/style";
import { SvgXml, parseSvgXml, camelName, decodeEntities } from "../../../src/components/svg/xml";
import { attrOf } from "../../../src/components/svg/scene";

function listOf(root: MockNode): string {
	for (const a of root.children[0].attrs) {
		if (a.name === "displayList") { return a.value ?? ""; }
	}
	return "<none>";
}

const LOGO = "<?xml version=\"1.0\"?>\n<!-- logo -->\n<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" viewBox=\"0 0 10 10\" width=\"20\">" +
	"<defs><linearGradient id='g' x2='1'><stop offset='0' stop-color='#f00'/><stop offset='1' style='stop-color: #00f; stop-opacity: .5'/></linearGradient></defs>" +
	"<title>ignored</title><g fill-rule=\"evenodd\" stroke-width=\"2\"><rect width=\"10\" height=\"10\" fill=\"url(#g)\"/>" +
	"<path d=\"M0 0h5v5z\" style=\"fill:none;stroke:black\"/><use xlink:href=\"#dot\" x=\"1\"/></g>" +
	"<circle id=\"dot\" r=\"1\" fill=\"red\"/><text x=\"1\" y=\"9\" font-size=\"3\">A &amp; B</text></svg>";

test "kebab-case attributes become props, entities decode" {
	assert camelName("stroke-width") === "strokeWidth" && camelName("xlink:href") === "href" && camelName("fill") === "fill";
	assert decodeEntities("a &lt;&gt;&amp;&quot;&#65;&#x42; &unknown;") === "a <>&\"AB &unknown;", decodeEntities("a &lt;&gt;&amp;&quot;&#65;&#x42; &unknown;");
	const root = parseSvgXml(LOGO);
	assert root.tag === "svg" && attrOf(root, "viewBox") === "0 0 10 10", "root";
	const g = root.children[1];
	assert g.tag === "g" && attrOf(g, "fillRule") === "evenodd" && attrOf(g.children[1], "stroke") === "black" && attrOf(g.children[1], "fill") === "none", "g";
	assert attrOf(g.children[2], "href") === "#dot", "use";
	assert attrOf(root.children[0].children[0].children[1], "stopOpacity") === ".5", "style attr";
}

test "SvgXml draws the document through the same display list" {
	const [xml, setXml] = createSignal(LOGO);
	const root: MockNode = mockNode("root");
	render(element(<SvgXml xml={xml()} width={40} height={40} />), mockHost(), root as unknown as HostNode);
	const style = root.children[0].style as Style;
	assert style.width === 40, "sized by the props";
	const list = listOf(root);
	assert list.startsWith("V 0 0 10 10 5 0 M 0 0 L 10 0 L 10 10 L 0 10 Z F l 10 0 0 10 0 0 0 0 1 0 2 0 255 0 0 1 1 0 0 255 0.5 S n E 1 O"), list;
	assert list.indexOf("M 0 0 L 5 0 L 5 5 Z F n S c 0 0 0 1 E 1 W 2 0 0 4 D 0 0 O") > 0, list;
	assert list.indexOf("X 1 0 0 1 1 0 M 1 0 C") > 0, list;
	assert list.endsWith("T 0 1 1 1 1 9 0 0 3 0 0 0 0 1 A%20&%20B"), list;
	setXml("<svg viewBox='0 0 4 4'><rect width='4' height='4'/></svg>");
	assert listOf(root) === "V 0 0 4 4 5 0 M 0 0 L 4 0 L 4 4 L 0 4 Z F c 0 0 0 1 S n E 0 O", listOf(root);
	setXml("<svg><defs><symbol id='s'><rect width='2' height='2'/></symbol></defs><use xlink:href='#s' x='3'/></svg>");
	assert listOf(root) === "X 1 0 0 1 3 0 M 0 0 L 2 0 L 2 2 L 0 2 Z F c 0 0 0 1 S n E 0 O", listOf(root);
}

test "malformed XML is an error that says where" {
	let message = "";
	try { parseSvgXml("<svg><rect width='1'></svg>"); } catch (e) { message = e.message; }
	assert message.indexOf("</svg> closes <rect>") >= 0, message;
	message = "";
	try { parseSvgXml("<div/>"); } catch (e) { message = e.message; }
	assert message.indexOf("no <svg>") >= 0, message;
}
