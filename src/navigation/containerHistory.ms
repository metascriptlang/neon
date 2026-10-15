import { Signal, accessor, untrack } from "../core/signal";
import { Dispose } from "../core/types";
import {
	NavTarget,
	NavigationRoute,
	NavigationState,
	NavigatorLink,
	SeedRoute,
	WebRoutes,
	decodeSeedRoute,
	encodeSeedRoute,
} from "./core";
import {
	LinkingConfig,
	LinkingScreen,
	nestedScreens,
	screenPathPart,
	screenQuery,
	targetFromPath,
} from "./linking";
import { RoutePlan, RoutingError, RoutingParticipant } from "./routing";
import { RoutingSession } from "./routingHistory";
import {
	WebHistoryItem,
	WebKeySerializer,
	WebNavigationError,
	WebNavigationNode,
	WebNavigationOwner,
	pagesSerializer,
} from "./webNavigation";
import { createWebHistory } from "./webHistory";

export interface ContainerSlot {
	link: NavigatorLink;
	root: () => NavigatorLink | null;
	waiting: () => NavTarget | null;
	seedRoot: (state: NavigationState | null) => void;
}

export interface ContainerHistory {
	participant: RoutingParticipant;
	enable: (session: RoutingSession) => Dispose;
}

const rawKeys: WebKeySerializer<string> = {
	encode: (key: string): string => key,
	decode: (text: string): Result<string, WebNavigationError> => Result.ok(text),
};

interface Pending {
	keys: string[];
	pages: boolean;
	state: NavigationState;
}

function routeOf(stored: SeedRoute): NavigationRoute {
	return { key: stored.key, name: stored.name, params: stored.params, state: null };
}

function decodePending(keys: string[]): Result<Pending | null, WebNavigationError> {
	if (keys.length === 0 || (keys.length === 1 && keys[0] === "")) { return Result.ok(null); }
	const routes: NavigationRoute[] = [];
	if (keys.length === 1) {
		const pages = pagesSerializer<string>(rawKeys).decode(keys[0]);
		if (pages.ok) {
			for (const item of pages.value.items) {
				const stored = decodeSeedRoute(item);
				if (stored === null) { return Result.err(WebNavigationError.UndecodableKey); }
				routes.push(routeOf(stored as SeedRoute));
			}
			const at = pages.value.selectedIndex;
			if (at < 0 || at >= routes.length) {
				return Result.err(WebNavigationError.UndecodableKey);
			}
			const pending: Pending | null = {
				keys,
				pages: true,
				state: { index: at, routeNames: [], routes },
			};
			return Result.ok(pending);
		}
	}
	for (const key of keys) {
		const stored = decodeSeedRoute(key);
		if (stored === null) { return Result.err(WebNavigationError.UndecodableKey); }
		routes.push(routeOf(stored as SeedRoute));
	}
	const pending: Pending | null = {
		keys,
		pages: false,
		state: { index: (routes.length - 1) as int32, routeNames: [], routes },
	};
	return Result.ok(pending);
}

function pendingOfState(state: NavigationState): Pending {
	const keys: string[] = [];
	for (const route of state.routes) {
		keys.push(encodeSeedRoute({ key: route.key, name: route.name, params: route.params }));
	}
	return { keys, pages: false, state };
}

function stateOfTarget(target: NavTarget): NavigationState {
	const child = target.child;
	return {
		index: 0,
		routeNames: [],
		routes: [{
			key: "",
			name: target.name,
			params: target.values,
			state: child === null ? null : stateOfTarget(child as NavTarget),
		}],
	};
}

function declares(screens: LinkingScreen[] | null, name: string): boolean {
	return nestedScreens(screens, name) !== null;
}

function noLink(): NavigatorLink | null {
	return null;
}

function noTarget(): NavTarget | null {
	return null;
}

class HistorySlot {
	screens: LinkingScreen[] | null;
	revision: Signal<int32>;
	registered: () => NavigatorLink | null;
	seed: (state: NavigationState | null) => void;
	target: () => NavTarget | null;
	pending: Pending | null = null;
	pendingChildren: Map<int32, HistorySlot> = new Map<int32, HistorySlot>();
	children: Map<string, HistorySlot> = new Map<string, HistorySlot>();
	previous: Map<string, HistorySlot> = new Map<string, HistorySlot>();
	link: NavigatorLink | null = null;
	real: WebNavigationNode | null = null;
	node: WebNavigationNode;
	owner: WebNavigationOwner;

