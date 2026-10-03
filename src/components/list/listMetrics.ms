import { CellMetrics } from "./virtualizeUtils";

// React Native's ListMetricsAggregator (packages/virtualized-lists/Lists/ListMetricsAggregator.js):
// measured cell metrics keyed by cell, an average length for the cells not measured yet.

export struct ListOrientation {
	horizontal: boolean;
	rtl: boolean;
}

export struct LayoutBox {
	x: float64;
	y: float64;
	width: float64;
	height: float64;
}

export interface CellSource<K> {
	count: () => int32;
	keyAt: (index: int32) => K;
	layoutAt: ((index: int32) => CellMetrics) | null;
}

export class ListMetricsAggregator<K> {
	private averageCellLength: float64 = 0.0;
	private cellMetrics: Map<K, CellMetrics> = new Map<K, CellMetrics>();
	private contentLength: float64 | null = null;
	private highestMeasuredCellIndex: int32 = 0;
	private measuredCellsLength: float64 = 0.0;
	private measuredCellsCount: int32 = 0;
	private orientation: ListOrientation = { horizontal: false, rtl: false };

	notifyCellLayout(cellIndex: int32, cellKey: K, orientation: ListOrientation, layout: LayoutBox): boolean {
		this.invalidateIfOrientationChanged(orientation);
		const next: CellMetrics = { index: cellIndex, length: this.selectLength(layout.width, layout.height), offset: this.flowRelativeOffset(layout, null), isMounted: true };
		if (this.cellMetrics.has(cellKey)) {
			const curr = this.cellMetrics.get(cellKey) as CellMetrics;
			if (next.offset === curr.offset && next.length === curr.length) {
				this.cellMetrics.set(cellKey, { ...curr, isMounted: true });
				return false;
			}
			this.measuredCellsLength += next.length - curr.length;
		} else {
			this.measuredCellsLength += next.length;
			this.measuredCellsCount += 1;
		}
		this.averageCellLength = this.measuredCellsLength / (this.measuredCellsCount as float64);
		this.cellMetrics.set(cellKey, next);
		this.highestMeasuredCellIndex = Math.max(this.highestMeasuredCellIndex, cellIndex);
		return true;
	}

	notifyCellUnmounted(cellKey: K): void {
		if (!this.cellMetrics.has(cellKey)) { return; }
		const curr = this.cellMetrics.get(cellKey) as CellMetrics;
		this.cellMetrics.set(cellKey, { ...curr, isMounted: false });
	}

	notifyListContentLayout(orientation: ListOrientation, width: float64, height: float64): void {
		this.invalidateIfOrientationChanged(orientation);
		this.contentLength = this.selectLength(width, height);
	}

	getAverageCellLength(): float64 {
		return this.averageCellLength;
	}

	getHighestMeasuredCellIndex(): int32 {
		return this.highestMeasuredCellIndex;
	}

	getCellMetricsApprox(index: int32, source: CellSource<K>): CellMetrics {
		const frame = this.getCellMetrics(index, source);
		if (frame !== null && (frame as CellMetrics).index === index) { return frame as CellMetrics; }
		if (index < 0 || index >= source.count()) {
			throw `ListMetricsAggregator: cell index ${index} is outside the ${source.count()} cells`;
		}
		let offset = this.averageCellLength * (index as float64);
		const highest = this.highestMeasuredCellIndex;
		if (highest < index) {
			const highestFrame = this.getCellMetrics(highest, source);
			if (highestFrame !== null) {
				const h = highestFrame as CellMetrics;
				offset = h.offset + h.length + this.averageCellLength * ((index - highest - 1) as float64);
			}
		}
		return { index, length: this.averageCellLength, offset, isMounted: false };
	}

	getCellMetrics(index: int32, source: CellSource<K>): CellMetrics | null {
		if (index < 0 || index >= source.count()) {
			throw `ListMetricsAggregator: cell index ${index} is outside the ${source.count()} cells`;
		}
		const key = source.keyAt(index);
		if (this.cellMetrics.has(key)) {
			const frame = this.cellMetrics.get(key) as CellMetrics;
			if (frame.index === index) { return frame; }
		}
		if (source.layoutAt !== null) {
			const layout = (source.layoutAt as (index: int32) => CellMetrics)(index);
			return { index, length: layout.length, offset: layout.offset, isMounted: true };
		}
		return null;
	}

	getCellOffsetApprox(index: float64, source: CellSource<K>): float64 {
		const whole = Math.floor(index);
		const frame = this.getCellMetricsApprox(whole as int32, source);
		if (whole === index) { return frame.offset; }
		return frame.offset + (index - whole) * frame.length;
	}

	getContentLength(): float64 {
		return this.contentLength ?? 0.0;
	}

	hasContentLength(): boolean {
		return this.contentLength !== null;
	}

	flowRelativeOffset(layout: LayoutBox, referenceContentLength: float64 | null): float64 {
		if (this.orientation.horizontal && this.orientation.rtl) {
			const contentLength = referenceContentLength ?? this.contentLength;
			if (contentLength === null) {
				throw "ListMetricsAggregator needs the list's content layout before it resolves right-to-left offsets";
			}
			return (contentLength as float64) - (this.selectOffset(layout.x, layout.y) + this.selectLength(layout.width, layout.height));
		}
		return this.selectOffset(layout.x, layout.y);
	}

	cartesianOffset(flowRelativeOffset: float64): float64 {
		if (this.orientation.horizontal && this.orientation.rtl) {
			if (this.contentLength === null) {
				throw "ListMetricsAggregator needs the list's content layout before it resolves right-to-left offsets";
			}
			return (this.contentLength as float64) - flowRelativeOffset;
		}
		return flowRelativeOffset;
	}

	private invalidateIfOrientationChanged(orientation: ListOrientation): void {
		if (orientation.rtl !== this.orientation.rtl) { this.cellMetrics.clear(); }
		if (orientation.horizontal !== this.orientation.horizontal) {
			this.averageCellLength = 0.0;
			this.highestMeasuredCellIndex = 0;
			this.measuredCellsLength = 0.0;
			this.measuredCellsCount = 0;
		}
		this.orientation = orientation;
	}

	private selectLength(width: float64, height: float64): float64 {
		return this.orientation.horizontal ? width : height;
	}

	private selectOffset(x: float64, y: float64): float64 {
		return this.orientation.horizontal ? x : y;
	}
}
