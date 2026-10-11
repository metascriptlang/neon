export type PlatformOSType = "ios" | "android" | "macos" | "windows" | "web" | "native";

function chosen<T>(spec: {
	ios?: T | null;
	android?: T | null;
	macos?: T | null;
	windows?: T | null;
	web?: T | null;
	native?: T | null;
	default?: T | null;
}, os: string): T {
	const own = match (os) {
		"ios" => spec.ios,
		"android" => spec.android,
		"macos" => spec.macos,
		"windows" => spec.windows,
		"web" => spec.web,
		_ => null,
	};
	if (own != null) { return own as T; }
	if ((os === "ios" || os === "android") && spec.native != null) { return spec.native as T; }
	if (spec.default != null) { return spec.default as T; }
	throw new Error("Platform.select: no entry for " + os + " and no default");
}

// Callers write `select`'s type argument until compiler card
// 2026-10-07-generic-not-inferred-through-optional-object-field.md lands.
when (android) {
	export class Platform {
		static OS: PlatformOSType = "android";
		static Version: number = 0;
		static isPad: boolean = false;
		static isTV: boolean = false;
		static isTesting: boolean = false;

		static select<T>(spec: {
			ios?: T | null;
			android?: T | null;
			macos?: T | null;
			windows?: T | null;
			web?: T | null;
			native?: T | null;
			default?: T | null;
		}): T {
			return chosen<T>(spec, "android");
		}
	}

	export function publishPlatform(version: string, isPad: boolean): void {
		let level = 0;
		for (let i = 0; i < version.length; i += 1) {
			const digit = version.charCodeAt(i) - 48;
			if (digit < 0 || digit > 9) { break; }
			level = level * 10 + digit;
		}
		Platform.Version = level;
		Platform.isPad = isPad;
	}
} else {
	when (js) {
		const OS_NAME: PlatformOSType = "web";
	} else when (ios) {
		const OS_NAME: PlatformOSType = "ios";
	} else when (macos) {
		const OS_NAME: PlatformOSType = "macos";
	} else when (windows) {
		const OS_NAME: PlatformOSType = "windows";
	} else {
		const OS_NAME: PlatformOSType = "native";
	}

	export class Platform {
		static OS: PlatformOSType = OS_NAME;
		static Version: string = "";
		static isPad: boolean = false;
		static isTV: boolean = false;
		static isTesting: boolean = false;

		static select<T>(spec: {
			ios?: T | null;
			android?: T | null;
			macos?: T | null;
			windows?: T | null;
			web?: T | null;
			native?: T | null;
			default?: T | null;
		}): T {
			return chosen<T>(spec, OS_NAME as string);
		}
	}

	export function publishPlatform(version: string, isPad: boolean): void {
		Platform.Version = version;
		Platform.isPad = isPad;
	}
}
