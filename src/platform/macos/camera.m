#import <AVFoundation/AVFoundation.h>
#include "../native/components.h"
#import "media.h"

// --- CameraView: an AVCaptureSession behind an AVCaptureVideoPreviewLayer, photos through AVCapturePhotoOutput ---

@class NeonCamera;

@interface NeonPhotoCapture : NSObject <AVCapturePhotoCaptureDelegate>
@property(nonatomic, copy) NSString *pictureId;
@property(nonatomic) double quality;
@property(nonatomic) BOOL base64, answered;
@property(nonatomic, weak) NeonCamera *view;
@end

@interface NeonCamera : NeonView <NeonComponentView>
@property(nonatomic, strong) AVCaptureSession *session;
@property(nonatomic, strong) AVCapturePhotoOutput *photoOutput;
@property(nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property(nonatomic, strong) NSView *preview;
@property(nonatomic, strong) AVCaptureDeviceInput *input;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, strong) NSMutableSet<NeonPhotoCapture *> *captures;
@property(nonatomic, copy) NSString *facing;
@property(nonatomic) AVCaptureFlashMode flash;
@property(nonatomic) BOOL active, mirror, released, wanted, running;
@property(nonatomic) NSUInteger generation;
@end

static NSString *pictureError(NSString *pictureId, NSString *message) {
	return [@[pictureId, @"error", message] componentsJoinedByString:FIELD];
}

static void emitLater(NeonCamera *view, int phase, NSString *value) {
	dispatch_async(dispatch_get_main_queue(), ^{ emit(view.neonTag, phase, value); });
}

// A Mac's built-in camera faces the user; a facing no camera has falls back to the default camera.
static AVCaptureDevice *cameraFor(NSString *facing) {
	AVCaptureDevicePosition position = [facing isEqualToString:@"front"] ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
	AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:position];
	return device ?: [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
}

@implementation NeonPhotoCapture

- (void)finish:(NSString *)value {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self.answered) return;
		self.answered = YES;
		NeonCamera *view = self.view;
		[view.captures removeObject:self];
		emit(view.neonTag, CAMERA_PICTURE, value);
	});
}

- (NSString *)store:(NSData *)data {
	NSBitmapImageRep *image = data ? [NSBitmapImageRep imageRepWithData:data] : nil;
	if (!image) return pictureError(self.pictureId, @"the camera returned no image");
	NSData *bytes = self.quality < 1
		? [image representationUsingType:NSBitmapImageFileTypeJPEG properties:@{NSImageCompressionFactor: @(MAX(self.quality, 0))}]
		: data;
	NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
	NSString *folder = [caches stringByAppendingPathComponent:@"Camera"];
	[NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
	NSString *path = [folder stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".jpg"]];
	NSError *error = nil;
	if (!bytes || ![bytes writeToFile:path options:NSDataWritingAtomic error:&error]) {
		return pictureError(self.pictureId, error.localizedDescription ?: @"cannot store the picture");
	}
	return [@[self.pictureId, @"ok", [NSURL fileURLWithPath:path].absoluteString,
		[NSString stringWithFormat:@"%ld", (long)image.pixelsWide], [NSString stringWithFormat:@"%ld", (long)image.pixelsHigh],
		self.base64 ? [bytes base64EncodedStringWithOptions:0] : @""] componentsJoinedByString:FIELD];
}

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
	(void)output;
	if (error) [self finish:pictureError(self.pictureId, error.localizedDescription ?: @"the capture failed")];
	else [self finish:[self store:photo.fileDataRepresentation]];
}

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishCaptureForResolvedSettings:(AVCaptureResolvedPhotoSettings *)settings error:(NSError *)error {
	(void)output; (void)settings;
	[self finish:pictureError(self.pictureId, error.localizedDescription ?: @"the capture produced no photo")];
}

@end

@implementation NeonCamera

