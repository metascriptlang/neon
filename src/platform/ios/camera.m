#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#include <string.h>

void neonMediaEmit(int tag, int phase, NSString *value, float width, float height);

enum { CAMERA_READY = 30, CAMERA_MOUNT_ERROR = 31, CAMERA_PICTURE = 32 };

static NSString *const FIELD = @"\x1f";

@class NeonCameraView;

@interface NeonPhotoCapture : NSObject <AVCapturePhotoCaptureDelegate>
@property(nonatomic, copy) NSString *pictureId;
@property(nonatomic) double quality;
@property(nonatomic) BOOL base64;
@property(nonatomic) BOOL answered;
@property(nonatomic, weak) NeonCameraView *view;
@end

@interface NeonCameraView : UIView
@property(nonatomic, strong) AVCaptureSession *session;
@property(nonatomic, strong) AVCapturePhotoOutput *photoOutput;
@property(nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property(nonatomic, strong) AVCaptureDeviceInput *input;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, strong) NSMutableSet<NeonPhotoCapture *> *captures;
@property(nonatomic, copy) NSString *facing;
@property(nonatomic) AVCaptureFlashMode flash;
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL mirror;
@property(nonatomic) BOOL released;
@property(nonatomic) BOOL wanted;
@property(nonatomic) BOOL running;
@property(nonatomic) NSUInteger generation;
@end

static void emitLater(NeonCameraView *view, int phase, NSString *value) {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (view.tag != 0) neonMediaEmit((int)view.tag, phase, value, 0, 0);
	});
}

static NSString *pictureError(NSString *pictureId, NSString *message) {
	return [@[pictureId, @"error", message] componentsJoinedByString:FIELD];
}

static AVCaptureVideoOrientation captureOrientation(UIWindow *window) {
	switch (window.windowScene.interfaceOrientation) {
	case UIInterfaceOrientationLandscapeLeft: return AVCaptureVideoOrientationLandscapeLeft;
	case UIInterfaceOrientationLandscapeRight: return AVCaptureVideoOrientationLandscapeRight;
	case UIInterfaceOrientationPortraitUpsideDown: return AVCaptureVideoOrientationPortraitUpsideDown;
	default: return AVCaptureVideoOrientationPortrait;
	}
}

static AVCaptureDevice *cameraFor(NSString *facing) {
	AVCaptureDevicePosition position = [facing isEqualToString:@"front"] ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
	return [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:position];
}

@implementation NeonPhotoCapture

- (void)finish:(NSString *)value {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self.answered) return;
		self.answered = YES;
		NeonCameraView *view = self.view;
		[view.captures removeObject:self];
		if (view.tag != 0) neonMediaEmit((int)view.tag, CAMERA_PICTURE, value, 0, 0);
	});
}

- (NSString *)store:(NSData *)data {
	UIImage *image = data ? [UIImage imageWithData:data] : nil;
	if (!image) return pictureError(self.pictureId, @"the camera returned no image");
	NSData *bytes = self.quality < 1 ? UIImageJPEGRepresentation(image, MAX(self.quality, 0)) : data;
	NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
	NSString *folder = [caches stringByAppendingPathComponent:@"Camera"];
	[NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
	NSString *path = [folder stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".jpg"]];
	NSError *error = nil;
	if (!bytes || ![bytes writeToFile:path options:NSDataWritingAtomic error:&error]) {
		return pictureError(self.pictureId, error.localizedDescription ?: @"cannot store the picture");
	}
	return [@[self.pictureId, @"ok", [NSURL fileURLWithPath:path].absoluteString,
		[NSString stringWithFormat:@"%.0f", image.size.width * image.scale], [NSString stringWithFormat:@"%.0f", image.size.height * image.scale],
		self.base64 ? [bytes base64EncodedStringWithOptions:0] : @""] componentsJoinedByString:FIELD];
}

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
	if (error) [self finish:pictureError(self.pictureId, error.localizedDescription ?: @"the capture failed")];
	else [self finish:[self store:photo.fileDataRepresentation]];
}

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishCaptureForResolvedSettings:(AVCaptureResolvedPhotoSettings *)settings error:(NSError *)error {
	[self finish:pictureError(self.pictureId, error.localizedDescription ?: @"the capture produced no photo")];
}

