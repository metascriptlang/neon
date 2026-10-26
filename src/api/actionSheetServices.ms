export interface ActionSheetRequest {
	title: string;
	message: string;
	options: string[];
	cancelButtonIndex: int32;
	destructiveButtonIndices: int32[];
	disabledButtonIndices: int32[];
	tintColor: string;
	cancelButtonTintColor: string;
	disabledButtonTintColor: string;
	userInterfaceStyle: string;
	done: (index: int32) => void;
}

export interface ActionSheetServices {
	showActionSheet: (request: ActionSheetRequest) => void;
	dismissActionSheet: () => void;
}

let installed: ActionSheetServices | null = null;

export function installActionSheetServices(services: ActionSheetServices | null): void {
	installed = services;
}

export function actionSheetServices(api: string): ActionSheetServices {
	const services = installed;
	if (services === null) { throw new Error(`${api} is not available on this host`); }
	return services;
}
