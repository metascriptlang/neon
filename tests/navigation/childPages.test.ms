import { Accessor } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import { createRoot } from "../../src/core/owner";
import { Dispose } from "../../src/core/types";
import { NavigationChild } from "../../src/navigation/children";
import { ChildPages, Pages, createChildPages } from "../../src/navigation/childPages";

interface PageInstance {
	name: string;
	active: Accessor<boolean>;
}

let created = "";
let disposed = "";

function pageKey(name: string): string {
	return name;
}

function makePages(items: string[], selectedIndex: int32): ChildPages<string, PageInstance> {
	created = "";
	disposed = "";
	return createChildPages<string, PageInstance>(
		{ items, selectedIndex },
		pageKey,
		(configuration: Accessor<string>, active: Accessor<boolean>): PageInstance => {
			const name = configuration();
			created += name + ";";
			onCleanup((): void => { disposed += name + ";"; });
			return { name, active };
		},
	);
}

function names(pages: ChildPages<string, PageInstance>): string {
	let out = "";
	for (const child of pages.items()) { out += child.instance.name + (child.active() ? "*" : "") + ";"; }
	return out;
}

function failure(run: () => void): string {
	try { run(); } catch (error) { return error.message; }
	return "";
}

test "select moves the active page and every page keeps its instance" {
	const pages = makePages(["home", "search", "profile"], 0);
	const home = pages.items()[0].instance;
	const search = pages.items()[1].instance;
	assert names(pages) === "home*;search;profile;", names(pages);
	pages.select(2);
	assert names(pages) === "home;search;profile*;", names(pages);
	assert pages.selectedIndex() === 2;
	assert !home.active(), "a page that loses the selection becomes inactive";
	pages.select(1);
	const selected = pages.selected();
	assert search.active() && selected !== null;
	assert (selected as NavigationChild<string, PageInstance>).instance === search;
	assert pages.items()[0].instance === home, "pages keep their instances";
	assert created === "home;search;profile;", created;
	assert disposed === "", disposed;
	pages.dispose();
}

test "selectNext and selectPrev stop at the ends unless circular" {
	const pages = makePages(["a", "b", "c"], 0);
	pages.selectPrev(false);
	assert pages.selectedIndex() === 0, "the first page stays selected";
	pages.selectPrev(true);
	assert pages.selectedIndex() === 2, "circular wraps to the last page";
	pages.selectNext(false);
	assert pages.selectedIndex() === 2, "the last page stays selected";
	pages.selectNext(true);
	assert pages.selectedIndex() === 0, "circular wraps to the first page";
	pages.selectNext(false);
	assert names(pages) === "a;b*;c;", names(pages);
	pages.dispose();
}

test "navigate replaces the pages, disposing removed ones and keeping the rest" {
	const pages = makePages(["a", "b", "c"], 1);
	const b = pages.items()[1].instance;
	pages.navigate((current: Pages<string>): Pages<string> => {
		assert current.items.length === 3 && current.selectedIndex === 1;
		return { items: ["b", "d"], selectedIndex: 1 };
	});
	assert names(pages) === "b;d*;", names(pages);
	assert pages.items()[0].instance === b, "a kept page keeps its instance";
	assert disposed === "a;c;" || disposed === "c;a;", disposed;
	pages.navigate((current: Pages<string>): Pages<string> => ({ items: [], selectedIndex: -1 }));
	assert pages.items().length === 0 && pages.selectedIndex() === -1 && pages.selected() === null;
	pages.selectNext(true);
	assert pages.selectedIndex() === -1, "empty pages have nothing to select";
	pages.dispose();
}

test "select out of range fails loudly and changes nothing" {
	const pages = makePages(["a", "b"], 0);
	const above = failure((): void => { pages.select(2); });
	assert above === "child pages: selectedIndex 2 is outside 2 pages", above;
	const below = failure((): void => { pages.select(-1); });
	assert below === "child pages: selectedIndex -1 is outside 2 pages", below;
	const initial = failure((): void => { makePages(["a"], 1); });
	assert initial === "child pages: selectedIndex 1 is outside 1 pages", initial;
	const duplicate = failure((): void => {
		pages.navigate((current: Pages<string>): Pages<string> => ({ items: ["a", "a"], selectedIndex: 0 }));
	});
	assert duplicate === "duplicate child key: a", duplicate;
	pages.dispose();
}

test "the owner of the pages disposes every page" {
	let count = 0;
	createRoot((dispose: Dispose): void => {
		makePages(["a", "b"], 0);
		dispose();
		count = disposed.length;
	});
	assert count === 4, disposed;
}
