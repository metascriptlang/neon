import { Accessor, accessor } from "../core/signal";

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
