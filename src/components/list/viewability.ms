import { CellSource, ListMetricsAggregator } from "./listMetrics";
import { CellMetrics, CellRange } from "./virtualizeUtils";

export interface ViewabilityConfig {
	minimumViewTime?: number | null;
	viewAreaCoveragePercentThreshold?: number | null;
	itemVisiblePercentThreshold?: number | null;
	waitForInteraction?: boolean | null;
}

export interface ViewToken<T> {
	item: T;
	index: number;
	isViewable: boolean;
}

export interface ViewabilityInfo<T> {
	viewableItems: ViewToken<T>[];
	changed: ViewToken<T>[];
	viewabilityConfig: ViewabilityConfig;
}

export interface ViewabilityConfigCallbackPair<T> {
	viewabilityConfig: ViewabilityConfig;
	onViewableItemsChanged: (info: ViewabilityInfo<T>) => void;
}

export class ViewabilityHelper<T> {
	private config: ViewabilityConfig;
	private minimumViewTime: number;
	private waitForInteraction: boolean;
	private hasInteracted: boolean = false;
	private timers: Set<number> = new Set<number>();
	private scanIndices: int32[] = [];
	private viewableIndices: int32[] = [];
	private viewableItems: Map<T, ViewToken<T>> = new Map<T, ViewToken<T>>();

	constructor(config: ViewabilityConfig = { viewAreaCoveragePercentThreshold: 0 }) {
		this.config = config;
		this.minimumViewTime = config.minimumViewTime === null ? 0 : config.minimumViewTime as number;
		this.waitForInteraction = config.waitForInteraction === true;
	}

	update(source: CellSource<T>, metrics: ListMetricsAggregator<T>, offset: number, viewport: number, range: CellRange, callback: (info: ViewabilityInfo<T>) => void): void {
		const minimumViewTime = this.minimumViewTime;
		if ((this.waitForInteraction && !this.hasInteracted) || source.count() === 0 || metrics.getCellMetrics(0, source) === null) { return; }
		this.scan(source, metrics, offset, viewport, range);
		let same = this.viewableIndices.length === this.scanIndices.length;
		if (same) {
			for (let i = 0; i < this.scanIndices.length; i += 1) {
				if (this.viewableIndices[i] !== this.scanIndices[i]) { same = false; break; }
			}
		}
		if (same) { return; }
		const indices = this.scanIndices.slice(0, this.scanIndices.length);
		this.viewableIndices = indices;
		if (minimumViewTime !== 0) {
			let handle: number = -1;
			handle = setTimeout((): void => {
				this.timers.delete(handle);
				this.updateSync(source, indices, callback);
			}, minimumViewTime);
			this.timers.add(handle);
		} else {
			this.updateSync(source, indices, callback);
		}
	}

	recordInteraction(): void {
		this.hasInteracted = true;
	}

	resetViewableIndices(): void {
		this.viewableIndices = [];
	}

	dispose(): void {
		for (const handle of this.timers) { clearTimeout(handle); }
		this.timers.clear();
	}

	private scan(source: CellSource<T>, metrics: ListMetricsAggregator<T>, offset: number, viewport: number, range: CellRange): void {
		const itemVisiblePercentThreshold = this.config.itemVisiblePercentThreshold;
		const viewAreaCoveragePercentThreshold = this.config.viewAreaCoveragePercentThreshold;
		if ((itemVisiblePercentThreshold === null) === (viewAreaCoveragePercentThreshold === null)) {
			throw "Must set exactly one of itemVisiblePercentThreshold or viewAreaCoveragePercentThreshold";
		}
		const viewAreaMode = viewAreaCoveragePercentThreshold !== null;
		const threshold = viewAreaMode ? viewAreaCoveragePercentThreshold as number : itemVisiblePercentThreshold as number;
		let count: int32 = 0;
		let firstVisible: int32 = -1;
		const itemCount = source.count();
		if (range.last >= itemCount) {
			console.warn(`Invalid render range computing viewability ${range.first}..${range.last} for ${itemCount} items`);
		} else {
			for (let index = range.first; index <= range.last; index += 1) {
				const frame = metrics.getCellMetrics(index, source);
				if (frame === null) { continue; }
				const cell = frame as CellMetrics;
				const top = Math.floor(cell.offset - offset);
				const bottom = Math.floor(top + cell.length);
				if (top < viewport && bottom > 0) {
					firstVisible = index;
					if (isViewable(viewAreaMode, threshold, top, bottom, viewport, cell.length)) {
						if (count < this.scanIndices.length) { this.scanIndices[count] = index; }
						else { this.scanIndices.push(index); }
						count += 1;
					}
				} else if (firstVisible >= 0) {
					break;
				}
			}
		}
		while (this.scanIndices.length > count) { this.scanIndices.pop(); }
	}

	private updateSync(source: CellSource<T>, indices: int32[], callback: (info: ViewabilityInfo<T>) => void): void {
		const nextItems = new Map<T, ViewToken<T>>();
		let current: int32 = 0;
		for (const index of indices) {
			while (current < this.viewableIndices.length && this.viewableIndices[current] < index) { current += 1; }
			if (current >= this.viewableIndices.length || this.viewableIndices[current] !== index) { continue; }
			const item = source.keyAt(index);
			nextItems.set(item, { item, index: index as number, isViewable: true });
		}
		const changed: ViewToken<T>[] = [];
		for (const item of nextItems) {
			if (!this.viewableItems.has(item)) { changed.push(nextItems.get(item) as ViewToken<T>); }
		}
		for (const item of this.viewableItems) {
			if (!nextItems.has(item)) {
				const previous = this.viewableItems.get(item) as ViewToken<T>;
				changed.push({ item: previous.item, index: previous.index, isViewable: false });
			}
		}
		if (changed.length === 0) { return; }
		this.viewableItems = nextItems;
		callback({ viewableItems: nextItems.values(), changed, viewabilityConfig: this.config });
	}
}

function isViewable(viewAreaMode: boolean, threshold: number, top: number, bottom: number, viewport: number, length: number): boolean {
	if (top >= 0 && bottom <= viewport && bottom > top) { return true; }
	const pixels = Math.max(0.0, Math.min(bottom, viewport) - Math.max(top, 0.0));
	const percent = 100.0 * (viewAreaMode ? pixels / viewport : pixels / length);
	return percent >= threshold;
}
