import { AlertButtonSpec, appServices } from "./services";

export type AlertButtonStyle = "default" | "cancel" | "destructive";

export interface AlertButton {
	text?: string | null;
	onPress?: (() => void) | null;
	style?: AlertButtonStyle | null;
	isPreferred?: boolean | null;
}

export interface AlertOptions {
	cancelable?: boolean | null;
	onDismiss?: (() => void) | null;
}

when (android) {
	// RN Android shows at most three buttons: neutral, negative, positive (the last).
	function shown(buttons: AlertButton[]): AlertButton[] {
		return buttons.slice(0, Math.min(3, buttons.length));
	}
} else {
	function shown(buttons: AlertButton[]): AlertButton[] {
		return buttons;
	}
}

export class Alert {
	static alert(
		title: string,
		message: string = "",
		buttons: AlertButton[] = [],
		options: AlertOptions = {},
	): void {
		const given: AlertButton[] = buttons.length > 0 ? shown(buttons) : [{ text: "OK" }];
		const specs: AlertButtonSpec[] = [];
		for (const button of given) {
			const style = button.style;
			const text = button.text ?? "";
			specs.push({ text, style: style != null ? (style as string) : "default" });
		}
		appServices("Alert.alert").alert({
			title,
			message,
			buttons: specs,
			cancelable: options.cancelable === true,
			done: (index: int32): void => {
				if (index >= 0 && index < given.length) {
					const press = given[index].onPress;
					if (press != null) { press(); }
					return;
				}
				const dismissed = options.onDismiss;
				if (dismissed != null) { dismissed(); }
			},
		});
	}
}
