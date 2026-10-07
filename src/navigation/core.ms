import { Accessor, Setter, accessor, batch, createSignal, untrack } from "../core/signal";
import { createEffect } from "../core/effect";
import { createRoot } from "../core/owner";
import { onCleanup } from "../core/cleanup";
import { NeonNode } from "../render/hostTypes";
import { Style } from "../render/style";
import { createContext, useContext } from "../render/context";

export enum NavigatorKind {
	Container,
	Stack,
	Tabs,
	Drawer,
}

export enum DrawerAction {
	Open,
	Close,
	Toggle,
}

export interface TabBarIconProps {
	focused: boolean;
	color: string;
	size: number;
}

export interface ScreenOptions {
	title?: string | null;
	headerShown?: boolean | null;
	headerTitle?: string | null;
	headerBackTitle?: string | null;
	headerTintColor?: string | null;
	headerStyle?: Style | null;
	headerLeft?: NeonNode | null;
	headerRight?: NeonNode | null;
	tabBarLabel?: string | null;
	tabBarBadge?: string | null;
	tabBarIcon?: ((props: TabBarIconProps) => NeonNode) | null;
	tabBarActiveTintColor?: string | null;
	tabBarInactiveTintColor?: string | null;
	tabBarAccessibilityLabel?: string | null;
	drawerLabel?: string | null;
	drawerActiveTintColor?: string | null;
	lazy?: boolean | null;
	unmountOnBlur?: boolean | null;
}

export interface ScreenOptionsOf<P> extends ScreenOptions {}

export function plainOptions<P>(o: ScreenOptionsOf<P>): ScreenOptions {
	return {
		title: o.title,
		headerShown: o.headerShown,
		headerTitle: o.headerTitle,
		headerBackTitle: o.headerBackTitle,
		headerTintColor: o.headerTintColor,
		headerStyle: o.headerStyle,
		headerLeft: o.headerLeft,
		headerRight: o.headerRight,
		tabBarLabel: o.tabBarLabel,
		tabBarBadge: o.tabBarBadge,
		tabBarIcon: o.tabBarIcon,
		tabBarActiveTintColor: o.tabBarActiveTintColor,
		tabBarInactiveTintColor: o.tabBarInactiveTintColor,
		tabBarAccessibilityLabel: o.tabBarAccessibilityLabel,
		drawerLabel: o.drawerLabel,
		drawerActiveTintColor: o.drawerActiveTintColor,
		lazy: o.lazy,
		unmountOnBlur: o.unmountOnBlur,
	};
}

export function optionsAccessor<P>(declared: Accessor<ScreenOptionsOf<P>> | null): Accessor<ScreenOptions> | null {
	if (declared === null) { return null; }
	const read = declared as Accessor<ScreenOptionsOf<P>>;
	return accessor((): ScreenOptions => plainOptions<P>(read()));
}

export function mergeOptions(base: ScreenOptions, over: ScreenOptions): ScreenOptions {
	return {
		title: over.title !== null ? over.title : base.title,
		headerShown: over.headerShown !== null ? over.headerShown : base.headerShown,
		headerTitle: over.headerTitle !== null ? over.headerTitle : base.headerTitle,
		headerBackTitle: over.headerBackTitle !== null ? over.headerBackTitle : base.headerBackTitle,
		headerTintColor: over.headerTintColor !== null ? over.headerTintColor : base.headerTintColor,
		headerStyle: over.headerStyle !== null ? over.headerStyle : base.headerStyle,
		headerLeft: over.headerLeft !== null ? over.headerLeft : base.headerLeft,
		headerRight: over.headerRight !== null ? over.headerRight : base.headerRight,
		tabBarLabel: over.tabBarLabel !== null ? over.tabBarLabel : base.tabBarLabel,
		tabBarBadge: over.tabBarBadge !== null ? over.tabBarBadge : base.tabBarBadge,
		tabBarIcon: over.tabBarIcon !== null ? over.tabBarIcon : base.tabBarIcon,
		tabBarActiveTintColor: over.tabBarActiveTintColor !== null
			? over.tabBarActiveTintColor
			: base.tabBarActiveTintColor,
		tabBarInactiveTintColor: over.tabBarInactiveTintColor !== null
			? over.tabBarInactiveTintColor
			: base.tabBarInactiveTintColor,
		tabBarAccessibilityLabel: over.tabBarAccessibilityLabel !== null
			? over.tabBarAccessibilityLabel
			: base.tabBarAccessibilityLabel,
		drawerLabel: over.drawerLabel !== null ? over.drawerLabel : base.drawerLabel,
		drawerActiveTintColor: over.drawerActiveTintColor !== null
			? over.drawerActiveTintColor
			: base.drawerActiveTintColor,
		lazy: over.lazy !== null ? over.lazy : base.lazy,
		unmountOnBlur: over.unmountOnBlur !== null ? over.unmountOnBlur : base.unmountOnBlur,
	};
}

