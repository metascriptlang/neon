import { Accessor, Signal, accessor } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { Dispose } from "../../src/core/types";
import { NeonNode } from "../../src/render/hostTypes";
import { View, Text, Pressable } from "../../src/components/primitives";
import { Show, For } from "../../src/macros/ui/flow";
import {
	RouteCodec,
	RoutePlan,
	ChildState,
	createChildren,
	RoutingError,
	RoutingHistory,
	RoutingRegistry,
	RoutingSession,
	bindRoute,
	createRouteParticipant,
	createRoutingSession,
	decodeRouteComponent,
	encodeRouteComponent,
} from "../../src/navigation/index";

struct DocumentParams {
	id: string;
}

struct DocumentSnapshot {
	ids: string[];
}

export interface DocumentComponent {
	id: Accessor<string>;
	active: Accessor<boolean>;
	count: Accessor<int32>;
	increment: () => void;
}

export interface RoutingDemoModel {
	document: Accessor<string>;
	documentComponents: Accessor<DocumentComponent[]>;
	dispose: Dispose;
	documents: Accessor<string[]>;
	inspector: Accessor<string>;
	inventory: Accessor<string>;
	error: Accessor<string>;
	session: RoutingSession;
	open: (address: string) => void;
}

function validateName(name: string): Result<string, RoutingError> {
	if (name === "" || name.indexOf("/") >= 0 || name.indexOf("?") >= 0 ||
		name.indexOf("#") >= 0) {
		return Result.err(RoutingError.InvalidParams);
	}
	return Result.ok(name);
}

function namedCodec(id: string, prefix: string): RouteCodec<string> {
	return {
		id,
		decode: (address: string): Result<string, RoutingError> => {
			if (!address.startsWith(prefix)) { return Result.err(RoutingError.NoMatch); }
			const name = try decodeRouteComponent(address.substring(prefix.length, address.length));
			return validateName(name);
		},
		encode: (name: string): Result<string, RoutingError> => {
			const valid = try validateName(name);
			return Result.ok(prefix + encodeRouteComponent(valid));
		},
	};
}

function restoreName(
	value: string,
	write: (name: string) => void,
): Result<RoutePlan, RoutingError> {
	if (value !== "") { const checked = try validateName(value); }
	return Result.ok({ commit: (): void => write(value) });
}