- (instancetype)initWithFrame:(NSRect)frame {
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
		_preview = [[NSView alloc] initWithFrame:NSZeroRect];
		_preview.layer = _previewLayer;
		_preview.wantsLayer = YES;
		[self addSubview:_preview];
	}
	return self;
}

- (void)setFrameSize:(NSSize)size {
	[super setFrameSize:size];
	self.preview.frame = NSMakeRect(0, 0, size.width, size.height);
}

- (void)setNeonTag:(int32_t)tag {
	[super setNeonTag:tag];
	[self update];
}

- (void)viewDidMoveToWindow {
	[super viewDidMoveToWindow];
	[self update];
}

- (void)update {
	BOOL want = !self.released && self.neonTag != 0 && self.window != nil && self.active;
	if (want == self.wanted) return;
	self.wanted = want;
	self.generation += 1;
	self.running = NO;
	if (want) {
		[self start];
		return;
	}
	AVCaptureSession *session = self.session;
	dispatch_async(self.queue, ^{ [session stopRunning]; });
}

- (NSString *)configure:(AVCaptureDevice *)device {
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

// Reading the authorization never prompts; asking is the app's, through Camera.requestCameraPermissionsAsync.
- (void)start {
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
		NSString *problem = [self configure:device];
		if (!problem) [self.session startRunning];
		dispatch_async(dispatch_get_main_queue(), ^{
			if (generation != self.generation || self.neonTag == 0) return;
			if (problem) {
				emit(self.neonTag, CAMERA_MOUNT_ERROR, problem);
				return;
			}
			self.running = YES;
			emit(self.neonTag, CAMERA_READY, @"");
		});
	});
}

- (void)face:(NSString *)facing {
	if ([facing isEqualToString:self.facing]) return;
	self.facing = facing;
	if (!self.wanted) return;
	self.generation += 1;
	self.running = NO;
	[self start];
}

- (void)takePicture:(NSString *)argument {
	NSArray<NSString *> *fields = [argument componentsSeparatedByString:FIELD];
	if (fields.count != 3) {
		fprintf(stderr, "neon macos bridge: CameraView takePicture wants 3 fields, got \"%s\"\n", argument.UTF8String);
		fflush(stderr);
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
	AVCapturePhotoOutput *output = self.photoOutput;
	dispatch_async(self.queue, ^{
		AVCaptureConnection *connection = [output connectionWithMediaType:AVMediaTypeVideo];
		if (!connection) {
			[capture finish:pictureError(capture.pictureId, @"the camera is not running")];
			return;
		}
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

- (void)command:(NSString *)value {
	NSString *name, *argument;
	splitCommand(value, &name, &argument);
	if ([name isEqualToString:@"takePicture"]) [self takePicture:argument];
	else if ([name isEqualToString:@"pausePreview"]) self.previewLayer.connection.enabled = NO;
	else if ([name isEqualToString:@"resumePreview"]) self.previewLayer.connection.enabled = YES;
	else noCommand("CameraView", name);
}

- (void)setProp:(const char *)name value:(const char *)value {
	NSString *text = @(value);
	if (!strcmp(name, "facing")) [self face:[text isEqualToString:@"front"] ? @"front" : @"back"];
	else if (!strcmp(name, "flash")) {
		self.flash = [text isEqualToString:@"on"] ? AVCaptureFlashModeOn : [text isEqualToString:@"auto"] ? AVCaptureFlashModeAuto : AVCaptureFlashModeOff;
	} else if (!strcmp(name, "active")) {
		self.active = ![text isEqualToString:@"false"];
		[self update];
	} else if (!strcmp(name, "mirror")) self.mirror = [text isEqualToString:@"true"];
	else if (!strcmp(name, "command")) [self command:text];
	else noProp("CameraView", name);
}

- (void)neonRelease {
	self.released = YES;
	self.neonTag = 0;
}
@end

void *niCameraCreate(void) {
	neonRequireRoot("niCameraCreate");
	return (void *)CFBridgingRetain([[NeonCamera alloc] initWithFrame:NSZeroRect]);
}
