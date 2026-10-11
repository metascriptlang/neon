import { createSignal, Accessor } from "../../src/core/signal";
import { Dispose } from "../../src/core/types";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { Style } from "../../src/render/style";
import { HostNode, MockNode, mockNode, mockHost, render, fireEvent } from "../../src/render/host";
import { DataColumn, DataRow, DataTable, columnPadding, nextSortAscending } from "../../src/components/dataTable";

let disposeLast: Dispose | null = null;

function mount(app: () => NeonNode): MockNode {
	const root = mockNode("root");
	disposeLast = render(app(), mockHost(), root as unknown as HostNode);
	return root;
}

function attrOf(n: MockNode, name: string): string {
	for (const a of n.attrs) {
		if (a.name === name) { return a.value ?? ""; }
	}
	return "";
}

function collect(n: MockNode, test: (m: MockNode) => boolean, out: MockNode[]): MockNode[] {
	if (test(n)) { out.push(n); }
	for (const k of n.children) { collect(k, test, out); }
	return out;
}

function textOf(n: MockNode): string {
	let out = "";
	for (const m of collect(n, (m: MockNode): boolean => m.tag === "" && m.text !== "", [])) { out += m.text; }
	return out;
}

function pressableWith(root: MockNode, text: string): MockNode {
	return collect(root, (m: MockNode): boolean => m.tag === "pressable" && textOf(m) === text, [])[0];
}

interface Dessert {
	name: string;
	calories: int32;
}

function desserts(): Dessert[] {
	return [{ name: "Frozen yogurt", calories: 159 }, { name: "Eclair", calories: 262 }, { name: "Cupcake", calories: 305 }];
}

function before(a: Dessert, b: Dessert, column: number, up: boolean): boolean {
	const order = column === 0 ? (a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)) : a.calories - b.calories;
	return up ? order < 0 : order > 0;
}

function sorted(list: Dessert[], column: number, up: boolean): Dessert[] {
	const out: Dessert[] = [];
	for (const d of list) {
		let at = out.length;
		while (at > 0 && before(d, out[at - 1], column, up)) { at -= 1; }
		out.splice(at, 0, d);
	}
	return out;
}

test "column padding follows Flutter's margins and spacing" {
	assert columnPadding(0, 3, false, 24, 56).join(",") === "24,28";
	assert columnPadding(0, 3, true, 24, 56).join(",") === "12,28";
	assert columnPadding(1, 3, true, 24, 56).join(",") === "28,28";
	assert columnPadding(2, 3, true, 24, 56).join(",") === "28,24";
	assert nextSortAscending(1, 1, true) === false && nextSortAscending(1, 1, false) && nextSortAscending(0, 1, false);
}

test "a sortable header sorts, flips direction and announces the order" {
	const [sortColumn, setSortColumn] = createSignal<number>(-1);
	const [ascending, setAscending] = createSignal(true);
	const [items, setItems] = createSignal<Dessert[]>(desserts());
	const sorts: string[] = [];
	const sortBy = (column: number, up: boolean): void => {
		sorts.push(column.toString() + (up ? " up" : " down"));
		setSortColumn(column);
		setAscending(up);
		setItems(sorted(items(), column, up));
	};
	const columns: DataColumn[] = [{ label: "Dessert", onSort: sortBy }, { label: "Calories", numeric: true, onSort: sortBy }];
	const root = mount((): NeonNode => element(<DataTable columns={columns} sortColumnIndex={sortColumn()} sortAscending={ascending()}
		rows={items().map((d: Dessert): DataRow => ({ cells: [{ text: d.name }, { text: d.calories.toString() }] }))} />));
	const names = (): string => {
		const out: string[] = [];
		for (const d of desserts()) {
			const hits = collect(root, (m: MockNode): boolean => m.tag === "" && m.text === d.name, []);
			if (hits.length !== 1) { return "missing " + d.name; }
		}
		const cells = collect(root, (m: MockNode): boolean => m.tag === "" && (m.text === "Frozen yogurt" || m.text === "Eclair" || m.text === "Cupcake"), []);
		for (const c of cells) { out.push(c.text); }
		return out.join("|");
	};
	assert names() === "Frozen yogurt|Eclair|Cupcake", names();
	fireEvent(pressableWith(root, "Dessert↑"), "onPress");
	assert sorts.join(",") === "0 up" && names() === "Cupcake|Eclair|Frozen yogurt", names();
	const header = pressableWith(root, "Dessert↑");
	assert attrOf(header, "accessibilityLabel") === "Dessert, sorted ascending", attrOf(header, "accessibilityLabel");
	fireEvent(header, "onPress");
	assert sorts.join(",") === "0 up,0 down" && names() === "Frozen yogurt|Eclair|Cupcake", names();
	fireEvent(pressableWith(root, "↓Calories"), "onPress");
	assert sorts.join(",") === "0 up,0 down,1 up", sorts.join(",");
	const numeric = collect(root, (m: MockNode): boolean => m.tag === "view" && textOf(m) === "305" && m.style !== null && (m.style as Style).alignItems === "flex-end", []);
	assert numeric.length === 1, "a numeric cell is end-aligned";
	(disposeLast as Dispose)();
}

test "a selectable row toggles from a cell, the header checkbox selects every row" {
	const [chosen, setChosen] = createSignal<string[]>([]);
	const choose = (name: string, on: boolean): void => {
		const next: string[] = [];
		for (const n of chosen()) {
			if (n !== name) { next.push(n); }
		}
		if (on) { next.push(name); }
		setChosen(next);
	};
	const columns: DataColumn[] = [{ label: "Dessert" }, { label: "Calories", numeric: true }];
	const rows = (): DataRow[] => desserts().map((d: Dessert): DataRow => ({
		cells: [{ text: d.name }, { text: d.calories.toString() }],
		selected: chosen().indexOf(d.name) >= 0,
		onSelectChanged: (on: boolean): void => { choose(d.name, on); },
	}));
	const root = mount((): NeonNode => element(<DataTable columns={columns} rows={rows()} />));
	const checkboxes = (): MockNode[] => collect(root, (m: MockNode): boolean => attrOf(m, "accessibilityRole") === "checkbox", []);
	assert checkboxes().length === 4, "a header checkbox and one per row";
	fireEvent(pressableWith(root, "Eclair"), "onPress");
	assert chosen().join(",") === "Eclair", chosen().join(",");
	assert attrOf(checkboxes()[0], "accessibilityState") === "mixed", "the header is mixed: " + attrOf(checkboxes()[0], "accessibilityState");
	const tinted = collect(root, (m: MockNode): boolean => textOf(m) === "262" && m.style !== null && (m.style as Style).backgroundColor === "#e3f2fd", []);
	assert tinted.length === 1, "the selected row is tinted in every column";
	fireEvent(checkboxes()[0], "onPress");
	assert chosen().length === 3, "select all: " + chosen().join(",");
	fireEvent(checkboxes()[0], "onPress");
	assert chosen().length === 0, "and clear all";
	(disposeLast as Dispose)();
}
