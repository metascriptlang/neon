import { NeonNode } from "../../src/render/node";
import { Text } from "../../src/components/primitives";
import { FlatList, FlatListHandle, ListRenderItemInfo } from "../../src/components/flatList";

interface Message {
	id: string;
	body: string;
}

const messages: Message[] = [{ id: "m1", body: "hi" }];

export function Inbox(): NeonNode {
	return <FlatList data={messages}
		ref={(list: FlatListHandle<Message>): void => { list.scrollToItem({ item: "m1" }); }}
		renderItem={(info: ListRenderItemInfo<Message>): NeonNode => <Text>{info.item.body}</Text>} />;
}
