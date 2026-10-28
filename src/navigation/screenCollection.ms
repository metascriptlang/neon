import { Accessor, Signal, accessor } from "../core/signal";
import { createEffect } from "../core/effect";
import { Cleanup } from "../core/types";
import { onCleanup } from "../core/cleanup";
import { Host, HostNode, NeonNode } from "../render/hostTypes";
import { place } from "../render/reconcile";
import { MockNode, mockHost, mockNode } from "../render/host";
import { Context, createContext, useContext } from "../render/context";
import {
	NavigatorCore,
	ScreenConfig,
	ScreenOptions,
	ScreenParams,
	ScreenProps,
	mergeOptions,
	readRegistrationKey,
} from "./core";

export interface ScreenCollector {
	scope: Context<unknown>;
	groups: Context<Accessor<ScreenOptions>[]>;
	keys: Context<Accessor<string>[]>;
}

interface RegisteredScreen<PL> {
	marker: MockNode;
	config: ScreenConfig<PL>;
}

export class ScreenCollection<PL> {
	host: Host;
	parent: MockNode;
	entries: RegisteredScreen<PL>[] = [];
	version: Signal<int32> = new Signal<int32>(0, null, true);

	constructor() {
		this.host = mockHost();
		this.parent = mockNode("screens");
	}

	changed(): void {
		this.version.set(this.version.peek() + 1);
	}

	read(): ScreenConfig<PL>[] {
		this.version.get();
		const found: ScreenConfig<PL>[] = [];
		for (const marker of this.parent.children) {
			if (marker.tag !== "" || marker.text !== "") {
				throw new Error("a navigator's children must be Screen elements");
			}
			for (const entry of this.entries) {
				if (entry.marker === marker) {
					readRegistrationKey(entry.config.navigationKey);
					found.push(entry.config);
				}
			}
		}
		return found;
	}

	add(config: ScreenConfig<PL>, parent: HostNode, before: HostNode | null): void {
		for (const entry of this.entries) {
			if (entry.config.name === config.name) {
				throw new Error("two screens are named '" + config.name + "'");
			}
		}
		const marker = this.host.createText("") as unknown as MockNode;
		place(this.host, parent, marker as unknown as HostNode, before);
		this.entries.push({ marker, config });
		this.changed();
		onCleanup((): void => {
			for (let i = 0; i < this.entries.length; i += 1) {
				if (this.entries[i].marker === marker) {
					this.entries.splice(i, 1);
					this.changed();
					return;
				}
			}
		});
	}
}

export function createScreenCollector(): ScreenCollector {
	return {
		scope: createContext<unknown>(null),
		groups: createContext<Accessor<ScreenOptions>[]>([]),
		keys: createContext<Accessor<string>[]>([]),
	};
}

function withGroups(
	groups: Accessor<ScreenOptions>[],
	own: Accessor<ScreenOptions> | null,
): Accessor<ScreenOptions> | null {
	if (groups.length === 0) { return own; }
	return accessor((): ScreenOptions => {
		let merged: ScreenOptions = {};
		for (const group of groups) { merged = mergeOptions(merged, group()); }
		return own === null ? merged : mergeOptions(merged, (own as Accessor<ScreenOptions>)());
	});
}

function withKeys(keys: Accessor<string>[], own: Accessor<string> | null): Accessor<string> {
	const all = keys.slice(0);
	if (own !== null) { all.push(own as Accessor<string>); }
	return accessor((): string => {
		const values: string[] = [];
		for (const key of all) {
			const value = key();
			if (value === "") { throw new Error("navigationKey must be non-empty"); }
			values.push(value);
		}
		return JSON.stringify(values);
	});
}

export function groupOf(
	collector: ScreenCollector,
	children: NeonNode,
	screenOptions: Accessor<ScreenOptions> | null,
	navigationKey: Accessor<string> | null,
): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		if (useContext(collector.scope) === null) {
			throw new Error("a Group must be a child of its Navigator");
		}
		const groups = useContext(collector.groups).slice(0);
		const keys = useContext(collector.keys).slice(0);
		if (screenOptions !== null) { groups.push(screenOptions as Accessor<ScreenOptions>); }
		if (navigationKey !== null) { keys.push(navigationKey as Accessor<string>); }
		const keyed = collector.keys.provider({ value: accessor(() => keys), children });
		collector.groups.provider({ value: accessor(() => groups), children: keyed })(
			host, parent, before,
		);
	};
}

export function collectScreens<PL>(
	collector: ScreenCollector,
	children: NeonNode,
): ScreenCollection<PL> {
	const collection = new ScreenCollection<PL>();
	collector.scope.provider({ value: accessor((): unknown => collection), children })(
		collection.host, collection.parent as unknown as HostNode, null,
	);
	return collection;
}

export function watchScreens<PL>(collection: ScreenCollection<PL>, core: NavigatorCore<PL>): void {
	createEffect<int32>(
		(prev: int32 | null): int32 => { collection.read(); return 0; },
		(settled: int32, prev: int32 | null): Cleanup | null => { core.reconfigure(collection.read()); return null; },
	);
}

export function screenOf<PL>(
	collector: ScreenCollector,
	name: string,
	component: (props: ScreenProps<PL>) => NeonNode,
	options: Accessor<ScreenOptions> | null,
	params: ScreenParams<PL> | null,
	navigationKey: Accessor<string> | null,
): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const current = useContext(collector.scope);
		if (current === null) {
			throw new Error("Screen '" + name + "' must be a child of its Navigator");
		}
		const collection = current as ScreenCollection<PL>;
		if (host !== collection.host) {
			throw new Error("Screen '" + name + "' must be declared inside its Navigator");
		}
		if (params !== null && (params as ScreenParams<PL>).name !== name) {
			throw new Error(
				"Screen '" + name + "': its params are declared for '" + (params as ScreenParams<PL>).name + "'",
			);
		}
		const config = params === null
			? new ScreenConfig<PL>(name, component, options, null, null)
			: new ScreenConfig<PL>(name, component, options, (params as ScreenParams<PL>).initial, (params as ScreenParams<PL>).parse);
		config.options = withGroups(useContext(collector.groups), options);
		if (params !== null) { config.stringifyParams = (params as ScreenParams<PL>).stringify; }
		if (params !== null) { config.getId = (params as ScreenParams<PL>).getId; }
		config.navigationKey = withKeys(useContext(collector.keys), navigationKey);
		collection.add(config, parent, before);
	};
}
