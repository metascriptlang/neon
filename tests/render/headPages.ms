import { NeonNode } from "../../src/render/node";
import { Accessor } from "../../src/core/signal";
import { Head } from "../../src/render/head";
import { View, Text } from "../../src/components/primitives";

export function Page(props: { title: Accessor<string> }): NeonNode {
	return <View>
		<Head>
			<title>{props.title()}</title>
			<meta name="description" content="the page's own" />
			<meta name="robots" content="index" />
		</Head>
		<Text>body</Text>
	</View>;
}

export function Layout(props: { children: NeonNode }): NeonNode {
	return <View>
		<Head>
			<title>Site</title>
			<meta name="description" content="the layout's" />
			<meta name="theme-color" content="#101418" />
			<meta name="robots" content="index" />
			<link rel="canonical" href="/docs?a=1&b=2" />
		</Head>
		{props.children}
	</View>;
}
