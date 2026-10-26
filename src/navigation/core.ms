import { Accessor, Setter, Signal, accessor, createSignal, untrack } from "../core/signal";
import { flush } from "../core/runtime";
import { createEffect, createRenderEffect, onSettled } from "../core/effect";
import { Cleanup } from "../core/types";
import { createRoot } from "../core/owner";
import { onCleanup } from "../core/cleanup";
import { NeonNode } from "../render/hostTypes";
import { Style } from "../render/style";
import { StackLayout } from "./layout";
import { StackPresentation } from "./childView";
import { createContext, useContext } from "../render/context";
when (refresh || hcr) { import { refreshKeep } from "../render/refresh"; }
import {
	WebKeySerializer,
	WebNavigationError,
	WebNavigationNode,
	WebNavigationOwner,
} from "./webNavigation";

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

export const DRAWER_OPEN_KEY = "drawer-open";

export interface TabBarIconProps {
	focused: boolean;
	color: string;
	size: number;
}


export type StackAnimation = "default" | "slide_from_right" | "slide_from_bottom" | "fade" | "none";

export type DrawerType = "front" | "slide";

export type HeaderTitleAlign = "left" | "center";

export interface HeaderItemProps {
	tintColor: string;
	canGoBack: boolean;
}

export interface HeaderTitleProps {
	children: string;
	tintColor: string;
}

export interface ScreenOptions {
	title?: string | null;
	presentation?: StackPresentation | null;
	animation?: StackAnimation | null;
	animationDuration?: number | null;
	gestureEnabled?: boolean | null;
	swipeEnabled?: boolean | null;
	headerTitleAlign?: HeaderTitleAlign | null;
	headerShown?: boolean | null;
	headerTitle?: string | ((props: HeaderTitleProps) => NeonNode) | null;
	headerBackTitle?: string | null;
	headerTintColor?: string | null;
	headerStyle?: Style | null;
	headerBackVisible?: boolean | null;
	headerLeft?: ((props: HeaderItemProps) => NeonNode) | null;
	headerRight?: ((props: HeaderItemProps) => NeonNode) | null;
	contentStyle?: Style | null;
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
	popToTopOnBlur?: boolean | null;
	drawerType?: DrawerType | null;
	overlayColor?: string | null;
	swipeEdgeWidth?: number | null;
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
		headerBackVisible: over.headerBackVisible !== null
			? over.headerBackVisible
			: base.headerBackVisible,
		contentStyle: over.contentStyle !== null ? over.contentStyle : base.contentStyle,
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
		drawerType: over.drawerType !== null ? over.drawerType : base.drawerType,
		overlayColor: over.overlayColor !== null ? over.overlayColor : base.overlayColor,
		swipeEdgeWidth: over.swipeEdgeWidth !== null ? over.swipeEdgeWidth : base.swipeEdgeWidth,
		popToTopOnBlur: over.popToTopOnBlur !== null ? over.popToTopOnBlur : base.popToTopOnBlur,
	};
}

export interface NavTarget {
	name: string;
	values: Map<string, string> | null;
	child: NavTarget | null;
	pop: boolean;
}

export interface NavigateActionOptions {
	pop?: boolean | null;
}

export function reportUnhandled(type: string, name: string | null): void {
	when (debug) {
		let message = "The action '" + type + "'";
		if (name !== null) { message += " with payload {\"name\":\"" + (name as string) + "\"}"; }
		message += " was not handled by any navigator.";
		if (type === "NAVIGATE" || type === "PUSH" || type === "REPLACE" || type === "JUMP_TO") {
			message += "\n\nDo you have a route named '" + (name ?? "") + "'?";
		} else if (type === "GO_BACK" || type === "POP" || type === "POP_TO_TOP") {
			message += "\n\nIs there any screen to go back to?";
		} else if (type === "OPEN_DRAWER" || type === "CLOSE_DRAWER" || type === "TOGGLE_DRAWER") {
			message += "\n\nIs your screen inside a Drawer navigator?";
		}
		console.error(message + "\n\nThis is a development-only warning and won't be shown in production.");
	}
}

