import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonVoidArea",
	targets: [{ ...Target.iosApp("NeonVoidArea", "app.ms"), assets: ["assets/font.ttf"] }],
	plugins: [bundlePrefix("dev.neon")],
};