@end

@implementation NeonCameraView

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		_session = [[AVCaptureSession alloc] init];
		_photoOutput = [[AVCapturePhotoOutput alloc] init];
		_queue = dispatch_queue_create("neon.camera", DISPATCH_QUEUE_SERIAL);
		_captures = [NSMutableSet set];
		_facing = @"back";
		_flash = AVCaptureFlashModeOff;
		_active = YES;
		_previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:_session];
		_previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
		[self.layer addSublayer:_previewLayer];
		self.backgroundColor = UIColor.blackColor;
		self.clipsToBounds = YES;
	}
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	self.previewLayer.frame = self.bounds;
	[CATransaction commit];
	AVCaptureConnection *connection = self.previewLayer.connection;
	if (self.window && connection.isVideoOrientationSupported) connection.videoOrientation = captureOrientation(self.window);
}

- (void)setTag:(NSInteger)tag {
	[super setTag:tag];
	[self neonUpdate];
}

- (void)didMoveToWindow {
	[super didMoveToWindow];
	[self neonUpdate];
}

- (void)neonUpdate {
	BOOL want = !self.released && self.tag != 0 && self.window != nil && self.active;
	if (want == self.wanted) return;
	self.wanted = want;
	self.generation += 1;
	self.running = NO;
	if (want) [self neonStart];
	else {
		AVCaptureSession *session = self.session;
		dispatch_async(self.queue, ^{ [session stopRunning]; });
	}
}

- (NSString *)neonConfigure:(AVCaptureDevice *)device {
	NSError *error = nil;
	AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
	if (!input) return error.localizedDescription ?: @"cannot open the camera";
	NSString *problem = nil;
	[self.session beginConfiguration];
	if ([self.session canSetSessionPreset:AVCaptureSessionPresetPhoto]) self.session.sessionPreset = AVCaptureSessionPresetPhoto;
	AVCaptureDeviceInput *previous = self.input;
	if (previous) [self.session removeInput:previous];
	if ([self.session canAddInput:input]) {
		[self.session addInput:input];
		self.input = input;
	} else {
		problem = @"the camera cannot join the capture session";
		if (previous) [self.session addInput:previous];
	}
	if (!problem && ![self.session.outputs containsObject:self.photoOutput]) {
		if ([self.session canAddOutput:self.photoOutput]) [self.session addOutput:self.photoOutput];
		else problem = @"the photo output cannot join the capture session";
	}
	[self.session commitConfiguration];
	return problem;
}

- (void)neonStart {
	if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] != AVAuthorizationStatusAuthorized) {
		emitLater(self, CAMERA_MOUNT_ERROR, @"Camera permission not granted");
		return;
	}
	AVCaptureDevice *device = cameraFor(self.facing);
	if (!device) {
		emitLater(self, CAMERA_MOUNT_ERROR, @"No camera is available on this device");
		return;
	}
	NSUInteger generation = self.generation;
	dispatch_async(self.queue, ^{
		NSString *problem = [self neonConfigure:device];
		if (!problem) [self.session startRunning];
		dispatch_async(dispatch_get_main_queue(), ^{
			if (generation != self.generation || self.tag == 0) return;
			if (problem) {
				neonMediaEmit((int)self.tag, CAMERA_MOUNT_ERROR, problem, 0, 0);
				return;
			}
			self.running = YES;
			neonMediaEmit((int)self.tag, CAMERA_READY, @"", 0, 0);
		});
	});
}

- (void)neonFacing:(NSString *)facing {
	if ([facing isEqualToString:self.facing]) return;
	self.facing = facing;
	if (!self.wanted) return;
	self.generation += 1;
	self.running = NO;
	[self neonStart];
}

