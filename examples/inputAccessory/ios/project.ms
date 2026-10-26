import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonInputAccessory",
	targets: [Target.iosApp("NeonInputAccessory", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
