import { HapticsServices, installHapticsServices } from "../../api/hapticsServices";

export const ionHapticsServices: HapticsServices = {
	haptic: (kind: string, style: string): void => {},
};

installHapticsServices(ionHapticsServices);
