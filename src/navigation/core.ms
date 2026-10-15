import { Accessor, Setter, Signal, accessor, createSignal, untrack } from "../core/signal";
import { flush } from "../core/runtime";
import { createEffect, createRenderEffect } from "../core/effect";
import { Cleanup } from "../core/types";
import { createRoot } from "../core/owner";
import { onCleanup } from "../core/cleanup";
import { NeonNode } from "../render/hostTypes";
import { Style } from "../render/style";
import { StackLayout } from "./layout";
import { createContext, useContext } from "../render/context";
import { refreshKeep } from "../render/refresh";

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

export type StackPresentation = "card" | "modal" | "transparentModal";

export type StackAnimation = "default" | "slide_from_right" | "slide_from_bottom" | "fade" | "none";

export type HeaderTitleAlign = "left" | "center";

export interface ScreenOptions {
	title?: string | null;
	presentation?: StackPresentation | null;
	animation?: StackAnimation | null;
	animationDuration?: number | null;
	gestureEnabled?: boolean | null;
	swipeEnabled?: boolean | null;
	headerTitleAlign?: HeaderTitleAlign | null;
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

export function mergeOptions(base: ScreenOptions, over: ScreenOptions): ScreenOptions {
	return {
		title: over.title !== null ? over.title : base.title,
		presentation: over.presentation !== null ? over.presentation : base.presentation,
		animation: over.animation !== null ? over.animation : base.animation,
		animationDuration: over.animationDuration !== null
			? over.animationDuration
			: base.animationDuration,
		gestureEnabled: over.gestureEnabled !== null ? over.gestureEnabled : base.gestureEnabled,
		swipeEnabled: over.swipeEnabled !== null ? over.swipeEnabled : base.swipeEnabled,
		headerTitleAlign: over.headerTitleAlign !== null
			? over.headerTitleAlign
			: base.headerTitleAlign,
		headerShown: over.headerShown !== null ? over.headerShown : base.headerShown,
		headerTitle: over.headerTitle !== null ? over.headerTitle : base.headerTitle,
		headerBackTitle: over.headerBackTitle !== null
			? over.headerBackTitle
			: base.headerBackTitle,
		headerTintColor: over.headerTintColor !== null
			? over.headerTintColor
			: base.headerTintColor,
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

export interface NavigationRoute {
	key: string;
	name: string;
	params: Map<string, string> | null;
	state: NavigationState | null;
}

export interface NavigationState {
	index: int32;
	routeNames: string[];
	routes: NavigationRoute[];
}

export interface NavigatorLink {
	kind: NavigatorKind;
	hasRoute: (name: string) => boolean;
	navigateTo: (target: NavTarget) => boolean;
	pushTo: (name: string) => boolean;
	backLocal: () => boolean;
	canBackLocal: () => boolean;
	canPop: () => boolean;
	popToTop: () => boolean;
	handleBack: () => boolean;
	drawerAction: (action: DrawerAction) => boolean;
	isFocused: Accessor<boolean>;
	register: (routeKey: string, child: NavigatorLink) => NavTarget | null;
	seedFor: (routeKey: string) => NavigationState | null;
	restore: (state: NavigationState) => void;
	unregister: (routeKey: string, child: NavigatorLink) => void;
	focusedChild: () => NavigatorLink | null;
	focusedRoute: () => RouteKey | null;
	state: () => NavigationState;
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

export interface ThemeColors {
	primary: string;
	background: string;
	card: string;
	text: string;
	border: string;
	notification: string;
}

export interface Theme {
	dark: boolean;
	colors: ThemeColors;
}

export const DefaultTheme: Theme = {
	dark: false,
	colors: {
		primary: "#007aff",
		background: "#f2f2f2",
		card: "#ffffff",
		text: "#1c1c1e",
		border: "#d8d8d8",
		notification: "#ff3b30",
	},
};

export const DarkTheme: Theme = {
	dark: true,
	colors: {
		primary: "#0a84ff",
		background: "#010101",
		card: "#121212",
		text: "#e5e5e7",
		border: "#272729",
		notification: "#ff453a",
	},
};

export class ContainerState {
	linkTo: (path: string) => boolean;
	theme: Accessor<Theme>;
	ready: boolean = false;
	changed: () => void = (): void => {};

	constructor(linkTo: (path: string) => boolean, theme: Accessor<Theme>) {
		this.linkTo = linkTo;
		this.theme = theme;
	}
}

export const ScopeContext = createContext<unknown>(null);

export function currentScope(api: string): ScreenScope {
	const value = useContext(ScopeContext);
	if (value === null) {
		throw new Error(
			api + ": no navigator around this component; render it inside NavigationContainer",
		);
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

export function readRegistrationKey(read: Accessor<string> | null): string {
	return read === null ? "[]" : (read as Accessor<string>)();
}

export class ScreenConfig<P> {
	navigationKey: Accessor<string> | null = null;
	name: string;
	component: (props: ScreenProps<P>) => NeonNode;
	options: Accessor<ScreenOptions> | null;
	initialParams: P | null;
	parseParams: ((values: Map<string, string>) => P) | null;
	stringifyParams: ((params: P) => Map<string, string>) | null = null;

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

export type NavigationEvent = "focus" | "blur" | "state" | "beforeRemove" | "tabPress";

export class NavigationAction {
	type: string;
	run: () => void;

	constructor(type: string, run: () => void) {
		this.type = type;
		this.run = run;
	}
}

export class NavigationEventData {
	action: NavigationAction;

	constructor(action: NavigationAction) {
		this.action = action;
	}
}

export class NavigationEventArg {
	type: string;
	target: string;
	data: NavigationEventData;
	defaultPrevented: boolean = false;

	constructor(type: string, target: string, data: NavigationEventData) {
		this.type = type;
		this.target = target;
		this.data = data;
	}

	preventDefault(): void {
		this.defaultPrevented = true;
	}
}

interface EventListener {
	id: int32;
	type: string;
	handler: (event: NavigationEventArg) => void;
}

export function noAction(): void {}

export type Unsubscribe = () => void;

interface ChildEntry {
	routeKey: string;
	link: NavigatorLink;
}

interface PendingEntry {
	routeKey: string;
	target: NavTarget;
}

export interface RouteSeed<P> {
	key: string;
	name: string;
	params: P | null;
}

export function seedKey<P>(seed: RouteSeed<P>): string {
	return seed.key;
}

interface SeedEntry {
	routeKey: string;
	state: NavigationState;
}

interface StateListener {
	id: int32;
	handler: () => void;
}

export class Navigation<P> {
	registrationKey: string;
	revision: Signal<int32> = new Signal<int32>(0);
	core: NavigatorCore<P>;
	route: Route<P>;
	config: ScreenConfig<P>;
	writeParams: Setter<P | null>;
	overrides: Accessor<ScreenOptions>;
	writeOverrides: Setter<ScreenOptions>;

	constructor(
		core: NavigatorCore<P>,
		route: Route<P>,
		config: ScreenConfig<P>,
		writeParams: Setter<P | null>,
		overrides: Accessor<ScreenOptions>,
		writeOverrides: Setter<ScreenOptions>,
	) {
		this.core = core;
		this.registrationKey = readRegistrationKey(config.navigationKey);
		this.route = route;
		this.config = config;
		this.writeParams = writeParams;
		this.overrides = overrides;
		this.writeOverrides = writeOverrides;
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
		this.revision.get();
		const core = this.core;
		const declared = this.config.options;
		const base = declared === null
			? core.screenOptions()
			: mergeOptions(core.screenOptions(), declared());
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

	eventListeners: EventListener[] = [];
	nextEvent: int32 = 1;

	dispatch(action: NavigationAction): void {
		action.run();
	}

	emit(type: string, action: NavigationAction): boolean {
		const event = new NavigationEventArg(type, this.route.key, new NavigationEventData(action));
		for (const listener of this.eventListeners.slice(0, this.eventListeners.length)) {
			if (listener.type === type) { listener.handler(event); }
		}
		return event.defaultPrevented;
	}

	emitBeforeRemove(action: NavigationAction): boolean {
		return this.emit("beforeRemove", action);
	}

	addListener(event: NavigationEvent, handler: (event: NavigationEventArg) => void): Unsubscribe {
		const target = this.route.key;
		const notify = (type: string): void => {
			const data = new NavigationEventData(new NavigationAction("NONE", noAction));
			handler(new NavigationEventArg(type, target, data));
		};
		if (event === "state") {
			return this.core.addStateListener((): void => { notify("state"); });
		}
		if (event === "beforeRemove" || event === "tabPress") {
			const id = this.nextEvent;
			this.nextEvent += 1;
			this.eventListeners.push({ id, type: event as string, handler });
			return (): void => {
				for (let i = 0; i < this.eventListeners.length; i += 1) {
					if (this.eventListeners[i].id === id) {
						this.eventListeners.splice(i, 1);
						return;
					}
				}
			};
		}
		const wantFocus = event === "focus";
		return createRoot((dispose: () => void): Unsubscribe => {
			createRenderEffect<boolean>(
				(prev: boolean | null): boolean => this.focusedNow(),
				(now: boolean, prev: boolean | null): Cleanup | null => {
					if (prev === null || now === (prev as boolean)) { return null; }
					if (now === wantFocus) { notify(event); }
					return null;
				},
			);
			return dispose;
		});
	}
}

export function navigate<P>(
	this navigation: Navigation<P>,
	name: string,
	params: P | null = null,
): void {
	navigation.core.navigate(name, params);
}

export function push<P>(
	this navigation: Navigation<P>,
	name: string,
	params: P | null = null,
): void {
	navigation.core.push(name, params);
}

export function replace<P>(
	this navigation: Navigation<P>,
	name: string,
	params: P | null = null,
): void {
	navigation.core.replaceRoute(navigation.route.key, name, params);
}

export function jumpTo<P>(
	this navigation: Navigation<P>,
	name: string,
	params: P | null = null,
): void {
	navigation.core.navigate(name, params);
}

export function pop<P>(this navigation: Navigation<P>, count: int32 = 1): void {
	navigation.core.popCount(count);
}

export function getParent<P, Q>(this navigation: Navigation<P>): Navigation<Q> {
	const outer = navigation.core.parentNavigation;
	if (outer === null) {
		throw new Error(
			"getParent: the navigator of '" + navigation.route.name + "' is the root navigator",
		);
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

export interface NavigatorModel<P> {
	entries: Accessor<Navigation<P>[]>;
	index: Accessor<int32>;
	arrange: (kept: Navigation<P>[], focused: Navigation<P> | null) => void;
	navigate: (name: string, params: P | null) => void;
	push: (name: string, params: P | null) => boolean;
	replace: (key: string, name: string, params: P | null) => void;
	popTo: (at: int32) => void;
	reset: (list: RouteSeed<P>[], at: int32) => void;
	goBackFrom: (key: string) => boolean;
	canBack: () => boolean;
	back: () => boolean;
	canPop: () => boolean;
	drawer: (action: DrawerAction) => boolean;
}

export interface NavigatorSetup<P> {
	kind: NavigatorKind;
	screens: ScreenConfig<P>[];
	initialRouteName: string | null;
	screenOptions: Accessor<ScreenOptions>;
	scope: ScreenScope;
	model: (
		core: NavigatorCore<P>,
		restored: RouteSeed<P>[] | null,
		at: int32,
	) => NavigatorModel<P>;
}

export class NavigatorCore<P> {
	kind: NavigatorKind;
	screens: ScreenConfig<P>[];
	model: NavigatorModel<P>;
	entries: Accessor<Navigation<P>[]>;
	index: Accessor<int32>;
	screenOptions: Accessor<ScreenOptions>;
	initialName: string;
	parent: NavigatorLink | null;
	parentKey: string;
	focused: Accessor<boolean>;
	parentNavigation: unknown;
	container: ContainerState;
	link: NavigatorLink | null = null;
	children: ChildEntry[] = [];
	pending: PendingEntry[] = [];
	seeds: SeedEntry[] = [];
	listeners: StateListener[] = [];
	nextKey: int32 = 1;
	nextListener: int32 = 1;
	screenEpoch: int32 = 0;
	layout: StackLayout = new StackLayout();

	constructor(setup: NavigatorSetup<P>, initialName: string, restored: NavigationState | null) {
		this.kind = setup.kind;
		this.screens = setup.screens;
		this.screenOptions = setup.screenOptions;
		this.initialName = initialName;
		const scope = setup.scope;
		this.parent = scope.link;
		this.parentKey = scope.routeKey;
		this.focused = scope.focused;
		this.parentNavigation = scope.navigation;
		this.container = scope.container;
		if (restored === null) {
			this.model = setup.model(this, null, 0);
		} else {
			const state = restored as NavigationState;
			const list = this.restoredSeeds(state);
			this.model = setup.model(this, list, this.resetIndex(list, state.index));
		}
		this.entries = this.model.entries;
		this.index = this.model.index;
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

	reconfigure(screens: ScreenConfig<P>[]): void {
		if (screens.length === 0) {
			throw new Error("a navigator needs at least one Screen after a conditional update");
		}
		const previous = this.snapshot();
		let unchanged = screens.length === this.screens.length;
		for (let i = 0; i < screens.length && unchanged; i += 1) {
			if (screens[i] !== this.screens[i]) { unchanged = false; }
		}
		for (const entry of previous) {
			if (entry.registrationKey !== readRegistrationKey(entry.config.navigationKey)) {
				unchanged = false;
			}
		}
		if (unchanged) { return; }
		const focused = this.current();
		this.screens = screens;
		const kept: Navigation<P>[] = [];
		for (const entry of previous) {
			const config = this.config(entry.route.name);
			if (config !== null && entry.registrationKey === readRegistrationKey(config.navigationKey)) {
				entry.config = config as ScreenConfig<P>;
				entry.revision.set(entry.revision.peek() + 1);
				kept.push(entry);
			}
		}
		this.screenEpoch += 1;
		this.model.arrange(kept, focused);
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

	seed(name: string, params: P | null): RouteSeed<P> {
		const screen = this.config(name);
		if (screen === null) {
			throw new Error("navigator has no screen named '" + name + "'");
		}
		const config = screen as ScreenConfig<P>;
		const key = name + "-" + this.nextKey.toString();
		this.nextKey += 1;
		return { key, name, params: params !== null ? params : config.initialParams };
	}

	seedOf(entry: Navigation<P>): RouteSeed<P> {
		return {
			key: entry.route.key,
			name: entry.route.name,
			params: untrack((): P | null => entry.route.params()),
		};
	}

	instantiate(seed: RouteSeed<P>): Navigation<P> {
		const config = this.config(seed.name) as ScreenConfig<P>;
		const name = seed.name;
		const [read, write] = createSignal<P | null>(seed.params);
		const empty: ScreenOptions = {};
		const [overrides, writeOverrides] = createSignal<ScreenOptions>(empty);
		const route = new Route<P>(seed.key, name, read);
		const entry = new Navigation<P>(
			this,
			route,
			config,
			write,
			overrides,
			writeOverrides,
		);
		return entry;
	}

	child(seed: Accessor<RouteSeed<P>>, active: Accessor<boolean>): Navigation<P> {
		return this.instantiate(untrack((): RouteSeed<P> => seed()));
	}

	apply(change: () => void): void {
		flush(change);
	}

	notify(): void {
		for (const listener of this.listeners.slice(0, this.listeners.length)) {
			listener.handler();
		}
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

	routesNow(): ResetState<P> {
		const routes: ResetRoute<P>[] = [];
		for (const entry of this.snapshot()) {
			routes.push({ name: entry.route.name, params: untrack((): P | null => entry.route.params()) });
		}
		return { index: untrack((): int32 => this.index()), routes: routes };
	}

	resumeRoutes(kept: ResetState<P>): void {
		for (const route of kept.routes) {
			if (this.config(route.name) === null) { return; }
		}
		this.resetTo(kept);
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
				"navigate: '" + name + "' is not a screen of this navigator; " +
				"params of this navigator's type" +
				" cannot reach another navigator, use getParent<Q>().navigate",
			);
		}
		const parent = this.parent;
		const target: NavTarget = { name, values: null, child: null };
		if (parent !== null && navigateUp(parent as NavigatorLink, target)) { return; }
		throw new Error("navigate: no navigator has a screen named '" + name + "'");
	}

	bypass: boolean = false;

	guarded(type: string, removed: Navigation<P>[], apply: () => void): boolean {
		if (this.bypass || removed.length === 0) {
			apply();
			return true;
		}
		const action = new NavigationAction(type, (): void => {
			this.bypass = true;
			apply();
			this.bypass = false;
		});
		for (let i = removed.length - 1; i >= 0; i -= 1) {
			if (removed[i].emitBeforeRemove(action)) { return false; }
		}
		apply();
		return true;
	}

	navigateLocal(name: string, params: P | null): void {
		this.model.navigate(name, params);
	}

	push(name: string, params: P | null): void {
		if (this.hasRoute(name) && this.model.push(name, params)) { return; }
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
		this.model.replace(key, name, params);
	}

	popCount(count: int32): void {
		const keep = Math.max(1, this.snapshot().length - count);
		this.popTo((keep - 1) as int32);
	}

	popTo(at: int32): void {
		this.model.popTo(at);
	}

	resetIndex(list: RouteSeed<P>[], wanted: int32 | null): int32 {
		if (list.length === 0) {
			throw new Error("reset: a navigation state needs at least one route");
		}
		const at = wanted === null ? (list.length - 1) as int32 : wanted as int32;
		if (at < 0 || at >= list.length) {
			throw new Error(
				"reset: index " + at.toString() +
				" is outside " + list.length.toString() + " routes",
			);
		}
		return at;
	}

	resetTo(state: ResetState<P>): void {
		const list: RouteSeed<P>[] = [];
		for (const route of state.routes) {
			const params = route.params;
			list.push(this.seed(route.name, params === null ? null : params));
		}
		this.model.reset(list, this.resetIndex(list, state.index));
	}

	goBackFrom(key: string): boolean {
		return this.model.goBackFrom(key);
	}

	canBackLocal(): boolean {
		return this.model.canBack();
	}

	backLocal(): boolean {
		return this.model.back();
	}

	drawerLocal(action: DrawerAction): boolean {
		return this.model.drawer(action);
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

	seedFor(routeKey: string): NavigationState | null {
		for (let i = 0; i < this.seeds.length; i += 1) {
			if (this.seeds[i].routeKey === routeKey) {
				const state = this.seeds[i].state;
				this.seeds.splice(i, 1);
				return state;
			}
		}
		return null;
	}

	restoredSeeds(state: NavigationState): RouteSeed<P>[] {
		const list: RouteSeed<P>[] = [];
		for (const route of state.routes) {
			const screen = this.config(route.name);
			if (screen === null) {
				throw new Error("initialState: no screen named '" + route.name + "'");
			}
			const parse = (screen as ScreenConfig<P>).parseParams;
			const values = route.params;
			let params: P | null = null;
			if (values !== null) {
				if (parse === null) {
					throw new Error("initialState: screen '" + route.name + "' has params but no parseParams");
				}
				params = (parse as (values: Map<string, string>) => P)(values as Map<string, string>);
			}
			list.push({ key: "", name: route.name, params });
		}
		for (let i = 0; i < list.length; i += 1) {
			list[i] = this.seed(list[i].name, list[i].params);
			const child = state.routes[i].state;
			if (child !== null) {
				this.seeds.push({ routeKey: list[i].key, state: child as NavigationState });
			}
		}
		return list;
	}

	restore(state: NavigationState): void {
		const list = this.restoredSeeds(state);
		this.model.reset(list, this.resetIndex(list, state.index));
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

	repressFocused(): void {
		const child = this.focusedChild();
		if (child !== null) { (child as NavigatorLink).popToTop(); }
	}

	handleBack(): boolean {
		const child = this.focusedChild();
		if (child !== null && (child as NavigatorLink).handleBack()) { return true; }
		return this.backLocal();
	}

	state(): NavigationState {
		return untrack((): NavigationState => this.trackedState());
	}

	trackedState(): NavigationState {
		const routes: NavigationRoute[] = [];
		for (const entry of this.entries()) {
			const key = entry.route.key;
			let child: NavigationState | null = null;
			for (const each of this.children) {
				if (each.routeKey === key) { child = each.link.state(); }
			}
			routes.push({ key, name: entry.route.name, params: this.encodeParams(entry), state: child });
		}
		return { index: this.index(), routeNames: this.routeNames(), routes };
	}

	encodeParams(entry: Navigation<P>): Map<string, string> | null {
		const write = entry.config.stringifyParams;
		const params = entry.route.params();
		if (write === null || params === null) { return null; }
		return (write as (params: P) => Map<string, string>)(params as P);
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
		pushTo: (name: string): boolean => core.hasRoute(name) && core.model.push(name, null),
		backLocal: (): boolean => core.backLocal(),
		canBackLocal: (): boolean => core.canBackLocal(),
		canPop: (): boolean => core.model.canPop(),
		popToTop: (): boolean => {
			if (!untrack((): boolean => core.model.canPop())) { return false; }
			core.popTo(0);
			return true;
		},
		handleBack: (): boolean => core.handleBack(),
		drawerAction: (action: DrawerAction): boolean => core.drawerLocal(action),
		isFocused: accessor((): boolean => core.focused()),
		register: (routeKey: string, child: NavigatorLink): NavTarget | null => {
			return core.register(routeKey, child);
		},
		seedFor: (routeKey: string): NavigationState | null => core.seedFor(routeKey),
		restore: (state: NavigationState): void => core.restore(state),
		unregister: (routeKey: string, child: NavigatorLink): void => {
			core.unregister(routeKey, child);
		},
		focusedChild: (): NavigatorLink | null => core.focusedChild(),
		focusedRoute: (): RouteKey | null => {
			const current = core.current();
			if (current === null) { return null; }
			const route = (current as Navigation<P>).route;
			return { key: route.key, name: route.name };
		},
		state: (): NavigationState => core.trackedState(),
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
		if (!found) {
			throw new Error("initialRouteName '" + (named as string) + "' names no Screen");
		}
		initial = named as string;
	}
	const scope = setup.scope;
	const core = new NavigatorCore<P>(setup, initial, scope.link.seedFor(scope.routeKey));
	flush();
	const link = linkOf<P>(core);
	core.notify();
	core.container.changed();
	createEffect<boolean>(
		(prev: boolean | null): boolean => {
			core.entries();
			core.index();
			return true;
		},
		(changed: boolean, prev: boolean | null): Cleanup | null => {
			core.notify();
			core.container.changed();
			return null;
		},
		{ defer: true },
	);
	when (refresh || hcr) {
		refreshKeep<ResetState<P>>(
			"navigator",
			(): ResetState<P> => core.routesNow(),
			(kept: ResetState<P>): void => { core.resumeRoutes(kept); },
		);
	}
	const waiting = scope.link.register(scope.routeKey, link);
	onCleanup((): void => { scope.link.unregister(scope.routeKey, link); });
	if (waiting !== null) { core.navigateTo(waiting as NavTarget); }
	return core;
}

export function screenScope<P>(core: NavigatorCore<P>, entry: Navigation<P>): ScreenScope {
	const focused = accessor((): boolean => entry.focusedNow());
	const link = core.link as NavigatorLink;
	return new ScreenScope(link, entry.route.key, focused, entry as unknown, core.container);
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

export function useNavigationState<T>(selector: (state: NavigationState) => T): Accessor<T> {
	const link = currentScope("useNavigationState").link;
	return accessor((): T => selector(link.state()));
}

export function useFocusEffect(effect: () => Cleanup | null): void {
	const focused = currentScope("useFocusEffect").focused;
	createRenderEffect<boolean>(
		(prev: boolean | null): boolean => focused(),
		(isFocused: boolean, prev: boolean | null): Cleanup | null => {
			if (isFocused) { return effect(); }
			return null;
		},
	);
}

export function useTheme(): Accessor<Theme> {
	return currentScope("useTheme").container.theme;
}

export function useLinkTo(): (path: string) => void {
	const container = currentScope("useLinkTo").container;
	return (path: string): void => {
		if (!container.linkTo(path)) {
			throw new Error("useLinkTo: no screen matches '" + path + "'");
		}
	};
}
