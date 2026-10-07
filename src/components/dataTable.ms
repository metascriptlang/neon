// Flutter material/data_table.dart in Neon's vocabulary. Flutter sizes every column to its
// widest cell (IntrinsicColumnWidth); Neon gets the same widths in one layout pass by laying
// the table out column by column, each column a stack of fixed-height cells
// (WORKAROUND.md W3). A wide table scrolls horizontally inside its own ScrollView.

import { Accessor, accessor, untrack } from "../core/signal";
import { For, Show } from "../macros/ui/flow";
import { element } from "../macros/ui/element";
import { NeonNode, VAttr, dynAttr, evt, hostElement } from "../render/node";
import { NeonEvent } from "../render/event";
import { Style, mergeStyle } from "../render/style";
import { ScrollView, Text, View } from "./primitives";
import { Checkbox } from "./checkbox";
import { MATERIAL_ON_SURFACE } from "./material";

export interface DataColumn {
	label: string;
	numeric?: boolean | null;
	tooltip?: string | null;
	onSort?: ((columnIndex: number, ascending: boolean) => void) | null;
}

export interface DataCell {
	text?: string | null;
	child?: NeonNode | null;
	onTap?: (() => void) | null;
}

export interface DataRow {
	key?: string | null;
	cells: DataCell[];
	selected?: boolean | null;
	onSelectChanged?: ((selected: boolean) => void) | null;
}

// data_table.dart DataTable defaults.
const HEADING_ROW_HEIGHT = 56;
const DATA_ROW_HEIGHT = 48;
const HORIZONTAL_MARGIN = 24;
const COLUMN_SPACING = 56;
const DIVIDER = "#e0e0e0";
const SELECTED_ROW = "#e3f2fd";
const HEADING_INK = "#49454f";

// data_table.dart DataTable.build: start and end padding of a data column.
export function columnPadding(index: int32, count: int32, checkboxes: boolean, margin: number, spacing: number): number[] {
	let start = spacing / 2;
	if (index === 0) { start = checkboxes ? margin / 2 : margin; }
	const end = index === count - 1 ? margin : spacing / 2;
	return [start, end];
}

// What a press on a sortable header asks for: the other direction of the sorted column, or
// ascending for a column not yet sorted.
export function nextSortAscending(columnIndex: number, sortColumnIndex: number, sortAscending: boolean): boolean {
	return sortColumnIndex !== columnIndex || !sortAscending;
}

function rowSelected(row: DataRow): boolean {
	const selected = row.selected;
	return selected !== null && (selected as boolean);
}