export function drawerActionType(action: DrawerAction): string {
	if (action === DrawerAction.Open) { return "OPEN_DRAWER"; }
	if (action === DrawerAction.Close) { return "CLOSE_DRAWER"; }
	return "TOGGLE_DRAWER";
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

export interface WebRoutes {
	path: (name: string, values: Map<string, string> | null) => string | null;
	parameters: (
		routeKey: string,
		name: string,
		values: Map<string, string> | null,
	) => Map<string, string> | null;
	child: (routeKey: string, name: string) => WebNavigationOwner | null;
}

export interface NavigatorLink {
	kind: NavigatorKind;
	hasRoute: (name: string) => boolean;
	navigateTo: (target: NavTarget) => boolean;
	pushTo: (name: string) => boolean;
	popToRoute: (name: string) => boolean;
	backLocal: () => boolean;
	canBackLocal: () => boolean;
	canPop: () => boolean;
	popToTop: () => boolean;
	popBy: (count: int32) => boolean;
	replaceTo: (name: string) => boolean;
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
	webNavigation: (routes: WebRoutes) => WebNavigationNode;
	screen: () => unknown;
	nested: (routeKey: string) => NavigatorLink | null;
	prevents: (action: NavigationAction) => boolean;
	focusedOptions: () => ScreenOptions | null;
	seedNested: (routeKey: string, state: NavigationState | null) => void;
}

export interface SeedRoute {
	key: string;
	name: string;
	params: Map<string, string> | null;
}

struct SeedKey {
	key: string;
	name: string;
	hasParams: boolean;
	paramPairs: string[];
}

export function encodeSeedRoute(route: SeedRoute): string {
	const paramPairs: string[] = [];
	const values = route.params;
	if (values !== null) {
		for (const key of values as Map<string, string>) {
			paramPairs.push(key);
			paramPairs.push((values as Map<string, string>).get(key) ?? "");
		}
	}
	const stored: SeedKey = { key: route.key, name: route.name, hasParams: values !== null, paramPairs };
	return JSON.stringify(stored);
}

export function decodeSeedRoute(text: string): SeedRoute | null {
	const parsed = JSON.parse<SeedKey>(text);
	if (!parsed.ok) { return null; }
	const stored = parsed.value;
	if (stored.name === "" || stored.paramPairs.length % 2 !== 0) { return null; }
	let params: Map<string, string> | null = null;
	if (stored.hasParams) {
		const values = new Map<string, string>();
		for (let i = 0; i < stored.paramPairs.length; i += 2) {
			values.set(stored.paramPairs[i], stored.paramPairs[i + 1]);
		}
		params = values;
	}
	return { key: stored.key, name: stored.name, params };
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

export class ParamBox<T> {
	value: T;

	constructor(value: T) {
		this.value = value;
	}
}

export class ParamSlot {
	box: unknown;

	constructor(box: unknown) {
		this.box = box;
	}
}

export function boxParams<T>(value: T): ParamSlot {
	return new ParamSlot(new ParamBox<T>(value) as unknown);
}

export function slotOf<T>(value: T | null): ParamSlot | null {
	return value === null ? null : boxParams<T>(value as T);
}

export class Route {
	key: string;
	name: string;
	slot: Accessor<ParamSlot | null>;
	writeSlot: (slot: ParamSlot | null) => void;

	constructor(key: string, name: string, slot: Accessor<ParamSlot | null>, writeSlot: (slot: ParamSlot | null) => void) {
		this.key = key;
		this.name = name;
		this.slot = slot;
		this.writeSlot = writeSlot;
	}
}

export interface RouteProp<PL, K extends keyof PL> {
	key: string;
	name: string;
	params: Accessor<PL[K] | null>;
	setParams: (params: Partial<Exclude<PL[K], null>>) => void;
	replaceParams: (params: PL[K]) => void;
}

export function routeProp<PL, K extends keyof PL>(route: Route): RouteProp<PL, K> {
	return {
		key: route.key,
		name: route.name,
		params: accessor((): PL[K] | null => {
			const slot = route.slot();
			return slot === null ? null : ((slot as ParamSlot).box as ParamBox<PL[K]>).value;
		}),
		setParams: (patch: Partial<Exclude<PL[K], null>>): void => {
			const slot = route.slot();
			if (slot === null) {
				throw new Error("setParams: route '" + route.name + "' holds no params to merge into; use replaceParams");
			}
			const base = ((slot as ParamSlot).box as ParamBox<PL[K]>).value as Exclude<PL[K], null>;
			const merged: Exclude<PL[K], null> = { ...base, ...patch };
			route.writeSlot(boxParams<PL[K]>(merged as PL[K]));
		},
		replaceParams: (params: PL[K]): void => { route.writeSlot(boxParams<PL[K]>(params)); },
	};
}

export interface ScreenProps<PL> {
	navigation: Navigation<PL>;
	route: Route;
}

export function readRegistrationKey(read: Accessor<string> | null): string {
	return read === null ? "[]" : (read as Accessor<string>)();
}

export class ScreenConfig<PL> {
	navigationKey: Accessor<string> | null = null;
	name: string;
	component: (props: ScreenProps<PL>) => NeonNode;
	options: Accessor<ScreenOptions> | null;
	initialParams: ParamSlot | null;
	parseParams: ((values: Map<string, string>) => ParamSlot | null) | null;
	stringifyParams: ((params: ParamSlot | null) => Map<string, string>) | null = null;

	constructor(
		name: string,
		component: (props: ScreenProps<PL>) => NeonNode,
		options: Accessor<ScreenOptions> | null,
		initialParams: ParamSlot | null,
		parseParams: ((values: Map<string, string>) => ParamSlot | null) | null,
	) {
		this.name = name;
		this.component = component;
		this.options = options;
		this.initialParams = initialParams;
		this.parseParams = parseParams;
	}
}

export interface ScreenCodec<PL, K extends keyof PL> {
	initial?: PL[K] | null;
	parse?: ((values: Map<string, string>) => PL[K]) | null;
	stringify?: ((params: PL[K]) => Map<string, string>) | null;
}

export class ScreenParams<PL> {
	name: string;
	initial: ParamSlot | null;
	parse: ((values: Map<string, string>) => ParamSlot | null) | null;
	stringify: ((params: ParamSlot | null) => Map<string, string>) | null;

	constructor(
		name: string,
		initial: ParamSlot | null,
		parse: ((values: Map<string, string>) => ParamSlot | null) | null,
		stringify: ((params: ParamSlot | null) => Map<string, string>) | null,
	) {
		this.name = name;
		this.initial = initial;
		this.parse = parse;
		this.stringify = stringify;
	}
}

export class ScreenParamsBuilder<PL> {
	of<K extends keyof PL>(name: K, codec: ScreenCodec<PL, K>): ScreenParams<PL> {
		const initial = codec.initial;
		const parse = codec.parse;
		const stringify = codec.stringify;
		return new ScreenParams<PL>(
			name as string,
			initial === undefined || initial === null ? null : boxParams<PL[K]>(initial as PL[K]),
			parse === undefined || parse === null
				? null
				: (values: Map<string, string>): ParamSlot | null => boxParams<PL[K]>((parse as (values: Map<string, string>) => PL[K])(values)),
			stringify === undefined || stringify === null
				? null
				: (slot: ParamSlot | null): Map<string, string> => (stringify as (params: PL[K]) => Map<string, string>)(((slot as ParamSlot).box as ParamBox<PL[K]>).value),
		);
	}
}

export interface ResetRoute<PL> {
	name: string;
	slot: ParamSlot | null;
}

export interface ResetState<PL> {
	index?: int32 | null;
	routes: ResetRoute<PL>[];
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
	state: NavigationState | null;

	constructor(action: NavigationAction, state: NavigationState | null = null) {
		this.action = action;
		this.state = state;
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

export interface RouteSeed<PL> {
	key: string;
	name: string;
	params: ParamSlot | null;
}

export function seedKey<PL>(seed: RouteSeed<PL>): string {
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

export type ParamsArgs<PL, K extends keyof PL> = null extends PL[K]
	? [name: K, params?: PL[K]]
	: [name: K, params: PL[K]];

export type NavigateArgs<PL, K extends keyof PL> = null extends PL[K]
	? [name: K, params?: PL[K], options?: NavigateActionOptions]
	: [name: K, params: PL[K], options?: NavigateActionOptions];

export class Navigation<PL> {
	registrationKey: string;
	revision: Signal<int32> = new Signal<int32>(0);
	core: NavigatorCore<PL>;
	route: Route;
	config: ScreenConfig<PL>;
	writeParams: Setter<ParamSlot | null>;
	private overrides: Accessor<ScreenOptions>;
	private writeOverrides: Setter<ScreenOptions>;

	constructor(
		core: NavigatorCore<PL>,
		route: Route,
		config: ScreenConfig<PL>,
		writeParams: Setter<ParamSlot | null>,
		overrides: Accessor<ScreenOptions>,
		writeOverrides: Setter<ScreenOptions>,
	) {
		this.core = core;
		this.registrationKey = untrack((): string => readRegistrationKey(config.navigationKey));
		this.route = route;
		this.config = config;
		this.writeParams = writeParams;
		this.overrides = overrides;
		this.writeOverrides = writeOverrides;
	}

	navigate<K extends keyof PL>(...args: NavigateArgs<PL, K>): void {
		const options = args[2];
		const pop = options === null ? false : (options as NavigateActionOptions).pop ?? false;
		this.core.navigate(args[0] as string, slotOf<PL[K]>(args[1]), pop);
	}

	push<K extends keyof PL>(...args: ParamsArgs<PL, K>): void {
		this.core.push(args[0] as string, slotOf<PL[K]>(args[1]));
	}

	replace<K extends keyof PL>(...args: ParamsArgs<PL, K>): void {
		this.core.replaceRoute(this.route.key, args[0] as string, slotOf<PL[K]>(args[1]));
	}

	jumpTo<K extends keyof PL>(...args: ParamsArgs<PL, K>): void {
		this.core.navigate(args[0] as string, slotOf<PL[K]>(args[1]));
	}

	pop(count: int32 = 1): void {
		this.core.popCount(count);
	}

	goBack(): void {
		const core = this.core;
		if (core.goBackFrom(this.route.key)) { return; }
		const parent = core.parent;
		if (parent !== null && goBackUp(parent as NavigatorLink)) { return; }
		reportUnhandled("GO_BACK", null);
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
		this.core.popToTopFrom();
	}

	popTo<K extends keyof PL>(...args: ParamsArgs<PL, K>): void {
		this.core.popToRoute(args[0] as string, slotOf<PL[K]>(args[1]), this.route.key);
	}

	routeOf<K extends keyof PL>(...args: ParamsArgs<PL, K>): ResetRoute<PL> {
		return { name: args[0] as string, slot: slotOf<PL[K]>(args[1]) };
	}

	reset(state: ResetState<PL>): void {
		this.core.resetTo(state);
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
		reportUnhandled(drawerActionType(action), null);
	}

	private eventListeners: EventListener[] = [];
	private nextEvent: int32 = 1;

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
			const state = type === "state" ? untrack((): NavigationState => this.core.state()) : null;
			const data = new NavigationEventData(new NavigationAction("NONE", noAction), state);
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
			if (wantFocus) {
				onSettled((): Cleanup | null => {
					if (this.isFocused()) { notify(event); }
					return null;
				});
			}
			return dispose;
		});
	}
}

export function getParent<PL, Q>(this navigation: Navigation<PL>): Navigation<Q> {
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

export interface NavigatorModel<PL> {
	entries: Accessor<Navigation<PL>[]>;
	index: Accessor<int32>;
	arrange: (kept: Navigation<PL>[], focused: Navigation<PL> | null) => void;
	navigate: (name: string, params: ParamSlot | null, pop: boolean) => void;
	push: (name: string, params: ParamSlot | null) => boolean;
	popToRoute: (name: string, params: ParamSlot | null, source: string | null) => boolean;
	replace: (key: string, name: string, params: ParamSlot | null) => void;
	popTo: (at: int32, type: string) => void;
	reset: (list: RouteSeed<PL>[], at: int32) => void;
	goBackFrom: (key: string) => boolean;
	canBack: () => boolean;
	back: () => boolean;
	canPop: () => boolean;
	drawer: (action: DrawerAction) => boolean;
	webNavigation: (map: RouteWebMap<PL>) => WebNavigationNode;
}

export interface RouteWebMap<PL> {
	serializer: WebKeySerializer<RouteSeed<PL>>;
	path: (entry: Navigation<PL>) => string | null;
	parameters: (entry: Navigation<PL>) => Map<string, string> | null;
	child: (entry: Navigation<PL>) => WebNavigationOwner | null;
}

export interface NavigatorSetup<PL> {
	kind: NavigatorKind;
	screens: ScreenConfig<PL>[];
	initialRouteName: string | null;
	screenOptions: Accessor<ScreenOptions>;
	scope: ScreenScope;
	model: (
		core: NavigatorCore<PL>,
		restored: RouteSeed<PL>[] | null,
		at: int32,
	) => NavigatorModel<PL>;
}

export class NavigatorCore<PL> {
	kind: NavigatorKind;
	screens: ScreenConfig<PL>[];
	model: NavigatorModel<PL>;
	entries: Accessor<Navigation<PL>[]>;
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

	constructor(setup: NavigatorSetup<PL>, initialName: string, restored: NavigationState | null) {
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

	config(name: string): ScreenConfig<PL> | null {
		for (const screen of this.screens) {
			if (screen.name === name) { return screen; }
		}
		return null;
	}

	hasRoute(name: string): boolean {
		return this.config(name) !== null;
	}

	reconfigure(screens: ScreenConfig<PL>[]): void {
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
		const kept: Navigation<PL>[] = [];
		for (const entry of previous) {
			const config = this.config(entry.route.name);
			if (config !== null && entry.registrationKey === readRegistrationKey(config.navigationKey)) {
				entry.config = config as ScreenConfig<PL>;
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

	current(): Navigation<PL> | null {
		const list = untrack((): Navigation<PL>[] => this.entries());
		const at = untrack((): int32 => this.index());
		return at >= 0 && at < list.length ? list[at] : null;
	}

	seed(name: string, params: ParamSlot | null): RouteSeed<PL> {
		const screen = this.config(name);
		if (screen === null) {
			throw new Error("navigator has no screen named '" + name + "'");
		}
		const config = screen as ScreenConfig<PL>;
		const key = name + "-" + this.nextKey.toString();
		this.nextKey += 1;
		return { key, name, params: params !== null ? params : config.initialParams };
	}

	adopt(key: string, name: string, params: ParamSlot | null): RouteSeed<PL> {
		if (key === "") { return this.seed(name, params); }
		const screen = this.config(name);
		if (screen === null) {
			throw new Error("navigator has no screen named '" + name + "'");
		}
		const dash = key.lastIndexOf("-");
		if (dash >= 0) {
			const counted = parseInt(key.substring(dash + 1, key.length));
			if (counted >= this.nextKey) { this.nextKey = (counted + 1) as int32; }
		}
		return {
			key,
			name,
			params: params !== null ? params : (screen as ScreenConfig<PL>).initialParams,
		};
	}

	seedSerializer(): WebKeySerializer<RouteSeed<PL>> {
		return {
			encode: (seed: RouteSeed<PL>): string => {
				for (const entry of this.snapshot()) {
					if (entry.route.key === seed.key) {
						return encodeSeedRoute({
							key: seed.key,
							name: seed.name,
							params: this.encodeParams(entry),
						});
					}
				}
				throw new Error("web history: no live route has the key " + seed.key);
			},
			decode: (text: string): Result<RouteSeed<PL>, WebNavigationError> => {
				const route = decodeSeedRoute(text);
				if (route === null) { return Result.err(WebNavigationError.UndecodableKey); }
				const stored = route as SeedRoute;
				const screen = this.config(stored.name);
				if (screen === null) { return Result.err(WebNavigationError.UndecodableKey); }
				const values = stored.params;
				let params: ParamSlot | null = null;
				if (values !== null) {
					const parse = (screen as ScreenConfig<PL>).parseParams;
					if (parse === null) { return Result.err(WebNavigationError.UndecodableKey); }
					params = (parse as (values: Map<string, string>) => ParamSlot | null)(values as Map<string, string>);
				}
				return Result.ok(this.adopt(stored.key, stored.name, params));
			},
		};
	}

	webNavigation(routes: WebRoutes): WebNavigationNode {
		const values = (entry: Navigation<PL>): Map<string, string> | null => this.encodeParams(entry);
		return this.model.webNavigation({
			serializer: this.seedSerializer(),
			path: (entry: Navigation<PL>): string | null => {
				return routes.path(entry.route.name, values(entry));
			},
			parameters: (entry: Navigation<PL>): Map<string, string> | null => {
				return routes.parameters(entry.route.key, entry.route.name, values(entry));
			},
			child: (entry: Navigation<PL>): WebNavigationOwner | null => {
				return routes.child(entry.route.key, entry.route.name);
			},
		});
	}

	seedOf(entry: Navigation<PL>): RouteSeed<PL> {
		return {
			key: entry.route.key,
			name: entry.route.name,
			params: untrack((): ParamSlot | null => entry.route.slot()),
		};
	}

	instantiate(seed: RouteSeed<PL>): Navigation<PL> {
		const config = this.config(seed.name) as ScreenConfig<PL>;
		const name = seed.name;
		const [read, write] = createSignal<ParamSlot | null>(seed.params);
		const empty: ScreenOptions = {};
		const [overrides, writeOverrides] = createSignal<ScreenOptions>(empty, { ownedWrite: true });
		const route = new Route(seed.key, name, read, (slot: ParamSlot | null): void => {
			write(slot);
			this.container.changed();
		});
		const entry = new Navigation<PL>(
			this,
			route,
			config,
			write,
			overrides,
			writeOverrides,
		);
		return entry;
	}

	child(seed: Accessor<RouteSeed<PL>>, active: Accessor<boolean>): Navigation<PL> {
		return this.instantiate(untrack((): RouteSeed<PL> => seed()));
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

	snapshot(): Navigation<PL>[] {
		const list = untrack((): Navigation<PL>[] => this.entries());
		return list.slice(0, list.length);
	}

	routesNow(): ResetState<PL> {
		const routes: ResetRoute<PL>[] = [];
		for (const entry of this.snapshot()) {
			routes.push({ name: entry.route.name, slot: untrack((): ParamSlot | null => entry.route.slot()) });
		}
		return { index: untrack((): int32 => this.index()), routes: routes };
	}

	resumeRoutes(kept: ResetState<PL>): void {
		for (const route of kept.routes) {
			if (this.config(route.name) === null) { return; }
		}
		this.resetTo(kept);
	}

	indexOfName(list: Navigation<PL>[], name: string): int32 {
		for (let i = list.length - 1; i >= 0; i -= 1) {
			if (list[i].route.name === name) { return i as int32; }
		}
		return -1;
	}

	navigate(name: string, params: ParamSlot | null, pop: boolean = false): void {
		if (this.hasRoute(name)) {
			this.navigateLocal(name, params, pop);
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
		const target: NavTarget = { name, values: null, child: null, pop };
		if (parent !== null && navigateUp(parent as NavigatorLink, target)) { return; }
		reportUnhandled("NAVIGATE", name);
	}

	bypass: boolean = false;

	allows(type: string, removed: Navigation<PL>[], apply: () => void): boolean {
		if (this.bypass || removed.length === 0) { return true; }
		const action = new NavigationAction(type, (): void => {
			this.bypass = true;
			apply();
			this.bypass = false;
		});
		for (let i = removed.length - 1; i >= 0; i -= 1) {
			if (this.asksRemoval(removed[i], action)) { return false; }
		}
		return true;
	}

	asksRemoval(route: Navigation<PL>, action: NavigationAction): boolean {
		for (const entry of this.children) {
			if (entry.routeKey !== route.route.key) { continue; }
			if (entry.link.prevents(action)) { return true; }
		}
		return route.emitBeforeRemove(action);
	}

	preventsAll(action: NavigationAction): boolean {
		const list = this.snapshot();
		for (let i = list.length - 1; i >= 0; i -= 1) {
			if (this.asksRemoval(list[i], action)) { return true; }
		}
		return false;
	}

	guarded(type: string, removed: Navigation<PL>[], apply: () => void): boolean {
		if (!this.allows(type, removed, apply)) { return false; }
		apply();
		return true;
	}

	navigateLocal(name: string, params: ParamSlot | null, pop: boolean = false): void {
		this.model.navigate(name, params, pop);
	}

	push(name: string, params: ParamSlot | null): void {
		if (this.hasRoute(name) && this.model.push(name, params)) { return; }
		if (params === null) {
			let link = this.parent;
			while (link !== null) {
				const current = link as NavigatorLink;
				if (current.pushTo(name)) { return; }
				link = current.parent();
			}
		}
		reportUnhandled("PUSH", name);
	}

	popToRoute(name: string, params: ParamSlot | null, source: string): void {
		if (this.hasRoute(name) && this.model.popToRoute(name, params, source)) { return; }
		if (params === null) {
			let link = this.parent;
			while (link !== null) {
				const current = link as NavigatorLink;
				if (current.popToRoute(name)) { return; }
				link = current.parent();
			}
		}
		reportUnhandled("POP_TO", name);
	}

	replaceRoute(key: string, name: string, params: ParamSlot | null): void {
		if (this.hasRoute(name)) {
			this.model.replace(key, name, params);
			return;
		}
		if (params !== null) {
			throw new Error(
				"replace: '" + name + "' is not a screen of this navigator; " +
				"params of this navigator's type" +
				" cannot reach another navigator, use getParent<Q>().replace",
			);
		}
		let link = this.parent;
		while (link !== null) {
			const current = link as NavigatorLink;
			if (current.replaceTo(name)) { return; }
			link = current.parent();
		}
		throw new Error("The action 'REPLACE' with payload {\"name\":\"" + name + "\"} was not handled by any navigator");
	}

	popCount(count: int32): void {
		if (untrack((): boolean => this.model.canPop())) {
			this.popLocal(count);
			return;
		}
		let link = this.parent;
		while (link !== null) {
			const current = link as NavigatorLink;
			if (current.popBy(count)) { return; }
			link = current.parent();
		}
		reportUnhandled("POP", null);
	}

	popLocal(count: int32): void {
		const keep = Math.max(1, this.snapshot().length - count);
		this.popTo((keep - 1) as int32, "POP");
	}

	popToTopFrom(): void {
		if (untrack((): boolean => this.model.canPop())) {
			this.popTo(0, "POP_TO_TOP");
			return;
		}
		let link = this.parent;
		while (link !== null) {
			const current = link as NavigatorLink;
			if (current.popToTop()) { return; }
			link = current.parent();
		}
		reportUnhandled("POP_TO_TOP", null);
	}

	popTo(at: int32, type: string): void {
		this.model.popTo(at, type);
	}

	resetIndex(list: RouteSeed<PL>[], wanted: int32 | null): int32 {
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

	resetTo(state: ResetState<PL>): void {
		const list: RouteSeed<PL>[] = [];
		for (const route of state.routes) {
			list.push(this.seed(route.name, route.slot));
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
		const config = screen as ScreenConfig<PL>;
		let params: ParamSlot | null = null;
		const values = target.values;
		const parse = config.parseParams;
		if (values !== null && parse !== null) { params = parse(values as Map<string, string>); }
		this.navigateLocal(target.name, params, target.pop);
		const child = target.child;
		if (child === null) { return true; }
		const current = this.current();
		if (current === null) { return true; }
		const key = (current as Navigation<PL>).route.key;
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

	restoredSeeds(state: NavigationState): RouteSeed<PL>[] {
		const list: RouteSeed<PL>[] = [];
		for (const route of state.routes) {
			const screen = this.config(route.name);
			if (screen === null) {
				throw new Error("initialState: no screen named '" + route.name + "'");
			}
			const parse = (screen as ScreenConfig<PL>).parseParams;
			const values = route.params;
			let params: ParamSlot | null = null;
			if (values !== null) {
				if (parse === null) {
					throw new Error("initialState: screen '" + route.name + "' has params but no parseParams");
				}
				params = (parse as (values: Map<string, string>) => ParamSlot | null)(values as Map<string, string>);
			}
			list.push({ key: "", name: route.name, params });
		}
		for (let i = 0; i < list.length; i += 1) {
			list[i] = this.adopt(state.routes[i].key, list[i].name, list[i].params);
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

	nestedLink(routeKey: string): NavigatorLink | null {
		for (const entry of this.children) {
			if (entry.routeKey === routeKey && this.holds(entry.link.screen())) { return entry.link; }
		}
		return null;
	}

	holds(screen: unknown): boolean {
		for (const entry of this.snapshot()) {
			if ((entry as unknown) === screen) { return true; }
		}
		return false;
	}

	restoreParams(seeds: RouteSeed<PL>[]): void {
		for (const entry of this.snapshot()) {
			for (const seed of seeds) {
				if (seed.key === entry.route.key && seed.params !== null) { entry.writeParams(seed.params); }
			}
		}
	}

	seedNested(routeKey: string, state: NavigationState | null): void {
		const seeds: SeedEntry[] = [];
		for (const entry of this.seeds) {
			if (entry.routeKey !== routeKey) { seeds.push(entry); }
		}
		const pending: PendingEntry[] = [];
		for (const entry of this.pending) {
			if (entry.routeKey !== routeKey) { pending.push(entry); }
		}
		if (state !== null) { seeds.push({ routeKey, state: state as NavigationState }); }
		this.seeds = seeds;
		this.pending = pending;
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

	encodeParams(entry: Navigation<PL>): Map<string, string> | null {
		const write = entry.config.stringifyParams;
		const params = entry.route.slot();
		if (write === null || params === null) { return null; }
		return (write as (params: ParamSlot | null) => Map<string, string>)(params);
	}

	describe(): string {
		const current = this.current();
		if (current === null) { return ""; }
		const name = (current as Navigation<PL>).route.name;
		const child = this.focusedChild();
		return child === null ? name : name + ">" + (child as NavigatorLink).describe();
	}
}

export function linkOf<PL>(core: NavigatorCore<PL>): NavigatorLink {
	const link: NavigatorLink = {
		kind: core.kind,
		hasRoute: (name: string): boolean => core.hasRoute(name),
		navigateTo: (target: NavTarget): boolean => core.navigateTo(target),
		pushTo: (name: string): boolean => core.hasRoute(name) && core.model.push(name, null),
		popToRoute: (name: string): boolean => core.hasRoute(name) && core.model.popToRoute(name, null, null),
		backLocal: (): boolean => core.backLocal(),
		canBackLocal: (): boolean => core.canBackLocal(),
		canPop: (): boolean => core.model.canPop(),
		popBy: (count: int32): boolean => {
			if (!untrack((): boolean => core.model.canPop())) { return false; }
			core.popLocal(count);
			return true;
		},
		replaceTo: (name: string): boolean => {
			const current = core.current();
			if (current === null || !core.hasRoute(name)) { return false; }
			core.model.replace((current as Navigation<PL>).route.key, name, null);
			return true;
		},
		popToTop: (): boolean => {
			if (!untrack((): boolean => core.model.canPop())) { return false; }
			core.popTo(0, "POP_TO_TOP");
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
			const route = (current as Navigation<PL>).route;
			return { key: route.key, name: route.name };
		},
		state: (): NavigationState => core.trackedState(),
		parent: (): NavigatorLink | null => core.parent,
		describe: (): string => core.describe(),
		webNavigation: (routes: WebRoutes): WebNavigationNode => core.webNavigation(routes),
		screen: (): unknown => core.parentNavigation,
		nested: (routeKey: string): NavigatorLink | null => core.nestedLink(routeKey),
		prevents: (action: NavigationAction): boolean => core.preventsAll(action),
		focusedOptions: (): ScreenOptions | null => {
			const current = core.current();
			return current === null ? null : (current as Navigation<PL>).options();
		},
		seedNested: (routeKey: string, state: NavigationState | null): void => {
			core.seedNested(routeKey, state);
		},
	};
	core.link = link;
	return link;
}

export function createCore<PL>(setup: NavigatorSetup<PL>): NavigatorCore<PL> {
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
	const core = new NavigatorCore<PL>(setup, initial, scope.link.seedFor(scope.routeKey));
	flush();
	const link = linkOf<PL>(core);
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
		refreshKeep<ResetState<PL>>(
			"navigator",
			(): ResetState<PL> => core.routesNow(),
			(kept: ResetState<PL>): void => { core.resumeRoutes(kept); },
		);
	}
	const waiting = scope.link.register(scope.routeKey, link);
	onCleanup((): void => { scope.link.unregister(scope.routeKey, link); });
	if (waiting !== null) { core.navigateTo(waiting as NavTarget); }
	return core;
}

export function screenScope<PL>(core: NavigatorCore<PL>, entry: Navigation<PL>): ScreenScope {
	const focused = accessor((): boolean => entry.focusedNow());
	const link = core.link as NavigatorLink;
	return new ScreenScope(link, entry.route.key, focused, entry as unknown, core.container);
}

export function useNavigation<PL>(): Navigation<PL> {
	const scope = currentScope("useNavigation");
	if (scope.navigation === null) {
		throw new Error("useNavigation: this component is not inside a screen");
	}
	return scope.navigation as Navigation<PL>;
}

export function useRoute<PL, K extends keyof PL>(): RouteProp<PL, K> {
	return routeProp<PL, K>(useNavigation<PL>().route);
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

export function usePreventRemove<PL>(
	prevent: Accessor<boolean>,
	callback: (event: NavigationEventArg) => void,
): void {
	const stop = useNavigation<PL>().addListener("beforeRemove", (event: NavigationEventArg): void => {
		if (!untrack((): boolean => prevent())) { return; }
		event.preventDefault();
		callback(event);
	});
	onCleanup(stop);
}

export function getFocusedRouteNameFromRoute(route: NavigationRoute): string | null {
	const state = route.state;
	if (state !== null) {
		const nested = state as NavigationState;
		return nested.routes[nested.index].name;
	}
	const params = route.params;
	if (params === null) { return null; }
	return (params as Map<string, string>).get("screen") ?? null;
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
