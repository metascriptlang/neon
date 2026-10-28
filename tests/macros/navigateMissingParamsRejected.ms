import { Navigation } from "../../src/navigation/index";

interface Routes {
	Home: null;
	Detail: { id: string; tab: string | null };
}

export function go(navigation: Navigation<Routes>): void {
	navigation.navigate("Detail");
}
