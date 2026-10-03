// React Native's CellRenderMask (packages/virtualized-lists/Lists/CellRenderMask.js): the
// rows of a list split into runs of rendered cells and runs a spacer stands in for.

export struct CellRegion {
	first: int32;
	last: int32;
	isSpacer: boolean;
}

export struct CellSpan {
	first: int32;
	last: int32;
}

export class CellRenderMask {
	numCells: int32;
	private regions: CellRegion[];

	constructor(numCells: int32) {
		if (numCells < 0) { throw `CellRenderMask needs a non-negative number of cells, got ${numCells}`; }
		this.numCells = numCells;
		this.regions = numCells === 0 ? [] : [{ first: 0, last: numCells - 1, isSpacer: true }];
	}

	enumerateRegions(): CellRegion[] {
		return this.regions;
	}

	addCells(cells: CellSpan): void {
		if (cells.first < 0 || cells.first >= this.numCells || cells.last < -1 || cells.last >= this.numCells || cells.last < cells.first - 1) {
			throw `CellRenderMask.addCells: invalid cell range ${cells.first}..${cells.last} for ${this.numCells} cells`;
		}
		if (cells.last < cells.first) { return; }

		const firstIdx = this.findRegion(cells.first);
		const lastIdx = this.findRegion(cells.last);
		const firstIntersect = this.regions[firstIdx];
		const lastIntersect = this.regions[lastIdx];
		if (firstIdx === lastIdx && !firstIntersect.isSpacer) { return; }

		const replacement: CellRegion[] = [];
		let mainFirst = cells.first;
		let mainLast = cells.last;
		if (firstIntersect.first < mainFirst) {
			if (firstIntersect.isSpacer) {
				replacement.push({ first: firstIntersect.first, last: mainFirst - 1, isSpacer: true });
			} else {
				mainFirst = firstIntersect.first;
			}
		}
		let tail: CellRegion | null = null;
		if (lastIntersect.last > mainLast) {
			if (lastIntersect.isSpacer) {
				tail = { first: mainLast + 1, last: lastIntersect.last, isSpacer: true };
			} else {
				mainLast = lastIntersect.last;
			}
		}
		replacement.push({ first: mainFirst, last: mainLast, isSpacer: false });
		if (tail !== null) { replacement.push(tail as CellRegion); }

		const next: CellRegion[] = [];
		for (let i = 0; i < firstIdx; i += 1) { next.push(this.regions[i]); }
		for (const r of replacement) { next.push(r); }
		for (let i = lastIdx + 1; i < this.regions.length; i += 1) { next.push(this.regions[i]); }
		this.regions = next;
	}

	equals(other: CellRenderMask): boolean {
		const theirs = other.enumerateRegions();
		if (this.numCells !== other.numCells || this.regions.length !== theirs.length) { return false; }
		for (let i = 0; i < this.regions.length; i += 1) {
			const a = this.regions[i];
			const b = theirs[i];
			if (a.first !== b.first || a.last !== b.last || a.isSpacer !== b.isSpacer) { return false; }
		}
		return true;
	}

	private findRegion(cell: int32): int32 {
		let firstIdx: int32 = 0;
		let lastIdx: int32 = (this.regions.length as int32) - 1;
		while (firstIdx <= lastIdx) {
			const middleIdx: int32 = firstIdx + (lastIdx - firstIdx) / 2;
			const middle = this.regions[middleIdx];
			if (cell >= middle.first && cell <= middle.last) { return middleIdx; }
			if (cell < middle.first) {
				lastIdx = middleIdx - 1;
			} else {
				firstIdx = middleIdx + 1;
			}
		}
		throw `CellRenderMask: no region contains cell ${cell}`;
	}
}
