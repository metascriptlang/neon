import {
	PathMatch,
	normalizePath,
	joinPaths,
	createMatcher,
	scoreRoute,
	expandOptionals,
	routePatterns,
} from "../../src/navigation/routeMatcher";

function text(params: Map<string, string>): string {
	const pairs: string[] = [];
	for (const [key, value] of params) { pairs.push(key + "=" + value); }
	return pairs.join(";");
}

function matchOf(pattern: string, location: string, partial: boolean): PathMatch {
	const match = createMatcher(pattern, partial)(location);
	if (match === null) { throw new Error("no match: " + pattern + " " + location); }
	return match as PathMatch;
}

function matches(pattern: string, location: string): boolean {
	return createMatcher(pattern)(location) !== null;
}

test "createMatcher returns the path and no params for a simple path" {
	const match = matchOf("/foo/bar", "/foo/bar", false);
	assert match.path === "/foo/bar";
	assert text(match.params) === "";
	assert !matches("/foo/bar", "/foo/baz");
}

test "createMatcher tolerates one trailing slash and rejects empty interior segments" {
	assert matches("/foo/bar", "/foo/bar/");
	assert !matches("/foo/bar", "/foo//bar");
	assert !matches("/foo/bar", "//foo/bar");
	assert !matches("/foo/bar", "/foo/bar//");
	assert matches("/", "/");
	assert !matches("/", "//");
	assert matches("/files/*rest", "/files/a/b");
	assert !matches("/files/*rest", "/files/a//b");
	assert matches("/products/:id", "products/5");
}

test "createMatcher collects params and splats" {
	const param = matchOf("/foo/:id", "/foo/abc-123", false);
	assert param.path === "/foo/abc-123";
	assert text(param.params) === "id=abc-123";
	const unnamed = matchOf("/foo/bar/*", "/foo/bar/baz", false);
	assert unnamed.path === "/foo/bar";
	assert text(unnamed.params) === "";
	assert !matches("/foo/bar", "/foo/bar/baz");
	const named = matchOf("/foo/bar/*something", "/foo/bar/baz/qux", false);
	assert named.path === "/foo/bar";
	assert text(named.params) === "something=baz/qux";
	const exact = matchOf("/foo/bar/*something", "/foo/bar", false);
	assert exact.path === "/foo/bar";
	assert text(exact.params) === "something=";
}

test "createMatcher extracts params and the matched path of a route" {
	const match = matchOf("/foo/:id/bar/:name", "/foo/123/bar/solid", false);
	assert text(match.params) === "id=123;name=solid";
	assert match.path === "/foo/123/bar/solid";
}

test "createMatcher matches a route with children partially" {
	const match = matchOf("/foo/:id", "/foo/123/bar/solid", true);
	assert match.path === "/foo/123";
	assert text(match.params) === "id=123";
	const star = matchOf(routePatterns("foo/:id/*", "", true)[0], "/foo/123/bar/solid", false);
	assert star.path === "/foo/123";
	assert text(star.params) === "id=123";
	const all = matchOf(routePatterns("foo/:id/*all", "", true)[0], "/foo/123/bar/solid", false);
	assert all.path === "/foo/123";
	assert text(all.params) === "id=123;all=bar/solid";
}

test "createMatcher ignores the case of static segments and keeps the case of params" {
	assert matches("/foo/bar/baz", "/fOo/BAR/bAZ");
	assert matchOf("/foo", "/FOO", false).path === "/foo";
	const names = matchOf("/foo/:sUpEr/*aLL", "/foo/123/bar/solid", false);
	assert text(names.params) === "sUpEr=123;aLL=bar/solid";
	const values = matchOf("/foo/:id/*all", "/foo/someTHING/BaR/sOlId", false);
	assert text(values.params) === "id=someTHING;all=BaR/sOlId";
}

test "createMatcher decodes param values and refuses a malformed one" {
	const match = matchOf("/users/:name/*rest", "/users/caf%C3%A9/a%20b/c", false);
	assert text(match.params) === "name=café;rest=a b/c";
	assert match.path === "/users/caf%C3%A9";
	assert !matches("/users/:name", "/users/%ZZ");
	assert !matches("/users/:name", "/users/%C3");
}

test "joinPaths joins with a single slash" {
	assert joinPaths("/foo", "bar") === "/foo/bar";
	assert joinPaths("/foo/", "bar") === "/foo/bar";
	assert joinPaths("/foo", "/bar") === "/foo/bar";
	assert joinPaths("/foo/", "/bar") === "/foo/bar";
}

test "joinPaths ensures a leading slash" {
	assert joinPaths("/foo", "") === "/foo";
	assert joinPaths("foo", "") === "/foo";
	assert joinPaths("", "foo") === "/foo";
	assert joinPaths("", "/foo") === "/foo";
	assert joinPaths("/", "foo") === "/foo";
	assert joinPaths("/", "/foo") === "/foo";
}

