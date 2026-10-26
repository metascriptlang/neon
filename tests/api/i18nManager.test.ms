import { I18nManager } from "../../src/api/i18nManager";
import { I18nState, installI18nServices } from "../../src/api/i18nServices";

class Fake {
	state: I18nState = {
		allowRTL: true, forceRTL: false, swapLeftAndRightInRTL: true,
		supportsRtl: true, deviceRTL: false, localeIdentifier: "",
	};
	log: string[] = [];

	install(): void {
		installI18nServices({
			state: (): I18nState => { return this.state; },
			setPref: (name: string, value: boolean): void => { this.log.push(name + "=" + (value ? "1" : "0")); },
		});
	}
}

test "isRTL is supportsRtl && (force || (allow && deviceRTL)) on all sixteen inputs" {
	const fake = new Fake();
	fake.install();
	for (let bits = 0; bits < 16; bits += 1) {
		const supports = (bits & 1) !== 0;
		const force = (bits & 2) !== 0;
		const allow = (bits & 4) !== 0;
		const device = (bits & 8) !== 0;
		fake.state = {
			allowRTL: allow, forceRTL: force, swapLeftAndRightInRTL: true,
			supportsRtl: supports, deviceRTL: device, localeIdentifier: "",
		};
		let expected = false;
		if (supports) {
			if (force) { expected = true; }
			else if (allow && device) { expected = true; }
		}
		assert I18nManager.isRTL() === expected, "bits " + bits.toString();
	}
	installI18nServices(null);
}

test "getConstants reports isRTL, the swap flag and the locale identifier, null when the host has none" {
	const fake = new Fake();
	fake.install();
	fake.state.deviceRTL = true;
	fake.state.swapLeftAndRightInRTL = false;
	fake.state.localeIdentifier = "ar_EG";
	const c = I18nManager.getConstants();
	assert c.isRTL && !c.doLeftAndRightSwapInRTL && c.localeIdentifier === "ar_EG";
	fake.state.localeIdentifier = "";
	assert I18nManager.getConstants().localeIdentifier === null;
	installI18nServices(null);
}

test "allowRTL, forceRTL and swapLeftAndRightInRTL persist through the host's preference setter" {
	const fake = new Fake();
	fake.install();
	I18nManager.allowRTL(false);
	I18nManager.forceRTL(true);
	I18nManager.swapLeftAndRightInRTL(false);
	assert fake.log.join(";") === "allowRTL=0;forceRTL=1;swapLeftAndRightInRTL=0", fake.log.join(";");
	installI18nServices(null);
}

test "without a host the defaults are RN's: allowed, not forced, swapping, and forceRTL holds for the session" {
	installI18nServices(null);
	const c = I18nManager.getConstants();
	assert !c.isRTL && c.doLeftAndRightSwapInRTL && c.localeIdentifier === null;
	I18nManager.forceRTL(true);
	assert I18nManager.isRTL(), "forced RTL is RTL without any device language";
	I18nManager.forceRTL(false);
	assert !I18nManager.isRTL();
}
