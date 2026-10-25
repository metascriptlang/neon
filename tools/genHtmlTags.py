#!/usr/bin/env python3
import os
import re
import sys
import textwrap

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from htmlDocs import ATTRS, PER_TAG, TAGS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOME = os.path.expanduser("~")
JSX = sys.argv[1] if len(sys.argv) > 1 else HOME + "/projects/dom-expressions/packages/dom-expressions/src/jsx.d.ts"
DOM = sys.argv[2] if len(sys.argv) > 2 else HOME + "/projects/typescript-go/internal/bundled/libs/lib.dom.d.ts"
MDN = "https://developer.mozilla.org/en-US/docs/Web/HTML/"
RDFA = "https://www.w3.org/TR/rdfa-core/#s_syntax"
NOT_ATTRIBUTES = {"innerText", "innerHTML", "textContent", "key", "style", "children", "ref", "classList", "$ServerOnly", "inlist"}
GLOBAL_SOURCES = ("DOMAttributes", "HTMLAttributes")
RDFA_NAMES = {"about", "datatype", "prefix", "property", "resource", "typeof", "vocab"}
ROUTER_ANCHOR_URL = "https://docs.solidjs.com/solid-router/reference/components/a"
# solid-router src/components.tsx:15-25 augments AnchorHTMLAttributes with these, and its
# handlers read them back as strings (src/data/events.ts:88 `getAttribute("preload") !== "false"`).
ROUTER_ANCHOR_AUGMENTATION = [
    {"name": "state", "type": "string"},
    {"name": "noScroll", "type": '"true" | "false" | boolean'},
    {"name": "replace", "type": '"true" | "false" | boolean'},
    {"name": "preload", "type": '"true" | "false" | boolean'},
    {"name": "link", "type": '"true" | "false" | boolean'},
]
GLOBAL_PAGES = {
    "class": "Global_attributes/class",
    "role": "../Accessibility/ARIA/Roles",
    "elementtiming": "Attributes/elementtiming",
}


def width(line):
    return len(line.replace("\t", "    "))


def doc_lines(indent, text, url=None):
    label = "MDN" if url and "developer.mozilla.org" in url else "Docs"
    tail = " [" + label + "](" + url + ")" if url else ""
    one = indent + "/** " + text + tail + " */"
    if width(one) <= 100:
        return [one]
    body = textwrap.wrap(text, 100 - width(indent) - 3)
    if url:
        body.append("[" + label + "](" + url + ")")
    return [indent + "/**"] + [indent + " * " + b for b in body] + [indent + " */"]


def typed_line(indent, head, ts, tail):
    one = indent + head + ts + tail
    if width(one) <= 100:
        return [one]
    parts = union(ts)
    lines = [indent + head.rstrip()]
    for i, p in enumerate(parts):
        lines.append(indent + "\t" + p + (" |" if i < len(parts) - 1 else tail))
    return lines


def list_lines(indent, head, items, tail):
    one = indent + head + ", ".join(items) + tail
    if width(one) <= 100:
        return [one]
    return [indent + head.rstrip()] + [indent + "\t" + i + "," for i in items] + [indent + tail.lstrip()]


def interfaces(src):
    out = {}
    for m in re.finditer(r"\binterface\s+(\w+)(?:<[^>{]*>)?\s*(?:extends\s+([^{]+))?\{", src):
        i = m.end()
        depth = 1
        while depth:
            depth += {"{": 1, "}": -1}.get(src[i], 0)
            i += 1
        parents = [p.strip().split("<")[0] for p in split_top(m.group(2) or "", ",") if p.strip()]
        out.setdefault(m.group(1), (parents, src[m.end():i - 1]))
    return out


def split_top(s, sep):
    parts, depth, cur = [], 0, ""
    for c in s:
        if c in "(<{[":
            depth += 1
        elif c in ")>}]":
            depth -= 1
        if c == sep and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += c
    parts.append(cur)
    return parts


