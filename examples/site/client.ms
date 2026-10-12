import { HostNode } from "../../src/render/hostTypes";
import { hydrate } from "../../src/render/host";
import { domHost } from "../../src/platform/browser/dom";
import { createBrowserRoutingHistory, followLinks } from "../../src/platform/browser/routingHistory";
import { Site, createSite } from "./site";

extern class Element {}
extern function siteContainer(id: cstring): Element from "document.getElementById(#)";
extern function hydrated(count: int32): void from "(globalThis.neonSiteHydrated = #)";

const site = createSite(createBrowserRoutingHistory());
if (site.ok) {
	const model = site.value;
	hydrate(<Site model={model} />, domHost(), siteContainer("site") as unknown as HostNode);
	followLinks(model.open);
	hydrated(1);
}
