import { regionNode, renderToString } from "../src/render/node";

test "region throws only" {
	let threw = false;
	const r = regionNode((h) => () => [] as unknown[]);
	try {
		renderToString(r);
	} catch (e) {
		threw = true;
	}
	assert threw, "region must throw";
}
