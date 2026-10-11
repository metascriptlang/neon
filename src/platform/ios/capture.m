#import "modules.h"
#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <AVFoundation/AVFoundation.h>

enum { REPLY_EVENT = 9 };

@interface NeonPickRequest : NSObject
@property(nonatomic, copy) NSString *requestId;
@property(nonatomic) BOOL camera;
@property(nonatomic) BOOL images;
@property(nonatomic) BOOL videos;
@property(nonatomic) BOOL allowsEditing;
@property(nonatomic) double quality;
@property(nonatomic) BOOL base64;
@property(nonatomic) BOOL multiple;
@property(nonatomic) NSInteger selectionLimit;
@property(nonatomic, copy) NSString *cameraType;
@end

@implementation NeonPickRequest
@end

@interface NeonCapturePicker : NSObject <PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIAdaptivePresentationControllerDelegate>
@property(nonatomic, strong) NeonPickRequest *request;
@end

static NeonCapturePicker *g_picker;

static void finish(NSString *reply) {
	if (!g_picker) return;
	NSString *requestId = g_picker.request.requestId;
	g_picker = nil;
	niAppEmit(REPLY_EVENT, [@[requestId, reply] componentsJoinedByString:NIField]);
}

static void finishOnMain(NSString *reply) {
	dispatch_async(dispatch_get_main_queue(), ^{ finish(reply); });
}

static UIViewController *presenter(void) {
	UIWindow *key = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) continue;
		for (UIWindow *window in ((UIWindowScene *)scene).windows) {
			if (window.isKeyWindow) key = window;
		}
	}
	UIViewController *top = key.rootViewController;
	while (top.presentedViewController) top = top.presentedViewController;
	return top;
}

static NSString *pickFolder(void) {
	NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
	NSString *folder = [caches stringByAppendingPathComponent:@"ImagePicker"];
	[NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
	return folder;
}

static NSString *number(double value) {
	return [NSString stringWithFormat:@"%.0f", value];
}

static NSString *assetRecord(NSString *path, double width, double height, NSString *type, NSString *fileName, NSString *mimeType, NSString *duration, NSString *base64) {
	NSNumber *size = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFileSize];
	return [@[[NSURL fileURLWithPath:path].absoluteString, number(width), number(height), type, fileName,
		size ? number(size.doubleValue) : @"", mimeType, duration, base64] componentsJoinedByString:NIField];
}

static NSString *storedName(NSString *suggested, NSString *extension, NSString *path) {
	if (suggested.length == 0) return path.lastPathComponent;
	return [suggested.stringByDeletingPathExtension stringByAppendingPathExtension:extension];
}

static NSString *extensionOf(UTType *type) {
	if ([type conformsToType:UTTypeJPEG]) return @"jpg";
	return type.preferredFilenameExtension ?: @"bin";
}

