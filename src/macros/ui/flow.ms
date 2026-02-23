// Flow Control Macros
// Conditional rendering and iteration

export function Show<T>(props: {
	when: boolean | (() => boolean);
	children: T;
	fallback?: T;
}): T | null {
	const condition = typeof props.when === "function" ? props.when() : props.when;
	return condition ? props.children : (props.fallback || null);
}

export function For<T, U>(props: {
	each: T[];
	children: (item: T) => U;
}): U[] {
	return props.each.map(props.children);
}

export function Index<T, U>(props: {
	each: T[];
	children: (item: T, index: number) => U;
}): U[] {
	return props.each.map((item, index) => props.children(item, index));
}
