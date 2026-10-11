import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonMedia",
	targets: [Target.androidApp("NeonMedia", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
