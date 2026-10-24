import { HostNode } from "../../render/hostTypes";
import { NeonEvent } from "../../render/event";

export interface MediaElement {
	create: (tag: string) => HostNode;
	adopt: (node: HostNode, tag: string) => void;
	writeAttr: (node: HostNode, name: string, value: string) => boolean;
	addEvent: (node: HostNode, type: string, handler: (e: NeonEvent) => void) => boolean;
	release: (node: HostNode) => void;
}

const tags = new Map<string, MediaElement>();
const elements: MediaElement[] = [];
let svgWriter: ((node: HostNode, list: string) => void) | null = null;

export function registerMediaElement(tag: string, element: MediaElement): void {
	if (tags.has(tag)) { throw new Error(`registerMediaElement: <${tag}> is registered twice`); }
	tags.set(tag, element);
	if (elements.indexOf(element) < 0) { elements.push(element); }
}

export function isMediaTag(tag: string): boolean {
	return tags.has(tag);
}

export function createMediaNode(tag: string): HostNode {
	return (tags.get(tag) as MediaElement).create(tag);
}

export function adoptMedia(node: HostNode, tag: string): HostNode {
	(tags.get(tag) as MediaElement).adopt(node, tag);
	return node;
}

export function writeMediaAttr(node: HostNode, name: string, value: string): boolean {
	for (const element of elements) {
		if (element.writeAttr(node, name, value)) { return true; }
	}
	return false;
}

export function addMediaEvent(node: HostNode, type: string, handler: (e: NeonEvent) => void): boolean {
	for (const element of elements) {
		if (element.addEvent(node, type, handler)) { return true; }
	}
	return false;
}

export function releaseMedia(node: HostNode): void {
	for (const element of elements) { element.release(node); }
}

export function installSvgWriter(write: (node: HostNode, list: string) => void): void {
	svgWriter = write;
}

export function writeSvgList(node: HostNode, list: string): void {
	const write = svgWriter;
	if (write === null) { throw new Error("Svg: the browser host has no SVG writer; import the Svg component"); }
	write(node, list);
}