def members(body):
    docs = []

    def keep_doc(m):
        docs.append(m.group(0))
        return " @@DOC" + str(len(docs) - 1) + "@@ "

    clean = re.sub(r"/\*\*.*?\*/", keep_doc, body, flags=re.S)
    clean = re.sub(r"/\*.*?\*/", "", clean, flags=re.S)
    clean = re.sub(r"//[^\n]*", "", clean)
    setters = dict(re.findall(r"^\s*set\s+(\w+)\(\w+\s*:\s*([^)]+)\);", clean, flags=re.M))
    getters = re.findall(r"^\s*get\s+(\w+)\(\)\s*:\s*([^;]+);", clean, flags=re.M)
    clean = re.sub(r"^\s*(?:get|set)\s+\w+\([^)]*\)[^;]*;", "", clean, flags=re.M)
    pattern = r'(@@DOC(\d+)@@\s*)?(readonly\s+)?(?:"([^"]+)"|([\w$]+))(\?)?\s*(\([^;]*?\))?\s*:\s*([^;]+);'
    found = []
    for m in re.finditer(pattern, clean, re.S):
        found.append({
            "doc": docs[int(m.group(2))] if m.group(2) else "",
            "readonly": bool(m.group(3)),
            "name": m.group(4) or m.group(5),
            "optional": bool(m.group(6)),
            "params": m.group(7),
            "type": " ".join(re.sub(r"@@DOC\d+@@", "", m.group(8)).split()),
        })
    for name, ts in getters:
        found.append({"doc": "", "readonly": setters.get(name) != ts, "name": name, "optional": False,
                      "params": None, "type": " ".join(ts.split())})
    return found


def aliases(src):
    out = {}
    for m in re.finditer(r"\btype\s+(\w+)\s*=\s*([^;]+);", src):
        if not m.group(2).strip().startswith("{"):
            out.setdefault(m.group(1), " ".join(m.group(2).split()))
    return out


def union(ts):
    return [p.strip() for p in split_top(ts.strip().lstrip("|"), "|") if p.strip()]


def flatten(ts, alias):
    out = []
    for p in union(ts):
        out += flatten(alias[p], alias) if p in alias else [p]
    return out


def open_union(parts):
    return "string" in parts or "(string & {})" in parts or "SerializableAttributeValue" in parts


def attribute_type(ts, alias):
    parts = [p for p in flatten(ts, alias) if p != "undefined"]
    if parts == ["never"]:
        return "never", []
    literals = [p for p in parts if re.fullmatch(r'"[^"]*"', p)]
    known = {"string", "number", "boolean", "(string & {})", "SerializableAttributeValue", "string[]"}
    if any(p not in known and p not in literals for p in parts):
        return None, []
    kept = [] if open_union(parts) else literals
    for word in ("number", "string", "boolean"):
        if word in parts or (word == "string" and open_union(parts)):
            kept.append(word)
    return " | ".join(kept), (literals if open_union(parts) else [])


def jsx_tables():
    src = open(JSX).read()
    blocks = interfaces(src)
    alias = aliases(src)

    def own(name, stop):
        names, chain = [], [name]
        seen = []
        while chain:
            x = chain.pop(0)
            if x in stop or x not in blocks or x in seen:
                continue
            seen.append(x)
            parents, body = blocks[x]
            names += members(body)
            chain += parents
        return names

    def usable(m):
        n = m["name"]
        event = n.startswith("on") and (n[2:3].isupper() or "EventHandler" in m["type"])
        return not (n in NOT_ATTRIBUTES or ":" in n or event or m["params"])

    globals_ = [m for x in GLOBAL_SOURCES for m in members(blocks[x][1]) if usable(m)]
    globals_ += [m for m in members(blocks["AriaAttributes"][1]) if m["name"] == "role"]
    tags = []
    for m in members(blocks["HTMLElementTags"][1]):
        iface = m["type"].split("<")[0]
        attrs = [] if iface == "HTMLAttributes" else [a for a in own(iface, GLOBAL_SOURCES) if usable(a)]
        if m["name"] == "a":
            attrs += [dict(a, doc="", readonly=False, optional=True, params=None) for a in ROUTER_ANCHOR_AUGMENTATION]
        tags.append((m["name"], iface, attrs))
    return globals_, tags, alias


def ms_attrs_name(iface):
    if iface == "HTMLAttributes":
        return "HtmlGlobalAttributes"
    return "Html" + re.sub("(?i)htmlattributes$", "", iface) + "Attributes"


def describe(tag, name):
    lower = name.lower()
    text = PER_TAG.get(tag + "." + lower) if tag else None
    if text is None and name != lower and lower in ATTRS:
        text = "Same as `" + lower + "`."
    if text is None:
        text = ATTRS.get(lower)
    if text is None:
        raise SystemExit("genHtmlTags: no description for attribute '" + name + "'" + (" of <" + tag + ">" if tag else ""))
    return text