- (void)neonTakePicture:(NSString *)argument {
	NSArray<NSString *> *fields = [argument componentsSeparatedByString:FIELD];
	if (fields.count != 3) {
		NSLog(@"Neon CameraView takePicture: expected 3 fields, got %@", argument);
		abort();
	}
	if (!self.running) {
		emitLater(self, CAMERA_PICTURE, pictureError(fields[0], @"the camera is not running"));
		return;
	}
	NeonPhotoCapture *capture = [NeonPhotoCapture new];
	capture.pictureId = fields[0];
	capture.quality = fields[1].doubleValue;
	capture.base64 = [fields[2] isEqualToString:@"1"];
	capture.view = self;
	[self.captures addObject:capture];
	AVCaptureFlashMode flash = self.flash;
	BOOL mirrored = self.mirror && [self.facing isEqualToString:@"front"];
	AVCaptureVideoOrientation orientation = captureOrientation(self.window);
	AVCapturePhotoOutput *output = self.photoOutput;
	dispatch_async(self.queue, ^{
		AVCaptureConnection *connection = [output connectionWithMediaType:AVMediaTypeVideo];
		if (!connection) {
			[capture finish:pictureError(capture.pictureId, @"the camera is not running")];
			return;
		}
		if (connection.isVideoOrientationSupported) connection.videoOrientation = orientation;
		if (connection.isVideoMirroringSupported) {
			connection.automaticallyAdjustsVideoMirroring = NO;
			connection.videoMirrored = mirrored;
		}
		AVCapturePhotoSettings *settings = [output.availablePhotoCodecTypes containsObject:AVVideoCodecTypeJPEG]
			? [AVCapturePhotoSettings photoSettingsWithFormat:@{AVVideoCodecKey: AVVideoCodecTypeJPEG}]
			: [AVCapturePhotoSettings photoSettings];
		if ([output.supportedFlashModes containsObject:@(flash)]) settings.flashMode = flash;
		[output capturePhotoWithSettings:settings delegate:capture];
	});
}

- (void)neonCommand:(NSString *)value {
	NSRange cut = [value rangeOfString:FIELD];
	NSString *name = cut.location == NSNotFound ? value : [value substringToIndex:cut.location];
	NSString *argument = cut.location == NSNotFound ? @"" : [value substringFromIndex:cut.location + 1];
	if ([name isEqualToString:@"takePicture"]) [self neonTakePicture:argument];
	else if ([name isEqualToString:@"pausePreview"]) self.previewLayer.connection.enabled = NO;
	else if ([name isEqualToString:@"resumePreview"]) self.previewLayer.connection.enabled = YES;
	else {
		fprintf(stderr, "neon: CameraView has no command \"%s\"\n", name.UTF8String);
		abort();
	}
}

- (void)neonSetProp:(const char *)name value:(const char *)text {
	NSString *value = [NSString stringWithUTF8String:text ? text : ""];
	if (strcmp(name, "facing") == 0) [self neonFacing:[value isEqualToString:@"front"] ? @"front" : @"back"];
	else if (strcmp(name, "flash") == 0) {
		self.flash = [value isEqualToString:@"on"] ? AVCaptureFlashModeOn : [value isEqualToString:@"auto"] ? AVCaptureFlashModeAuto : AVCaptureFlashModeOff;
	}
	else if (strcmp(name, "active") == 0) {
		self.active = ![value isEqualToString:@"false"];
		[self neonUpdate];
	}
	else if (strcmp(name, "mirror") == 0) self.mirror = [value isEqualToString:@"true"];
	else if (strcmp(name, "command") == 0) [self neonCommand:value];
}

- (void)neonRelease {
	self.released = YES;
	self.tag = 0;
}

@end

void *neonCameraCreate(void) {
	return (void *)CFBridgingRetain([[NeonCameraView alloc] initWithFrame:CGRectZero]);
}

int neonCameraSetProp(UIView *view, const char *name, const char *text) {
	if (![view isKindOfClass:NeonCameraView.class]) return 0;
	[(NeonCameraView *)view neonSetProp:name value:text];
	return 1;
}

void neonCameraRelease(UIView *view) {
	if ([view isKindOfClass:NeonCameraView.class]) [(NeonCameraView *)view neonRelease];
}
