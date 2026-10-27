export function encodeRouteComponent(value: string): string {
	const hex = "0123456789ABCDEF";
	let encoded = "";
	for (let i = 0; i < value.byteLength(); i += 1) {
		const byte = value.byteAt(i);
		if ((byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) ||
			(byte >= 48 && byte <= 57) || byte === 45 || byte === 46 ||
			byte === 95 || byte === 126) {
			encoded += String.fromCharCode(byte);
		} else {
			encoded += "%" + hex.substring(byte / 16, byte / 16 + 1) +
				hex.substring(byte % 16, byte % 16 + 1);
		}
	}
	return encoded;
}

export class QueryParams {
	names: string[] = [];
	values: string[] = [];

	get(name: string): string | null {
		for (let i = 0; i < this.names.length; i += 1) {
			if (this.names[i] === name) { return this.values[i]; }
		}
		return null;
	}

	getAll(name: string): string[] {
		const found: string[] = [];
		for (let i = 0; i < this.names.length; i += 1) {
			if (this.names[i] === name) { found.push(this.values[i]); }
		}
		return found;
	}

	has(name: string): boolean {
		return this.names.indexOf(name) >= 0;
	}

	append(name: string, value: string): QueryParams {
		this.names.push(name);
		this.values.push(value);
		return this;
	}

	set(name: string, value: string): QueryParams {
		this.delete(name);
		return this.append(name, value);
	}

	delete(name: string): void {
		for (let i = this.names.length - 1; i >= 0; i -= 1) {
			if (this.names[i] === name) {
				this.names.splice(i, 1);
				this.values.splice(i, 1);
			}
		}
	}

	get size(): int32 {
		return this.names.length as int32;
	}

	entries(): Array<[string, string]> {
		const pairs: Array<[string, string]> = [];
		for (let i = 0; i < this.names.length; i += 1) { pairs.push([this.names[i], this.values[i]]); }
		return pairs;
	}

	toString(): string {
		const pairs: string[] = [];
		for (let i = 0; i < this.names.length; i += 1) {
			pairs.push(encodeRouteComponent(this.names[i]) + "=" + encodeRouteComponent(this.values[i]));
		}
		return pairs.join("&");
	}
}
