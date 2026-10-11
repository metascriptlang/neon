import { sleepAsync } from "std/core/promise";
import { CellSource, ListMetricsAggregator } from "../../../src/components/list/listMetrics";
import { CellMetrics, CellRange } from "../../../src/components/list/virtualizeUtils";
import { ViewabilityConfig, ViewToken, ViewabilityInfo, ViewabilityConfigCallbackPair, ViewabilityHelper } from "../../../src/components/list/viewability";

interface Fixture<T> {
	source: CellSource<T>;
	metrics: ListMetricsAggregator<T>;
	range: CellRange;
}

class Notifications<T> {
	calls: ViewabilityInfo<T>[] = [];
}

interface Item {
	label: string;
}

function fixture<T>(items: T[], offsets: float64[], lengths: float64[]): Fixture<T> {
	const source: CellSource<T> = {
		count: (): int32 => items.length as int32,
		keyAt: (index: int32): T => items[index],
		layoutAt: null,
	};
	const metrics = new ListMetricsAggregator<T>();
	for (let i = 0; i < offsets.length; i += 1) {
		metrics.notifyCellLayout(i as int32, items[i], { horizontal: false, rtl: false }, { x: 0.0, y: offsets[i], width: 100.0, height: lengths[i] });
	}
	return { source, metrics, range: { first: 0, last: (items.length as int32) - 1 } };
}

function observe<T>(notifications: Notifications<T>): (info: ViewabilityInfo<T>) => void {
	return (info: ViewabilityInfo<T>): void => { notifications.calls.push(info); };
}

function indices(tokens: ViewToken<string>[]): string {
	let result = "";
	for (const token of tokens) {
		if (result !== "") { result += ","; }
		result += token.index.toString();
	}
	return result;
}

function tokensShown(tokens: ViewToken<string>[]): string {
	let result = "";
	for (const token of tokens) {
		if (result !== "") { result += ","; }
		result += token.item + "@" + token.index.toString() + (token.isViewable ? "+" : "-");
	}
	return result;
}

function shown(info: ViewabilityInfo<string>): string {
	return "visible:" + tokensShown(info.viewableItems) + " changed:" + tokensShown(info.changed);
}

function visible(config: ViewabilityConfig, rows: Fixture<string>, offset: number, viewport: number): string {
	const helper = new ViewabilityHelper<string>(config);
	const notifications = new Notifications<string>();
	helper.update(rows.source, rows.metrics, offset, viewport, rows.range, observe(notifications));
	helper.dispose();
	if (notifications.calls.length === 0) { return ""; }
	return indices(notifications.calls[0].viewableItems);
}

function caught(fn: () => void): string {
	try {
		fn();
	} catch (e) {
		return e.message;
	}
	return "";
}

test "returns all four entirely visible rows regardless of area threshold" {
	const rows = fixture<string>(["a", "b", "c", "d"], [0.0, 50.0, 100.0, 150.0], [50.0, 50.0, 50.0, 50.0]);
	assert visible({ viewAreaCoveragePercentThreshold: 50 }, rows, 0, 200) === "0,1,2,3", "fully visible short rows do not need to cover half the viewport";
}

test "returns a fully visible row and a row covering the majority of the viewport" {
	const rows = fixture<string>(["a", "b", "c", "d"], [0.0, 50.0, 200.0, 250.0], [50.0, 150.0, 50.0, 50.0]);
	assert visible({ viewAreaCoveragePercentThreshold: 50 }, rows, 0, 200) === "0,1", "top two";
	assert visible({ viewAreaCoveragePercentThreshold: 50 }, rows, 25, 200) === "1", "a partially visible short row covers too little view area";
}

