import { mountGuest, HostPlace } from "../../../src/platform/raiser/guest";
import { View, Text } from "../../../src/components/primitives";
import { Show, For } from "../../../src/macros/ui/flow";
import { element } from "../../../src/macros/ui/element";
import { createSignal } from "../../../src/core/signal";
import { flush } from "../../../src/core/runtime";
import { NeonNode } from "../../../src/render/hostTypes";

export { raiserDispatch, raiserDispose } from "../../../src/platform/raiser/guest";

const [placeShown, setPlaceShown] = createSignal(true);

export function showPlace(shown: boolean): void {
	setPlaceShown(shown);
	flush();
}

const [placeNames, setPlaceNames] = createSignal<string[]>(["preview"]);

export function dropPlaces(): void {
	setPlaceNames([]);
	flush();
}

export function listed(root: int32): void {
	mountGuest(root, (): NeonNode => element(<View>
		<Text>editor</Text>
		<For each={placeNames()}>{(name: string): NeonNode => element(<HostPlace name={name} />)}</For>
	</View>));
}

export function editor(root: int32): void {
	mountGuest(root, (): NeonNode => element(<View>
		<Text>editor</Text>
		<Show when={placeShown}><HostPlace name="preview" /></Show>
	</View>));
}

export function twoPlaces(root: int32): void {
	mountGuest(root, (): NeonNode => element(<View>
		<HostPlace name="preview" />
		<HostPlace name="preview" />
	</View>));
}