export interface NavTarget {
	name: string;
	values: Map<string, string> | null;
	child: NavTarget | null;
}

export interface RouteKey {
	key: string;
	name: string;
}

export interface NavigationState {
	index: int32;
	routeNames: string[];
	routes: RouteKey[];
}

export interface NavigatorLink {
	kind: NavigatorKind;
	hasRoute: (name: string) => boolean;
	navigateTo: (target: NavTarget) => boolean;
	pushTo: (name: string) => boolean;
	backLocal: () => boolean;
	canBackLocal: () => boolean;
	handleBack: () => boolean;
	drawerAction: (action: DrawerAction) => boolean;
	isFocused: Accessor<boolean>;
	register: (routeKey: string, child: NavigatorLink) => NavTarget | null;
	unregister: (routeKey: string, child: NavigatorLink) => void;
	focusedChild: () => NavigatorLink | null;
	focusedRoute: () => RouteKey | null;
	parent: () => NavigatorLink | null;
	describe: () => string;
}

export class ScreenScope {
	link: NavigatorLink;
	routeKey: string;
	focused: Accessor<boolean>;
	navigation: unknown;
	container: ContainerState;

	constructor(
		link: NavigatorLink,
		routeKey: string,
		focused: Accessor<boolean>,
		navigation: unknown,
		container: ContainerState,
	) {
		this.link = link;
		this.routeKey = routeKey;
		this.focused = focused;
		this.navigation = navigation;
		this.container = container;
	}
}

export class ContainerState {
	linkTo: (path: string) => boolean;
	ready: boolean = false;

	constructor(linkTo: (path: string) => boolean) {
		this.linkTo = linkTo;
	}
}

export const ScopeContext = createContext<unknown>(null);

export function currentScope(api: string): ScreenScope {
	const value = useContext(ScopeContext);
	if (value === null) {
		throw new Error(api + ": no navigator around this component; render it inside NavigationContainer");
	}
	return value as ScreenScope;
}

export class Route<P> {
	key: string;
	name: string;
	params: Accessor<P | null>;

	constructor(key: string, name: string, params: Accessor<P | null>) {
		this.key = key;
		this.name = name;
		this.params = params;
	}
}

export interface ScreenProps<P> {
	navigation: Navigation<P>;
	route: Route<P>;
}

export class ScreenConfig<P> {
	name: string;
	component: (props: ScreenProps<P>) => NeonNode;
	options: Accessor<ScreenOptions> | null;
	initialParams: P | null;
	parseParams: ((values: Map<string, string>) => P) | null;

	constructor(
		name: string,
		component: (props: ScreenProps<P>) => NeonNode,
		options: Accessor<ScreenOptions> | null,
		initialParams: P | null,
		parseParams: ((values: Map<string, string>) => P) | null,
	) {
		this.name = name;
		this.component = component;
		this.options = options;
		this.initialParams = initialParams;
		this.parseParams = parseParams;
	}
}

export interface ResetRoute<P> {
	name: string;
	params?: P | null;
}

export interface ResetState<P> {
	index?: int32 | null;
	routes: ResetRoute<P>[];
}

export type NavigationEvent = "focus" | "blur" | "state";