test "area threshold zero requires positive overlap at viewport boundaries" {
	const rows = fixture<string>(["a", "b", "c", "d"], [0.0, 50.0, 200.0, 700.0], [50.0, 150.0, 500.0, 50.0]);
	const config: ViewabilityConfig = { viewAreaCoveragePercentThreshold: 0 };
	assert visible(config, rows, 0, 50) === "0", "a row starting at the viewport end is not visible";
	assert visible(config, rows, 1, 50) === "0,1", "one pixel is enough";
	assert visible(config, rows, 199, 50) === "1,2", "one pixel before the next row";
	assert visible(config, rows, 250, 50) === "2", "a row larger than the viewport";
	assert visible(config, rows, 50, 150) === "1", "a row ending at the viewport start is not visible";
}

test "area threshold one hundred accepts full rows or full viewport coverage" {
	const rows = fixture<string>(["a", "b", "c", "d"], [0.0, 50.0, 200.0, 700.0], [50.0, 150.0, 500.0, 50.0]);
	const config: ViewabilityConfig = { viewAreaCoveragePercentThreshold: 100 };
	assert visible(config, rows, 0, 200) === "0,1", "fully visible rows";
	assert visible(config, rows, 1, 200) === "1", "clipped short row does not cover the viewport";
	assert visible(config, rows, 400, 200) === "2", "oversized row covers the whole viewport";
	assert visible(config, rows, 600, 200) === "3", "fully visible short row beats the area threshold";
}

test "area threshold includes equality and rejects one pixel below it" {
	const rows = fixture<string>(["a", "b", "c", "d"], [0.0, 50.0, 200.0, 700.0], [50.0, 150.0, 500.0, 50.0]);
	assert visible({ viewAreaCoveragePercentThreshold: 10 }, rows, 30, 200) === "0,1,2", "twenty pixels is ten percent";
	assert visible({ viewAreaCoveragePercentThreshold: 10 }, rows, 31, 200) === "1,2", "nineteen pixels is below ten percent";
}

test "item threshold zero requires positive overlap" {
	const rows = fixture<string>(["a", "b", "c", "d"], [0.0, 50.0, 200.0, 250.0], [50.0, 150.0, 50.0, 50.0]);
	assert visible({ itemVisiblePercentThreshold: 0 }, rows, 0, 50) === "0", "touching the viewport is not visibility";
	assert visible({ itemVisiblePercentThreshold: 0 }, rows, 1, 50) === "0,1", "both rows have positive overlap";
}

test "item threshold one hundred requires an entire item" {
	const rows = fixture<string>(["a", "b", "c", "d"], [0.0, 50.0, 200.0, 250.0], [50.0, 150.0, 50.0, 50.0]);
	assert visible({ itemVisiblePercentThreshold: 100 }, rows, 0, 250) === "0,1,2", "three whole rows";
	assert visible({ itemVisiblePercentThreshold: 100 }, rows, 1, 250) === "1,2", "first and last are clipped";
	assert visible({ itemVisiblePercentThreshold: 100 }, rows, 100, 50) === "", "covering the viewport is not enough in item mode";
}

test "item threshold uses item length rather than viewport length" {
	const rows = fixture<string>(["a", "b", "c", "d"], [0.0, 50.0, 200.0, 250.0], [50.0, 150.0, 50.0, 50.0]);
	const config: ViewabilityConfig = { itemVisiblePercentThreshold: 10 };
	assert visible(config, rows, 184, 20) === "1", "sixteen pixels of the tall row";
	assert visible(config, rows, 185, 20) === "1,2", "fifteen and five pixels meet equality for their own row lengths";
	assert visible(config, rows, 186, 20) === "2", "fourteen pixels is below the tall row threshold";
}

test "floors cell boundaries to account for imprecise layout measurements" {
	const rows = fixture<string>(["Item"], [1767.6190185546875], [147.4285888671875]);
	assert visible({ itemVisiblePercentThreshold: 100 }, rows, 1503.61901855, 411.4285583496094) === "0", "RN fractional measurement case";
}

test "floors top before calculating and flooring bottom" {
	const rows = fixture<string>(["a", "b"], [0.0, 50.0], [50.0, 50.0]);
	assert visible({ viewAreaCoveragePercentThreshold: 0 }, rows, 0.9, 50) === "0,1", "the second row starts at floor(49.1), not fifty";
	assert visible({ viewAreaCoveragePercentThreshold: 0 }, rows, 50, 50) === "1", "the first row ends at zero";
}