def attribute_url(tag, name):
    lower = name.lower()
    if tag == "a" and name in {a["name"] for a in ROUTER_ANCHOR_AUGMENTATION}:
        return ROUTER_ANCHOR_URL
    if tag:
        return MDN + "Element/" + tag + "#" + lower
    if lower in RDFA_NAMES:
        return RDFA
    return MDN + GLOBAL_PAGES.get(lower, "Global_attributes/" + lower)


def field_lines(tags, attrs, alias, skipped, hyphenated, refused):
    tag = tags[0] if tags else ""
    lines, seen = [], set()
    for a in attrs:
        name = a["name"]
        if name in seen:
            continue
        seen.add(name)
        ms_type, values = attribute_type(a["type"], alias)
        if ms_type is None:
            skipped.append((tag or "*", name, a["type"]))
            continue
        if "-" in name:
            hyphenated.add(name)
            continue
        if ms_type == "never":
            refused.update(t + "." + name for t in tags)
            continue
        text = describe(tag, name)
        if "@deprecated" in a["doc"]:
            text = "Deprecated. " + text
        if values:
            text += " Common values: " + ", ".join("`" + v.strip('"') + "`" for v in values) + "."
        lines += doc_lines("\t", text, attribute_url(tag, name))
        lines += typed_line("\t", name + ": ", ms_type, ";")
    return lines


def dom_tag_map():
    src = open(DOM).read()
    body = re.search(r"interface HTMLElementTagNameMap \{(.*?)\n\}", src, re.S).group(1)
    foreign = []
    for map_name in ("SVGElementTagNameMap", "MathMLElementTagNameMap"):
        foreign += re.findall(r'"(\w+)":', re.search(r"interface " + map_name + r" \{(.*?)\n\}", src, re.S).group(1))
    return re.findall(r'"(\w+)": (\w+);', body), foreign


def write_tags(path):
    globals_, tags, alias = jsx_tables()
    tag_map, foreign = dom_tag_map()
    by_tag = {t: (iface, attrs) for t, iface, attrs in tags}
    skipped, hyphenated, refused = [], set(), set()
    out = ["// Generated by tools/genHtmlTags.py; edit the generator, not this file.", ""]
    out += doc_lines("", "Attributes every HTML element takes, beside `style`, `ref`, events and the open `data-*` and `aria-*` names.")
    out.append("export interface HtmlGlobalAttributes {")
    out += field_lines([], globals_, alias, skipped, hyphenated, refused)
    out.append("}")
    written = set()
    for tag, _ in tag_map:
        iface, attrs = by_tag[tag]
        name = ms_attrs_name(iface)
        if name in written or name == "HtmlGlobalAttributes":
            continue
        written.add(name)
        users = [t for t, _ in tag_map if by_tag[t][0] == iface]
        out.append("")
        out += doc_lines("", "Attributes of " + ", ".join("`<" + t + ">`" for t in users) + " beyond the global ones.")
        out.append("export interface " + name + " {")
        out += field_lines(users, attrs, alias, skipped, hyphenated, refused)
        out.append("}")
    out.append("")
    out += doc_lines("", "The HTML elements a lowercase JSX tag may name, each with its attributes beyond `HtmlGlobalAttributes`.")
    out.append("export interface HtmlElements {")
    for tag, _ in tag_map:
        if tag not in TAGS:
            raise SystemExit("genHtmlTags: no description for <" + tag + ">")
        out += doc_lines("\t", "`<" + tag + ">`: " + TAGS[tag], MDN + "Element/" + tag)
        out.append("\t" + tag + ": " + ms_attrs_name(by_tag[tag][0]) + ";")
    out.append("}")
    html = {t for t, _ in tag_map}
    open_tags = sorted({t for t in foreign if t not in html})
    out.append("")
    out.append("@comptime export function foreignTagNames(): string[] {")
    out += list_lines("\t", "return [", ['"' + t + '"' for t in open_tags], "];")
    out.append("}")
    out.append("")
    out.append("@comptime export function hyphenatedAttributeNames(): string[] {")
    out += list_lines("\t", "return [", ['"' + n + '"' for n in sorted(hyphenated)], "];")
    out.append("}")
    out.append("")
    out.append("@comptime export function refusedAttributeNames(): string[] {")
    out += list_lines("\t", "return [", ['"' + n + '"' for n in sorted(refused)], "];")
    out.append("}")
    open(path, "w").write("\n".join(out) + "\n")
    for tag, name, ts in skipped:
        print("skipped <" + tag + "> " + name + ": " + ts)
    print("wrote " + path + ": " + str(len(tag_map)) + " tags")


