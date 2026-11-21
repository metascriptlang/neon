import { domHost, documentBody } from "../../src/platform/browser/dom";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/hostTypes";
import {
	createBrowserRoutingHistory,
	followExternalRedirects,
	followLinks,
} from "../../src/platform/browser/routingHistory";
import {
	NavigateOptions,
	RouterProvider,
	createRouter,
	createRoutes,
	useLocation,
	useRouter,
} from "../../src/navigation/router";

extern function expose(
	update: () => void,
	navigate: (url: string, replace: boolean) => boolean,
): void from
	"((u, n) => { globalThis.neonUpdate = u; globalThis.neonNavigate = n; })(#, #)";

function Page(): NeonNode {
	const router = useRouter("Page");
	const location = useLocation();
	return <main>
		<p id="at">{"n=" + (location().search.get("n") ?? "none")}</p>
		<p id="version">{router.updated.get() ? "new version" : "current"}</p>
		<a id="next" href="/tests/browser/documentLoad.html?n=2">next</a>
		<a id="later" href="/tests/browser/documentLoad.html?n=3">later</a>
	</main>;
}

const opened = createRouter(
	createRoutes([{ path: "/documentLoad.html", component: Page }], "/tests/browser"),
	createBrowserRoutingHistory(),
);
if (opened.ok) {
	const router = opened.value;
	render(element(<RouterProvider router={router} />), domHost(), documentBody());
	followExternalRedirects(router);
	followLinks(
		(url: string, options: NavigateOptions): boolean => router.navigate(url, options),
		router.base,
	);
	expose(
		(): void => router.updated.set(true),
		(url: string, replace: boolean): boolean => router.navigate(url, { replace }),
	);
}
