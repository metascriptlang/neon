import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonMotion",
	targets: [Target.iosApp("NeonMotion", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
