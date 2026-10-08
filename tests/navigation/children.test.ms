import { createRoot } from "../../src/core/owner";
import { Dispose } from "../../src/core/types";
import { onCleanup } from "../../src/core/cleanup";
import { Accessor } from "../../src/core/signal";
import { createChildren, ChildState } from "../../src/navigation/children";

struct Destination {
	name: string;
}

interface DestinationInstance {
	read: Accessor<Destination>;
}

function state(key: string, name: string, active: boolean): ChildState<Destination> {
	return { key, configuration: { name }, active };
}

test "keyed children retain instances and expose reactive configuration and activation" {
	let created: int32 = 0;
	let disposed: int32 = 0;
	const navigation = createChildren<Destination, DestinationInstance>(
		[state("document", "first", true), state("inspector", "material", true)],
		(configuration: Accessor<Destination>, active: Accessor<boolean>): DestinationInstance => {
			created += 1;
			onCleanup(() => { disposed += 1; });
			return { read: configuration };
		},
	);
	const document = navigation.children()[0];
	navigation.navigate([state("inspector", "material", false), state("document", "second", true)]);
	assert created === 2;
	assert disposed === 0;
	assert navigation.children()[1].instance === document.instance;
	assert document.instance.read().name === "second";
	assert !navigation.children()[0].active();
	navigation.navigate([state("document", "second", true)]);
	assert disposed === 1;
	navigation.dispose();
	navigation.dispose();
	assert disposed === 2;
}

test "duplicate identities fail before creating or changing any child" {
	let created: int32 = 0;
	const navigation = createChildren<Destination, string>(
		[state("world", "world", true)],
		(configuration: Accessor<Destination>, active: Accessor<boolean>): string => {
			created += 1;
			return configuration().name;
		},
	);
	let message = "";
	try {
		navigation.navigate([state("world", "a", true), state("world", "b", false)]);
	} catch (error) { message = error.message; }
	assert message.indexOf("duplicate child key: world") >= 0, message;
	assert created === 1;
	assert navigation.state()[0].configuration.name === "world";
	navigation.dispose();
}

test "parent disposal owns every retained child including inactive overlays" {
	let disposed: int32 = 0;
	let message = "";
	createRoot((dispose: Dispose): void => {
		const navigation = createChildren<Destination, string>(
			[state("world", "world", true), state("inventory", "inventory", false)],
			(configuration: Accessor<Destination>, active: Accessor<boolean>): string => {
				onCleanup(() => { disposed += 1; });
				return configuration().name;
			},
		);
		dispose();
		try { navigation.navigate([]); } catch (error) { message = error.message; }
	});
	assert disposed === 2;
	assert message.indexOf("disposed") >= 0, message;
}

test "a failing factory disposes new children and leaves previous state unchanged" {
	let disposed: int32 = 0;
	const navigation = createChildren<Destination, string>(
		[state("world", "world", true)],
		(configuration: Accessor<Destination>, active: Accessor<boolean>): string => {
			onCleanup(() => { disposed += 1; });
			if (configuration().name === "fail") { throw new Error("factory failed"); }
			return configuration().name;
		},
	);
	let message = "";
	try {
		navigation.navigate([
			state("world", "changed", true),
			state("inventory", "inventory", true),
			state("broken", "fail", true),
		]);
	} catch (error) { message = error.message; }
	assert message === "factory failed", message;
	assert navigation.state().length === 1;
	assert navigation.state()[0].configuration.name === "world";
	assert disposed === 2;
	navigation.dispose();
	assert disposed === 3;
}