BASE = ["Node", "Element", "ChildNode", "HTMLElement", "HTMLOrSVGElement", "ElementContentEditable",
        "ElementCSSInlineStyle"]
EXTRA_CLASSES = ["DOMRect", "TextMetrics", "CanvasRenderingContext2D", "CSSStyleDeclaration", "DOMTokenList",
                 "NodeList", "Event"]
METHODS = {
    "Node": ["hasChildNodes"],
    "ChildNode": ["remove"],
    "CSSStyleDeclarationBase": ["getPropertyValue", "removeProperty"],
    "DOMTokenList": ["contains", "toggle", "replace"],
    "Event": ["preventDefault", "stopPropagation", "stopImmediatePropagation"],
    "Element": ["getAttribute", "setAttribute", "removeAttribute", "hasAttribute", "toggleAttribute",
                "getBoundingClientRect", "scrollIntoView", "scrollTo", "scrollBy", "matches",
                "requestFullscreen", "checkVisibility"],
    "HTMLElement": ["click", "showPopover", "hidePopover", "togglePopover"],
    "HTMLOrSVGElement": ["focus", "blur"],
    "HTMLInputElement": ["select", "setSelectionRange", "checkValidity", "reportValidity", "setCustomValidity",
                         "showPicker", "stepUp", "stepDown", "setRangeText"],
    "HTMLTextAreaElement": ["select", "setSelectionRange", "checkValidity", "reportValidity", "setCustomValidity",
                            "setRangeText"],
    "HTMLSelectElement": ["checkValidity", "reportValidity", "setCustomValidity", "showPicker"],
    "HTMLButtonElement": ["checkValidity", "reportValidity", "setCustomValidity"],
    "HTMLFieldSetElement": ["checkValidity", "reportValidity", "setCustomValidity"],
    "HTMLOutputElement": ["checkValidity", "reportValidity", "setCustomValidity"],
    "HTMLObjectElement": ["checkValidity", "reportValidity", "setCustomValidity"],
    "HTMLFormElement": ["submit", "reset", "requestSubmit", "checkValidity", "reportValidity"],
    "HTMLDialogElement": ["show", "showModal", "close", "requestClose"],
    "HTMLMediaElement": ["play", "pause", "load", "canPlayType", "fastSeek"],
    "HTMLCanvasElement": ["getContext", "toDataURL"],
    "HTMLImageElement": ["decode"],
    "HTMLTableElement": ["deleteRow", "deleteCaption", "deleteTHead", "deleteTFoot"],
    "CanvasRect": ["fillRect", "strokeRect", "clearRect"],
    "CanvasText": ["fillText", "strokeText", "measureText"],
    "CanvasPath": ["closePath", "moveTo", "lineTo", "arc", "arcTo", "ellipse", "rect", "bezierCurveTo",
                   "quadraticCurveTo"],
    "CanvasDrawPath": ["beginPath", "fill", "stroke", "clip"],
    "CanvasState": ["save", "restore", "reset"],
    "CanvasTransform": ["translate", "rotate", "scale", "setTransform", "resetTransform", "transform"],
    "CanvasPathDrawingStyles": ["setLineDash"],
}
# lib.dom writes these with a rest parameter, a generic or a listener object, which the member mapper
# above does not translate; the shapes below are the subset the platform hosts call.
HAND_MAPPED_MEMBERS = {
    "HTMLElement": ["extern addEventListener(type: string, listener: (event: Event) => void): void;",
                    "extern querySelectorAll(selectors: string): NodeList;"],
    "DOMTokenList": ["extern add(token: string): void;", "extern remove(token: string): void;"],
    "NodeList": ["extern item(index: number): HTMLElement | null;"],
}
CLASS_MEMBER_NAMES_THAT_DO_NOT_PARSE = {"async", "static", "readonly", "abstract"}


def member_type(ts, alias, declared, param):
    parts = flatten(ts, alias)
    literals = [p for p in parts if re.fullmatch(r'"[^"]*"', p)]
    if len(parts) == 1 and re.fullmatch(r"Promise<void>", parts[0]):
        return None if param else "Promise<void>"
    if ts == "number[]":
        return "number[]"
    keep = []
    for p in parts:
        if p in ("string", "number", "boolean", "void"):
            keep.append(p)
        elif p in literals:
            keep.append("string" if param else p)
        elif p == "null" and not param:
            keep.append(p)
        elif p in declared and not param:
            keep.append(p)
        elif param or "string" not in parts:
            return None
    if param and len(set(keep)) > 1:
        return None
    keep = list(dict.fromkeys(keep))
    return " | ".join(keep) if keep else None