export type Unsubscribe = () => void;

interface ChildEntry {
	routeKey: string;
	link: NavigatorLink;
}

interface PendingEntry {
	routeKey: string;
	target: NavTarget;
}

interface StateListener {
	id: int32;
	handler: () => void;
}

export class Navigation<P> {
	core: NavigatorCore<P>;
	route: Route<P>;
	config: ScreenConfig<P>;
	writeParams: Setter<P | null>;
	overrides: Accessor<ScreenOptions>;
	writeOverrides: Setter<ScreenOptions>;
	visited: Accessor<boolean>;
	markVisited: Setter<boolean>;

	constructor(
		core: NavigatorCore<P>,
		route: Route<P>,
		config: ScreenConfig<P>,
		writeParams: Setter<P | null>,
		overrides: Accessor<ScreenOptions>,
		writeOverrides: Setter<ScreenOptions>,
		visited: Accessor<boolean>,
		markVisited: Setter<boolean>,
	) {
		this.core = core;
		this.route = route;
		this.config = config;
		this.writeParams = writeParams;
		this.overrides = overrides;
		this.writeOverrides = writeOverrides;
		this.visited = visited;
		this.markVisited = markVisited;
	}

	goBack(): void {
		const core = this.core;
		if (core.goBackFrom(this.route.key)) { return; }
		const parent = core.parent;
		if (parent !== null && goBackUp(parent as NavigatorLink)) { return; }
		throw new Error("goBack: no navigator could go back from '" + this.route.name + "'");
	}

	canGoBack(): boolean {
		if (this.core.canBackLocal()) { return true; }
		let link = this.core.parent;
		while (link !== null) {
			const current = link as NavigatorLink;
			if (current.canBackLocal()) { return true; }
			link = current.parent();
		}
		return false;
	}

	popToTop(): void {
		this.core.popTo(0);
	}

	reset(state: ResetState<P>): void {
		this.core.resetTo(state);
	}

	setParams(params: P): void {
		this.writeParams(params);
	}

	setOptions(options: ScreenOptions): void {
		const previous = untrack((): ScreenOptions => this.overrides());
		this.writeOverrides(mergeOptions(previous, options));
	}

	options(): ScreenOptions {
		const core = this.core;
		const declared = this.config.options;
		const base = declared === null ? core.screenOptions() : mergeOptions(core.screenOptions(), declared());
		return mergeOptions(base, this.overrides());
	}

	isFocused(): boolean {
		return untrack((): boolean => this.focusedNow());
	}

	focusedNow(): boolean {
		return this.core.currentKey() === this.route.key && this.core.focused();
	}

	getState(): NavigationState {
		return this.core.state();
	}

	openDrawer(): void {
		this.drawer(DrawerAction.Open);
	}

	closeDrawer(): void {
		this.drawer(DrawerAction.Close);
	}

	toggleDrawer(): void {
		this.drawer(DrawerAction.Toggle);
	}

	private drawer(action: DrawerAction): void {
		if (this.core.drawerLocal(action)) { return; }
		let link = this.core.parent;
		while (link !== null) {
			const current = link as NavigatorLink;
			if (current.drawerAction(action)) { return; }
			link = current.parent();
		}
		throw new Error("drawer action: no drawer navigator around '" + this.route.name + "'");
	}

	addListener(event: NavigationEvent, handler: () => void): Unsubscribe {
		if (event === "state") { return this.core.addStateListener(handler); }
		const wantFocus = event === "focus";
		return createRoot((dispose: () => void): Unsubscribe => {
			let first = true;
			let last = false;
			createEffect((): void => {
				const now = this.focusedNow();
				if (first) {
					first = false;
					last = now;
					return;
				}
				if (now === last) { return; }
				last = now;
				if (now === wantFocus) { untrack((): void => { handler(); }); }
			});
			return dispose;
		});
	}
}

export function navigate<P>(this navigation: Navigation<P>, name: string, params: P | null = null): void {
	navigation.core.navigate(name, params);
}