static NSString *storeImage(NSData *original, UTType *originalType, UIImage *image, NSString *suggested, NeonPickRequest *request, NSString **error) {
	if (!image) {
		*error = @"cannot decode the picked image";
		return nil;
	}
	BOOL keep = original && request.quality >= 1 &&
		([originalType conformsToType:UTTypeJPEG] || [originalType conformsToType:UTTypePNG] || [originalType conformsToType:UTTypeGIF]);
	NSData *bytes = keep ? original : UIImageJPEGRepresentation(image, MIN(MAX(request.quality, 0), 1));
	UTType *type = keep ? originalType : UTTypeJPEG;
	if (!bytes) {
		*error = @"cannot encode the picked image as JPEG";
		return nil;
	}
	NSString *extension = extensionOf(type);
	NSString *path = [pickFolder() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", NSUUID.UUID.UUIDString, extension]];
	NSError *writeError = nil;
	if (![bytes writeToFile:path options:NSDataWritingAtomic error:&writeError]) {
		*error = writeError.localizedDescription ?: @"cannot store the picked image";
		return nil;
	}
	return assetRecord(path, image.size.width * image.scale, image.size.height * image.scale, @"image",
		storedName(suggested, extension, path), type.preferredMIMEType ?: @"image/jpeg", @"",
		request.base64 ? [bytes base64EncodedStringWithOptions:0] : @"");
}

static NSString *storeVideo(NSURL *source, NSString *suggested, NSString **error) {
	NSString *extension = source.pathExtension.lowercaseString.length ? source.pathExtension.lowercaseString : @"mov";
	NSString *path = [pickFolder() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", NSUUID.UUID.UUIDString, extension]];
	NSError *copyError = nil;
	if (![NSFileManager.defaultManager copyItemAtURL:source toURL:[NSURL fileURLWithPath:path] error:&copyError]) {
		*error = copyError.localizedDescription ?: @"cannot store the picked video";
		return nil;
	}
	AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
	AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
	CGSize size = track ? CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform) : CGSizeZero;
	double seconds = CMTimeGetSeconds(asset.duration);
	NSString *duration = isfinite(seconds) ? number(seconds * 1000) : @"";
	NSString *mime = [UTType typeWithFilenameExtension:extension].preferredMIMEType ?: @"video/quicktime";
	return assetRecord(path, fabs(size.width), fabs(size.height), @"video", storedName(suggested, extension, path), mime, duration, @"");
}

static NSString *pickedType(NSItemProvider *provider, NeonPickRequest *request, BOOL *video) {
	for (NSString *identifier in provider.registeredTypeIdentifiers) {
		UTType *type = [UTType typeWithIdentifier:identifier];
		if (request.videos && [type conformsToType:UTTypeMovie]) {
			*video = YES;
			return identifier;
		}
		if (request.images && [type conformsToType:UTTypeImage]) {
			*video = NO;
			return identifier;
		}
	}
	return nil;
}

@implementation NeonCapturePicker

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
	[picker dismissViewControllerAnimated:YES completion:nil];
	if (g_picker != self) return;
	if (results.count == 0) {
		finish(@"canceled");
		return;
	}
	NeonPickRequest *request = self.request;
	NSMutableArray *records = [NSMutableArray array];
	for (NSUInteger i = 0; i < results.count; i++) [records addObject:@""];
	NSMutableArray<NSString *> *failures = [NSMutableArray array];
	dispatch_group_t group = dispatch_group_create();
	[results enumerateObjectsUsingBlock:^(PHPickerResult *result, NSUInteger at, BOOL *stop) {
		NSItemProvider *provider = result.itemProvider;
		BOOL video = NO;
		NSString *identifier = pickedType(provider, request, &video);
		if (!identifier) {
			@synchronized (records) { [failures addObject:@"the picked item is neither an image nor a video"]; }
			return;
		}
		NSString *suggested = provider.suggestedName;
		dispatch_group_enter(group);
		[provider loadFileRepresentationForTypeIdentifier:identifier completionHandler:^(NSURL *url, NSError *loadError) {
			NSString *problem = loadError.localizedDescription ?: @"the picked item has no file";
			NSString *record = nil;
			if (url && video) record = storeVideo(url, suggested, &problem);
			else if (url) {
				NSData *bytes = [NSData dataWithContentsOfURL:url];
				record = storeImage(bytes, [UTType typeWithIdentifier:identifier], bytes ? [UIImage imageWithData:bytes] : nil, suggested, request, &problem);
			}
			@synchronized (records) {
				if (record) records[at] = record;
				else [failures addObject:problem];
			}
			dispatch_group_leave(group);
		}];
	}];
	dispatch_group_notify(group, dispatch_get_main_queue(), ^{
		if (failures.count) {
			finish([NSString stringWithFormat:@"!ImagePicker: cannot load the picked media: %@", failures.firstObject]);
			return;
		}
		finish([[@[@"ok"] arrayByAddingObjectsFromArray:records] componentsJoinedByString:NIRecord]);
	});
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)controller {
	if (g_picker == self) finish(@"canceled");
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	[picker dismissViewControllerAnimated:YES completion:nil];
	if (g_picker == self) finish(@"canceled");
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
	[picker dismissViewControllerAnimated:YES completion:nil];
	if (g_picker != self) return;
	NeonPickRequest *request = self.request;
	NSString *mediaType = info[UIImagePickerControllerMediaType];
	BOOL video = [[UTType typeWithIdentifier:mediaType] conformsToType:UTTypeMovie];
	UIImage *image = request.allowsEditing ? (info[UIImagePickerControllerEditedImage] ?: info[UIImagePickerControllerOriginalImage]) : info[UIImagePickerControllerOriginalImage];
	NSURL *movie = info[UIImagePickerControllerMediaURL];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSString *problem = @"the camera returned no media";
		NSString *record = nil;
		if (video && movie) record = storeVideo(movie, nil, &problem);
		else if (!video) record = storeImage(nil, UTTypeJPEG, image, nil, request, &problem);
		finishOnMain(record ? [@[@"ok", record] componentsJoinedByString:NIRecord] : [@"!ImagePicker: " stringByAppendingString:problem]);
	});
}

