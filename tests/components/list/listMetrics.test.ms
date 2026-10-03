import { ListMetricsAggregator, ListOrientation, LayoutBox, CellSource } from "../../../src/components/list/listMetrics";
import { CellMetrics } from "../../../src/components/list/virtualizeUtils";

// Ported from React Native packages/virtualized-lists/Lists/__tests__/ListMetricsAggregator-test.js;
// each test keeps the RN case's name, layouts and expected metrics. RN keys cells by the
// default keyExtractor, String(index), and so do these sources.

const V: ListOrientation = { horizontal: false, rtl: false };
const H: ListOrientation = { horizontal: true, rtl: false };
const HR: ListOrientation = { horizontal: true, rtl: true };
const VR: ListOrientation = { horizontal: false, rtl: true };

const five: CellSource<string> = {
	count: (): int32 => 5,
	keyAt: (index: int32): string => index.toString(),
	layoutAt: null,
};

const fiveWithLayout: CellSource<string> = {
	count: (): int32 => 5,
	keyAt: (index: int32): string => index.toString(),
	layoutAt: (index: int32): CellMetrics => ({ index: 2, length: 40.0, offset: 30.0, isMounted: true }),
};

function box(x: float64, y: float64, width: float64, height: float64): LayoutBox {
	return { x, y, width, height };
}

function shown(m: CellMetrics | null): string {
	if (m === null) { return "null"; }
	const c = m as CellMetrics;
	return `${c.index},${c.length},${c.offset},${c.isMounted}`;
}

function caught(fn: () => void): string {
	try {
		fn();
	} catch (e) {
		return e.toString();
	}
	return "";
}

function measured(orientation: ListOrientation, a: LayoutBox, b: LayoutBox): ListMetricsAggregator<string> {
	const agg = new ListMetricsAggregator<string>();
	agg.notifyCellLayout(0, "0", orientation, a);
	agg.notifyCellLayout(1, "1", orientation, b);
	return agg;
}

test "keeps a running average length of measured cells" {
	const agg = new ListMetricsAggregator<string>();
	assert agg.getAverageCellLength() === 0.0, "nothing measured";
	agg.notifyCellLayout(0, "0", V, box(0.0, 0.0, 5.0, 10.0));
	assert agg.getAverageCellLength() === 10.0, "one cell";
	agg.notifyCellLayout(1, "1", V, box(0.0, 10.0, 5.0, 20.0));
	assert agg.getAverageCellLength() === 15.0, "two cells";
}

test "adjusts the average cell length when layout changes" {
	const agg = measured(V, box(0.0, 0.0, 5.0, 10.0), box(0.0, 10.0, 5.0, 20.0));
	assert agg.getAverageCellLength() === 15.0, "two cells";
	agg.notifyCellLayout(0, "0", V, box(0.0, 0.0, 5.0, 20.0));
	assert agg.getAverageCellLength() === 20.0, "the same key replaces its length: " + agg.getAverageCellLength().toString();
}

test "keeps track of the highest measured cell index" {
	const agg = new ListMetricsAggregator<string>();
	assert agg.getHighestMeasuredCellIndex() === 0, "nothing measured";
	agg.notifyCellLayout(0, "0", V, box(0.0, 0.0, 5.0, 10.0));
	assert agg.getHighestMeasuredCellIndex() === 0, "cell 0";
	agg.notifyCellLayout(1, "1", V, box(0.0, 10.0, 5.0, 20.0));
	assert agg.getHighestMeasuredCellIndex() === 1, "cell 1";
}

test "resets measurements if list orientation changes" {
	const agg = new ListMetricsAggregator<string>();
	agg.notifyCellLayout(0, "0", V, box(0.0, 0.0, 5.0, 10.0));
	assert agg.getAverageCellLength() === 10.0, "vertical";
	agg.notifyCellLayout(1, "1", H, box(0.0, 10.0, 5.0, 20.0));
	assert agg.getAverageCellLength() === 5.0, "a horizontal flip resets and measures width: " + agg.getAverageCellLength().toString();
}

test "resolves metrics of already measured cell" {
	const agg = measured(V, box(0.0, 0.0, 5.0, 10.0), box(0.0, 10.0, 5.0, 20.0));
	assert shown(agg.getCellMetrics(1, five)) === "1,20,10,true", shown(agg.getCellMetrics(1, five));
	assert shown(agg.getCellMetricsApprox(1, five)) === "1,20,10,true", shown(agg.getCellMetricsApprox(1, five));
}

test "estimates metrics of unmeasured cell" {
	const agg = measured(V, box(0.0, 100.0, 5.0, 10.0), box(0.0, 110.0, 5.0, 20.0));
	assert shown(agg.getCellMetrics(2, five)) === "null", shown(agg.getCellMetrics(2, five));
	assert shown(agg.getCellMetricsApprox(2, five)) === "2,15,130,false", shown(agg.getCellMetricsApprox(2, five));
}