export function push<P>(this navigation: Navigation<P>, name: string, params: P | null = null): void {
	navigation.core.push(name, params);
}

export function replace<P>(this navigation: Navigation<P>, name: string, params: P | null = null): void {
	navigation.core.replaceRoute(navigation.route.key, name, params);
}

export function jumpTo<P>(this navigation: Navigation<P>, name: string, params: P | null = null): void {
	navigation.core.navigate(name, params);
}

export function pop<P>(this navigation: Navigation<P>, count: int32 = 1): void {
	navigation.core.popCount(count);
}

export function getParent<P, Q>(this navigation: Navigation<P>): Navigation<Q> {
	const outer = navigation.core.parentNavigation;
	if (outer === null) {
		throw new Error("getParent: the navigator of '" + navigation.route.name + "' is the root navigator");
	}
	return outer as Navigation<Q>;
}

function goBackUp(link: NavigatorLink): boolean {
	let current: NavigatorLink | null = link;
	while (current !== null) {
		const here = current as NavigatorLink;
		if (here.backLocal()) { return true; }
		current = here.parent();
	}
	return false;
}

export function navigateUp(link: NavigatorLink, target: NavTarget): boolean {
	let current: NavigatorLink | null = link;
	while (current !== null) {
		const here = current as NavigatorLink;
		if (here.hasRoute(target.name)) { return here.navigateTo(target); }
		current = here.parent();
	}
	return false;
}

export function deepestFocused(link: NavigatorLink): NavigatorLink {
	let current = link;
	let child = current.focusedChild();
	while (child !== null) {
		current = child as NavigatorLink;
		child = current.focusedChild();
	}
	return current;
}

export interface NavigatorSetup<P> {
	kind: NavigatorKind;
	screens: ScreenConfig<P>[];
	initialRouteName: string | null;
	initialParams: P | null;
	screenOptions: Accessor<ScreenOptions>;
	backBehavior: string;
	scope: ScreenScope;
}

export class NavigatorCore<P> {
	kind: NavigatorKind;
	screens: ScreenConfig<P>[];
	entries: Accessor<Navigation<P>[]>;
	writeEntries: Setter<Navigation<P>[]>;
	index: Accessor<int32>;
	writeIndex: Setter<int32>;
	drawerOpen: Accessor<boolean>;
	writeDrawerOpen: Setter<boolean>;
	screenOptions: Accessor<ScreenOptions>;
	backBehavior: string;
	initialName: string;
	parent: NavigatorLink | null;
	parentKey: string;
	focused: Accessor<boolean>;
	parentNavigation: unknown;
	container: ContainerState;
	link: NavigatorLink | null = null;
	children: ChildEntry[] = [];
	pending: PendingEntry[] = [];
	history: string[] = [];
	listeners: StateListener[] = [];
	nextKey: int32 = 1;
	nextListener: int32 = 1;

	constructor(
		kind: NavigatorKind,
		screens: ScreenConfig<P>[],
		entries: Accessor<Navigation<P>[]>,
		writeEntries: Setter<Navigation<P>[]>,
		index: Accessor<int32>,
		writeIndex: Setter<int32>,
		drawerOpen: Accessor<boolean>,
		writeDrawerOpen: Setter<boolean>,
		screenOptions: Accessor<ScreenOptions>,
		backBehavior: string,
		initialName: string,
		scope: ScreenScope,
	) {
		this.kind = kind;
		this.screens = screens;
		this.entries = entries;
		this.writeEntries = writeEntries;
		this.index = index;
		this.writeIndex = writeIndex;
		this.drawerOpen = drawerOpen;
		this.writeDrawerOpen = writeDrawerOpen;
		this.screenOptions = screenOptions;
		this.backBehavior = backBehavior;
		this.initialName = initialName;
		this.parent = scope.link;
		this.parentKey = scope.routeKey;
		this.focused = scope.focused;
		this.parentNavigation = scope.navigation;
		this.container = scope.container;
	}

	isStack(): boolean {
		return this.kind === NavigatorKind.Stack;
	}