@end

static NSString *launchCamera(NeonCapturePicker *picker, UIViewController *top) {
	NeonPickRequest *request = picker.request;
	if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
		return @"!ImagePicker.launchCameraAsync: the camera is not available on this device";
	}
	if (![NSBundle.mainBundle objectForInfoDictionaryKey:@"NSCameraUsageDescription"]) {
		return @"!ImagePicker.launchCameraAsync: add NSCameraUsageDescription to the app's Info.plist";
	}
	NSArray<NSString *> *available = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypeCamera];
	NSMutableArray<NSString *> *mediaTypes = [NSMutableArray array];
	if (request.images && [available containsObject:UTTypeImage.identifier]) [mediaTypes addObject:UTTypeImage.identifier];
	if (request.videos && [available containsObject:UTTypeMovie.identifier]) [mediaTypes addObject:UTTypeMovie.identifier];
	if (mediaTypes.count == 0) return @"!ImagePicker.launchCameraAsync: the camera cannot capture the requested media types";
	UIImagePickerController *controller = [[UIImagePickerController alloc] init];
	controller.sourceType = UIImagePickerControllerSourceTypeCamera;
	controller.mediaTypes = mediaTypes;
	controller.allowsEditing = request.allowsEditing;
	controller.videoQuality = UIImagePickerControllerQualityTypeHigh;
	UIImagePickerControllerCameraDevice device = [request.cameraType isEqualToString:@"front"] ? UIImagePickerControllerCameraDeviceFront : UIImagePickerControllerCameraDeviceRear;
	if ([UIImagePickerController isCameraDeviceAvailable:device]) controller.cameraDevice = device;
	controller.delegate = picker;
	g_picker = picker;
	[top presentViewController:controller animated:YES completion:nil];
	return @"";
}

static NSString *launchLibrary(NeonCapturePicker *picker, UIViewController *top) {
	NeonPickRequest *request = picker.request;
	PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
	configuration.selectionLimit = request.multiple ? MAX(request.selectionLimit, 0) : 1;
	if (request.images && request.videos) configuration.filter = [PHPickerFilter anyFilterMatchingSubfilters:@[PHPickerFilter.imagesFilter, PHPickerFilter.videosFilter]];
	else if (request.images) configuration.filter = PHPickerFilter.imagesFilter;
	else if (request.videos) configuration.filter = PHPickerFilter.videosFilter;
	else return @"!ImagePicker: no media type was requested";
	PHPickerViewController *controller = [[PHPickerViewController alloc] initWithConfiguration:configuration];
	controller.delegate = picker;
	controller.presentationController.delegate = picker;
	g_picker = picker;
	[top presentViewController:controller animated:YES completion:nil];
	return @"";
}

static NSString *pick(NSString *arg) {
	NSArray<NSString *> *fields = [arg componentsSeparatedByString:NIField];
	if (fields.count != 10) {
		NSLog(@"Neon capture.pick: expected 10 fields, got %lu: %@", (unsigned long)fields.count, arg);
		abort();
	}
	if (g_picker) return @"!ImagePicker: another picker is already open";
	NeonPickRequest *request = [NeonPickRequest new];
	request.requestId = fields[0];
	request.camera = [fields[1] isEqualToString:@"1"];
	request.images = [fields[2] isEqualToString:@"1"];
	request.videos = [fields[3] isEqualToString:@"1"];
	request.allowsEditing = [fields[4] isEqualToString:@"1"];
	request.quality = fields[5].doubleValue;
	request.base64 = [fields[6] isEqualToString:@"1"];
	request.multiple = [fields[7] isEqualToString:@"1"];
	request.selectionLimit = fields[8].integerValue;
	request.cameraType = fields[9];
	UIViewController *top = presenter();
	if (!top) return @"!ImagePicker: there is no window to present the picker from";
	NeonCapturePicker *picker = [NeonCapturePicker new];
	picker.request = request;
	return request.camera ? launchCamera(picker, top) : launchLibrary(picker, top);
}

NSString *niCaptureCall(NSString *name, NSString *arg) {
	if ([name isEqualToString:@"capture.pick"]) return pick(arg);
	NSLog(@"Neon niAppCall: unknown command %@", name);
	abort();
}
