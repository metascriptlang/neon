import { Navigation } from "../../src/navigation/index";

interface TabList {
	Browse: null;
	Settings: { theme: string };
}

interface StackList {
	List: null;
	Detail: { id: int32 };
}

export function go(navigation: Navigation<StackList>): void {
	navigation.getParent<StackList, TabList>().navigate("Detail", { id: 1 });
}
