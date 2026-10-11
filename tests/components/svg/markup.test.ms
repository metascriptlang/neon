import { svgMarkup } from "../../../src/components/svg/markup";

test "paths carry their matrix, paint, rule and stroke geometry" {
	const m = svgMarkup("V 0 0 24 24 5 0 X 2 0 0 2 1 1 M 0 0 L 5 5 Z F c 255 0 0 0.5 S c 0 0 255 1 E 1 W 2 1 2 4 D 2 3 1 0.5 O " +
		"X 1 0 0 1 0 0 M 1 1 L 2 2 F n S n E 0 O", "s1");
	assert m.viewBox === "0 0 24 24" && m.preserveAspectRatio === "xMidYMid meet", m.viewBox + "|" + m.preserveAspectRatio;
	assert m.body === "<path d=\"M 0 0 L 5 5 Z\" transform=\"matrix(2 0 0 2 1 1)\" fill=\"rgb(255,0,0)\" fill-opacity=\"0.5\" fill-rule=\"evenodd\" " +
		"stroke=\"rgb(0,0,255)\" stroke-opacity=\"1\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"bevel\" stroke-miterlimit=\"4\" " +
		"stroke-dasharray=\"3 1\" stroke-dashoffset=\"0.5\"/>" +
		"<path d=\"M 1 1 L 2 2\" fill=\"none\" stroke=\"none\"/>", m.body;
}

test "gradients become user-space gradient elements before their path" {
	const m = svgMarkup("M 0 0 L 1 1 F l 100 0 0 50 10 20 0 0 1 0 2 0 255 0 0 1 1 0 0 255 0.5 S n E 0 O", "s2");
	assert m.body === "<linearGradient id=\"s2-g1\" gradientUnits=\"userSpaceOnUse\" gradientTransform=\"matrix(100 0 0 50 10 20)\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"0\">" +
		"<stop offset=\"0\" stop-color=\"rgb(255,0,0)\" stop-opacity=\"1\"/><stop offset=\"1\" stop-color=\"rgb(0,0,255)\" stop-opacity=\"0.5\"/></linearGradient>" +
		"<path d=\"M 0 0 L 1 1\" fill=\"url(#s2-g1)\" stroke=\"none\"/>", m.body;
	assert m.viewBox === "" && m.preserveAspectRatio === "", "no viewBox";
}

test "clips and layers nest as groups; text runs become tspans" {
	const m = svgMarkup("M 0 0 L 5 0 L 5 5 Z E 0 K G 0.5 T 1 2 1 10 1 20 0 0 14 0 0 0 0 1 a%20%3C%26 0 0 0 0 4 0 14 1 255 0 0 1 b g k", "s3");
	assert m.body === "<clipPath id=\"s3-c1\"><path d=\"M 0 0 L 5 0 L 5 5 Z\"/></clipPath><g clip-path=\"url(#s3-c1)\"><g opacity=\"0.5\">" +
		"<text text-anchor=\"middle\"><tspan x=\"10\" y=\"20\" font-size=\"14\" fill=\"rgb(0,0,0)\" fill-opacity=\"1\">a %3C%26</tspan>" +
		"<tspan dx=\"4\" font-size=\"14\" font-weight=\"bold\" fill=\"rgb(255,0,0)\" fill-opacity=\"1\">b</tspan></text></g></g>", m.body;
}

test "markup escapes text and refuses an unknown op" {
	const m = svgMarkup("T 0 1 1 0 1 0 0 0 12 0 0 0 0 1 <b>&amp;</b>", "s4");
	assert m.body.indexOf("&lt;b&gt;&amp;amp;&lt;/b&gt;") > 0, m.body;
	let message = "";
	try { svgMarkup("Y 1", "s5"); } catch (e) { message = e.message; }
	assert message.indexOf("\"Y\"") > 0, message;
}