export function createRoutingDemo(history: RoutingHistory): Result<RoutingDemoModel, RoutingError> {
	const documents = new Signal<string[]>([]);
	const inspector = new Signal<string>("");
	const inventory = new Signal<string>("");
	const error = new Signal<string>("");
	const document = accessor((): string => {
		const ids = documents.get();
		return ids.length === 0 ? "" : ids[ids.length - 1];
	});
	const names = namedCodec("document", "/documents/");
	const documentCodec: RouteCodec<DocumentParams> = {
		id: "document",
		decode: (address: string): Result<DocumentParams, RoutingError> => {
			const id = try names.decode(address);
			return Result.ok({ id });
		},
		encode: (params: DocumentParams): Result<string, RoutingError> => names.encode(params.id),
	};
	const documentBinding = bindRoute<DocumentParams>(
		documentCodec,
		(): DocumentParams | null => document() === "" ? null : ({ id: document() }),
		(params: DocumentParams): void => {
			if (document() === params.id) { return; }
			const ids = documents.get().slice(0);
			ids.push(params.id);
			documents.set(ids);
		},
	);
	const inspectorBinding = bindRoute<string>(
		namedCodec("material", "/materials/"),
		(): string | null => inspector.get() === "" ? null : inspector.get(),
		(name: string): void => inspector.set(name),
	);
	const inventoryBinding = bindRoute<string>(
		namedCodec("inventory", "/items/"),
		(): string | null => inventory.get() === "" ? null : inventory.get(),
		(name: string): void => inventory.set(name),
	);
	const registry = new RoutingRegistry("main");
	registry.register(createRouteParticipant(
		"main",
		[documentBinding],
		(): void => documents.set([]),
		(): string => JSON.stringify({ ids: documents.get() }),
		(state: string): Result<RoutePlan, RoutingError> => {
			const parsed = JSON.parse<DocumentSnapshot>(state);
			if (!parsed.ok) { return Result.err(RoutingError.IncompleteSnapshot); }
			const ids = parsed.value.ids.slice(0);
			if (ids.length === 0) { return Result.err(RoutingError.IncompleteSnapshot); }
			for (const id of ids) { const valid = try validateName(id); }
			return Result.ok({ commit: (): void => documents.set(ids) });
		},
	));
	registry.register(createRouteParticipant(
		"inspector",
		[inspectorBinding],
		(): void => inspector.set(""),
		(): string => inspector.get(),
		(state: string): Result<RoutePlan, RoutingError> => {
			return restoreName(state, (name: string): void => inspector.set(name));
		},
	));
	registry.register(createRouteParticipant(
		"inventory",
		[inventoryBinding],
		(): void => inventory.set(""),
		(): string => inventory.get(),
		(state: string): Result<RoutePlan, RoutingError> => {
			return restoreName(state, (name: string): void => inventory.set(name));
		},
	));
	const session = try createRoutingSession(
		registry,
		history,
		(failure: RoutingError): void => error.set(failure.toString()),
	);
	const components = createChildren<string, DocumentComponent>(
		[],
		(id: Accessor<string>, active: Accessor<boolean>): DocumentComponent => {
			const count = new Signal<int32>(0);
			return {
				id,
				active,
				count: accessor((): int32 => count.get()),
				increment: (): void => count.set(count.get() + 1),
			};
		},
	);
	const stop = createEffect((): void => {
		const ids = documents.get();
		const state: ChildState<string>[] = [];
		for (let i = 0; i < ids.length; i += 1) {
			state.push({
				key: i.toString() + ":" + ids[i],
				configuration: ids[i],
				active: i === ids.length - 1,
			});
		}
		components.navigate(state);
	});
	return Result.ok({
		document,
		documentComponents: components.instances,
		dispose: (): void => { stop(); components.dispose(); session.dispose(); },
		documents: accessor((): string[] => documents.get().slice(0)),
		inspector: accessor((): string => inspector.get()),
		inventory: accessor((): string => inventory.get()),
		error: accessor((): string => error.get()),
		session,
		open: (address: string): void => {
			const result = session.navigate(address, false);
			error.set(result.ok ? "" : result.error.toString());
		},
	});
}

function DocumentPanel(props: { component: DocumentComponent }): NeonNode {
	const component = props.component;
	return <Show when={component.active}>
		<View>
			<Text>{"Document " + component.id()}</Text>
			<Text>{"Edits " + component.count().toString()}</Text>
			<Pressable accessibilityLabel={"Increment document " + component.id()}
				onPress={(): void => component.increment()}>
				<Text>Increment edits</Text>
			</Pressable>
		</View>
	</Show>;
}

export function RoutingDemo(props: { model: RoutingDemoModel }): NeonNode {
	const model = props.model;
	const hasInspector = accessor((): boolean => model.inspector() !== "");
	const hasInventory = accessor((): boolean => model.inventory() !== "");
	const hasError = accessor((): boolean => model.error() !== "");
	const panel = (component: DocumentComponent, index: Accessor<number>): NeonNode => {
		return <DocumentPanel component={component} />;
	};
	return <View>
		<For each={model.documentComponents}>{panel}</For>
		<Show when={hasInspector}>
			<Text>{"Inspector " + model.inspector()}</Text>
		</Show>
		<Show when={hasInventory}>
			<Text>{"Inventory " + model.inventory()}</Text>
		</Show>
		<Show when={hasError}>
			<Text>{"Routing error: " + model.error()}</Text>
		</Show>
		<Pressable accessibilityLabel="Open document 42"
			onPress={(): void => model.open("/documents/42")}>
			<Text>Open document 42</Text>
		</Pressable>
		<Pressable accessibilityLabel="Open inspector"
			onPress={(): void => model.open("/documents/42?__nav.inspector=%2Fmaterials%2Fmetal")}>
			<Text>Open inspector</Text>
		</Pressable>
		<Pressable accessibilityLabel="Open inventory"
			onPress={(): void => model.open("/documents/42?__nav.inventory=%2Fitems%2Fsword")}>
			<Text>Open inventory</Text>
		</Pressable>
	</View>;
}
