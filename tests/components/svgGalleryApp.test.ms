import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { SvgGallery, arcPath } from "../../examples/components/svgGallery";

function svgs(n: MockNode, out: MockNode[]): MockNode[] {
	if (n.tag === "svg") { out.push(n); }
	for (const c of n.children) { svgs(c, out); }
	return out;
}

function attr(n: MockNode, name: string): string {
	for (const a of n.attrs) {
		if (a.name === name) { return a.value ?? ""; }
	}
	return "";
}

test "the gallery mounts eight Svg views, each with a display list" {
	const root: MockNode = mockNode("root");
	render(element(<SvgGallery />), mockHost(), root as unknown as HostNode);
	const found = svgs(root, []);
	assert found.length === 8, "svg views: " + found.length.toString();
	const labels: string[] = [];
	for (const s of found) {
		labels.push(attr(s, "accessibilityLabel"));
		assert attr(s, "displayList") !== "", "empty list on " + attr(s, "accessibilityLabel");
	}
	assert labels.join(",") === "icon heart,icon star,icon check,icon home,donut chart,progress ring,line chart,logo", labels.join(",");
	const ring = attr(found[5], "displayList");
	assert ring.indexOf("S c 142 36 170 0 E 0 W 12 1 0 4 D 2 314.1593 314.1593 314.1593") > 0, ring;
	assert ring.endsWith("0%25"), ring;
	const logo = attr(found[7], "displayList");
	assert logo.startsWith("V 0 0 200 60 5 0 M 12 0") && logo.endsWith("NEON"), logo;
}

test "a donut slice is an arc with the large flag past half a turn" {
	assert arcPath(0, 0, 10, 0, 90).startsWith("M 10 0 A 10 10 0 0 1 "), arcPath(0, 0, 10, 0, 90);
	assert arcPath(0, 0, 10, 0, 270).indexOf(" 0 1 1 ") > 0;
}