test "joinPaths strips a trailing slash of the base" {
	assert joinPaths("/foo/", "/") === "/foo";
	assert joinPaths("/foo/", "bar/") === "/foo/bar/";
}

test "joinPaths strips a trailing splat of the base" {
	assert joinPaths("foo/*", "") === "/foo";
	assert joinPaths("foo/*", "/") === "/foo";
	assert joinPaths("/foo/*all", "") === "/foo";
	assert joinPaths("/foo/*", "bar") === "/foo/bar";
	assert joinPaths("/foo/*all", "bar") === "/foo/bar";
	assert joinPaths("/*", "foo") === "/foo";
	assert joinPaths("/*all", "foo") === "/foo";
	assert joinPaths("*", "foo") === "/foo";
}

test "joinPaths preserves parameters" {
	assert joinPaths("/foo/:bar", "") === "/foo/:bar";
	assert joinPaths("/foo/:bar", "baz") === "/foo/:bar/baz";
	assert joinPaths("/foo", ":bar/baz") === "/foo/:bar/baz";
	assert joinPaths("", ":bar/baz") === "/:bar/baz";
}

test "normalizePath trims slashes the way Solid's regular expression does" {
	assert normalizePath("") === "";
	assert normalizePath("/") === "";
	assert normalizePath("//") === "";
	assert normalizePath("foo") === "/foo";
	assert normalizePath("/foo/") === "/foo/";
	assert normalizePath("/foo//") === "/foo/";
	assert normalizePath("?a=1") === "?a=1";
	assert normalizePath("foo", true) === "foo";
}

test "expandOptionals expands each optional param in order" {
	assert expandOptionals("/foo/:x").join("|") === "/foo/:x";
	assert expandOptionals("/foo/:x?").join("|") === "/foo|/foo/:x";
	assert expandOptionals("/bar/:x?/").join("|") === "/bar/|/bar/:x/";
	assert expandOptionals("/foo/:x?/:y?/:z").join("|") === "/foo/:z|/foo/:x/:z|/foo/:x/:y/:z";
	assert expandOptionals("/foo/:x?/:y/:z?").join("|") ===
		"/foo/:y|/foo/:x/:y|/foo/:y/:z|/foo/:x/:y/:z";
	assert expandOptionals("/foo/:x?/:y?/:z?").join("|") ===
		"/foo|/foo/:x|/foo/:x/:y|/foo/:x/:y/:z";
	assert expandOptionals("/foo/:x?/bar/:y?/baz/:z?").join("|") ===
		"/foo/bar/baz|/foo/:x/bar/baz|/foo/bar/:y/baz|/foo/:x/bar/:y/baz|" +
		"/foo/bar/baz/:z|/foo/:x/bar/baz/:z|/foo/bar/:y/baz/:z|/foo/:x/bar/:y/baz/:z";
}

test "routePatterns joins the base and strips its splat" {
	assert routePatterns("bar", "/foo", true).join("|") === "/foo/bar";
	assert routePatterns("bar", "/foo/*", true).join("|") === "/foo/bar";
	assert routePatterns("bar", "/foo/*all", true).join("|") === "/foo/bar";
	assert routePatterns("foo/*", "", false).join("|") === "/foo";
	assert routePatterns("foo/:id?", "", true).join("|") === "/foo|/foo/:id";
}

test "routePatterns encodes static segments but not params, splats or pchar" {
	assert routePatterns("foo/ほげ/ふが/bar", "/root", true).join("|") ===
		"/root/foo/%E3%81%BB%E3%81%92/%E3%81%B5%E3%81%8C/bar";
	assert routePatterns("ほげ/:ふが/*ぴよ", "/root", true).join("|") ===
		"/root/%E3%81%BB%E3%81%92/:ふが/*ぴよ";
	const pchar = routePatterns("+foo/@user/a=b", "", true)[0];
	assert pchar === "/+foo/@user/a=b";
	assert matches(pchar, "/+foo/@user/a=b");
	assert !matches(pchar, "/%2Bfoo/@user/a=b");
	const spaced = routePatterns("foo bar/ほげ", "", true)[0];
	assert spaced === "/foo%20bar/%E3%81%BB%E3%81%92";
	assert matches(spaced, "/foo%20bar/%E3%81%BB%E3%81%92");
}

test "scoreRoute prefers more segments, literal segments and no splat" {
	assert scoreRoute("/foo/bar/baz") > scoreRoute("/foo/bar");
	assert scoreRoute("/foo/bar") > scoreRoute("/foo/:id");
	assert scoreRoute("/foo/bar") > scoreRoute("/foo/bar/*");
	assert scoreRoute("/root/foo/bar") === scoreRoute("/root/baz/qux");
	assert scoreRoute("/root/baz/qux") > scoreRoute("/root/foo/bar/*");
	assert scoreRoute("/root/foo/bar/*") > scoreRoute("/root/:id");
	assert scoreRoute("/root/:id") > scoreRoute("/root/*");
}