test "zero length cells and a zero length viewport are not viewable" {
	const rows = fixture<string>(["a", "b"], [0.0, 0.0], [0.0, 50.0]);
	assert visible({ viewAreaCoveragePercentThreshold: 0 }, rows, 0, 50) === "1", "zero length row has no pixels";
	assert visible({ viewAreaCoveragePercentThreshold: 0 }, rows, 0, 0) === "", "viewport has no pixels";
}

test "requires exactly one threshold when a config is supplied" {
	const rows = fixture<string>(["a"], [0.0], [50.0]);
	const message = "Must set exactly one of itemVisiblePercentThreshold or viewAreaCoveragePercentThreshold";
	assert caught((): void => { visible({}, rows, 0, 50); }) === message, "neither threshold";
	assert caught((): void => { visible({ itemVisiblePercentThreshold: 0, viewAreaCoveragePercentThreshold: 0 }, rows, 0, 50); }) === message, "zero still counts as a supplied threshold";
	assert caught((): void => { visible({ itemVisiblePercentThreshold: null, viewAreaCoveragePercentThreshold: null }, rows, 0, 50); }) === message, "null is absence";
	assert caught((): void => { visible({ minimumViewTime: 10 }, rows, 0, 50); }) === message, "an absent threshold is absence on every backend";
}

test "an omitted config defaults to view area threshold zero" {
	const rows = fixture<string>(["a"], [0.0], [50.0]);
	const helper = new ViewabilityHelper<string>();
	const notifications = new Notifications<string>();
	helper.update(rows.source, rows.metrics, 49, 100, rows.range, observe(notifications));
	assert notifications.calls.length === 1, "one pixel fires under the default";
	assert notifications.calls[0].viewabilityConfig.viewAreaCoveragePercentThreshold === 0, "callback exposes the effective config";
	assert visible({ itemVisiblePercentThreshold: 1 }, rows, 49, 100) === "0", "a single item threshold is the one supplied threshold";
}

test "waitForInteraction blocks updates until an interaction is recorded" {
	const rows = fixture<string>(["a", "b"], [0.0, 200.0], [200.0, 200.0]);
	const helper = new ViewabilityHelper<string>({ waitForInteraction: true, viewAreaCoveragePercentThreshold: 0 });
	const notifications = new Notifications<string>();
	const callback = observe(notifications);
	helper.update(rows.source, rows.metrics, 0, 100, rows.range, callback);
	assert notifications.calls.length === 0, "initial render is not an interaction";
	helper.recordInteraction();
	assert notifications.calls.length === 0, "recordInteraction does not invent metrics or a callback";
	helper.update(rows.source, rows.metrics, 20, 100, rows.range, callback);
	assert notifications.calls.length === 1, "subsequent update reports visibility";
	assert shown(notifications.calls[0]) === "visible:a@0+ changed:a@0+", shown(notifications.calls[0]);
}

test "reports enter and exit tokens without duplicate callbacks" {
	const rows = fixture<string>(["a", "b"], [0.0, 200.0], [200.0, 200.0]);
	const helper = new ViewabilityHelper<string>();
	const notifications = new Notifications<string>();
	const callback = observe(notifications);
	helper.update(rows.source, rows.metrics, 0, 200, rows.range, callback);
	assert shown(notifications.calls[0]) === "visible:a@0+ changed:a@0+", shown(notifications.calls[0]);
	for (let i = 0; i < 20; i += 1) { helper.update(rows.source, rows.metrics, 0, 200, rows.range, callback); }
	assert notifications.calls.length === 1, "unchanged scroll events are silent";
	helper.update(rows.source, rows.metrics, 100, 200, rows.range, callback);
	assert shown(notifications.calls[1]) === "visible:a@0+,b@1+ changed:b@1+", shown(notifications.calls[1]);
	helper.update(rows.source, rows.metrics, 200, 200, rows.range, callback);
	assert shown(notifications.calls[2]) === "visible:b@1+ changed:a@0-", shown(notifications.calls[2]);
	helper.update(rows.source, rows.metrics, 400, 200, rows.range, callback);
	assert shown(notifications.calls[3]) === "visible: changed:b@1-", shown(notifications.calls[3]);
	assert shown(notifications.calls[0]) === "visible:a@0+ changed:a@0+", "later events do not mutate prior callback arrays";
}

