import { Haptics, ImpactFeedbackStyle, NotificationFeedbackType } from "../../src/api/haptics";
import { installHapticsServices } from "../../src/api/hapticsServices";
import { ionHapticsServices } from "../../src/platform/ion/haptics";

test "Haptics on an Ion desktop host resolve without feedback, as the browser host does where navigator.vibrate is absent" {
	installHapticsServices(ionHapticsServices);
	await Haptics.impactAsync(ImpactFeedbackStyle.Heavy);
	await Haptics.notificationAsync(NotificationFeedbackType.Error);
	await Haptics.selectionAsync();
}
