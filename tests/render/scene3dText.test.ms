import { element } from "../../src/macros/ui/element";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Text3D } from "../../src/components/scene3d";
import { rgba } from "../../../void/src/void2d/types";

function mountError(body: () => void): string {
	try { body(); } catch (error) { return error.message; }
	return "";
}

test "Text3D refuses a mount outside Scene3D before it allocates a label" {
	const message = mountError((): void => {
		render(element(<Void><Text3D text="lost" /></Void>), mockHost(), mockNode("root") as unknown as HostNode);
	});
	assert message === "Text3D: mount inside Scene3D within Void", message;
}

test "Text3D refuses half an outline before it allocates a label" {
	const message = mountError((): void => {
		render(element(<Void><Scene3D>
			<Text3D text="edge" outlineWidth={1.0} />
		</Scene3D></Void>), mockHost(), mockNode("root") as unknown as HostNode);
	});
	assert message === "Text3D: provide outlineWidth and outlineColor together", message;
	const other = mountError((): void => {
		render(element(<Void><Scene3D>
			<Text3D text="edge" outlineColor={rgba(0.0, 0.0, 0.0, 1.0)} />
		</Scene3D></Void>), mockHost(), mockNode("root") as unknown as HostNode);
	});
	assert other === "Text3D: provide outlineWidth and outlineColor together", other;
}
