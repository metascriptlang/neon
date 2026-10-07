import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonSvg",
	targets: [Target.androidApp("NeonSvg", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