test "lists newly viewable tokens before exiting tokens" {
	const rows = fixture<string>(["a", "b"], [0.0, 200.0], [200.0, 200.0]);
	const helper = new ViewabilityHelper<string>();
	const notifications = new Notifications<string>();
	const callback = observe(notifications);
	helper.update(rows.source, rows.metrics, 0, 200, rows.range, callback);
	helper.update(rows.source, rows.metrics, 200, 200, rows.range, callback);
	assert shown(notifications.calls[1]) === "visible:b@1+ changed:b@1+,a@0-", shown(notifications.calls[1]);
}

test "reset reevaluates unchanged indices using item identity" {
	const a: Item = { label: "same" };
	const b: Item = { label: "same" };
	const items: Item[] = [a];
	const rows = fixture<Item>(items, [0.0], [200.0]);
	const helper = new ViewabilityHelper<Item>();
	const notifications = new Notifications<Item>();
	const callback = observe(notifications);
	helper.update(rows.source, rows.metrics, 0, 200, rows.range, callback);
	items[0] = b;
	rows.metrics.notifyCellLayout(0, b, { horizontal: false, rtl: false }, { x: 0.0, y: 0.0, width: 100.0, height: 200.0 });
	helper.resetViewableIndices();
	helper.update(rows.source, rows.metrics, 0, 200, rows.range, callback);
	assert notifications.calls.length === 2, "same index, different Solid identity";
	const info = notifications.calls[1];
	assert info.viewableItems.length === 1 && info.viewableItems[0].item === b, "the new item is viewable";
	assert info.changed.length === 2, "enter and exit";
	assert info.changed[0].item === b && info.changed[0].isViewable, "new identity enters even with the same label";
	assert info.changed[1].item === a && !info.changed[1].isViewable && info.changed[1].index === 0, "previous identity and previous index exit";
}

test "callback pairs expose plain configs and typed item notifications" {
	const rows = fixture<string>(["a"], [0.0], [50.0]);
	const notifications = new Notifications<string>();
	const config: ViewabilityConfig = { viewAreaCoveragePercentThreshold: 10 };
	const pair: ViewabilityConfigCallbackPair<string> = { viewabilityConfig: config, onViewableItemsChanged: observe(notifications) };
	const helper = new ViewabilityHelper<string>(pair.viewabilityConfig);
	helper.update(rows.source, rows.metrics, 0, 50, rows.range, pair.onViewableItemsChanged);
	assert notifications.calls[0].viewabilityConfig === config, "the callback receives the configured object";
	assert notifications.calls[0].viewableItems[0].item === "a", "item identity needs no React string key";
}

test "scans only the render range and stops after the last overlapping measured row" {
	const queried: int32[] = [];
	const source: CellSource<string> = {
		count: (): int32 => 10000,
		keyAt: (index: int32): string => index.toString(),
		layoutAt: (index: int32): CellMetrics => {
			queried.push(index);
			return { index, offset: (index as float64) * 100.0, length: 100.0, isMounted: true };
		},
	};
	const helper = new ViewabilityHelper<string>();
	const metrics = new ListMetricsAggregator<string>();
	const notifications = new Notifications<string>();
	helper.update(source, metrics, 500000, 100, { first: 5000, last: 5002 }, observe(notifications));
	assert queried.length === 3, "one RN first-cell guard and two render-range metrics";
	assert queried[0] === 0 && queried[1] === 5000 && queried[2] === 5001, "does not scan thousands of off-window rows";
	assert shown(notifications.calls[0]) === "visible:5000@5000+ changed:5000@5000+", shown(notifications.calls[0]);
}