def method_line(name, overloads, alias, declared):
    best = None
    for m in overloads:
        params = []
        ok = True
        for p in split_top(m["params"][1:-1], ","):
            p = p.strip()
            if not p:
                continue
            pm = re.fullmatch(r"(\w+)(\?)?\s*:\s*(.+)", p)
            if not pm:
                ok = False
                break
            if pm.group(2):
                continue
            t = member_type(pm.group(3), alias, declared, True)
            if t is None:
                ok = False
                break
            params.append(pm.group(1) + ": " + t)
        ret = member_type(m["type"], alias, declared, False)
        if ok and ret is not None and (best is None or len(params) > len(best[0])):
            best = (params, ret)
    if best is None:
        return None
    return list_lines("\t\t", "extern " + name + "(", best[0], "): " + best[1] + ";")


def class_body(sources, blocks, alias, declared, emitted_props):
    lines = []
    for src_name in sources:
        if src_name not in blocks:
            continue
        ms = members(blocks[src_name][1])
        overloads = {}
        for m in ms:
            if m["params"] is not None:
                overloads.setdefault(m["name"], []).append(m)
        for m in ms:
            name = m["name"]
            if m["params"] is not None or name in emitted_props or name.startswith("on"):
                continue
            if name in CLASS_MEMBER_NAMES_THAT_DO_NOT_PARSE or not re.fullmatch(r"[A-Za-z_]\w*", name):
                continue
            t = member_type(m["type"], alias, declared, False)
            if t is None or t == "void":
                continue
            emitted_props.add(name)
            lines += typed_line("\t\t", ("readonly " if m["readonly"] else "") + name + ": ", t, ";")
        for name in METHODS.get(src_name, []):
            if name in emitted_props or name not in overloads:
                continue
            line = method_line(name, overloads[name], alias, declared)
            if line is not None:
                emitted_props.add(name)
                lines += line
    return lines


def mixins(name, blocks):
    out, chain = [], [name]
    while chain:
        x = chain.pop(0)
        if x not in blocks or x in out:
            continue
        out.append(x)
        chain += [p for p in blocks[x][0] if not p.startswith("HTML") or not p.endswith("Element")]
    return out


def write_elements(path):
    src = open(DOM).read()
    blocks = interfaces(src)
    alias = aliases(src)
    tag_map, _ = dom_tag_map()
    classes = []
    for _, cls in tag_map:
        chain = [cls]
        while chain[-1] != "HTMLElement":
            chain.append(next(p for p in blocks[chain[-1]][0] if p.startswith("HTML") and p.endswith("Element")))
        for c in reversed(chain):
            if c not in classes:
                classes.append(c)
    declared = set(classes) | set(EXTRA_CLASSES)
    out = ["// Generated by tools/genHtmlTags.py; edit the generator, not this file.", "", "when (js) {"]
    for cls in EXTRA_CLASSES:
        out.append("\texport extern class " + cls + " {")
        out += class_body(mixins(cls, blocks), blocks, alias, declared, set())
        out += ["\t\t" + line for line in HAND_MAPPED_MEMBERS.get(cls, [])]
        out.append("\t}")
        out.append("")
    inherited = {}
    for cls in classes:
        if cls == "HTMLElement":
            parent = None
            sources = BASE
        else:
            parent = next(p for p in blocks[cls][0] if p.startswith("HTML") and p.endswith("Element"))
            sources = [s for s in mixins(cls, blocks)]
        seen = set(inherited.get(parent, set()))
        body = class_body(sources, blocks, alias, declared, seen)
        inherited[cls] = seen
        out.append("\texport extern class " + cls + (" extends " + parent if parent else "") + " {")
        out += body
        out += ["\t\t" + line for line in HAND_MAPPED_MEMBERS.get(cls, [])]
        out.append("\t}")
        out.append("")
    out += doc_lines("\t", "The DOM element class each HTML tag creates, as TypeScript's `HTMLElementTagNameMap`.")
    out.append("\texport interface HTMLElementTagNameMap {")
    for tag, cls in tag_map:
        out.append("\t\t" + tag + ": " + cls + ";")
    out.append("\t}")
    out.append("}")
    open(path, "w").write("\n".join(out) + "\n")
    print("wrote " + path + ": " + str(len(classes)) + " element classes")


if __name__ == "__main__":
    write_tags(os.path.join(ROOT, "src/render/htmlTags.ms"))
    write_elements(os.path.join(ROOT, "src/render/htmlElements.ms"))
