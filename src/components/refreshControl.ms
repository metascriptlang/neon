import { Accessor } from "../core/signal";
import { NeonEvent } from "../render/event";
import { NeonNode } from "../render/node";
import { Host, HostNode } from "../render/hostTypes";
import { bindAttr } from "../render/bind";

interface RefreshControlProps {
	refreshing: Accessor<boolean>;
	onRefresh?: (() => void) | null;
	enabled?: Accessor<boolean> | null;
	tintColor?: Accessor<string> | null;
	title?: Accessor<string> | null;
	colors?: Accessor<string[]> | null;
	progressBackgroundColor?: Accessor<string> | null;
}

// RN's RefreshControl is a native child the ScrollView adopts as its pull-to-
// refresh control. Here it is a NeonNode that mounts no node of its own: the
// ScrollView mounts it onto its own scroll node, where it writes the scroll
// view's refresh options and routes its refresh event, the same channel as
// ScrollView's `refreshing`/`onRefresh` props.
export function RefreshControl(props: RefreshControlProps): NeonNode {
	const { refreshing, onRefresh, enabled, tintColor, title, colors, progressBackgroundColor } = props;
	return (host: Host, scroll: HostNode, before: HostNode | null): void => {
		bindAttr(host, scroll, "refreshEnabled", (): string | null => enabled === null || (enabled as Accessor<boolean>)() ? "true" : "false");
		bindAttr(host, scroll, "refreshing", (): string | null => refreshing() ? "true" : "false");
		if (tintColor !== null) { bindAttr(host, scroll, "refreshTintColor", (): string | null => (tintColor as Accessor<string>)()); }
		if (title !== null) { bindAttr(host, scroll, "refreshTitle", (): string | null => (title as Accessor<string>)()); }
		if (colors !== null) { bindAttr(host, scroll, "refreshColors", (): string | null => (colors as Accessor<string[]>)().join(",")); }
		if (progressBackgroundColor !== null) {
			bindAttr(host, scroll, "refreshBackgroundColor", (): string | null => (progressBackgroundColor as Accessor<string>)());
		}
		if (onRefresh !== null) {
			host.addEvent(scroll, "onRefresh", (e: NeonEvent): void => { (onRefresh as () => void)(); });
		}
	};
}
