import { RoutingError } from "../../src/navigation/routing";
import {
	ParamsCodec,
	GuardDecision,
	RouteDef,
	RouteEntry,
	RouteMatch,
	RouteTree,
	route,
	path,
	proceed,
	redirect,
	notFound,
	createRouteTree,
	hrefOf,
	paramsOf,
} from "../../src/navigation/route";

struct UserParams {
	id: int32;
}

function digits(text: string): Result<int32, RoutingError> {
	if (text === "" || text.length > 9) { return Result.err(RoutingError.InvalidParams); }
	let value: int32 = 0;
	for (let i: int32 = 0; i < text.byteLength(); i += 1) {
		const byte = text.byteAt(i);
		if (byte < 48 || byte > 57) { return Result.err(RoutingError.InvalidParams); }
		value = value * 10 + (byte - 48);
	}
	return Result.ok(value);
}

const userCodec: ParamsCodec<UserParams> = {
	parse: (values: Map<string, string>): Result<UserParams, RoutingError> => {
		const raw = values.get("id");
		if (raw === null) { return Result.err(RoutingError.InvalidParams); }
		const id = try digits(raw as string);
		return Result.ok({ id });
	},
	stringify: (params: UserParams): Map<string, string> => {
		const values = new Map<string, string>();
		values.set("id", String(params.id));
		return values;
	},
};

function pairs(items: string[]): Map<string, string> {
	const values = new Map<string, string>();
	for (let i: int32 = 0; i + 1 < items.length; i += 2) { values.set(items[i], items[i + 1]); }
	return values;
}

function text(values: Map<string, string>): string {
	const shown: string[] = [];
	for (const [key, value] of values) { shown.push(key + "=" + value); }
	return shown.join(";");
}

function leaf(node: RouteDef<Map<string, string>>): RouteEntry {
	return { node: node.node };
}

function matched(tree: RouteTree, address: string): RouteMatch {
	const found = tree.match(address);
	if (!found.ok) { throw new Error("no match for " + address + ": " + found.error.toString()); }
	return found.value;
}

function chainOf(tree: RouteTree, address: string): string {
	const found = tree.match(address);
	if (!found.ok) { return found.error.toString(); }
	const shown: string[] = [];
	for (const level of found.value.chain) {
		shown.push(level.path + (level.params.size > 0 ? "{" + text(level.params) + "}" : ""));
	}
	return shown.join(" > ");
}

function failure(build: () => RouteTree): string {
	try { build(); } catch (error) { return error.message; }
	return "";
}

test "nested routes join their patterns and pathless groups add no segment" {
	const app = path("app");
	const group = path(null);
	const users = path("users");
	const index = path("");
	const user = path(":id");
	const settings = path("settings");
	const tree = createRouteTree([
		leaf(path("/")),
		{ node: app.node, children: [
			{ node: group.node, children: [
				{ node: users.node, children: [
					{ node: index.node },
					{ node: user.node, children: [{ node: settings.node }] },
				] },
			] },
		] },
	]);
	assert chainOf(tree, "/") === "/";
	assert chainOf(tree, "/app/users") === "/app > /app > /app/users > /app/users";
	assert chainOf(tree, "/app/users/42/settings") ===
		"/app > /app > /app/users > /app/users/42{id=42} > /app/users/42/settings{id=42}";
	assert chainOf(tree, "/app/users/42") === "NoMatch";
	const found = matched(tree, "/APP/Users/42/settings/");
	assert found.chain.length === 5;
	assert found.chain[1].node === group.node;
	assert found.chain[4].node === settings.node;
	assert found.chain[4].path === "/app/users/42/settings";
}

test "branches rank by Solid's score, highest first" {
	const tree = createRouteTree([
		{ node: path("root").node, children: [
			leaf(path("/*")),
			leaf(path(":id")),
			{ node: path("foo").node, children: [leaf(path("bar")), leaf(path("bar/*"))] },
			leaf(path("baz/qux")),
		] },
	]);
	assert chainOf(tree, "/root/foo/bar") === "/root > /root/foo > /root/foo/bar";
	assert chainOf(tree, "/root/baz/qux") === "/root > /root/baz/qux";
	assert chainOf(tree, "/root/foo/bar/x") === "/root > /root/foo > /root/foo/bar";
	assert chainOf(tree, "/root/abc") === "/root > /root/abc{id=abc}";
	assert chainOf(tree, "/root/a/b") === "/root > /root";
}

