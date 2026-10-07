import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonSettings",
	targets: [Target.androidApp("NeonSettings", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
