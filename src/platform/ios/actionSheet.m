#import "modules.h"
#include "component.h"

enum { ACTION_SHEET_EVENT = 15 };

static NSMutableArray<NSArray *> *g_sheets;

static NSSet<NSNumber *> *indexSet(NSString *list) {
	NSMutableSet *set = [NSMutableSet set];
	for (NSString *part in [list componentsSeparatedByString:@","]) {
		if (part.length) [set addObject:@(part.integerValue)];
	}
	return set;
}

static UIColor *color(NSString *css) {
	return css.length ? neonCssColor(css.UTF8String, nil) : nil;
}

// react-native 693e9628e8c, React/CoreModules/RCTActionSheetManager.mm:49-217.
static void show(NSString *arg) {
	NSArray<NSString *> *parts = [arg componentsSeparatedByString:NIRecord];
	NSArray<NSString *> *head = [parts[0] componentsSeparatedByString:NIField];
	if (head.count != 10) {
		NSLog(@"Neon actionsheet.show: malformed request");
		abort();
	}
	NSString *sheetId = head[0];
	NSString *title = head[1].length ? head[1] : nil;
	NSString *message = head[2].length ? head[2] : nil;
	NSInteger cancelIndex = head[3].integerValue;
	NSSet<NSNumber *> *destructive = indexSet(head[4]);
	NSSet<NSNumber *> *disabled = indexSet(head[5]);
	UIColor *tint = color(head[6]);
	UIColor *cancelTint = color(head[7]);
	UIColor *disabledTint = color(head[8]);
	NSString *style = head[9];

	UIViewController *top = niPresenter();
	if (!top) {
		NSLog(@"Neon ActionSheetIOS: no application window to show the action sheet in");
		abort();
	}
	UIAlertController *controller = [UIAlertController alertControllerWithTitle:title message:message
		preferredStyle:UIAlertControllerStyleActionSheet];
	__block BOOL answered = NO;
	for (NSUInteger i = 1; i < parts.count; i++) {
		NSInteger index = (NSInteger)(i - 1);
		UIAlertActionStyle actionStyle = [destructive containsObject:@(index)] ? UIAlertActionStyleDestructive
			: index == cancelIndex ? UIAlertActionStyleCancel : UIAlertActionStyleDefault;
		UIAlertAction *action = [UIAlertAction actionWithTitle:parts[i] style:actionStyle handler:^(UIAlertAction *chosen) {
			if (answered) return;
			answered = YES;
			for (NSArray *sheet in [g_sheets copy]) {
				if (sheet[1] == controller) [g_sheets removeObject:sheet];
			}
			niAppEmit(ACTION_SHEET_EVENT, [@[sheetId, [@(index) stringValue]] componentsJoinedByString:NIField]);
		}];
		UIColor *titleColor = actionStyle == UIAlertActionStyleCancel && cancelTint ? cancelTint
			: actionStyle == UIAlertActionStyleDefault ? tint : nil;
		if (titleColor) [action setValue:titleColor forKey:@"titleTextColor"];
		[controller addAction:action];
	}
	for (NSNumber *index in disabled) {
		UIAlertAction *action = controller.actions[index.unsignedIntegerValue];
		action.enabled = NO;
		if (disabledTint) [action setValue:disabledTint forKey:@"titleTextColor"];
	}
	controller.view.tintColor = tint;
	controller.overrideUserInterfaceStyle = [style isEqualToString:@"dark"] ? UIUserInterfaceStyleDark
		: [style isEqualToString:@"light"] ? UIUserInterfaceStyleLight : UIUserInterfaceStyleUnspecified;
	if (!g_sheets) g_sheets = [NSMutableArray array];
	[g_sheets addObject:@[sheetId, controller]];

	// The anchor option needs a view tag Neon has no registry for: the sheet is centered, which is RN's answer without one.
	controller.modalPresentationStyle = UIModalPresentationPopover;
	controller.popoverPresentationController.permittedArrowDirections = 0;
	if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
		controller.popoverPresentationController.sourceView = top.view;
		controller.popoverPresentationController.sourceRect = top.view.bounds;
	}
	[top presentViewController:controller animated:YES completion:nil];
}

static NSString *dismiss(void) {
	NSArray *sheet = g_sheets.lastObject;
	if (!sheet) {
		NSLog(@"Neon ActionSheetIOS.dismissActionSheet: Unable to dismiss action sheet");
		return @"";
	}
	[g_sheets removeLastObject];
	[(UIAlertController *)sheet[1] dismissViewControllerAnimated:YES completion:nil];
	return sheet[0];
}

NSString *niActionSheetCall(NSString *name, NSString *arg) {
	if ([name isEqualToString:@"actionsheet.show"]) {
		show(arg);
		return @"";
	}
	if ([name isEqualToString:@"actionsheet.dismiss"]) return dismiss();
	NSLog(@"Neon niAppCall: unknown command %@", name);
	abort();
}