test "a tie in score goes to the route whose segments are more static, in any order" {
	const orders: string[] = [];
	for (let pass: int32 = 0; pass < 2; pass += 1) {
		const splat = path("a/*rest");
		const param = path(":x");
		const deep = path("a/b/*tail");
		const mixed = path("a/:y");
		const entries: RouteEntry[] = pass === 0
			? [leaf(param), leaf(mixed), leaf(splat), leaf(deep)]
			: [leaf(deep), leaf(splat), leaf(mixed), leaf(param)];
		const tree = createRouteTree(entries);
		assert matched(tree, "/a").chain[0].node === splat.node;
		assert matched(tree, "/z").chain[0].node === param.node;
		assert matched(tree, "/a/b").chain[0].node === deep.node;
		assert matched(tree, "/a/c").chain[0].node === mixed.node;
		orders.push(
			chainOf(tree, "/a") + "|" + chainOf(tree, "/a/b") + "|" + chainOf(tree, "/a/c"),
		);
	}
	assert orders[0] === orders[1];
	assert orders[0] === "/a{rest=}|/a/b{tail=}|/a/c{y=c}";
}

test "a route whose codec refuses the params falls through to the next one" {
	const byId = route<UserParams>(":id", { params: userCodec });
	const bySlug = path(":slug");
	const tree = createRouteTree([
		{ node: path("users").node, children: [{ node: byId.node }, leaf(bySlug)] },
	]);
	const numeric = matched(tree, "/users/42");
	assert numeric.chain[1].node === byId.node;
	const typed = paramsOf<UserParams>(byId, numeric);
	assert typed.ok;
	if (typed.ok) { assert typed.value.id === 42; }
	const named = matched(tree, "/users/ada");
	assert named.chain[1].node === bySlug.node;
	assert text(named.chain[1].params) === "slug=ada";
	const absent = paramsOf<UserParams>(byId, named);
	assert !absent.ok;
	if (!absent.ok) { assert absent.error === RoutingError.NoMatch; }
	const onlyTyped = route<UserParams>("users/:id", { params: userCodec });
	const only = createRouteTree([{ node: onlyTyped.node }]);
	assert chainOf(only, "/users/ada") === "NoMatch";
	const person = route<UserParams>("people/:id", { params: userCodec });
	const profile = path("");
	const byName = path("people/:name");
	const nested = createRouteTree([{ node: person.node, children: [leaf(profile)] }, leaf(byName)]);
	assert matched(nested, "/people/7").chain[1].node === profile.node;
	assert matched(nested, "/people/ada").chain[0].node === byName.node;
}

test "two routes of the same shape are refused, naming both" {
	const message = failure((): RouteTree => createRouteTree([
		{ node: path("a").node, children: [leaf(path(":x"))] },
		leaf(path("/A/:y")),
	]));
	assert message === "routing: \"/a/:x\" and \"/A/:y\" match the same addresses";
	const optional = failure((): RouteTree => createRouteTree([
		leaf(path("blog/:page?")),
		leaf(path("blog")),
	]));
	assert optional === "routing: \"/blog/:page?\" and \"/blog\" match the same addresses";
	const shadowed = failure((): RouteTree => createRouteTree([
		leaf(path("users/:slug")),
		{ node: route<UserParams>("users/:id", { params: userCodec }).node },
	]));
	assert shadowed === "routing: \"/users/:slug\" and \"/users/:id\" match the same addresses";
}

