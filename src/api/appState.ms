import { Accessor, accessor, createSignal } from "../core/signal";
import { EventSubscription, onChange, Listeners } from "./subscription";

export type AppStateStatus = "active" | "background" | "inactive" | "unknown" | "extension";
export type AppStateEvent = "change" | "memoryWarning" | "focus" | "blur";

// A string signal: createSignal of a literal union is refused (compiler card
// 2026-10-04-string-literal-union-signal-rejects-its-function-layout.md).
const [state, setState] = createSignal<string>("active");
const memoryWarnings = new Listeners<AppStateStatus>();

export class AppState {
	static currentState: AppStateStatus = "active";
	static isAvailable: boolean = true;

	static addEventListener(
		type: AppStateEvent,
		handler: (state: AppStateStatus) => void,
	): EventSubscription {
		const name: string = type;
		return match (name) {
			"change" => onChange(useAppState(), handler),
			"memoryWarning" => memoryWarnings.add(handler),
			"focus" => onChange(useAppState(), (next: AppStateStatus): void => {
				if (next === "active") { handler(next); }
			}),
			_ => onChange(useAppState(), (next: AppStateStatus): void => {
				if (next !== "active") { handler(next); }
			}),
		};
	}
}

export function useAppState(): Accessor<AppStateStatus> {
	return accessor((): AppStateStatus => state() as AppStateStatus);
}

export function publishAppState(next: AppStateStatus): void {
	AppState.currentState = next;
	const value: string = next;
	if (state() !== value) { setState(value); }
}

export function publishMemoryWarning(): void {
	memoryWarnings.emit(AppState.currentState);
}
