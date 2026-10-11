import { appServices } from "./services";

// Integer enums: MetaScript enums take integer initializers only, where expo's hold strings.
export enum ImpactFeedbackStyle {
	Light,
	Medium,
	Heavy,
	Soft,
	Rigid,
}

export enum NotificationFeedbackType {
	Success,
	Warning,
	Error,
}

function impactName(style: ImpactFeedbackStyle): string {
	return match (style) {
		ImpactFeedbackStyle.Light => "light",
		ImpactFeedbackStyle.Medium => "medium",
		ImpactFeedbackStyle.Heavy => "heavy",
		ImpactFeedbackStyle.Soft => "soft",
		ImpactFeedbackStyle.Rigid => "rigid",
	};
}

function notificationName(type: NotificationFeedbackType): string {
	return match (type) {
		NotificationFeedbackType.Success => "success",
		NotificationFeedbackType.Warning => "warning",
		NotificationFeedbackType.Error => "error",
	};
}

export class Haptics {
	static async impactAsync(style: ImpactFeedbackStyle = ImpactFeedbackStyle.Medium): Promise<void> {
		appServices("Haptics.impactAsync").haptic("impact", impactName(style));
	}

	static async notificationAsync(type: NotificationFeedbackType = NotificationFeedbackType.Success): Promise<void> {
		appServices("Haptics.notificationAsync").haptic("notification", notificationName(type));
	}

	static async selectionAsync(): Promise<void> {
		appServices("Haptics.selectionAsync").haptic("selection", "");
	}
}
