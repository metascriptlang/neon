export interface I18nState {
	allowRTL: boolean;
	forceRTL: boolean;
	swapLeftAndRightInRTL: boolean;
	supportsRtl: boolean;
	deviceRTL: boolean;
	localeIdentifier: string;
}

export interface I18nServices {
	state: () => I18nState;
	setPref: (name: string, value: boolean) => void;
}

const memory: I18nState = {
	allowRTL: true, forceRTL: false, swapLeftAndRightInRTL: true,
	supportsRtl: true, deviceRTL: false, localeIdentifier: "",
};

const memoryServices: I18nServices = {
	state: (): I18nState => { return memory; },
	setPref: (name: string, value: boolean): void => {
		if (name === "allowRTL") { memory.allowRTL = value; }
		else if (name === "forceRTL") { memory.forceRTL = value; }
		else if (name === "swapLeftAndRightInRTL") { memory.swapLeftAndRightInRTL = value; }
		else { throw new Error("I18nManager: unknown preference " + name); }
	},
};

let installed: I18nServices = memoryServices;

export function installI18nServices(services: I18nServices | null): void {
	installed = services === null ? memoryServices : services;
}

export function i18nServices(): I18nServices {
	return installed;
}
