#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import "component.h"
#include "../native/components.h"
#include <string.h>
#include <stdlib.h>

static NSString *mediaText(const char *text) { return [NSString stringWithUTF8String:text ? text : ""]; }

// Native players take files, not data: URIs, and the app bundles no asset files, so a data: URI is
// decoded once into the temporary directory.
static NSURL *playableURL(NSString *uri) {
	if (![uri hasPrefix:@"data:"]) {
		if ([uri hasPrefix:@"/"]) return [NSURL fileURLWithPath:uri];
		return [NSURL URLWithString:uri];
	}
	NSRange comma = [uri rangeOfString:@","];
	if (comma.location == NSNotFound) return nil;
	NSString *header = [uri substringToIndex:comma.location];
	if (![header hasSuffix:@";base64"]) return nil;
	NSData *bytes = [[NSData alloc] initWithBase64EncodedString:[uri substringFromIndex:comma.location + 1] options:NSDataBase64DecodingIgnoreUnknownCharacters];
	if (!bytes) return nil;
	NSString *mime = [[header substringFromIndex:5] componentsSeparatedByString:@";"].firstObject;
	NSString *extension = [mime isEqualToString:@"video/quicktime"] ? @"mov" :
		[mime isEqualToString:@"audio/mpeg"] ? @"mp3" :
		[mime hasPrefix:@"audio/"] ? @"m4a" : @"mp4";
	NSString *name = [NSString stringWithFormat:@"neon-media-%lx-%lu.%@", (unsigned long)uri.hash, (unsigned long)bytes.length, extension];
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
	if (![[NSFileManager defaultManager] fileExistsAtPath:path] && ![bytes writeToFile:path atomically:YES]) return nil;
	return [NSURL fileURLWithPath:path];
}

// --- Video ---

@interface NeonVideoView : UIView <NeonComponentView>
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *item;
@property (nonatomic, strong) id timeObserver;
@property (nonatomic, strong) AVPlayerViewController *controlsController;
@property (nonatomic, copy) NSString *source;
@property (nonatomic) BOOL paused;
@property (nonatomic) BOOL repeats;
@property (nonatomic) float rate;
@property (nonatomic) double progressEvery;
@property (nonatomic, copy) NSString *gravity;
@end

static void *kNeonItemStatus = &kNeonItemStatus;

@implementation NeonVideoView

+ (Class)layerClass { return AVPlayerLayer.class; }

- (AVPlayerLayer *)playerLayer { return (AVPlayerLayer *)self.layer; }

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		_player = [[AVPlayer alloc] init];
		_player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
		_rate = 1;
		_progressEvery = 250;
		_gravity = AVLayerVideoGravityResizeAspect;
		self.playerLayer.player = _player;
		self.playerLayer.videoGravity = _gravity;
		self.backgroundColor = UIColor.blackColor;
		[self neonObserveTime];
	}
	return self;
}

- (void)dealloc {
	[self neonStop];
}

- (void)neonStop {
	if (self.timeObserver) {
		[self.player removeTimeObserver:self.timeObserver];
		self.timeObserver = nil;
	}
	[self neonForgetItem];
	[self.player pause];
}

- (void)neonForgetItem {
	if (!self.item) return;
	[self.item removeObserver:self forKeyPath:@"status" context:kNeonItemStatus];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
	self.item = nil;
}

- (double)neonPlayable {
	NSValue *last = self.item.loadedTimeRanges.lastObject;
	if (!last) return 0;
	CMTimeRange range = last.CMTimeRangeValue;
	return CMTimeGetSeconds(CMTimeRangeGetEnd(range));
}

- (double)neonDuration {
	double d = self.item ? CMTimeGetSeconds(self.item.duration) : 0;
	return isfinite(d) ? d : 0;
}

- (void)neonReportProgress {
	if (!self.item || self.item.status != AVPlayerItemStatusReadyToPlay) return;
	NSString *value = [NSString stringWithFormat:@"%g\x1f%g\x1f%g", CMTimeGetSeconds(self.player.currentTime), [self neonPlayable], [self neonDuration]];
	neonEmitControl((int)self.tag, 13, value, 0, 0);
}

- (void)neonObserveTime {
	if (self.timeObserver) [self.player removeTimeObserver:self.timeObserver];
	__weak NeonVideoView *weakSelf = self;
	CMTime every = CMTimeMakeWithSeconds(MAX(self.progressEvery, 16) / 1000.0, 600);
	self.timeObserver = [self.player addPeriodicTimeObserverForInterval:every queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
		(void)time;
		NeonVideoView *me = weakSelf;
		if (me && me.player.rate > 0) [me neonReportProgress];
	}];
}

- (void)neonApplyPlayback {
	if (self.paused || !self.item) [self.player pause];
	else [self.player playImmediatelyAtRate:self.rate];
}

