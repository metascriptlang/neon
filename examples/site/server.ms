import { NeonNode } from "../../src/render/hostTypes";
import { renderToMarkup } from "../../src/render/ssr";
import { RoutingError } from "../../src/navigation/routing";
import { createRequestRoutingHistory } from "../../src/navigation/routingHistory";
import { Site, NotFound, createSite } from "./site";

struct SiteResponse {
	status: int32;
	body: string;
}

function document(page: NeonNode): string {
	const markup = renderToMarkup(page);
	return "<!doctype html><html><head><meta charset=\"utf-8\">" + markup.head +
		"<style>" + markup.css + "</style></head><body><div id=\"site\">" + markup.html +
		"</div><script type=\"module\" src=\"/client.js\"></script></body></html>";
}

function respond(url: string): SiteResponse {
	const site = createSite(createRequestRoutingHistory(url));
	if (!site.ok) {
		return { status: site.error === RoutingError.NoMatch ? 404 : 400, body: document(<NotFound />) };
	}
	const model = site.value;
	try {
		return { status: 200, body: document(<Site model={model} />) };
	} finally {
		model.dispose();
	}
}

extern function serve(respond: (url: string) => SiteResponse): void from "(globalThis.neonSite = #)";

serve(respond);