	config(name: string): ScreenConfig<P> | null {
		for (const screen of this.screens) {
			if (screen.name === name) { return screen; }
		}
		return null;
	}

	hasRoute(name: string): boolean {
		return this.config(name) !== null;
	}

	routeNames(): string[] {
		const names: string[] = [];
		for (const screen of this.screens) { names.push(screen.name); }
		return names;
	}

	currentKey(): string {
		const list = this.entries();
		const at = this.index();
		return at >= 0 && at < list.length ? list[at].route.key : "";
	}

	current(): Navigation<P> | null {
		const list = untrack((): Navigation<P>[] => this.entries());
		const at = untrack((): int32 => this.index());
		return at >= 0 && at < list.length ? list[at] : null;
	}

	makeEntry(name: string, params: P | null): Navigation<P> {
		const screen = this.config(name);
		if (screen === null) {
			throw new Error("navigator has no screen named '" + name + "'");
		}
		const config = screen as ScreenConfig<P>;
		const initial = params !== null ? params : config.initialParams;
		const [read, write] = createSignal<P | null>(initial);
		const empty: ScreenOptions = {};
		const [overrides, writeOverrides] = createSignal<ScreenOptions>(empty);
		const [visited, markVisited] = createSignal<boolean>(false);
		const key = name + "-" + this.nextKey.toString();
		this.nextKey += 1;
		const route = new Route<P>(key, name, read);
		return new Navigation<P>(this, route, config, write, overrides, writeOverrides, visited, markVisited);
	}

	start(initialParams: P | null): void {
		if (this.isStack()) {
			const first = this.makeEntry(this.initialName, initialParams);
			first.markVisited(true);
			this.commit([first], 0);
			return;
		}
		const list: Navigation<P>[] = [];
		let at: int32 = 0;
		for (let i = 0; i < this.screens.length; i += 1) {
			const name = this.screens[i].name;
			const entry = this.makeEntry(name, name === this.initialName ? initialParams : null);
			if (name === this.initialName) {
				at = i as int32;
				entry.markVisited(true);
			}
			list.push(entry);
		}
		this.history = [list[at].route.key];
		this.commit(list, at);
	}

	commit(list: Navigation<P>[], at: int32): void {
		batch((): void => {
			this.writeEntries(list);
			this.writeIndex(at);
			list[at].markVisited(true);
		});
		this.notify();
	}

	notify(): void {
		for (const listener of this.listeners.slice(0, this.listeners.length)) { listener.handler(); }
	}

	addStateListener(handler: () => void): Unsubscribe {
		const id = this.nextListener;
		this.nextListener += 1;
		this.listeners.push({ id, handler });
		return (): void => {
			for (let i = 0; i < this.listeners.length; i += 1) {
				if (this.listeners[i].id === id) {
					this.listeners.splice(i, 1);
					return;
				}
			}
		};
	}

	snapshot(): Navigation<P>[] {
		const list = untrack((): Navigation<P>[] => this.entries());
		return list.slice(0, list.length);
	}

	indexOfName(list: Navigation<P>[], name: string): int32 {
		for (let i = list.length - 1; i >= 0; i -= 1) {
			if (list[i].route.name === name) { return i as int32; }
		}
		return -1;
	}

	navigate(name: string, params: P | null): void {
		if (this.hasRoute(name)) {
			this.navigateLocal(name, params);
			return;
		}
		if (params !== null) {
			throw new Error(
				"navigate: '" + name + "' is not a screen of this navigator; params of this navigator's type" +
				" cannot reach another navigator, use getParent<Q>().navigate",
			);
		}
		const parent = this.parent;
		if (parent !== null && navigateUp(parent as NavigatorLink, { name, values: null, child: null })) { return; }
		throw new Error("navigate: no navigator has a screen named '" + name + "'");
	}

	navigateLocal(name: string, params: P | null): void {
		const list = this.snapshot();
		const at = this.indexOfName(list, name);
		if (this.isStack()) {
			if (at < 0) {
				list.push(this.makeEntry(name, params));
				this.commit(list, (list.length - 1) as int32);
				return;
			}
			if (params !== null) { list[at].writeParams(params); }
			this.commit(list.slice(0, at + 1), at);
			return;
		}
		if (params !== null) { list[at].writeParams(params); }
		this.focusIndex(list, at);
	}