test "uses measured metrics and never average approximations for missing cells" {
	const rows = fixture<string>(["a", "b", "c"], [0.0], [50.0]);
	const helper = new ViewabilityHelper<string>();
	const notifications = new Notifications<string>();
	const callback = observe(notifications);
	helper.update(rows.source, rows.metrics, 0, 200, rows.range, callback);
	assert shown(notifications.calls[0]) === "visible:a@0+ changed:a@0+", "estimated unmeasured rows cannot enter";
	rows.metrics.notifyCellLayout(2, "c", { horizontal: false, rtl: false }, { x: 0.0, y: 100.0, width: 100.0, height: 50.0 });
	helper.update(rows.source, rows.metrics, 0, 200, rows.range, callback);
	assert shown(notifications.calls[1]) === "visible:a@0+,c@2+ changed:c@2+", "a missing metric does not stop the scan";
}

test "defers updates until the first cell has exact metrics" {
	const rows = fixture<string>(["a", "b"], [], []);
	rows.metrics.notifyCellLayout(1, "b", { horizontal: false, rtl: false }, { x: 0.0, y: 50.0, width: 100.0, height: 50.0 });
	const helper = new ViewabilityHelper<string>();
	const notifications = new Notifications<string>();
	const callback = observe(notifications);
	helper.update(rows.source, rows.metrics, 50, 50, { first: 1, last: 1 }, callback);
	assert notifications.calls.length === 0, "RN first-cell guard applies even outside the scan range";
	rows.metrics.notifyCellLayout(0, "a", { horizontal: false, rtl: false }, { x: 0.0, y: 0.0, width: 100.0, height: 50.0 });
	helper.update(rows.source, rows.metrics, 50, 50, { first: 1, last: 1 }, callback);
	assert shown(notifications.calls[0]) === "visible:b@1+ changed:b@1+", shown(notifications.calls[0]);
}

test "exact metrics remain usable after a cell unmounts" {
	const rows = fixture<string>(["a"], [0.0], [50.0]);
	rows.metrics.notifyCellUnmounted("a");
	assert visible({ viewAreaCoveragePercentThreshold: 0 }, rows, 0, 50) === "0", "RN viewability does not require isMounted";
}

test "empty data does not emit an initial callback" {
	const rows = fixture<string>([], [], []);
	assert visible({ viewAreaCoveragePercentThreshold: 0 }, rows, 0, 200) === "", "empty source";
}

test "minimumViewTime delays a callback and unchanged updates stay silent" {
	const rows = fixture<string>(["a", "b"], [0.0, 200.0], [200.0, 200.0]);
	const helper = new ViewabilityHelper<string>({ minimumViewTime: 180, viewAreaCoveragePercentThreshold: 0 });
	const notifications = new Notifications<string>();
	const callback = observe(notifications);
	helper.update(rows.source, rows.metrics, 0, 200, rows.range, callback);
	assert notifications.calls.length === 0, "not synchronous";
	await sleepAsync(60);
	assert notifications.calls.length === 0, "before minimum duration";
	await sleepAsync(250);
	assert notifications.calls.length === 1, "after minimum duration";
	assert shown(notifications.calls[0]) === "visible:a@0+ changed:a@0+", shown(notifications.calls[0]);
	helper.update(rows.source, rows.metrics, 0, 200, rows.range, callback);
	await sleepAsync(250);
	assert notifications.calls.length === 1, "same indices do not schedule a duplicate notification";
	helper.dispose();
}

test "minimumViewTime filters briefly visible rows that exited before their timer" {
	const rows = fixture<string>(["a", "b"], [0.0, 250.0], [250.0, 200.0]);
	const helper = new ViewabilityHelper<string>({ minimumViewTime: 180, viewAreaCoveragePercentThreshold: 0 });
	const notifications = new Notifications<string>();
	const callback = observe(notifications);
	helper.update(rows.source, rows.metrics, 0, 200, rows.range, callback);
	helper.update(rows.source, rows.metrics, 300, 200, rows.range, callback);
	await sleepAsync(300);
	assert notifications.calls.length === 1, "only the surviving item gets a callback";
	assert shown(notifications.calls[0]) === "visible:b@1+ changed:b@1+", shown(notifications.calls[0]);
	helper.dispose();
}

