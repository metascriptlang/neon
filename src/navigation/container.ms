import { Accessor, Signal, accessor, untrack } from "../core/signal";
import { onCleanup } from "../core/cleanup";
import { createEffect } from "../core/effect";
import { Cleanup, Dispose } from "../core/types";
import { Host, HostNode, NeonNode } from "../render/hostTypes";
import { BackHandler } from "../api/backHandler";
import { Linking, LinkingUrlEvent } from "../api/linking";
import { hasAppServices } from "../api/services";
import {
	ContainerState,
	DefaultTheme,
	DrawerAction,
	Theme,
	NavTarget,
	NavigatorKind,
	NavigatorLink,
	NavigationState,
	RouteKey,
	ScopeContext,
	ScreenScope,
	WebRoutes,
	deepestFocused,
	navigateUp,
	reportUnhandled,
	drawerActionType,
} from "./core";
import { LinkingOptions, targetFromPath, targetFromURL } from "./linking";
import { RoutingRegistry } from "./routing";
import { RoutingSession } from "./routingHistory";
import { WebNavigationNode } from "./webNavigation";
import { ContainerSlot, createContainerHistory } from "./containerHistory";

export interface ContainerRouting {
	registry: RoutingRegistry;
	scope: string;
}

export class NavigationContainerRef {
	link: NavigatorLink | null = null;
	linkPath: (path: string) => boolean = (path: string): boolean => false;
	history: ((session: RoutingSession) => Dispose) | null = null;

	enableHistory(session: RoutingSession): Dispose {
		const history = this.history;
		if (history === null) {
			throw new Error("enableHistory: the NavigationContainer has no routing");
		}
		return (history as (session: RoutingSession) => Dispose)(session);
	}

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
		if (!navigateUp(leaf, { name, values: null, child: null, pop: false })) {
			reportUnhandled("NAVIGATE", name);
		}
	}

	goBack(): void {
		let link: NavigatorLink | null = this.focusedLeaf("goBack");
		while (link !== null) {
			const here = link as NavigatorLink;
			if (here.backLocal()) { return; }
			link = here.parent();
		}
		reportUnhandled("GO_BACK", null);
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

	getRootState(): NavigationState {
		const link = this.link;
		if (link === null) {
			throw new Error("getRootState: the navigation container is not mounted yet");
		}
		return (link as NavigatorLink).state();
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
		reportUnhandled(drawerActionType(action), null);
	}

	linkTo(path: string): boolean {
		return this.linkPath(path);
	}
}

export function createNavigationContainerRef(): NavigationContainerRef {
	return new NavigationContainerRef();
}

function emptyState(): NavigationState {
	return { index: 0, routeNames: [], routes: [] };
}