	focusIndex(list: Navigation<P>[], at: int32): void {
		const key = list[at].route.key;
		const kept: string[] = [];
		for (const visited of this.history) {
			if (visited !== key) { kept.push(visited); }
		}
		kept.push(key);
		this.history = kept;
		batch((): void => {
			this.commit(list, at);
			if (this.kind === NavigatorKind.Drawer) { this.writeDrawerOpen(false); }
		});
	}

	push(name: string, params: P | null): void {
		if (this.isStack() && this.hasRoute(name)) {
			const list = this.snapshot();
			list.push(this.makeEntry(name, params));
			this.commit(list, (list.length - 1) as int32);
			return;
		}
		if (params === null) {
			let link = this.parent;
			while (link !== null) {
				const current = link as NavigatorLink;
				if (current.pushTo(name)) { return; }
				link = current.parent();
			}
		}
		throw new Error("push: no stack navigator has a screen named '" + name + "'");
	}

	replaceRoute(key: string, name: string, params: P | null): void {
		if (!this.isStack()) {
			this.navigate(name, params);
			return;
		}
		const list = this.snapshot();
		for (let i = 0; i < list.length; i += 1) {
			if (list[i].route.key === key) {
				list[i] = this.makeEntry(name, params);
				const top = (list.length - 1) as int32;
				this.commit(list, top);
				return;
			}
		}
	}

	popCount(count: int32): void {
		const list = this.snapshot();
		const keep = Math.max(1, list.length - count);
		this.popTo((keep - 1) as int32);
	}

	popTo(at: int32): void {
		if (!this.isStack()) { return; }
		const list = this.snapshot();
		if (at >= list.length - 1) { return; }
		this.commit(list.slice(0, at + 1), at);
	}

	resetTo(state: ResetState<P>): void {
		const list: Navigation<P>[] = [];
		for (const route of state.routes) {
			const params = route.params;
			list.push(this.makeEntry(route.name, params === null ? null : params));
		}
		if (list.length === 0) { throw new Error("reset: a navigation state needs at least one route"); }
		const wanted = state.index;
		let at = (list.length - 1) as int32;
		if (wanted !== null) { at = wanted as int32; }
		if (!this.isStack()) {
			const full: Navigation<P>[] = [];
			let focus: int32 = 0;
			for (let i = 0; i < this.screens.length; i += 1) {
				const name = this.screens[i].name;
				let entry: Navigation<P> | null = null;
				for (const given of list) {
					if (given.route.name === name) { entry = given; }
				}
				if (entry === null) { entry = this.makeEntry(name, null); }
				if (name === list[at].route.name) { focus = i as int32; }
				full.push(entry as Navigation<P>);
			}
			this.history = [full[focus].route.key];
			this.commit(full, focus);
			return;
		}
		this.commit(list, at);
	}

	goBackFrom(key: string): boolean {
		if (this.isStack()) {
			const list = this.snapshot();
			if (list.length <= 1) { return false; }
			const kept: Navigation<P>[] = [];
			for (const entry of list) {
				if (entry.route.key !== key) { kept.push(entry); }
			}
			if (kept.length === list.length) { return false; }
			this.commit(kept, (kept.length - 1) as int32);
			return true;
		}
		return this.backLocal();
	}

	canBackLocal(): boolean {
		if (this.isStack()) { return untrack((): Navigation<P>[] => this.entries()).length > 1; }
		if (this.kind === NavigatorKind.Drawer && untrack((): boolean => this.drawerOpen())) { return true; }
		return this.backTarget() >= 0;
	}