- (void)neonLoad:(NSString *)uri {
	[self neonForgetItem];
	self.source = uri;
	NSInteger tag = self.tag;
	__weak NeonVideoView *weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		NeonVideoView *me = weakSelf;
		if (me) neonEmitControl((int)(me.tag ? me.tag : tag), 10, uri, 0, 0);
	});
	NSURL *url = playableURL(uri);
	if (!url) {
		dispatch_async(dispatch_get_main_queue(), ^{
			NeonVideoView *me = weakSelf;
			if (me) neonEmitControl((int)me.tag, 6, [NSString stringWithFormat:@"0\x1f%@", @"the video source is not a playable url"], 0, 0);
		});
		[self.player replaceCurrentItemWithPlayerItem:nil];
		return;
	}
	self.item = [AVPlayerItem playerItemWithURL:url];
	[self.item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:kNeonItemStatus];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(neonEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
	[self.player replaceCurrentItemWithPlayerItem:self.item];
	[self neonApplyPlayback];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (context != kNeonItemStatus) {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
		return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		AVPlayerItem *item = self.item;
		if (object != item) return;
		if (item.status == AVPlayerItemStatusReadyToPlay) {
			CGSize size = item.presentationSize;
			NSString *value = [NSString stringWithFormat:@"%g\x1f%g\x1f%g\x1f%g", [self neonDuration], CMTimeGetSeconds(self.player.currentTime), size.width, size.height];
			neonEmitControl((int)self.tag, 5, value, 0, 0);
			[self neonApplyPlayback];
		} else if (item.status == AVPlayerItemStatusFailed) {
			NSError *error = item.error;
			neonEmitControl((int)self.tag, 6, [NSString stringWithFormat:@"%ld\x1f%@", (long)error.code, error.localizedDescription ?: @"the video failed"], 0, 0);
		}
	});
}

- (void)neonEnded:(NSNotification *)note {
	(void)note;
	if (self.repeats) {
		[self.player seekToTime:kCMTimeZero];
		[self neonApplyPlayback];
		return;
	}
	[self neonReportProgress];
	neonEmitControl((int)self.tag, 14, @"", 0, 0);
}

- (void)neonControls:(BOOL)shown {
	if (shown && !self.controlsController) {
		AVPlayerViewController *controller = [[AVPlayerViewController alloc] init];
		controller.player = self.player;
		controller.videoGravity = self.gravity;
		controller.view.frame = self.bounds;
		controller.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		[self addSubview:controller.view];
		self.controlsController = controller;
	} else if (!shown && self.controlsController) {
		[self.controlsController.view removeFromSuperview];
		self.controlsController.player = nil;
		self.controlsController = nil;
	}
}

- (void)neonSeek:(double)seconds {
	__weak NeonVideoView *weakSelf = self;
	[self.player seekToTime:CMTimeMakeWithSeconds(seconds, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
		if (!finished) return;
		dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf neonReportProgress]; });
	}];
}

- (void)neonSetProp:(const char *)name value:(const char *)text {
	if (strcmp(name, "source") == 0) [self neonLoad:mediaText(text)];
	else if (strcmp(name, "paused") == 0) { self.paused = strcmp(text, "true") == 0; [self neonApplyPlayback]; }
	else if (strcmp(name, "muted") == 0) self.player.muted = strcmp(text, "true") == 0;
	else if (strcmp(name, "volume") == 0) self.player.volume = (float)MAX(0, MIN(1, atof(text)));
	else if (strcmp(name, "rate") == 0) {
		self.rate = (float)atof(text);
		if (self.player.rate > 0) self.player.rate = self.rate;
	}
	else if (strcmp(name, "repeat") == 0) self.repeats = strcmp(text, "true") == 0;
	else if (strcmp(name, "controls") == 0) [self neonControls:strcmp(text, "true") == 0];
	else if (strcmp(name, "progressUpdateInterval") == 0) { self.progressEvery = atof(text); [self neonObserveTime]; }
	else if (strcmp(name, "resizeMode") == 0) {
		self.gravity = strcmp(text, "cover") == 0 ? AVLayerVideoGravityResizeAspectFill :
			strcmp(text, "stretch") == 0 ? AVLayerVideoGravityResize : AVLayerVideoGravityResizeAspect;
		self.playerLayer.videoGravity = self.gravity;
		self.controlsController.videoGravity = self.gravity;
	}
	else if (strcmp(name, "command") == 0) {
		NSString *value = mediaText(text);
		NSRange cut = [value rangeOfString:@"\x1f"];
		NSString *command = cut.location == NSNotFound ? value : [value substringToIndex:cut.location];
		if ([command isEqualToString:@"seek"]) [self neonSeek:[value substringFromIndex:cut.location + 1].doubleValue];
		else if ([command isEqualToString:@"pause"]) [self.player pause];
		else if ([command isEqualToString:@"resume"]) [self.player playImmediatelyAtRate:self.rate];
		else {
			fprintf(stderr, "neon: Video has no command \"%s\"\n", command.UTF8String);
			abort();
		}
	}
}

- (void)neonRelease { [self neonStop]; }
@end

void *niVideoCreate(void) { return CFBridgingRetain([[NeonVideoView alloc] initWithFrame:CGRectZero]); }
