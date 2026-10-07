import { sleepAsync } from "std/core/promise";

export interface Product {
	id: string;
	title: string;
	description: string;
	price: number;
	image: string;
}

export enum CatalogError {
	Offline,
}

const LATENCY_MS = 450;

function product(id: int32, title: string, description: string, price: number): Product {
	return { id: "p" + id.toString(), title, description, price, image: `https://picsum.photos/id/${id + 10}/160/160` };
}

const products: Product[] = [
	product(1, "Field notebook", "Dot grid, 120 pages.", 12),
	product(2, "Walnut desk tray", "Oiled walnut tray with a felt base that keeps pens, keys and a phone in one place on a crowded desk.", 48),
	product(3, "Brass pen", "Machined brass, refillable.", 36),
	product(4, "Linen tote", "Heavy washed linen with an inner pocket. Carries a laptop, a lunch and the notebook without stretching at the handles.", 29),
	product(5, "Desk lamp", "Warm dimmable LED.", 89),
	product(6, "Ceramic mug", "Stoneware, 350 ml, glazed by hand so every mug is a little different from the one beside it.", 18),
	product(7, "Cable organiser", "Silicone clips, set of six.", 9),
	product(8, "Wool throw", "Merino and cashmere blend woven in Portugal; soft enough for the sofa and warm enough for a cold reading corner in winter.", 120),
	product(9, "Plant mister", "Glass with a brass pump.", 22),
	product(10, "Weekly planner", "Undated spreads, lay-flat binding.", 16),
	product(11, "Pocket knife", "Stainless blade, olive wood scales, a slip joint that is legal to carry almost everywhere.", 54),
	product(12, "Coffee grinder", "Hand grinder, conical burrs.", 75),
];

let offline = false;

export function setOffline(value: boolean): void {
	offline = value;
}

function matches(p: Product, query: string): boolean {
	const q = query.trim().toLowerCase();
	if (q === "") { return true; }
	return p.title.toLowerCase().indexOf(q) >= 0 || p.description.toLowerCase().indexOf(q) >= 0;
}

export async function fetchProducts(query: string): Promise<Result<Product[], CatalogError>> {
	const failing = offline;
	const found: Product[] = [];
	for (const p of products) {
		if (matches(p, query)) { found.push({ ...p }); }
	}
	await sleepAsync(LATENCY_MS);
	if (failing) { return Result.err(CatalogError.Offline); }
	return Result.ok(found);
}

export function validateProduct(title: string, price: string): string | null {
	if (title.trim() === "") { return "Title is required."; }
	const value = parseFloat(price);
	if (!(value > 0)) { return "Price must be a number above zero."; }
	return null;
}

function applyEdit(id: string, title: string, description: string, price: string): Product | null {
	for (const p of products) {
		if (p.id !== id) { continue; }
		p.title = title.trim();
		p.description = description.trim();
		p.price = parseFloat(price);
		const copy: Product = { ...p };
		return copy;
	}
	return null;
}

export async function saveProduct(id: string, title: string, description: string, price: string): Promise<Result<Product, string>> {
	const failing = offline;
	const invalid = validateProduct(title, price);
	const saved = invalid === null && !failing ? applyEdit(id, title, description, price) : null;
	await sleepAsync(LATENCY_MS);
	if (invalid !== null) { return Result.err(invalid as string); }
	if (failing) { return Result.err("You are offline; the change was not saved."); }
	if (saved === null) { return Result.err("This product no longer exists."); }
	return Result.ok(saved as Product);
}

export function formatPrice(price: number): string {
	return "$" + Math.round(price).toString();
}
