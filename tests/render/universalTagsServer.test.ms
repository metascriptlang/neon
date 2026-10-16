import { element } from "../../src/macros/ui/element";
import { View, Text, Pressable } from "../../src/components/primitives";
import { renderToString } from "../../src/render/ssr";

test "a container with no children mounts empty, several mount in order" {
	const empty = renderToString(element(<View />));
	assert empty === "<div class=\"neon-view\"></div>", "empty View: " + empty;
	const many = renderToString(element(<View><Text>a</Text>mid<Text>b</Text></View>));
	assert many === "<div class=\"neon-view\"><span class=\"neon-text\">a</span>mid" +
		"<span class=\"neon-text\">b</span></div>", "several: " + many;
	const label = renderToString(element(<Pressable>go</Pressable>));
	assert label === "<button class=\"neon-view\">go</button>", "text only: " + label;
}

test "ssr serializes the vocabulary as html" {
	const s = renderToString(element(<View><Text>hi</Text></View>));
	assert s === "<div class=\"neon-view\"><span class=\"neon-text\">hi</span></div>",
		"ssr wrote " + s;
}
