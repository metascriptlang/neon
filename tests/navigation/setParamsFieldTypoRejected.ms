import { RouteProp } from "../../src/navigation/index";

interface DetailList {
	Detail: { id: string; tab: string };
}

export function go(route: RouteProp<DetailList, "Detail">): void {
	route.setParams({ tba: "reviews" });
}
