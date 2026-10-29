import { createRoot } from "../../src/core/owner";
import { resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { HostNode, NeonNode, mockNode, mockHost } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, RenderTexture } from "../../src/components/scene3d";

// A texture target needs the GPU, so what disposal releases when a Mesh still shows the material
// is checked on the device: tests/device/renderTexture.ms.
function refusal(app: () => NeonNode): string {
	let message = "";
	createRoot((dispose: () => void): void => {
		try {
			app()(mockHost(), mockNode("root") as unknown as HostNode, null);
		} catch (error) { message = error.toString(); } finally { dispose(); resetErrorHalt(); }
	});
	return message;
}

test "RenderTexture refuses a size that is not positive before it allocates a target" {
	const wide = refusal((): NeonNode => element(<Void><Scene3D><RenderTexture width={0} height={64} /></Scene3D></Void>));
	assert wide.includes("RenderTexture: width and height must be positive"), "names the rule: " + wide;
	const tall = refusal((): NeonNode => element(<Void><Scene3D><RenderTexture width={64} height={-1} /></Scene3D></Void>));
	assert tall.includes("RenderTexture: width and height must be positive"), "names the rule: " + tall;
}

test "RenderTexture refuses a mount outside Scene3D" {
	const outside = refusal((): NeonNode => element(<Void><RenderTexture width={64} height={64} /></Void>));
	assert outside.includes("RenderTexture: mount inside Scene3D within Void"), "names the rule: " + outside;
}
