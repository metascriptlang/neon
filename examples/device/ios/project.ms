import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonDevice",
	targets: [Target.iosApp("NeonDevice", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