	constructor(
		screens: LinkingScreen[] | null,
		revision: Signal<int32>,
		registered: () => NavigatorLink | null,
		seed: (state: NavigationState | null) => void,
		target: () => NavTarget | null,
	) {
		this.screens = screens;
		this.revision = revision;
		this.registered = registered;
		this.seed = seed;
		this.target = target;
		this.node = {
			history: accessor((): WebHistoryItem<string>[] => {
				this.revision.get();
				return untrack((): WebHistoryItem<string>[] => this.items());
			}),
			onBeforeNavigate: (): boolean => {
				const real = this.live();
				return real === null ? true : (real as WebNavigationNode).onBeforeNavigate();
			},
			navigate: (keys: string[]): Result<void, WebNavigationError> => this.navigate(keys),
		};
		this.owner = { webNavigation: this.node };
	}

	live(): WebNavigationNode | null {
		const link = this.registered();
		if (link === null) { return null; }
		if (link !== this.link) {
			this.link = link;
			this.real = (link as NavigatorLink).webNavigation(this.routes(link as NavigatorLink));
		}
		return this.real;
	}

	routes(link: NavigatorLink): WebRoutes {
		return {
			path: (name: string, values: Map<string, string> | null): string | null => {
				return screenPathPart(this.screens, name, values);
			},
			parameters: (
				routeKey: string,
				name: string,
				values: Map<string, string> | null,
			): Map<string, string> | null => {
				const child = this.childSlot(link, routeKey, name);
				if (child.present(name, this.screens) && !child.empty()) { return null; }
				return screenQuery(this.screens, name, values);
			},
			child: (routeKey: string, name: string): WebNavigationOwner | null => {
				const child = this.childSlot(link, routeKey, name);
				return child.present(name, this.screens) ? child.owner : null;
			},
		};
	}

	childSlot(link: NavigatorLink, routeKey: string, name: string): HistorySlot {
		const known = this.children.get(routeKey);
		if (known !== null) { return known as HistorySlot; }
		const kept = this.previous.get(routeKey);
		const slot = kept !== null ? kept as HistorySlot : new HistorySlot(
			nestedScreens(this.screens, name),
			this.revision,
			(): NavigatorLink | null => link.nested(routeKey),
			(state: NavigationState | null): void => { link.seedNested(routeKey, state); },
			noTarget,
		);
		this.children.set(routeKey, slot);
		return slot;
	}

	present(name: string, screens: LinkingScreen[] | null): boolean {
		return this.registered() !== null || this.pending !== null || declares(screens, name);
	}

	empty(): boolean {
		return this.registered() === null && this.pending === null && this.target() === null;
	}

	items(): WebHistoryItem<string>[] {
		const real = this.live();
		if (real !== null) {
			this.previous = this.children;
			this.children = new Map<string, HistorySlot>();
			try {
				return (real as WebNavigationNode).history();
			} finally {
				this.previous = new Map<string, HistorySlot>();
			}
		}
		const pending = this.pending;
		if (pending !== null) { return this.pendingItems(pending as Pending); }
		const target = this.target();
		if (target !== null) {
			return this.pendingItems(pendingOfState(stateOfTarget(target as NavTarget)));
		}
		return [{ key: "", path: "", parameters: new Map<string, string>(), child: null }];
	}

	pendingItems(pending: Pending): WebHistoryItem<string>[] {
		const state = pending.state;
		const items: WebHistoryItem<string>[] = [];
		if (pending.pages) {
			items.push(this.pendingItem(pending.keys[0], state.index));
			return items;
		}
		for (let i = 0; i < state.routes.length; i += 1) {
			items.push(this.pendingItem(pending.keys[i], i as int32));
		}
		return items;
	}

