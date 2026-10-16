import { createSignal, Accessor } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { renderToString } from "../../src/render/ssr";

interface CounterProps {
	count: Accessor<number>;
	label: Accessor<string>;
}

function Counter(props: CounterProps): NeonNode {
	return element(<p class={props.label}>n={props.count().toString()}</p>);
}

test "component nests inside a lowercase tree" {
	const [n, setN] = createSignal(2);
	const view = element(<div><Counter count={n()} label="x" /></div>);
	const out = renderToString(view);
	assert out === "<div><p class=\"x\">n=<!--!-->2</p></div>", "got " + out;
}

interface CardProps {
	title: Accessor<string>;
	children: NeonNode;
}

function Card(props: CardProps): NeonNode {
	return <section title={props.title()}>{props.children}</section>;
}

test "single element child passes as the children prop" {
	const view = element(<Card title="t"><p>inner</p></Card>);
	const out = renderToString(view);
	assert out === "<section title=\"t\"><p>inner</p></section>", "got " + out;
}

interface WrapProps {
	children: NeonNode;
}

function Wrap(props: WrapProps): NeonNode {
	return element(<ul>{props.children}</ul>);
}

test "one element child arrives as one NeonNode" {
	const out = renderToString(element(<Wrap><li>a</li></Wrap>));
	assert out === "<ul><li>a</li></ul>", "got " + out;
}

test "several children arrive as one NeonNode that places every root" {
	const out = renderToString(element(<Wrap><li>a</li><li>b</li></Wrap>));
	assert out === "<ul><li>a</li><li>b</li></ul>", "got " + out;
}

test "one text child arrives as one NeonNode" {
	const out = renderToString(element(<Wrap>plain</Wrap>));
	assert out === "<ul>plain</ul>", "got " + out;
}

test "text beside an element keeps source order inside the one NeonNode" {
	const out = renderToString(element(<Wrap>lead<li>a</li>tail</Wrap>));
	assert out === "<ul>lead<li>a</li>tail</ul>", "got " + out;
}

test "a NeonNode value as the only child crosses as itself" {
	const item: NeonNode = element(<li>held</li>);
	const out = renderToString(element(<Wrap>{item}</Wrap>));
	assert out === "<ul><li>held</li></ul>", "got " + out;
}

interface StyledProps {
	style: Accessor<{ gap: number }>;
	label: Accessor<string>;
}

function Styled(props: StyledProps): NeonNode {
	return element(<p class={props.label}>{props.style.gap.toString()}</p>);
}

test "an object literal prop is stamped by the accessor's declared payload" {
	const view = element(<Styled style={{ gap: 12 }} label="s" />);
	assert renderToString(view) === "<p class=\"s\">12</p>", "got " + renderToString(view);
}