export function DataTable(props: {
	columns: Accessor<DataColumn[]>;
	rows: Accessor<DataRow[]>;
	sortColumnIndex?: Accessor<number> | null;
	sortAscending?: Accessor<boolean> | null;
	onSelectAll?: ((selected: boolean) => void) | null;
	showCheckboxColumn?: Accessor<boolean> | null;
	headingRowHeight?: Accessor<number> | null;
	dataRowHeight?: Accessor<number> | null;
	horizontalMargin?: Accessor<number> | null;
	columnSpacing?: Accessor<number> | null;
	headingTextStyle?: Accessor<Style> | null;
	dataTextStyle?: Accessor<Style> | null;
	style?: Accessor<Style> | null;
}): NeonNode {
	const { columns, rows, onSelectAll } = props;
	const sortIndexProp = props.sortColumnIndex;
	const ascendingProp = props.sortAscending;
	const checkboxProp = props.showCheckboxColumn;
	const headingProp = props.headingRowHeight;
	const rowHeightProp = props.dataRowHeight;
	const marginProp = props.horizontalMargin;
	const spacingProp = props.columnSpacing;
	const headingTextProp = props.headingTextStyle;
	const dataTextProp = props.dataTextStyle;
	const sortIndex = (): number => sortIndexProp === null ? -1 : (sortIndexProp as Accessor<number>)();
	const ascending = (): boolean => ascendingProp === null || (ascendingProp as Accessor<boolean>)();
	const headingHeight = (): number => headingProp === null ? HEADING_ROW_HEIGHT : (headingProp as Accessor<number>)();
	const rowHeight = (): number => rowHeightProp === null ? DATA_ROW_HEIGHT : (rowHeightProp as Accessor<number>)();
	const margin = (): number => marginProp === null ? HORIZONTAL_MARGIN : (marginProp as Accessor<number>)();
	const spacing = (): number => spacingProp === null ? COLUMN_SPACING : (spacingProp as Accessor<number>)();
	// data_table.dart: the checkbox column shows when any row can be selected.
	const checkboxes = (): boolean => {
		if (checkboxProp !== null && !(checkboxProp as Accessor<boolean>)()) { return false; }
		for (const row of rows()) {
			if (row.onSelectChanged !== null) { return true; }
		}
		return false;
	};

	const rowFill = (row: DataRow): string => rowSelected(row) ? SELECTED_ROW : "#ffffff";
	const toggleRow = (row: DataRow): void => {
		const change = row.onSelectChanged;
		if (change !== null) { (change as (s: boolean) => void)(!rowSelected(row)); }
	};
	const divider = (): NeonNode => View({ style: accessor((): Style => ({ height: 1, backgroundColor: DIVIDER })) });

	const dataCell = (column: Accessor<number>, row: DataRow, numeric: boolean, padding: () => number[]): NeonNode => {
		const at = untrack<number>(column) as int32;
		const cell: DataCell = at < row.cells.length ? row.cells[at] : { text: "" };
		const box = (): Style => {
			const pad = padding();
			return {
				height: rowHeight(), paddingLeft: pad[0], paddingRight: pad[1], justifyContent: "center",
				alignItems: numeric ? "flex-end" : "flex-start", backgroundColor: rowFill(row),
			};
		};
		const textStyle = accessor((): Style => {
			const base: Style = { fontSize: 14, color: MATERIAL_ON_SURFACE };
			return dataTextProp === null ? base : mergeStyle(base, (dataTextProp as Accessor<Style>)());
		});
		const child = cell.child;
		const label = cell.text;
		const content: NeonNode = child !== null ? child as NeonNode : element(<Text style={textStyle}>{label === null ? "" : label as string}</Text>);
		const tap = cell.onTap;
		const events = tap !== null
			? [evt("onPress", (e: NeonEvent): void => { (tap as () => void)(); })]
			: (row.onSelectChanged !== null ? [evt("onPress", (e: NeonEvent): void => { toggleRow(row); })] : []);
		const attrs: VAttr[] = [];
		const kind = events.length === 0 ? "view" : "pressable";
		return element(<View>{hostElement(kind, attrs, events, content, box, null)}{divider()}</View>);
	};

	const headerCell = (column: DataColumn, at: Accessor<number>, padding: () => number[]): NeonNode => {
		const numeric = column.numeric !== null && (column.numeric as boolean);
		const sorted = (): boolean => sortIndex() === at();
		const arrow = accessor((): Style => ({
			fontSize: 14, color: HEADING_INK, opacity: sorted() ? 1 : 0, marginLeft: numeric ? 0 : 2, marginRight: numeric ? 2 : 0,
		}));
		const textStyle = accessor((): Style => {
			const base: Style = { fontSize: 14, fontWeight: "bold", color: HEADING_INK };
			return headingTextProp === null ? base : mergeStyle(base, (headingTextProp as Accessor<Style>)());
		});
		const label = element(<Text style={textStyle}>{column.label}</Text>);
		const sortable = column.onSort !== null;
		const mark = element(<Text style={arrow}>{ascending() ? "↑" : "↓"}</Text>);
		const content: NeonNode = !sortable ? label : (numeric ? element(<>{mark}{label}</>) : element(<>{label}{mark}</>));
		const box = (): Style => {
			const pad = padding();
			return {
				height: headingHeight(), paddingLeft: pad[0], paddingRight: pad[1], flexDirection: "row", alignItems: "center",
				justifyContent: numeric ? "flex-end" : "flex-start",
			};
		};
		const attrs: VAttr[] = [];
		if (sortable) {
			attrs.push(dynAttr("accessibilityRole", (): string | null => "button"));
			attrs.push(dynAttr("accessibilityLabel", (): string | null => sorted() ? `${column.label}, sorted ${ascending() ? "ascending" : "descending"}` : column.label));
		}
		const tooltip = column.tooltip;
		if (tooltip !== null) { attrs.push(dynAttr("accessibilityHint", (): string | null => tooltip as string)); }
		const press = (e: NeonEvent): void => {
			const sort = column.onSort;
			if (sort === null) { return; }
			const index = at();
			(sort as (i: number, a: boolean) => void)(index, nextSortAscending(index, sortIndex(), ascending()));
		};
		const events = sortable ? [evt("onPress", press)] : [];
		return element(<View>{hostElement(sortable ? "pressable" : "view", attrs, events, content, box, null)}{divider()}</View>);
	};

	const dataColumn = (column: DataColumn, at: Accessor<number>): NeonNode => {
		const numeric = column.numeric !== null && (column.numeric as boolean);
		const padding = (): number[] => columnPadding(at() as int32, columns().length as int32, checkboxes(), margin(), spacing());
		const cells = For<DataRow>({ each: rows, children: (row: DataRow, r: Accessor<number>): NeonNode => dataCell(at, row, numeric, padding) });
		return element(<View>{headerCell(column, at, padding)}{cells}</View>);
	};

	// data_table.dart: tristate header checkbox, onSelectAll or every row's onSelectChanged.
	const allState = (): int32 => {
		let selected: int32 = 0;
		let selectable: int32 = 0;
		for (const row of rows()) {
			if (row.onSelectChanged === null) { continue; }
			selectable += 1;
			if (rowSelected(row)) { selected += 1; }
		}
		if (selected === 0) { return 0; }
		return selected === selectable ? 2 : 1;
	};
	const selectAll = (checked: boolean): void => {
		if (onSelectAll !== null) {
			(onSelectAll as (s: boolean) => void)(checked);
			return;
		}
		for (const row of untrack<DataRow[]>(rows)) {
			const change = row.onSelectChanged;
			if (change !== null && rowSelected(row) !== checked) { (change as (s: boolean) => void)(checked); }
		}
	};
	const checkPad = (): Style => ({ paddingLeft: margin(), paddingRight: margin() / 2, justifyContent: "center" });
	const checkboxColumn = (): NeonNode => {
		const head = element(<View style={{ ...checkPad(), height: headingHeight() }}>
			<Checkbox value={allState() === 2} indeterminate={allState() === 1} accessibilityLabel="select all rows"
				onValueChange={(v: boolean): void => { selectAll(allState() !== 2); }} />
		</View>);
		const cells = For<DataRow>({
			each: rows,
			children: (row: DataRow, r: Accessor<number>): NeonNode => element(<View>
				<View style={{ ...checkPad(), height: rowHeight(), backgroundColor: rowFill(row) }}>
					<Checkbox value={rowSelected(row)} accessibilityLabel={`select row ${r() + 1}`}
						onValueChange={(v: boolean): void => { toggleRow(row); }} />
				</View>
				{divider()}
			</View>),
		});
		return element(<View>{head}{divider()}{cells}</View>);
	};

	const table = element(<View style={{ flexDirection: "row", alignItems: "flex-start" }}>
		<Show when={checkboxes()}>{checkboxColumn()}</Show>
		<For each={columns()}>{(column: DataColumn, at: Accessor<number>): NeonNode => dataColumn(column, at)}</For>
	</View>);
	const userStyle = props.style;
	return ScrollView({
		horizontal: accessor((): boolean => true),
		style: accessor((): Style => mergeStyle({ flexGrow: 0, backgroundColor: "#ffffff" }, userStyle === null ? {} : (userStyle as Accessor<Style>)())),
		children: table,
	});
}