	backTarget(): int32 {
		const list = untrack((): Navigation<P>[] => this.entries());
		const at = untrack((): int32 => this.index());
		const behavior = this.backBehavior;
		if (behavior === "none") { return -1; }
		if (behavior === "history") {
			if (this.history.length < 2) { return -1; }
			const previous = this.history[this.history.length - 2];
			for (let i = 0; i < list.length; i += 1) {
				if (list[i].route.key === previous) { return i as int32; }
			}
			return -1;
		}
		let goal: int32 = 0;
		if (behavior === "initialRoute") { goal = this.indexOfName(list, this.initialName); }
		return goal === at || goal < 0 ? -1 : goal;
	}

	backLocal(): boolean {
		if (this.isStack()) {
			const list = this.snapshot();
			if (list.length <= 1) { return false; }
			list.pop();
			this.commit(list, (list.length - 1) as int32);
			return true;
		}
		if (this.kind === NavigatorKind.Drawer && untrack((): boolean => this.drawerOpen())) {
			this.writeDrawerOpen(false);
			return true;
		}
		const goal = this.backTarget();
		if (goal < 0) { return false; }
		if (this.backBehavior === "history") {
			this.history.pop();
			const list = this.snapshot();
			batch((): void => { this.commit(list, goal); });
			return true;
		}
		this.focusIndex(this.snapshot(), goal);
		return true;
	}

	drawerLocal(action: DrawerAction): boolean {
		if (this.kind !== NavigatorKind.Drawer) { return false; }
		const open = untrack((): boolean => this.drawerOpen());
		const next = match (action) {
			DrawerAction.Open => true,
			DrawerAction.Close => false,
			DrawerAction.Toggle => !open,
		};
		this.writeDrawerOpen(next);
		return true;
	}

	navigateTo(target: NavTarget): boolean {
		const screen = this.config(target.name);
		if (screen === null) { return false; }
		const config = screen as ScreenConfig<P>;
		let params: P | null = null;
		const values = target.values;
		const parse = config.parseParams;
		if (values !== null && parse !== null) { params = parse(values as Map<string, string>); }
		this.navigateLocal(target.name, params);
		const child = target.child;
		if (child === null) { return true; }
		const current = this.current();
		if (current === null) { return true; }
		const key = (current as Navigation<P>).route.key;
		for (const entry of this.children) {
			if (entry.routeKey === key) { return entry.link.navigateTo(child as NavTarget); }
		}
		this.pending.push({ routeKey: key, target: child as NavTarget });
		return true;
	}

	register(routeKey: string, child: NavigatorLink): NavTarget | null {
		this.children.push({ routeKey, link: child });
		for (let i = 0; i < this.pending.length; i += 1) {
			if (this.pending[i].routeKey === routeKey) {
				const target = this.pending[i].target;
				this.pending.splice(i, 1);
				return target;
			}
		}
		return null;
	}

	unregister(routeKey: string, child: NavigatorLink): void {
		for (let i = 0; i < this.children.length; i += 1) {
			if (this.children[i].routeKey === routeKey && this.children[i].link === child) {
				this.children.splice(i, 1);
				return;
			}
		}
	}

	focusedChild(): NavigatorLink | null {
		const key = untrack((): string => this.currentKey());
		for (const entry of this.children) {
			if (entry.routeKey === key) { return entry.link; }
		}
		return null;
	}

	handleBack(): boolean {
		const child = this.focusedChild();
		if (child !== null && (child as NavigatorLink).handleBack()) { return true; }
		return this.backLocal();
	}

	state(): NavigationState {
		const list = untrack((): Navigation<P>[] => this.entries());
		const routes: RouteKey[] = [];
		for (const entry of list) { routes.push({ key: entry.route.key, name: entry.route.name }); }
		return { index: untrack((): int32 => this.index()), routeNames: this.routeNames(), routes };
	}

	describe(): string {
		const current = this.current();
		if (current === null) { return ""; }
		const name = (current as Navigation<P>).route.name;
		const child = this.focusedChild();
		return child === null ? name : name + ">" + (child as NavigatorLink).describe();
	}
}