function containerLink(initialState: NavigationState | null): ContainerSlot {
	let root: NavigatorLink | null = null;
	let waiting: NavTarget | null = null;
	let initial = initialState;
	let seed = initialState;
	const seedRoot = (state: NavigationState | null): void => {
		seed = state === null ? initial : state;
		if (state !== null) { waiting = null; }
	};
	const link: NavigatorLink = {
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
		popToRoute: (name: string): boolean => false,
		backLocal: (): boolean => false,
		canBackLocal: (): boolean => false,
		canPop: (): boolean => false,
		popToTop: (): boolean => false,
		handleBack: (): boolean => root !== null && (root as NavigatorLink).handleBack(),
		drawerAction: (action: DrawerAction): boolean => false,
		isFocused: accessor((): boolean => true),
		register: (routeKey: string, child: NavigatorLink): NavTarget | null => {
			if (root !== null) { throw new Error("NavigationContainer holds one root navigator"); }
			root = child;
			initial = untrack((): NavigationState => child.state());
			const target = waiting;
			waiting = null;
			return target;
		},
		seedFor: (routeKey: string): NavigationState | null => {
			const state = seed;
			seed = null;
			return state;
		},
		restore: (state: NavigationState): void => {
			const wanted = state.routes.length === 0 ? initial : state;
			if (root === null) {
				seed = wanted;
				waiting = null;
				return;
			}
			(root as NavigatorLink).restore(wanted as NavigationState);
		},
		unregister: (routeKey: string, child: NavigatorLink): void => {
			if (root === child) { root = null; }
		},
		focusedChild: (): NavigatorLink | null => root,
		focusedRoute: (): RouteKey | null => null,
		state: (): NavigationState => root === null
			? emptyState()
			: (root as NavigatorLink).state(),
		parent: (): NavigatorLink | null => null,
		describe: (): string => root === null ? "" : (root as NavigatorLink).describe(),
		webNavigation: (routes: WebRoutes): WebNavigationNode => {
			throw new Error("NavigationContainer publishes its history through its root navigator");
		},
		screen: (): unknown => null,
		nested: (routeKey: string): NavigatorLink | null => root,
		seedNested: (routeKey: string, state: NavigationState | null): void => seedRoot(state),
	};
	return {
		link,
		root: (): NavigatorLink | null => root,
		waiting: (): NavTarget | null => waiting,
		seedRoot,
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
	onStateChange?: ((state: NavigationState) => void) | null;
	initialState?: NavigationState | null;
	theme?: Accessor<Theme> | null;
	routing?: ContainerRouting | null;
}): NeonNode {
	const slot = containerLink(props.initialState);
	const link = slot.link;
	const ownTheme = props.theme;
	const theme = accessor((): Theme => {
		return ownTheme === null ? DefaultTheme : (ownTheme as Accessor<Theme>)();
	});
	const linking = props.linking;
	const routing = props.routing;
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
	const state = new ContainerState(openPath, theme);
	const changes = new Signal<int32>(0, null, true);
	const stateChange = props.onStateChange;
	state.changed = (): void => {
		changes.set(changes.peek() + 1);
		if (stateChange !== null && state.ready) {
			(stateChange as (state: NavigationState) => void)(untrack((): NavigationState => link.state()));
		}
	};
	let history: ((session: RoutingSession) => Dispose) | null = null;
	if (routing !== null) {
		if (linking === null) {
			throw new Error("NavigationContainer: routing needs a linking config");
		}
		const joined = routing as ContainerRouting;
		const revision = new Signal<int32>(0, null, true);
		const web = createContainerHistory(
			joined.scope,
			slot,
			(linking as LinkingOptions).config,
			revision,
		);
		onCleanup(joined.registry.register(web.participant));
		createEffect<int32>(
			(prev: int32 | null): int32 => changes.get(),
			(count: int32, prev: int32 | null): Cleanup | null => {
				revision.set(revision.peek() + 1);
				return null;
			},
			{ defer: true },
		);
		const stops: Dispose[] = [];
		onCleanup((): void => {
			for (const stop of stops.slice(0, stops.length)) { stop(); }
		});
		history = (session: RoutingSession): Dispose => {
			if (!state.ready) {
				throw new Error("enableHistory: the NavigationContainer is not mounted yet");
			}
			const mirror = web.enable(session);
			let stopped = false;
			const stop = (): void => {
				if (stopped) { return; }
				stopped = true;
				mirror();
			};
			stops.push(stop);
			return stop;
		};
	}
	const scope = new ScreenScope(link, "", accessor((): boolean => true), null, state);
	const ref = props.ref;
	if (ref !== null) {
		const handle = ref as NavigationContainerRef;
		handle.link = link;
		handle.linkPath = openPath;
		handle.history = history;
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
		const body: NeonNode = <ScopeContext value={scope as unknown}>
			{children}
		</ScopeContext>;
		body(host, parent, before);
		state.ready = true;
		if (enabled && hasAppServices()) { openInitialURL(openURL); }
		if (ready !== null) { (ready as () => void)(); }
	};
}
