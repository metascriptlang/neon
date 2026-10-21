export interface DevNode {
	tag: string;
	text: string;
	value: string | null;
	focused: boolean;
	pressable: boolean;
	x: float32;
	y: float32;
	w: float32;
	h: float32;
	children: DevNode[];
}

export interface DevDriver {
	host: string;
	tree: () => DevNode;
	pressAt: (x: float32, y: float32) => void;
	type: (text: string) => void;
}

let current: DevDriver | null = null;

export function setDevDriver(driver: DevDriver | null): void {
	current = driver;
}

export function devDriver(): DevDriver | null {
	return current;
}
