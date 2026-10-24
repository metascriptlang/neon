import { lazy } from "../../src/macros/lazy";
import { lazyModule } from "../../src/render/component";
import { NeonNode } from "../../src/render/hostTypes";
import { el, text } from "../../src/render/node";

async function load(): Promise<(props: {}) => NeonNode> {
	return (props: {}): NeonNode => el("p", [], [], text("x"));
}

const Page = lazy<{}>(load);