test "minimumViewTime does not report rows that leave for an empty viewport" {
	const rows = fixture<string>(["a"], [0.0], [200.0]);
	const helper = new ViewabilityHelper<string>({ minimumViewTime: 180, viewAreaCoveragePercentThreshold: 0 });
	const notifications = new Notifications<string>();
	const callback = observe(notifications);
	helper.update(rows.source, rows.metrics, 0, 200, rows.range, callback);
	helper.update(rows.source, rows.metrics, 1000, 200, rows.range, callback);
	await sleepAsync(300);
	assert notifications.calls.length === 0, "an unreported item produces neither enter nor exit";
	helper.dispose();
}

test "minimumViewTime delays exit notifications for previously reported rows" {
	const rows = fixture<string>(["a"], [0.0], [200.0]);
	const helper = new ViewabilityHelper<string>({ minimumViewTime: 180, viewAreaCoveragePercentThreshold: 0 });
	const notifications = new Notifications<string>();
	const callback = observe(notifications);
	helper.update(rows.source, rows.metrics, 0, 200, rows.range, callback);
	await sleepAsync(300);
	assert notifications.calls.length === 1, "entry reported";
	helper.update(rows.source, rows.metrics, 1000, 200, rows.range, callback);
	assert notifications.calls.length === 1, "exit is not synchronous";
	await sleepAsync(300);
	assert notifications.calls.length === 2, "exit reported after the timer";
	assert shown(notifications.calls[1]) === "visible: changed:a@0-", shown(notifications.calls[1]);
	helper.dispose();
}

test "pending timers retain their own candidates while filtering against current visibility" {
	const rows = fixture<string>(["a", "b"], [0.0, 200.0], [200.0, 200.0]);
	const helper = new ViewabilityHelper<string>({ minimumViewTime: 180, viewAreaCoveragePercentThreshold: 0 });
	const notifications = new Notifications<string>();
	const callback = observe(notifications);
	helper.update(rows.source, rows.metrics, 0, 200, rows.range, callback);
	helper.update(rows.source, rows.metrics, 100, 200, rows.range, callback);
	await sleepAsync(300);
	assert notifications.calls.length === 2, "each snapshot is checked independently";
	assert shown(notifications.calls[0]) === "visible:a@0+ changed:a@0+", "first timer must not inherit the later row";
	assert shown(notifications.calls[1]) === "visible:a@0+,b@1+ changed:b@1+", "second timer adds only its new item";
	helper.dispose();
}

test "dispose cancels every pending minimumViewTime timer" {
	const rows = fixture<string>(["a", "b"], [0.0, 200.0], [200.0, 200.0]);
	const helper = new ViewabilityHelper<string>({ minimumViewTime: 180, viewAreaCoveragePercentThreshold: 0 });
	const notifications = new Notifications<string>();
	const callback = observe(notifications);
	helper.update(rows.source, rows.metrics, 0, 200, rows.range, callback);
	helper.update(rows.source, rows.metrics, 100, 200, rows.range, callback);
	helper.dispose();
	helper.dispose();
	await sleepAsync(300);
	assert notifications.calls.length === 0, "no late callback after disposal";
}

test "resetViewableIndices invalidates candidates in pending timers" {
	const rows = fixture<string>(["a"], [0.0], [200.0]);
	const helper = new ViewabilityHelper<string>({ minimumViewTime: 180, viewAreaCoveragePercentThreshold: 0 });
	const notifications = new Notifications<string>();
	helper.update(rows.source, rows.metrics, 0, 200, rows.range, observe(notifications));
	helper.resetViewableIndices();
	await sleepAsync(300);
	assert notifications.calls.length === 0, "reset indices no longer pass the delayed visibility filter";
	helper.dispose();
}
