import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { mockHost, mockNode, render, HostNode } from "../../src/render/host";
import { Style, mergeStyle } from "../../src/render/style";
import { styleOf } from "../../src/macros/ui/style";

const handMade: Style = styleOf({ width: 1, media: [{ fromWidth: 10, width: 2 }] });

function failure(run: () => void): string {
	try {
		run();
	} catch (e) {
		return (e as Error).message;
	}
	return "";
}

test "media blocks without a breakpoint table fail loud when mounted" {
	const message = failure((): void => {
		render(element(<div style={handMade}></div>), mockHost(), mockNode("root") as unknown as HostNode);
	});
	assert message.indexOf("no breakpoint table was loaded") >= 0, "got '" + message + "'";
}

test "media blocks without a breakpoint table fail loud when layered" {
	const message = failure((): void => { mergeStyle(handMade, styleOf({ height: 3 })); });
	assert message.indexOf("no breakpoint table was loaded") >= 0, "got '" + message + "'";
}
