import { NeonNode } from "../../src/render/node";
import { renderToString } from "../../src/render/ssr";

test "bare JSX lowers at an annotated const boundary" {
	const v: NeonNode = <div class="box">hi</div>;
	assert renderToString(v) === "<div class=\"box\">hi</div>", renderToString(v);
}