test "param names that differ only by non-word symbols are refused, naming both" {
	const message = failure((): RouteTree => createRouteTree([
		{ node: path("posts/:post-id").node, children: [leaf(path(":postid"))] },
	]));
	assert message === "routing: the param names \"post-id\" of \"/posts/:post-id\" and " +
		"\"postid\" of \"/posts/:post-id/:postid\" differ only by non-word symbols";
	const repeated = failure((): RouteTree => createRouteTree([
		{ node: path(":id").node, children: [leaf(path("x/:id"))] },
	]));
	assert repeated === "routing: \"/:id\" and \"/:id/x/:id\" both name the param \"id\"";
}

test "a splat that is not the last segment is refused, naming both routes" {
	const message = failure((): RouteTree => createRouteTree([
		{ node: path("files/*rest").node, children: [leaf(path("x"))] },
	]));
	assert message === "routing: the splat of \"/files/*rest\" is not the last segment of " +
		"\"/files/*rest/x\"";
	const inside = failure((): RouteTree => createRouteTree([leaf(path("a/*rest/b"))]));
	assert inside === "routing: the splat of \"/a/*rest/b\" is not its last segment";
}

test "two splats at one level are refused, naming both" {
	const message = failure((): RouteTree => createRouteTree([
		{ node: path("docs").node, children: [leaf(path("*")), leaf(path("*rest"))] },
	]));
	assert message === "routing: \"/docs/*\" and \"/docs/*rest\" match the same addresses";
}

test "the same route node used twice is refused, naming both places" {
	const shared = path("x");
	const message = failure((): RouteTree => createRouteTree([
		{ node: path("a").node, children: [leaf(shared)] },
		{ node: path(null).node, children: [{ node: path("b").node, children: [leaf(shared)] }] },
	]));
	assert message === "routing: one route is declared at \"/a/x\" and at \"/b/x\"";
}

test "guards run root to leaf and the first decision that is not continue wins" {
	let seen: int32 = 0;
	const account = path("account", {
		guard: (params: Map<string, string>, found: RouteMatch): GuardDecision => {
			return found.search.get("session") === null ? redirect("/login") : proceed();
		},
	});
	const user = route<UserParams>("users/:id", {
		params: userCodec,
		guard: (params: UserParams, found: RouteMatch): GuardDecision => {
			seen = params.id;
			if (params.id === 0) { return notFound(); }
			return params.id === 1 ? redirect("/account/users/2", 308) : proceed();
		},
	});
	const fallback = path("*", { status: 404 });
	const tree = createRouteTree([
		{ node: account.node, children: [{ node: user.node }] },
		leaf(fallback),
	]);
	const passed = tree.resolve("/account/users/7?session=s");
	assert passed.ok;
	if (passed.ok) {
		assert passed.value.status === 200;
		assert passed.value.redirect === null;
		assert passed.value.match.chain[1].node === user.node;
	}
	assert seen === 7;
	const login = tree.resolve("/account/users/7");
	assert login.ok;
	if (login.ok) {
		assert login.value.status === 307;
		assert login.value.redirect === "/login";
	}
	const moved = tree.resolve("/account/users/1?session=s");
	assert moved.ok;
	if (moved.ok) {
		assert moved.value.status === 308;
		assert moved.value.redirect === "/account/users/2";
	}
	const missing = tree.resolve("/account/users/0?session=s");
	assert missing.ok;
	if (missing.ok) {
		assert missing.value.status === 404;
		assert missing.value.redirect === null;
		assert missing.value.match.chain[0].node === fallback.node;
	}
	const alone = createRouteTree([{ node: account.node, children: [{ node: user.node }] }]);
	const refused = alone.resolve("/account/users/0?session=s");
	assert !refused.ok;
	if (!refused.ok) { assert refused.error === RoutingError.NoMatch; }
	const unknown = tree.resolve("/nothing/here");
	assert unknown.ok;
	if (unknown.ok) {
		assert unknown.value.status === 404;
		assert unknown.value.redirect === null;
		assert text(unknown.value.match.chain[0].params) === "";
	}
}

