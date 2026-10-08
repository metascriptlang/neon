import { renderToString } from "../../src/render/ssr";
import { HostNode } from "../../src/render/hostTypes";
import { mockHost, mockNode, mockToString, render } from "../../src/render/host";
import {
	createMemoryRoutingHistory,
	createRequestRoutingHistory,
} from "../../src/navigation/index";
import { createRoutingDemo, RoutingDemo } from "../../examples/components/routing";

test "SSR initializes typed document and parallel inspector routes before mounting" {
	const demo = createRoutingDemo(createRequestRoutingHistory(
		"/documents/42?__nav.inspector=%2Fmaterials%2Fmetal",
	));
	assert demo.ok;
	if (demo.ok) {
		const model = demo.value;
		const html = renderToString(<RoutingDemo model={model} />);
		assert html.indexOf("Document 42") >= 0, html;
		assert html.indexOf("Inspector metal") >= 0, html;
		assert html.indexOf("Inventory sword") < 0, html;
		model.dispose();
	}
}

test "custom panes and overlays share routing while keeping unrelated document state" {
	const history = createMemoryRoutingHistory({ url: "/documents/home", state: "" });
	const demo = createRoutingDemo(history);
	assert demo.ok;
	if (demo.ok) {
		const model = demo.value;
		const root = mockNode("root");
		const dispose = render(
			<RoutingDemo model={model} />, mockHost(), root as unknown as HostNode,
		);
		const home = model.documentComponents()[0];
		home.increment();
		assert model.session.navigate("/documents/42", false).ok;
		assert model.documentComponents()[0] === home;
		assert model.session.navigate(
			"/documents/42?__nav.inspector=%2Fmaterials%2Fmetal&__nav.inventory=%2Fitems%2Fsword",
			false,
		).ok;
		assert model.documents().length === 2;
		assert model.document() === "42";
		assert model.inspector() === "metal";
		assert model.inventory() === "sword";
		const shown = mockToString(root);
		assert shown.indexOf("Document 42") >= 0 && shown.indexOf("Inventory sword") >= 0;
		assert history.go(-1);
		assert model.document() === "42" && model.inventory() === "";
		assert history.go(-1);
		assert model.document() === "home" && model.documents().length === 1;
		assert model.documentComponents()[0] === home && home.count() === 1;
		dispose();
		model.dispose();
	}
}

test "SSR requests use separate routing registries and reject malformed typed params" {
	const first = createRoutingDemo(createRequestRoutingHistory("/documents/first"));
	const second = createRoutingDemo(createRequestRoutingHistory("/documents/second"));
	assert first.ok && second.ok;
	if (first.ok && second.ok) {
		assert first.value.document() === "first";
		assert second.value.document() === "second";
		first.value.dispose();
		second.value.dispose();
	}
	const invalid = createRoutingDemo(createRequestRoutingHistory("/documents/%2F"));
	assert !invalid.ok;
}
