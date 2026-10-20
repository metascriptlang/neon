import { reload, lastReload, reloadKindName, ReloadKind } from "std/hcr";

export const RELOAD_POLL_MS = 50;

export function pollReload(): void {
	const kind = reload();
	if (kind == ReloadKind.NoChange) return;
	const r = lastReload();
	console.log(`HCR ${reloadKindName(kind)} [${r.modules.join(",")}] ${r.reason}`);
}