	pendingItem(key: string, at: int32): WebHistoryItem<string> {
		const route = (this.pending === null ? null : this.pending as Pending);
		const state = route === null
			? stateOfTarget(this.target() as NavTarget)
			: (route as Pending).state;
		const entry = state.routes[at];
		let child: HistorySlot | null = null;
		if (entry.state !== null || declares(this.screens, entry.name)) {
			child = this.pendingChild(entry, at);
		}
		const leaf = child === null || (child as HistorySlot).empty();
		const query = leaf ? screenQuery(this.screens, entry.name, entry.params) : null;
		return {
			key,
			path: screenPathPart(this.screens, entry.name, entry.params),
			parameters: query === null ? new Map<string, string>() : query as Map<string, string>,
			child: child === null ? null : (child as HistorySlot).owner,
		};
	}

	pendingChild(entry: NavigationRoute, at: int32): HistorySlot {
		const known = this.pendingChildren.get(at);
		if (known !== null) { return known as HistorySlot; }
		const slot = new HistorySlot(
			nestedScreens(this.screens, entry.name),
			this.revision,
			noLink,
			(state: NavigationState | null): void => { entry.state = state; },
			noTarget,
		);
		const nested = entry.state;
		if (nested !== null) { slot.pending = pendingOfState(nested as NavigationState); }
		this.pendingChildren.set(at, slot);
		return slot;
	}

	navigate(keys: string[]): Result<void, WebNavigationError> {
		const real = this.live();
		if (real !== null) { return (real as WebNavigationNode).navigate(keys); }
		const decoded = decodePending(keys);
		if (!decoded.ok) { return Result.err(decoded.error); }
		this.hold(decoded.value);
		return Result.ok(null);
	}

	hold(pending: Pending | null): void {
		this.pending = pending;
		this.pendingChildren = new Map<int32, HistorySlot>();
		this.seed(pending === null ? null : (pending as Pending).state);
	}
}

function checkExact(screens: LinkingScreen[], nested: boolean): void {
	for (const screen of screens) {
		const exact = screen.exact;
		if (nested && exact !== null && (exact as boolean)) {
			throw new Error(
				"NavigationContainer: routing history joins each level's path, so screen '" +
				screen.name + "' cannot take an exact path",
			);
		}
		const children = screen.screens;
		if (children !== null) { checkExact(children as LinkingScreen[], true); }
	}
}

export function createContainerHistory(
	scope: string,
	container: ContainerSlot,
	config: LinkingConfig,
	revision: Signal<int32>,
): ContainerHistory {
	checkExact(config.screens, false);
	const root = new HistorySlot(
		config.screens,
		revision,
		container.root,
		container.seedRoot,
		container.waiting,
	);
	const bump = (): void => { revision.set(revision.peek() + 1); };
	const node: WebNavigationNode = {
		history: root.node.history,
		onBeforeNavigate: root.node.onBeforeNavigate,
		navigate: (keys: string[]): Result<void, WebNavigationError> => {
			bump();
			return root.navigate(keys);
		},
	};
	const forget = (): void => {
		if (root.live() === null) { root.hold(null); }
	};
	const web = createWebHistory(
		scope,
		node,
		(address: string | null): Result<RoutePlan, RoutingError> => {
			if (address === null) {
				return Result.ok({ commit: (): void => {
					bump();
					forget();
					container.link.restore({ index: 0, routeNames: [], routes: [] });
				} });
			}
			const path = address as string;
			const target = targetFromPath(path, config);
			if (target === null) { return Result.err(RoutingError.NoMatch); }
			return Result.ok({ commit: (): void => {
				bump();
				forget();
				if (!container.link.navigateTo(target as NavTarget)) {
					throw new Error("routing: no navigator has a screen for '" + path + "'");
				}
			} });
		},
	);
	return {
		participant: {
			scope,
			prepare: web.participant.prepare,
			address: (): Result<string | null, RoutingError> => {
				if (root.empty()) { return Result.ok(null); }
				return web.participant.address();
			},
			capture: (): string => root.empty() ? "" : web.participant.capture(),
			restore: (state: string): Result<RoutePlan, RoutingError> => {
				if (state === "") { return web.participant.prepare(null); }
				return web.participant.restore(state);
			},
		},
		enable: web.enable,
	};
}