export function linkOf<P>(core: NavigatorCore<P>): NavigatorLink {
	const link: NavigatorLink = {
		kind: core.kind,
		hasRoute: (name: string): boolean => core.hasRoute(name),
		navigateTo: (target: NavTarget): boolean => core.navigateTo(target),
		pushTo: (name: string): boolean => {
			if (!core.isStack() || !core.hasRoute(name)) { return false; }
			core.push(name, null);
			return true;
		},
		backLocal: (): boolean => core.backLocal(),
		canBackLocal: (): boolean => core.canBackLocal(),
		handleBack: (): boolean => core.handleBack(),
		drawerAction: (action: DrawerAction): boolean => core.drawerLocal(action),
		isFocused: accessor((): boolean => core.focused()),
		register: (routeKey: string, child: NavigatorLink): NavTarget | null => core.register(routeKey, child),
		unregister: (routeKey: string, child: NavigatorLink): void => { core.unregister(routeKey, child); },
		focusedChild: (): NavigatorLink | null => core.focusedChild(),
		focusedRoute: (): RouteKey | null => {
			const current = core.current();
			if (current === null) { return null; }
			const route = (current as Navigation<P>).route;
			return { key: route.key, name: route.name };
		},
		parent: (): NavigatorLink | null => core.parent,
		describe: (): string => core.describe(),
	};
	core.link = link;
	return link;
}

export function createCore<P>(setup: NavigatorSetup<P>): NavigatorCore<P> {
	if (setup.screens.length === 0) {
		throw new Error("a navigator needs at least one Screen child");
	}
	const named = setup.initialRouteName;
	let initial = setup.screens[0].name;
	if (named !== null) {
		let found = false;
		for (const screen of setup.screens) {
			if (screen.name === named) { found = true; }
		}
		if (!found) { throw new Error("initialRouteName '" + (named as string) + "' names no Screen"); }
		initial = named as string;
	}
	const empty: Navigation<P>[] = [];
	const [entries, writeEntries] = createSignal<Navigation<P>[]>(empty);
	const [index, writeIndex] = createSignal<int32>(0);
	const [drawerOpen, writeDrawerOpen] = createSignal<boolean>(false);
	const core = new NavigatorCore<P>(
		setup.kind,
		setup.screens,
		entries,
		writeEntries,
		index,
		writeIndex,
		drawerOpen,
		writeDrawerOpen,
		setup.screenOptions,
		setup.backBehavior,
		initial,
		setup.scope,
	);
	const link = linkOf<P>(core);
	core.start(setup.initialParams);
	const scope = setup.scope;
	const waiting = scope.link.register(scope.routeKey, link);
	onCleanup((): void => { scope.link.unregister(scope.routeKey, link); });
	if (waiting !== null) { core.navigateTo(waiting as NavTarget); }
	return core;
}

export function screenScope<P>(core: NavigatorCore<P>, entry: Navigation<P>): ScreenScope {
	const focused = accessor((): boolean => entry.focusedNow());
	return new ScreenScope(core.link as NavigatorLink, entry.route.key, focused, entry as unknown, core.container);
}

export function useNavigation<P>(): Navigation<P> {
	const scope = currentScope("useNavigation");
	if (scope.navigation === null) {
		throw new Error("useNavigation: this component is not inside a screen");
	}
	return scope.navigation as Navigation<P>;
}

export function useRoute<P>(): Route<P> {
	return useNavigation<P>().route;
}

export function useIsFocused(): Accessor<boolean> {
	return currentScope("useIsFocused").focused;
}

export function useFocusEffect(effect: () => (() => void) | null): void {
	const focused = currentScope("useFocusEffect").focused;
	let cleanup: (() => void) | null = null;
	const release = (): void => {
		const done = cleanup;
		cleanup = null;
		if (done !== null) { (done as () => void)(); }
	};
	createEffect((): void => {
		if (focused()) {
			untrack((): void => { cleanup = effect(); });
		} else {
			untrack((): void => { release(); });
		}
	});
	onCleanup(release);
}

export function useLinkTo(): (path: string) => void {
	const container = currentScope("useLinkTo").container;
	return (path: string): void => {
		if (!container.linkTo(path)) { throw new Error("useLinkTo: no screen matches '" + path + "'"); }
	};
}
