import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonMinimal",
	targets: [Target.androidApp("NeonMinimal", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
