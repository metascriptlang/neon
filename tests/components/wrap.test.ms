import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { Style } from "../../src/render/style";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import { Wrap, wrapStyle } from "../../src/components/wrap";

function mount(app: () => NeonNode): MockNode {
	const root = mockNode("root");
	render(app(), mockHost(), root as unknown as HostNode);
	return root;
}

test "a horizontal Wrap puts spacing between children and runSpacing between runs" {
	const s = wrapStyle("horizontal", "spaceBetween", "center", "end", 8, 4);
	assert s.flexDirection === "row" && s.flexWrap === "wrap" && s.justifyContent === "space-between";
	assert s.alignContent === "center" && s.alignItems === "flex-end" && s.columnGap === 8 && s.rowGap === 4;
	const v = wrapStyle("vertical", "start", "start", "start", 8, 4);
	assert v.flexDirection === "column" && v.rowGap === 8 && v.columnGap === 4, "a vertical Wrap swaps the gaps";
}

test "the Wrap component carries Flutter's defaults and the author's style" {
	const root = mount((): NeonNode => element(<Wrap spacing={6} runSpacing={10} style={{ padding: 4 }}>
		<Text>one</Text><Text>two</Text>
	</Wrap>));
	const s = root.children[0].style as Style;
	assert s.justifyContent === "flex-start" && s.alignItems === "flex-start" && s.alignContent === "flex-start";
	assert s.columnGap === 6 && s.rowGap === 10 && s.padding === 4;
}

test "a spaced run alignment is refused by name" {
	let message = "";
	try {
		wrapStyle("horizontal", "start", "spaceAround", "start", 0, 0);
	} catch (e) {
		message = e.toString();
	}
	assert message.indexOf("spaceAround") >= 0, "refused: " + message;
}
