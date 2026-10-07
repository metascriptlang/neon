import { accessor } from "../core/signal";
import { onCleanup } from "../core/cleanup";
import { Host, HostNode, NeonNode } from "../render/hostTypes";
import { BackHandler } from "../api/backHandler";
import { Linking, LinkingUrlEvent } from "../api/linking";
import { hasAppServices } from "../api/services";
import {
	ContainerState,
	DrawerAction,
	NavTarget,
	NavigatorKind,
	NavigatorLink,
	NavigationState,
	RouteKey,
	ScopeContext,
	ScreenScope,
	deepestFocused,
	navigateUp,
} from "./core";
import { LinkingOptions, targetFromPath, targetFromURL } from "./linking";

export class NavigationContainerRef {
	link: NavigatorLink | null = null;
	linkPath: (path: string) => boolean = (path: string): boolean => false;

	isReady(): boolean {
		return this.root() !== null;
	}

	root(): NavigatorLink | null {
		const link = this.link;
		if (link === null) { return null; }
		return (link as NavigatorLink).focusedChild();
	}

	private focusedLeaf(api: string): NavigatorLink {
		const root = this.root();
		if (root === null) {
			throw new Error(api + ": the navigation container is not mounted yet");
		}
		return deepestFocused(root as NavigatorLink);
	}

	navigate(name: string): void {
		const leaf = this.focusedLeaf("navigate");
		if (!navigateUp(leaf, { name, values: null, child: null })) {
			throw new Error("navigate: no focused navigator has a screen named '" + name + "'");
		}
	}

	goBack(): void {
		let link: NavigatorLink | null = this.focusedLeaf("goBack");
		while (link !== null) {
			const here = link as NavigatorLink;
			if (here.backLocal()) { return; }
			link = here.parent();
		}
		throw new Error("goBack: no navigator can go back");
	}

	canGoBack(): boolean {
		const root = this.root();
		if (root === null) { return false; }
		let link: NavigatorLink | null = deepestFocused(root as NavigatorLink);
		while (link !== null) {
			const here = link as NavigatorLink;
			if (here.canBackLocal()) { return true; }
			link = here.parent();
		}
		return false;
	}

	getCurrentRoute(): RouteKey | null {
		const root = this.root();
		if (root === null) { return null; }
		return deepestFocused(root as NavigatorLink).focusedRoute();
	}

	currentPath(): string {
		const root = this.root();
		return root === null ? "" : (root as NavigatorLink).describe();
	}

	handleBack(): boolean {
		const root = this.root();
		return root !== null && (root as NavigatorLink).handleBack();
	}

	openDrawer(): void {
		this.drawer(DrawerAction.Open);
	}

	closeDrawer(): void {
		this.drawer(DrawerAction.Close);
	}

	private drawer(action: DrawerAction): void {
		let link: NavigatorLink | null = this.focusedLeaf("drawer");
		while (link !== null) {
			const here = link as NavigatorLink;
			if (here.drawerAction(action)) { return; }
			link = here.parent();
		}
		throw new Error("drawer action: no drawer navigator is focused");
	}

	linkTo(path: string): boolean {
		return this.linkPath(path);
	}
}

export function createNavigationContainerRef(): NavigationContainerRef {
	return new NavigationContainerRef();
}

function containerLink(): NavigatorLink {
	let root: NavigatorLink | null = null;
	let waiting: NavTarget | null = null;
	return {
		kind: NavigatorKind.Container,
		hasRoute: (name: string): boolean => {
			return root !== null && (root as NavigatorLink).hasRoute(name);
		},
		navigateTo: (target: NavTarget): boolean => {
			if (root === null) {
				waiting = target;
				return true;
			}
			return (root as NavigatorLink).navigateTo(target);
		},
		pushTo: (name: string): boolean => false,
		backLocal: (): boolean => false,
		canBackLocal: (): boolean => false,
		popToTop: (): boolean => false,
		handleBack: (): boolean => root !== null && (root as NavigatorLink).handleBack(),
		drawerAction: (action: DrawerAction): boolean => false,
		isFocused: accessor((): boolean => true),
		register: (routeKey: string, child: NavigatorLink): NavTarget | null => {
			if (root !== null) { throw new Error("NavigationContainer holds one root navigator"); }
			root = child;
			const target = waiting;
			waiting = null;
			return target;
		},
		unregister: (routeKey: string, child: NavigatorLink): void => {
			if (root === child) { root = null; }
		},
		focusedChild: (): NavigatorLink | null => root,
		focusedRoute: (): RouteKey | null => null,
		state: (): NavigationState => root === null
			? { index: 0, routeNames: [], routes: [] }
			: (root as NavigatorLink).state(),
		parent: (): NavigatorLink | null => null,
		describe: (): string => root === null ? "" : (root as NavigatorLink).describe(),
	};
}

async function openInitialURL(open: (url: string) => boolean): Promise<void> {
	const url = await Linking.getInitialURL();
	if (url !== null) { open(url as string); }
}

export function NavigationContainer(props: {
	children: NeonNode;
	linking?: LinkingOptions | null;
	ref?: NavigationContainerRef | null;
	onReady?: (() => void) | null;
}): NeonNode {
	const link = containerLink();
	const linking = props.linking;
	const enabled = linking !== null && (linking as LinkingOptions).enabled !== false;
	const openURL = (url: string): boolean => {
		if (!enabled) { return false; }
		const target = targetFromURL(url, linking as LinkingOptions);
		if (target === null) { return false; }
		return link.navigateTo(target as NavTarget);
	};
	const openPath = (path: string): boolean => {
		if (linking === null) {
			throw new Error("linkTo: the NavigationContainer has no linking config");
		}
		const target = targetFromPath(path, (linking as LinkingOptions).config);
		if (target === null) { return false; }
		return link.navigateTo(target as NavTarget);
	};
	const state = new ContainerState(openPath);
	const scope = new ScreenScope(link, "", accessor((): boolean => true), null, state);
	const ref = props.ref;
	if (ref !== null) {
		const handle = ref as NavigationContainerRef;
		handle.link = link;
		handle.linkPath = openPath;
	}
	const back = BackHandler.addEventListener(
		"hardwareBackPress",
		(): boolean => link.handleBack(),
	);
	onCleanup((): void => { back.remove(); });
	if (enabled) {
		const urls = Linking.addEventListener("url", (event: LinkingUrlEvent): void => {
			openURL(event.url);
		});
		onCleanup((): void => { urls.remove(); });
	}
	const children = props.children;
	const ready = props.onReady;
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const body: NeonNode = <ScopeContext.Provider value={scope as unknown}>
			{children}
		</ScopeContext.Provider>;
		body(host, parent, before);
		state.ready = true;
		if (enabled && hasAppServices()) { openInitialURL(openURL); }
		if (ready !== null) { (ready as () => void)(); }
	};
}
