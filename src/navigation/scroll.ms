export interface Scroller {
	arrived: (address: string, replace: boolean, scroll: boolean) => void;
}