test "uses getItemLayout for metrics of unmeasured cell" {
	const agg = measured(V, box(0.0, 0.0, 5.0, 10.0), box(0.0, 10.0, 5.0, 20.0));
	assert shown(agg.getCellMetrics(2, fiveWithLayout)) === "2,40,30,true", shown(agg.getCellMetrics(2, fiveWithLayout));
	assert shown(agg.getCellMetricsApprox(2, fiveWithLayout)) === "2,40,30,true", shown(agg.getCellMetricsApprox(2, fiveWithLayout));
}

test "resolves horizontal metrics of already measured cell" {
	const agg = measured(H, box(0.0, 0.0, 10.0, 5.0), box(10.0, 0.0, 20.0, 5.0));
	assert shown(agg.getCellMetrics(1, five)) === "1,20,10,true", shown(agg.getCellMetrics(1, five));
	assert shown(agg.getCellMetricsApprox(1, five)) === "1,20,10,true", shown(agg.getCellMetricsApprox(1, five));
}

test "estimates horizontal metrics of unmeasured cell" {
	const agg = measured(H, box(0.0, 0.0, 10.0, 5.0), box(10.0, 0.0, 20.0, 5.0));
	assert shown(agg.getCellMetrics(2, five)) === "null", shown(agg.getCellMetrics(2, five));
	assert shown(agg.getCellMetricsApprox(2, five)) === "2,15,30,false", shown(agg.getCellMetricsApprox(2, five));
}

test "uses getItemLayout for horizontal metrics of unmeasured cell" {
	const agg = measured(H, box(0.0, 0.0, 10.0, 5.0), box(10.0, 0.0, 20.0, 5.0));
	assert shown(agg.getCellMetrics(2, fiveWithLayout)) === "2,40,30,true", shown(agg.getCellMetrics(2, fiveWithLayout));
	assert shown(agg.getCellMetricsApprox(2, fiveWithLayout)) === "2,40,30,true", shown(agg.getCellMetricsApprox(2, fiveWithLayout));
}

test "resolves RTL metrics of already measured cell" {
	const agg = new ListMetricsAggregator<string>();
	agg.notifyListContentLayout(HR, 100.0, 5.0);
	agg.notifyCellLayout(0, "0", HR, box(90.0, 0.0, 10.0, 5.0));
	agg.notifyCellLayout(1, "1", HR, box(70.0, 0.0, 20.0, 5.0));
	assert shown(agg.getCellMetrics(1, five)) === "1,20,10,true", shown(agg.getCellMetrics(1, five));
	assert shown(agg.getCellMetricsApprox(1, five)) === "1,20,10,true", shown(agg.getCellMetricsApprox(1, five));
}

test "estimates RTL metrics of unmeasured cell" {
	const agg = new ListMetricsAggregator<string>();
	agg.notifyListContentLayout(HR, 100.0, 5.0);
	agg.notifyCellLayout(0, "0", HR, box(70.0, 0.0, 10.0, 5.0));
	agg.notifyCellLayout(1, "1", HR, box(50.0, 0.0, 20.0, 5.0));
	assert shown(agg.getCellMetricsApprox(2, five)) === "2,15,50,false", shown(agg.getCellMetricsApprox(2, five));
}

test "uses getItemLayout for RTL metrics of unmeasured cell" {
	const agg = new ListMetricsAggregator<string>();
	agg.notifyListContentLayout(HR, 100.0, 5.0);
	agg.notifyCellLayout(0, "0", HR, box(90.0, 0.0, 10.0, 5.0));
	agg.notifyCellLayout(1, "1", HR, box(70.0, 0.0, 20.0, 5.0));
	assert shown(agg.getCellMetrics(2, fiveWithLayout)) === "2,40,30,true", "getItemLayout is not mirrored: " + shown(agg.getCellMetrics(2, fiveWithLayout));
	assert shown(agg.getCellMetricsApprox(2, fiveWithLayout)) === "2,40,30,true", shown(agg.getCellMetricsApprox(2, fiveWithLayout));
}

test "resolves vertical rtl metrics of already measured cell" {
	const agg = measured(VR, box(0.0, 0.0, 5.0, 10.0), box(0.0, 10.0, 5.0, 20.0));
	assert shown(agg.getCellMetrics(1, five)) === "1,20,10,true", "rtl is ignored when vertical: " + shown(agg.getCellMetrics(1, five));
	assert shown(agg.getCellMetricsApprox(1, five)) === "1,20,10,true", shown(agg.getCellMetricsApprox(1, five));
}

