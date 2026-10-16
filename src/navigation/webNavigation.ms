import { Accessor, accessor } from "../core/signal";
import { NavigationChild } from "./children";
import { ChildStack } from "./childStack";
import { ChildPages, Pages } from "./childPages";
import { ChildPanels } from "./childPanels";

export enum WebNavigationError {
	UndecodableKey,
}

export interface WebKeySerializer<C> {
	encode: (key: C) => string;
	decode: (text: string) => Result<C, WebNavigationError>;
}

export interface WebNavigationOwner {
	webNavigation: WebNavigationNode;
}

export interface WebHistoryItem<C> {
	key: C;
	path: string;
	parameters: Map<string, string>;
	child: WebNavigationOwner | null;
}

export interface WebNavigation<C> {
	serializer: WebKeySerializer<C>;
	history: Accessor<WebHistoryItem<C>[]>;
	onBeforeNavigate: () => boolean;
	navigate: (history: C[]) => void;
}

export interface WebNavigationNode {
	history: Accessor<WebHistoryItem<string>[]>;
	onBeforeNavigate: () => boolean;
	navigate: (keys: string[]) => Result<void, WebNavigationError>;
}

export function webNavigationNode<C>(navigation: WebNavigation<C>): WebNavigationNode {
	const serializer = navigation.serializer;
	return {
		history: accessor((): WebHistoryItem<string>[] => {
			const items: WebHistoryItem<string>[] = [];
			for (const item of navigation.history()) {
				items.push({
					key: serializer.encode(item.key),
					path: item.path,
					parameters: item.parameters,
					child: item.child,
				});
			}
			return items;
		}),
		onBeforeNavigate: navigation.onBeforeNavigate,
		navigate: (keys: string[]): Result<void, WebNavigationError> => {
			const history: C[] = [];
			for (const key of keys) {
				const decoded = serializer.decode(key);
				if (!decoded.ok) { return Result.err(decoded.error); }
				history.push(decoded.value);
			}
			navigation.navigate(history);
			return Result.ok(null);
		},
	};
}

export interface StackWebNavigationOptions<C, T> {
	enableHistory?: boolean | null;
	pathMapper?: ((child: NavigationChild<C, T>) => string | null) | null;
	parametersMapper?: ((child: NavigationChild<C, T>) => Map<string, string> | null) | null;
	onBeforeNavigate?: (() => boolean) | null;
	childSelector?: ((child: NavigationChild<C, T>) => WebNavigationOwner | null) | null;
}

export interface PagesWebNavigationOptions<C, T> {
	pathMapper?: ((page: NavigationChild<C, T>) => string | null) | null;
	parametersMapper?: ((page: NavigationChild<C, T>) => Map<string, string> | null) | null;
	onBeforeNavigate?: (() => boolean) | null;
	childSelector?: ((child: NavigationChild<C, T>) => WebNavigationOwner | null) | null;
	visited?: ((pages: ChildPages<C, T>) => int32[]) | null;
}

export interface PanelsHistoryKey<MC, DC, EC> {
	main: MC;
	details: DC | null;
	extra: EC | null;
}

export interface PanelsWebNavigationOptions<MC, MT, DC, DT, EC, ET> {
	pathMapper?: ((panels: ChildPanels<MC, MT, DC, DT, EC, ET>) => string | null) | null;
	parametersMapper?: (
		(panels: ChildPanels<MC, MT, DC, DT, EC, ET>) => Map<string, string> | null
	) | null;
	onBeforeNavigate?: (() => boolean) | null;
	childSelector?: (
		(panels: ChildPanels<MC, MT, DC, DT, EC, ET>) => WebNavigationOwner | null
	) | null;
}

struct PagesKey {
	items: string[];
	selectedIndex: int32;
}

struct PanelsKey {
	main: string;
	hasDetails: boolean;
	details: string;
	hasExtra: boolean;
	extra: string;
}

function allow(): boolean {
	return true;
}

function historyItem<C>(
	key: C,
	path: string | null,
	parameters: Map<string, string> | null,
	child: WebNavigationOwner | null,
): WebHistoryItem<C> {
	return {
		key,
		path: path === null ? "" : path as string,
		parameters: parameters === null
			? new Map<string, string>()
			: parameters as Map<string, string>,
		child,
	};
}

