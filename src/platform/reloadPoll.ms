import { reload, lastReload, reloadKindName, ReloadKind } from "std/hcr";
import { jsonString, jsonArrayOfStrings } from "std/serialize/json/builder";
import { devEvent } from "../devtools/events";
import { devDriver } from "../devtools/driver";
import { pollControl } from "../devtools/control";

export const RELOAD_POLL_MS = 50;

let announced = false;

export function pollReload(): void {
	if (!announced) {
		announced = true;
		const d = devDriver();
		devEvent("ready", ["host"], [jsonString(d === null ? "" : d.host)]);
	}
	const kind = reload();
	if (kind != ReloadKind.NoChange) {
		const r = lastReload();
		console.log(`HCR ${reloadKindName(kind)} [${r.modules.join(",")}] ${r.reason}`);
		devEvent("reload", ["kind", "modules", "reason"], [jsonString(reloadKindName(kind)), jsonArrayOfStrings(r.modules), jsonString(r.reason)]);
	}
	pollControl();
}