test "estimates vertical RTL metrics of unmeasured cell" {
	const agg = measured(VR, box(0.0, 0.0, 5.0, 10.0), box(0.0, 10.0, 5.0, 20.0));
	assert shown(agg.getCellMetrics(2, five)) === "null", shown(agg.getCellMetrics(2, five));
	assert shown(agg.getCellMetricsApprox(2, five)) === "2,15,30,false", shown(agg.getCellMetricsApprox(2, five));
}

test "uses getItemLayout for vertical RTL metrics of unmeasured cell" {
	const agg = measured(VR, box(0.0, 0.0, 5.0, 10.0), box(0.0, 10.0, 5.0, 20.0));
	assert shown(agg.getCellMetrics(2, fiveWithLayout)) === "2,40,30,true", shown(agg.getCellMetrics(2, fiveWithLayout));
	assert shown(agg.getCellMetricsApprox(2, fiveWithLayout)) === "2,40,30,true", shown(agg.getCellMetricsApprox(2, fiveWithLayout));
}

test "resolves metrics of unmounted cell after list shift" {
	const agg = new ListMetricsAggregator<string>();
	agg.notifyListContentLayout(HR, 100.0, 5.0);
	agg.notifyCellLayout(0, "0", HR, box(90.0, 0.0, 10.0, 5.0));
	agg.notifyCellLayout(1, "1", HR, box(70.0, 0.0, 20.0, 5.0));
	assert shown(agg.getCellMetrics(1, five)) === "1,20,10,true", "measured";
	agg.notifyListContentLayout(HR, 120.0, 5.0);
	agg.notifyCellLayout(2, "2", HR, box(50.0, 0.0, 20.0, 5.0));
	assert shown(agg.getCellMetrics(1, five)) === "1,20,10,true", "offsets are frozen at measurement: " + shown(agg.getCellMetrics(1, five));
	agg.notifyListContentLayout(HR, 100.0, 5.0);
	assert shown(agg.getCellMetrics(1, five)) === "1,20,10,true", "still frozen";
	agg.notifyCellUnmounted("1");
	assert shown(agg.getCellMetrics(1, five)) === "1,20,10,false", "unmounting keeps the metrics: " + shown(agg.getCellMetrics(1, five));
}

test "resolves integral offset of already measured cell" {
	const agg = measured(V, box(0.0, 0.0, 5.0, 10.0), box(0.0, 10.0, 5.0, 20.0));
	assert agg.getCellOffsetApprox(1.0, five) === 10.0, agg.getCellOffsetApprox(1.0, five).toString();
}

test "estimates integral offset of unmeasured cell" {
	const agg = measured(V, box(0.0, 0.0, 5.0, 10.0), box(0.0, 10.0, 5.0, 20.0));
	assert agg.getCellOffsetApprox(2.0, five) === 30.0, agg.getCellOffsetApprox(2.0, five).toString();
}

test "resolves fractional offset of already measured cell" {
	const agg = measured(V, box(0.0, 0.0, 5.0, 10.0), box(0.0, 10.0, 5.0, 20.0));
	assert agg.getCellOffsetApprox(1.5, five) === 20.0, agg.getCellOffsetApprox(1.5, five).toString();
}

test "estimates fractional offset of unmeasured cell" {
	const agg = measured(V, box(0.0, 0.0, 5.0, 10.0), box(0.0, 10.0, 5.0, 20.0));
	assert agg.getCellOffsetApprox(2.5, five) === 37.5, agg.getCellOffsetApprox(2.5, five).toString();
}

test "remembers most recent content length" {
	const agg = new ListMetricsAggregator<string>();
	assert !agg.hasContentLength() && agg.getContentLength() === 0.0, "nothing laid out";
	agg.notifyListContentLayout(V, 20.0, 10.0);
	assert agg.hasContentLength() && agg.getContentLength() === 10.0, "first layout";
	agg.notifyListContentLayout(V, 25.0, 15.0);
	assert agg.getContentLength() === 15.0, "latest layout";
}

test "remembers most recent horizontal content length" {
	const agg = new ListMetricsAggregator<string>();
	assert !agg.hasContentLength() && agg.getContentLength() === 0.0, "nothing laid out";
	agg.notifyListContentLayout(H, 20.0, 10.0);
	assert agg.getContentLength() === 20.0, "width";
	agg.notifyListContentLayout(H, 25.0, 15.0);
	assert agg.getContentLength() === 25.0, "latest width";
}

test "requires contentLength to resolve RTL metrics" {
	const agg = new ListMetricsAggregator<string>();
	const msg = caught((): void => { agg.notifyCellLayout(0, "0", HR, box(0.0, 0.0, 5.0, 10.0)); });
	assert msg.includes("content layout"), "fails loud and names the missing content layout: " + msg;
}