export function pagesSerializer<C>(serializer: WebKeySerializer<C>): WebKeySerializer<Pages<C>> {
	return {
		encode: (pages: Pages<C>): string => {
			const items: string[] = [];
			for (const item of pages.items) { items.push(serializer.encode(item)); }
			const key: PagesKey = { items, selectedIndex: pages.selectedIndex };
			return JSON.stringify(key);
		},
		decode: (text: string): Result<Pages<C>, WebNavigationError> => {
			const parsed = JSON.parse<PagesKey>(text);
			if (!parsed.ok) { return Result.err(WebNavigationError.UndecodableKey); }
			const key = parsed.value;
			const count = key.items.length;
			if (count > 0 && (key.selectedIndex < 0 || key.selectedIndex >= count)) {
				return Result.err(WebNavigationError.UndecodableKey);
			}
			const items: C[] = [];
			for (const item of key.items) {
				const decoded = serializer.decode(item);
				if (!decoded.ok) { return Result.err(decoded.error); }
				items.push(decoded.value);
			}
			return Result.ok({ items, selectedIndex: key.selectedIndex });
		},
	};
}

function panelsSerializer<MC, DC, EC>(
	main: WebKeySerializer<MC>,
	details: WebKeySerializer<DC>,
	extra: WebKeySerializer<EC>,
): WebKeySerializer<PanelsHistoryKey<MC, DC, EC>> {
	return {
		encode: (panels: PanelsHistoryKey<MC, DC, EC>): string => {
			const key: PanelsKey = {
				main: main.encode(panels.main),
				hasDetails: panels.details !== null,
				details: panels.details === null ? "" : details.encode(panels.details as DC),
				hasExtra: panels.extra !== null,
				extra: panels.extra === null ? "" : extra.encode(panels.extra as EC),
			};
			return JSON.stringify(key);
		},
		decode: (text: string): Result<PanelsHistoryKey<MC, DC, EC>, WebNavigationError> => {
			const parsed = JSON.parse<PanelsKey>(text);
			if (!parsed.ok) { return Result.err(WebNavigationError.UndecodableKey); }
			const key = parsed.value;
			const decodedMain = main.decode(key.main);
			if (!decodedMain.ok) { return Result.err(decodedMain.error); }
			let decodedDetails: DC | null = null;
			if (key.hasDetails) {
				const decoded = details.decode(key.details);
				if (!decoded.ok) { return Result.err(decoded.error); }
				decodedDetails = decoded.value;
			}
			let decodedExtra: EC | null = null;
			if (key.hasExtra) {
				const decoded = extra.decode(key.extra);
				if (!decoded.ok) { return Result.err(decoded.error); }
				decodedExtra = decoded.value;
			}
			return Result.ok({
				main: decodedMain.value,
				details: decodedDetails,
				extra: decodedExtra,
			});
		},
	};
}

export function childStackWebNavigation<C, T>(
	stack: ChildStack<C, T>,
	serializer: WebKeySerializer<C>,
	options: StackWebNavigationOptions<C, T>,
): WebNavigation<C> {
	const enableHistory = options.enableHistory ?? true;
	const pathMapper = options.pathMapper;
	const parametersMapper = options.parametersMapper;
	const onBeforeNavigate = options.onBeforeNavigate;
	const childSelector = options.childSelector;
	return {
		serializer,
		history: accessor((): WebHistoryItem<C>[] => {
			const items = stack.items();
			const history: WebHistoryItem<C>[] = [];
			for (let i = enableHistory ? 0 : items.length - 1; i < items.length; i += 1) {
				const child = items[i];
				history.push(historyItem<C>(
					child.configuration(),
					pathMapper === null ? null : pathMapper(child),
					parametersMapper === null ? null : parametersMapper(child),
					childSelector === null ? null : childSelector(child),
				));
			}
			return history;
		}),
		onBeforeNavigate: onBeforeNavigate === null ? allow : onBeforeNavigate,
		navigate: (history: C[]): void => {
			stack.navigate((current: C[]): C[] => history);
		},
	};
}

