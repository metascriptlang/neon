import { NeonNode } from "../../src/render/node";
import { createSignal, Accessor } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { renderToString } from "../../src/render/ssr";

class User {
	name: string;
	constructor(name: string) { this.name = name; }
}

test "the function forms render to a string" {
	const [user, setUser] = createSignal<User | null>(new User("ann"));
	const html = renderToString(element(<div>
		<Show when={user()}>{(u: Accessor<User>): NeonNode => <b>{u().name}</b>}</Show>
		<Show when={user()} keyed>{(u: User): NeonNode => <i>{u.name}</i>}</Show>
		<Show when={user()} keyed fallback={<u>none</u>}><s>kept</s></Show>
	</div>));
	assert html === "<div><b>ann</b><!----><i>ann</i><!----><s>kept</s><!----></div>", html;
}
