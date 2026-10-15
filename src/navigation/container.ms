import { Accessor, accessor } from "../core/signal";
import { onCleanup } from "../core/cleanup";
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
	NavigationRoute,
	NavigationState,
	RouteKey,
	ScopeContext,
	ScreenScope,
	deepestFocused,
	navigateUp,
} from "./core";
import {
	LinkingConfig,
	LinkingOptions,
	pathFromState,
	targetFromPath,
	targetFromURL,
} from "./linking";
import { RoutePlan, RoutingError, RoutingParticipant, RoutingRegistry } from "./routing";

export interface ContainerRouting {
	registry: RoutingRegistry;
	scope: string;
}

struct RouteSnapshot {
	name: string;
	hasParams: boolean;
	paramPairs: string[];
	nested: StateSnapshot[];
}

struct StateSnapshot {
	index: int32;
	routes: RouteSnapshot[];
}

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
		throw new Error("drawer action: no drawer navigator is focused");
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

function containerLink(initialState: NavigationState | null): NavigatorLink {
	let root: NavigatorLink | null = null;
	let waiting: NavTarget | null = null;
	let initial = initialState;
	let seed = initialState;
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
			initial = child.state();
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
	};
}

function snapshotOf(state: NavigationState): StateSnapshot {
	const routes: RouteSnapshot[] = [];
	for (const route of state.routes) {
		const paramPairs: string[] = [];
		const values = route.params;
		if (values !== null) {
			for (const key of values as Map<string, string>) {
				paramPairs.push(key);
				paramPairs.push((values as Map<string, string>).get(key) ?? "");
			}
		}
		const nested = route.state;
		routes.push({
			name: route.name,
			hasParams: values !== null,
			paramPairs,
			nested: nested === null ? [] : [snapshotOf(nested as NavigationState)],
		});
	}
	return { index: state.index, routes };
}

function stateOfSnapshot(snapshot: StateSnapshot): Result<NavigationState, RoutingError> {
	const count = snapshot.routes.length;
	if (count === 0 || snapshot.index < 0 || snapshot.index >= count) {
		return Result.err(RoutingError.IncompleteSnapshot);
	}
	const routes: NavigationRoute[] = [];
	for (const route of snapshot.routes) {
		if (route.paramPairs.length % 2 !== 0 || route.nested.length > 1) {
			return Result.err(RoutingError.IncompleteSnapshot);
		}
		let params: Map<string, string> | null = null;
		if (route.hasParams) {
			const values = new Map<string, string>();
			for (let i = 0; i < route.paramPairs.length; i += 2) {
				values.set(route.paramPairs[i], route.paramPairs[i + 1]);
			}
			params = values;
		}
		let state: NavigationState | null = null;
		if (route.nested.length === 1) {
			const nested = try stateOfSnapshot(route.nested[0]);
			state = nested;
		}
		routes.push({ key: "", name: route.name, params, state });
	}
	return Result.ok({ index: snapshot.index, routeNames: [], routes });
}

function containerParticipant(
	scope: string,
	link: NavigatorLink,
	config: LinkingConfig,
): RoutingParticipant {
	return {
		scope,
		prepare: (address: string | null): Result<RoutePlan, RoutingError> => {
			if (address === null) {
				return Result.ok({ commit: (): void => link.restore(emptyState()) });
			}
			const path = address as string;
			const target = targetFromPath(path, config);
			if (target === null) { return Result.err(RoutingError.NoMatch); }
			return Result.ok({ commit: (): void => {
				if (!link.navigateTo(target as NavTarget)) {
					throw new Error("routing: no navigator has a screen for '" + path + "'");
				}
			} });
		},
		address: (): Result<string | null, RoutingError> => {
			const path: string | null = pathFromState(link.state(), config);
			return Result.ok(path);
		},
		capture: (): string => JSON.stringify(snapshotOf(link.state())),
		restore: (state: string): Result<RoutePlan, RoutingError> => {
			const parsed = JSON.parse<StateSnapshot>(state);
			if (!parsed.ok) { return Result.err(RoutingError.IncompleteSnapshot); }
			if (parsed.value.routes.length === 0) {
				return Result.ok({ commit: (): void => link.restore(emptyState()) });
			}
			const restored = try stateOfSnapshot(parsed.value);
			return Result.ok({ commit: (): void => link.restore(restored) });
		},
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
	const link = containerLink(props.initialState);
	const ownTheme = props.theme;
	const theme = accessor((): Theme => {
		return ownTheme === null ? DefaultTheme : (ownTheme as Accessor<Theme>)();
	});
	const linking = props.linking;
	const routing = props.routing;
	if (routing !== null) {
		if (linking === null) {
			throw new Error("NavigationContainer: routing needs a linking config");
		}
		const joined = routing as ContainerRouting;
		const participant = containerParticipant(
			joined.scope,
			link,
			(linking as LinkingOptions).config,
		);
		onCleanup(joined.registry.register(participant));
	}
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
	const stateChange = props.onStateChange;
	if (stateChange !== null) {
		const report = stateChange as (state: NavigationState) => void;
		state.changed = (): void => {
			if (state.ready) { report(link.state()); }
		};
	}
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
