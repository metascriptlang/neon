export interface NativeElement {
	create: () => Ptr<void> | null;
	sizesItself: boolean;
}

const elements = new Map<string, NativeElement>();

export function registerNativeElement(tag: string, element: NativeElement): void {
	if (elements.has(tag)) { throw new Error(`registerNativeElement: <${tag}> is registered twice`); }
	elements.set(tag, element);
}

export function nativeElement(tag: string, component: string): NativeElement {
	if (!elements.has(tag)) {
		throw new Error(`native host: <${tag}> has no renderer on this host; import ${component}, on a platform that renders it`);
	}
	return elements.get(tag) as NativeElement;
}
