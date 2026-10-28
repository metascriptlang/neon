import { Node, NodeKind, define, expansionFile, childCount, childAt, getImpl, bindSym, stringValue } from "std/meta";
import { lazyModule } from "../render/lazy";

export macro lazy(load: Node): Node {
	function importedIn(n: Node): string {
		if (n.kind === NodeKind.CallExpr && childCount(n) === 2) {
			const callee = childAt(n, 0);
			const arg = childAt(n, 1);
			if (callee.kind === NodeKind.Identifier && callee.name === "import" && arg.kind === NodeKind.StringLiteral) {
				return stringValue(arg);
			}
		}
		for (let i = 0; i < childCount(n); i += 1) {
			const found = importedIn(childAt(n, i));
			if (found !== "") { return found; }
		}
		return "";
	}

	function moduleKey(file: string, source: string): string {
		if (!source.startsWith(".")) { return source; }
		const root = define("projectDir").split("\\").join("/");
		const path = file.split("\\").join("/");
		const inside = path.startsWith(root + "/") ? path.slice(root.length + 1) : path;
		const parts: string[] = [];
		for (const part of (inside.slice(0, inside.lastIndexOf("/") + 1) + source).split("/")) {
			if (part === "." || part === "") { continue; }
			if (part === ".." && parts.length > 0) { parts.pop(); continue; }
			parts.push(part);
		}
		return parts.join("/");
	}

	let source = importedIn(load);
	if (source === "" && load.kind === NodeKind.Identifier) {
		const impl = getImpl(load);
		if (impl !== null) { source = importedIn(impl as Node); }
	}
	if (source === "") {
		error("lazy reads its module from a thunk or a function that holds a literal import(\"./page\"); for another loader write lazyModule(key, load)", load);
	}
	const runtime = bindSym("lazyModule");
	if (runtime === null) { error("lazy needs lazyModule in scope: import it beside lazy", load); }
	return {
		kind: NodeKind.CallExpr,
		line: load.line,
		column: load.column,
		callee: runtime as Node,
		arguments: [{ kind: NodeKind.StringLiteral, line: load.line, column: load.column, value: moduleKey(expansionFile(), source) }, load],
		isDirectCall: true,
	};
}