test "typed and untyped hrefs round-trip through the tree" {
	const user = route<UserParams>(":id", { params: userCodec });
	const slug = path(":slug");
	const blog = path("blog/:page?");
	const files = path("files/*path");
	const tree = createRouteTree([
		{ node: path("users").node, children: [{ node: user.node }, leaf(slug)] },
		leaf(blog),
		leaf(files),
	]);
	const typed = hrefOf<UserParams>(tree, user, { id: 42 }, pairs(["tab", "a b"]));
	assert typed.ok;
	if (typed.ok) {
		assert typed.value === "/users/42?tab=a%20b";
		const back = paramsOf<UserParams>(user, matched(tree, typed.value));
		assert back.ok;
		if (back.ok) { assert back.value.id === 42; }
		assert matched(tree, typed.value).search.get("tab") === "a b";
	}
	const untyped = hrefOf<Map<string, string>>(
		tree,
		slug,
		pairs(["slug", "ada lovelace/1"]),
		pairs([]),
	);
	assert untyped.ok;
	if (untyped.ok) {
		assert untyped.value === "/users/ada%20lovelace%2F1";
		assert text(matched(tree, untyped.value).chain[1].params) === "slug=ada lovelace/1";
	}
	const first = hrefOf<Map<string, string>>(tree, blog, pairs([]), pairs([]));
	assert first.ok;
	if (first.ok) { assert first.value === "/blog"; }
	const second = hrefOf<Map<string, string>>(tree, blog, pairs(["page", "2"]), pairs([]));
	assert second.ok;
	if (second.ok) { assert chainOf(tree, second.value) === "/blog/2{page=2}"; }
	const nested = hrefOf<Map<string, string>>(tree, files, pairs(["path", "a b/c"]), pairs([]));
	assert nested.ok;
	if (nested.ok) {
		assert nested.value === "/files/a%20b/c";
		assert chainOf(tree, nested.value) === "/files{path=a b/c}";
	}
	const missing = hrefOf<Map<string, string>>(tree, slug, pairs([]), pairs([]));
	assert !missing.ok;
	if (!missing.ok) { assert missing.error === RoutingError.InvalidParams; }
	const outside = hrefOf<Map<string, string>>(tree, path("x"), pairs([]), pairs([]));
	assert !outside.ok;
	if (!outside.ok) { assert outside.error === RoutingError.NoMatch; }
}

test "search parses the way URLSearchParams does and the hash is kept" {
	const tree = createRouteTree([leaf(path("foo/bar")), leaf(path("search"))]);
	const plain = matched(tree, "/foo/bar?hello=world&fizz=buzz");
	assert text(plain.search) === "hello=world;fizz=buzz";
	assert plain.hash === "";
	const spaced = matched(tree, "/foo/bar?hello+world=bar+baz");
	assert text(spaced.search) === "hello world=bar baz";
	const mixed = matched(tree, "/search?q=a+b&x=%2B1&q=second&flag&=empty&&#top?x=1");
	assert text(mixed.search) === "q=a b;x=+1;flag=;=empty";
	assert mixed.hash === "top?x=1";
	assert chainOf(tree, "/search#a") === "/search";
	assert chainOf(tree, "/search?x=%ZZ") === "InvalidAddress";
	assert chainOf(tree, "/search/%E0") === "InvalidAddress";
}

test "static paths list every leaf without params and expand the enumerated ones" {
	const posts = path("posts/:slug", {
		paths: (): Map<string, string>[] => [pairs(["slug", "a"]), pairs(["slug", "b c"])],
	});
	const users = route<UserParams>("users/:id", {
		params: userCodec,
		paths: (): UserParams[] => [{ id: 1 }, { id: 2 }],
	});
	const tree = createRouteTree([
		leaf(path("/")),
		{ node: path(null).node, children: [leaf(path("about")), leaf(path("blog/:page?"))] },
		leaf(posts),
		{ node: users.node },
		leaf(path("drafts/:id")),
		leaf(path("*", { status: 404 })),
	]);
	const listed = tree.staticPaths();
	assert listed.ok;
	if (listed.ok) {
		assert listed.value.join(" ") === "/ /about /blog /posts/a /posts/b%20c /users/1 /users/2";
	}
}