export function childPagesWebNavigation<C, T>(
	pages: ChildPages<C, T>,
	serializer: WebKeySerializer<C>,
	options: PagesWebNavigationOptions<C, T>,
): WebNavigation<Pages<C>> {
	const pathMapper = options.pathMapper;
	const parametersMapper = options.parametersMapper;
	const onBeforeNavigate = options.onBeforeNavigate;
	const childSelector = options.childSelector;
	const visited = options.visited;
	return {
		serializer: pagesSerializer<C>(serializer),
		history: accessor((): WebHistoryItem<Pages<C> >[] => {
			const children = pages.items();
			const items: C[] = [];
			for (const child of children) { items.push(child.configuration()); }
			const selectedIndex = pages.selectedIndex();
			const order = visited === null || selectedIndex < 0 ? [selectedIndex] : visited(pages);
			if (order.length === 0 || order[order.length - 1] !== selectedIndex) {
				throw new Error("child pages web navigation: the visited pages do not end with the selected one");
			}
			const history: WebHistoryItem<Pages<C> >[] = [];
			for (const at of order) {
				if (at >= children.length) {
					throw new Error("child pages web navigation: visited page " + at.toString() + " does not exist");
				}
				const page: NavigationChild<C, T> | null = at < 0 ? null : children[at];
				history.push(historyItem<Pages<C>>(
					{ items, selectedIndex: at },
					pathMapper === null || page === null ? null : pathMapper(page as NavigationChild<C, T>),
					parametersMapper === null || page === null
						? null
						: parametersMapper(page as NavigationChild<C, T>),
					childSelector === null || page === null
						? null
						: childSelector(page as NavigationChild<C, T>),
				));
			}
			return history;
		}),
		onBeforeNavigate: onBeforeNavigate === null ? allow : onBeforeNavigate,
		navigate: (history: Pages<C>[]): void => {
			if (history.length === 0) {
				throw new Error("child pages web navigation: an empty history");
			}
			const last = history[history.length - 1];
			pages.navigate((current: Pages<C>): Pages<C> => last);
		},
	};
}

export function childPanelsWebNavigation<MC, MT, DC, DT, EC, ET>(
	panels: ChildPanels<MC, MT, DC, DT, EC, ET>,
	mainSerializer: WebKeySerializer<MC>,
	detailsSerializer: WebKeySerializer<DC>,
	extraSerializer: WebKeySerializer<EC>,
	options: PanelsWebNavigationOptions<MC, MT, DC, DT, EC, ET>,
): WebNavigation<PanelsHistoryKey<MC, DC, EC>> {
	const pathMapper = options.pathMapper;
	const parametersMapper = options.parametersMapper;
	const onBeforeNavigate = options.onBeforeNavigate;
	const childSelector = options.childSelector;
	return {
		serializer: panelsSerializer<MC, DC, EC>(
			mainSerializer,
			detailsSerializer,
			extraSerializer,
		),
		history: accessor((): WebHistoryItem<PanelsHistoryKey<MC, DC, EC> >[] => {
			const details = panels.details();
			const extra = panels.extra();
			const key: PanelsHistoryKey<MC, DC, EC> = {
				main: panels.main().configuration(),
				details: details === null
					? null
					: (details as NavigationChild<DC, DT>).configuration(),
				extra: extra === null ? null : (extra as NavigationChild<EC, ET>).configuration(),
			};
			return [historyItem<PanelsHistoryKey<MC, DC, EC>>(
				key,
				pathMapper === null ? null : pathMapper(panels),
				parametersMapper === null ? null : parametersMapper(panels),
				childSelector === null ? null : childSelector(panels),
			)];
		}),
		onBeforeNavigate: onBeforeNavigate === null ? allow : onBeforeNavigate,
		navigate: (history: PanelsHistoryKey<MC, DC, EC>[]): void => {
			if (history.length !== 1) {
				throw new Error(
					"child panels web navigation: a history of " + history.length.toString() +
					" items, expected 1",
				);
			}
			const key = history[0];
			panels.navigateTo(key.main, key.details, key.extra);
		},
	};
}
