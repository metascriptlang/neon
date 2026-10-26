import { Vibration } from "../../src/api/vibration";
import { installVibrationServices } from "../../src/api/vibrationServices";
import { ionVibrationServices } from "../../src/platform/ion/vibration";

test "Vibration on an Ion desktop host is a silent no-op, as react-native-web's is where navigator.vibrate is absent" {
	installVibrationServices(ionVibrationServices);
	Vibration.vibrate();
	Vibration.vibrate(100);
	Vibration.vibrate([0, 100, 200], true);
	Vibration.cancel();
}
