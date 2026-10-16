import { NeonNode } from "../../src/render/node";
import { createSignal, Accessor } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { renderToString } from "../../src/render/ssr";

class User {
	name: string;
	constructor(name: string) { this.name = name; }
}

test "the server writes the selected case, and the fallback when none matches" {
	const [n, setN] = createSignal(2);
	const view = (): string => renderToString(element(<div><Match fallback={<i>none</i>}>
		<Case when={n() === 1}><b>one</b></Case>
		<Case when={n() >= 2}><b>many</b></Case>
		<Case when={n() >= 2}><b>also many</b></Case>
	</Match></div>));
	assert view() === "<div><b>many</b><!----></div>", view();
	setN(1);
	assert view() === "<div><b>one</b><!----></div>", view();
	setN(0);
	assert view() === "<div><i>none</i><!----></div>", view();
}

test "the server writes the callback and keyed forms with the narrowed value" {
	const [user, setUser] = createSignal<User | null>(new User("ann"));
	const html = renderToString(element(<div>
		<Match fallback={<u>none</u>}>
			<Case when={user()}>{(u: Accessor<User>): NeonNode => <b>{u().name}</b>}</Case>
		</Match>
		<Match>
			<Case when={user()} keyed>{(u: User): NeonNode => <i>{u.name}</i>}</Case>
		</Match>
	</div>));
	assert html === "<div><b>ann</b><!----><i>ann</i><!----></div>", html;
}
