import { VibrationServices, installVibrationServices } from "../../api/vibrationServices";

export const ionVibrationServices: VibrationServices = {
	vibrate: (pattern: int32[], repeat: boolean): void => {},
	cancelVibration: (): void => {},
};

installVibrationServices(ionVibrationServices);
