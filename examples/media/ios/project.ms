import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonMedia",
	targets: [Target.iosApp("NeonMedia", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
