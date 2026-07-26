import { group, label, addChild, Node2D } from "../../void/src/void2d/node";
import { layoutPass } from "../../void/src/void2d/layout";
function main(): void {
	const root = group();
	root.layoutStyle = { flexDirection: "column", width: 100.0, height: 50.0 };
	const a = label("hi", 16.0, { r: 1.0, g: 1.0, b: 1.0, a: 1.0 });
	a.layoutStyle = { flexGrow: 1.0 };
	root.addChild(a);
	layoutPass(root, 100.0, 50.0);
	console.log("probe w=" + a.w.toString() + " h=" + a.h.toString());
}
main();

