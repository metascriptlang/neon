import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonGallery",
	targets: [Target.iosApp("NeonGallery", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
