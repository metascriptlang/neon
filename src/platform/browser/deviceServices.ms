extern class localStorage {
	static length: number;
	static extern setItem(key: cstring, value: cstring): void;
	static extern removeItem(key: cstring): void;
	static extern clear(): void;
}

extern function storageHas(key: cstring): boolean from "(localStorage.getItem(#) !== null)";
extern function storageRead(key: cstring): string from "(localStorage.getItem(#) ?? '')";
extern function storageKeyAt(index: number): string from "(localStorage.key(#) ?? '')";

export function storageGet(key: string): string | null {
	return storageHas(key) ? storageRead(key) : null;
}

export function storageSet(key: string, value: string): void {
	localStorage.setItem(key, value);
}

export function storageRemove(key: string): void {
	localStorage.removeItem(key);
}

export function storageClear(): void {
	localStorage.clear();
}

export function storageKeys(): string[] {
	const keys: string[] = [];
	const count = localStorage.length;
	for (let i = 0; i < count; i += 1) { keys.push(storageKeyAt(i)); }
	return keys;
}
