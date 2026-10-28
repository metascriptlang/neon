import { ActionSheetIOS } from "../../src/api/actionSheetIOS";
import { ActionSheetRequest, ActionSheetServices, installActionSheetServices } from "../../src/api/actionSheetServices";
import { Settings } from "../../src/api/settings";
import { SettingsServices, installSettingsServices, settingsEvent } from "../../src/api/settingsServices";

class FakeIosApis {
	sheets: ActionSheetRequest[] = [];
	dismissals: int32 = 0;
	keys: string[] = [];
	texts: string[] = [];
	watching: int32 = 0;

	install(): void {
		const sheets: ActionSheetServices = {
			showActionSheet: (request: ActionSheetRequest): void => { this.sheets.push(request); },
			dismissActionSheet: (): void => { this.dismissals += 1; },
		};
		installActionSheetServices(sheets);
		const settings: SettingsServices = {
			settingsGet: (key: string): string | null => {
				const at = this.keys.indexOf(key);
				return at < 0 ? null : this.texts[at];
			},
			settingsSet: (values: string): void => {
				const parsed = JSON.parseValue(values);
				if (!parsed.ok) { throw new Error(values); }
				const object = parsed.value;
				if (object.kind !== JsonKind.Object) { throw new Error(values); }
				for (let i = 0; i < object.keys.length; i += 1) { this.put(object.keys[i], object.values[i]); }
			},
			watchSettings: (): void => { this.watching += 1; },
		};
		installSettingsServices(settings);
	}

	put(key: string, value: JsonValue): void {
		const at = this.keys.indexOf(key);
		if (value.kind === JsonKind.Null) {
			if (at >= 0) {
				this.keys.splice(at, 1);
				this.texts.splice(at, 1);
			}
			return;
		}
		if (at < 0) {
			this.keys.push(key);
			this.texts.push(stringify(value));
		} else {
			this.texts[at] = stringify(value);
		}
	}

	external(key: string, text: string): void {
		const parsed = JSON.parseValue(text);
		if (!parsed.ok) { throw new Error(text); }
		this.put(key, parsed.value);
		settingsEvent();
	}
}

test "ActionSheetIOS maps RN's options to the host request and answers the chosen index" {
	const fake = new FakeIosApis();
	fake.install();
	let chosen: number = -2;
	ActionSheetIOS.showActionSheetWithOptions({
		title: "Photo",
		message: "Pick one",
		options: ["Save", "Share", "Delete", "Cancel"],
		destructiveButtonIndex: 2,
		cancelButtonIndex: 3,
		disabledButtonIndices: [1],
		tintColor: "#ff0000",
		userInterfaceStyle: "dark",
	}, (index: number): void => { chosen = index; });
	assert fake.sheets.length === 1;
	const request = fake.sheets[0];
	assert request.title === "Photo" && request.message === "Pick one";
	assert request.options.join(",") === "Save,Share,Delete,Cancel", request.options.join(",");
	assert request.cancelButtonIndex === 3;
	assert request.destructiveButtonIndices.length === 1 && request.destructiveButtonIndices[0] === 2;
	assert request.disabledButtonIndices.length === 1 && request.disabledButtonIndices[0] === 1;
	assert request.tintColor === "#ff0000" && request.userInterfaceStyle === "dark";
	assert request.cancelButtonTintColor === "" && request.disabledButtonTintColor === "";
	request.done(2);
	assert chosen === 2, chosen.toString();
}

test "ActionSheetIOS defaults an absent cancel index to -1 and takes one or many destructive indices" {
	const fake = new FakeIosApis();
	fake.install();
	ActionSheetIOS.showActionSheetWithOptions({ options: ["A", "B"] }, (index: number): void => {});
	ActionSheetIOS.showActionSheetWithOptions({ options: ["A", "B", "C"], destructiveButtonIndex: [0, 2] }, (index: number): void => {});
	assert fake.sheets[0].cancelButtonIndex === -1 && fake.sheets[0].destructiveButtonIndices.length === 0;
	assert fake.sheets[0].title === "" && fake.sheets[0].message === "";
	assert fake.sheets[1].destructiveButtonIndices.join(",") === "0,2", fake.sheets[1].destructiveButtonIndices.join(",");
}

test "ActionSheetIOS refuses a disabled index out of bounds, dismisses through the host, and names itself where no host has it" {
	const fake = new FakeIosApis();
	fake.install();
	let message = "";
	try {
		ActionSheetIOS.showActionSheetWithOptions({ options: ["A"], disabledButtonIndices: [1] }, (index: number): void => {});
	} catch (e) {
		message = (e as Error).message;
	}
	assert message.includes("index 1 from disabledButtonIndices is out of bounds, the maximum is 0"), message;
	assert fake.sheets.length === 0;
	ActionSheetIOS.dismissActionSheet();
	assert fake.dismissals === 1;
	installActionSheetServices(null);
	message = "";
	try {
		ActionSheetIOS.dismissActionSheet();
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "ActionSheetIOS.dismissActionSheet is not available on this host", message;
}

test "Settings reads, writes and removes keys through the host" {
	const fake = new FakeIosApis();
	fake.install();
	assert Settings.get("theme") === null;
	Settings.set({ theme: "dark", volume: 3, loud: true });
	assert Settings.get("theme")!.asString() === "dark";
	assert Settings.get("volume")!.asInt32() === 3;
	assert Settings.get("loud")!.asBoolean();
	const gone: string | null = null;
	Settings.set({ theme: gone });
	assert Settings.get("theme") === null, "null removes the key";
	assert Settings.get("volume")!.asInt32() === 3;
}

test "Settings.watchKeys fires per changed watched key for outside writes only, until clearWatch" {
	const fake = new FakeIosApis();
	fake.install();
	Settings.set({ theme: "light" });
	const seen: string[] = [];
	const first = Settings.watchKeys(["theme", "volume"], (): void => { seen.push("a"); });
	const second = Settings.watchKeys("theme", (): void => { seen.push("b"); });
	assert second === first + 1, `${first} ${second}`;
	assert fake.watching === 2;
	Settings.set({ theme: "dark" });
	assert seen.length === 0, "a write through Settings.set does not fire";
	fake.external("other", "1");
	assert seen.length === 0, "an unwatched key does not fire";
	fake.external("theme", "\"light\"");
	assert seen.join(",") === "a,b", seen.join(",");
	fake.external("theme", "\"light\"");
	assert seen.length === 2, "an unchanged value does not fire";
	Settings.clearWatch(first);
	fake.external("volume", "2");
	fake.external("theme", "\"dark\"");
	assert seen.join(",") === "a,b,b", seen.join(",");
	Settings.clearWatch(second);
	fake.external("theme", "\"light\"");
	assert seen.length === 3;
}

test "Settings off iOS warns and answers null or -1, as RN's SettingsFallback does" {
	installSettingsServices(null);
	assert Settings.get("theme") === null;
	Settings.set({ theme: "dark" });
	assert Settings.watchKeys("theme", (): void => {}) === -1;
	Settings.clearWatch(0);
}
