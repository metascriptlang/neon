// What a handler receives. One flat struct, not a union of pointer/key/input
// events: a union would force every handler to narrow before reading anything,
// and BUGS.md §2 still has a bare-union-at-use-site hole on the C lane.
//
// A field a host cannot supply stays at its zero value rather than becoming
// nullable — `e.value` on a click is "", `e.x` on a keypress is 0. Handlers read
// what the event they subscribed to actually carries, so the zero is never
// ambiguous in practice, and no handler pays for narrowing.
//
// Adding a field here is backward compatible (hosts construct events, handlers
// only read them), so this starts deliberately small. Changing the ARITY of a
// handler is the expensive move, and that is what landing this does once.

export interface NeonEvent {
	type: string;   // "click", "input", "keydown" — the JSX name with "on" stripped
	value: string;  // the target's text value where it has one
	x: number;      // pointer position in host coordinates
	y: number;
	key: string;    // key name for keyboard events
}

export function neonEvent(type: string): NeonEvent {
	return { type, value: "", x: 0, y: 0, key: "" };
}

// "onClick" → "click". Every host derives the type the same way, so a handler
// comparing `e.type` sees one spelling everywhere.
export function eventType(name: string): string {
	if (name.length > 2 && name.charAt(0) === "o" && name.charAt(1) === "n") {
		return name.slice(2, name.length).toLowerCase();
	}
	return name.toLowerCase();
}
