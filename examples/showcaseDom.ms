import { createSignal } from "../src/core/signal";
import { el, attr, evt, text, dynText } from "../src/render/node";
import { element } from "../src/macros/ui/element";
import { renderToHost } from "../src/render/host";
import { domHost, documentBody } from "../src/platform/browser/dom";

const [count, setCount] = createSignal(0);

const view = <div class="card">
	<div class="kicker">NEON REACTIVE</div>
	<div class="badge">{count() + ""}</div>
	<p class="meta">square {count() * count() + ""} - {count() % 2 === 0 ? "even" : "odd"}</p>
	<div class="row">
		<button class="btn ghost" onPress={() => setCount(count() - 1)}>-</button>
		<button class="btn" onPress={() => setCount(0)}>reset</button>
		<button class="btn solid" onPress={() => setCount(count() + 1)}>+</button>
	</div>
</div>;

renderToHost(element(view), domHost(), documentBody());
