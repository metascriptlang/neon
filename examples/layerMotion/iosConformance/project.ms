import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonLayerConformance",
	targets: [Target.iosApp("NeonLayerConformance", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
