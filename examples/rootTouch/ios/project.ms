import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonRootTouch",
	targets: [Target.iosApp("NeonRootTouch", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
