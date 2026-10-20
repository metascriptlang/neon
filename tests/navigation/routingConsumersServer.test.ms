import { renderToString } from "../../src/render/ssr";
import { createRequestRoutingHistory, encodeRouteComponent } from "../../src/navigation/index";
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

test "request route text cannot inject SSR markup or attributes" {
	const id = "<img src=x onerror='alert(1)'> &amp;";
	const ready = createRoutingDemo(
		createRequestRoutingHistory("/documents/" + encodeRouteComponent(id)),
	);
	assert ready.ok;
	if (ready.ok) {
		const model = ready.value;
		const html = renderToString(<RoutingDemo model={model} />);
		assert html.indexOf("<img") < 0, html;
		assert html.indexOf("Document &lt;img") >= 0, html;
		assert html.indexOf("&amp;amp;") >= 0, html;
		assert html.indexOf("onerror=&#39;alert(1)&#39;") >= 0, html;
		assert model.document() === id;
		model.dispose();
	}
}
