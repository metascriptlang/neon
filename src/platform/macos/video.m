#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#include "../native/components.h"
#import "media.h"

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

// --- Video: an AVPlayer drawn by an AVPlayerLayer, with an AVPlayerView over it while `controls` is set ---

@interface NeonVideo : NeonView <NeonComponentView>
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerItem *item;
@property(nonatomic, strong) NSView *surface;
@property(nonatomic, strong) AVPlayerLayer *playerLayer;
@property(nonatomic, strong) AVPlayerView *playerView;
@property(nonatomic, strong) id timeObserver;
@property(nonatomic) BOOL paused, repeats;
@property(nonatomic) float rate;
@property(nonatomic) double progressEvery;
@end

static void *kItemStatus = &kItemStatus;

@implementation NeonVideo

- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		_player = [[AVPlayer alloc] init];
		_player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
		_rate = 1;
		_progressEvery = 250;
		_playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
		_playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
		_surface = [[NSView alloc] initWithFrame:NSZeroRect];
		_surface.layer = _playerLayer;
		_surface.wantsLayer = YES;
		[self addSubview:_surface];
		[self observeTime];
	}
	return self;
}

- (void)setFrameSize:(NSSize)size {
	[super setFrameSize:size];
	self.surface.frame = NSMakeRect(0, 0, size.width, size.height);
	self.playerView.frame = self.surface.frame;
}

- (void)showControls:(BOOL)shown {
	if (shown && !self.playerView) {
		self.playerView = [[AVPlayerView alloc] initWithFrame:self.surface.frame];
		self.playerView.controlsStyle = AVPlayerViewControlsStyleInline;
		self.playerView.videoGravity = self.playerLayer.videoGravity;
		self.playerView.player = self.player;
		[self addSubview:self.playerView];
	} else if (!shown && self.playerView) {
		[self.playerView removeFromSuperview];
		self.playerView.player = nil;
		self.playerView = nil;
	}
}

- (void)dealloc { [self stop]; }

- (void)stop {
	if (self.timeObserver) {
		[self.player removeTimeObserver:self.timeObserver];
		self.timeObserver = nil;
	}
	[self forgetItem];
	[self.player pause];
}

- (void)forgetItem {
	if (!self.item) return;
	[self.item removeObserver:self forKeyPath:@"status" context:kItemStatus];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
	self.item = nil;
}

- (double)playable {
	NSValue *last = self.item.loadedTimeRanges.lastObject;
	return last ? CMTimeGetSeconds(CMTimeRangeGetEnd(last.CMTimeRangeValue)) : 0;
}

- (double)duration {
	double d = self.item ? CMTimeGetSeconds(self.item.duration) : 0;
	return isfinite(d) ? d : 0;
}

- (void)reportProgress {
	if (!self.item || self.item.status != AVPlayerItemStatusReadyToPlay) return;
	emit(self.neonTag, MEDIA_PROGRESS, [NSString stringWithFormat:@"%g\x1f%g\x1f%g", CMTimeGetSeconds(self.player.currentTime), [self playable], [self duration]]);
}

- (void)observeTime {
	if (self.timeObserver) [self.player removeTimeObserver:self.timeObserver];
	__weak NeonVideo *weakSelf = self;
	CMTime every = CMTimeMakeWithSeconds(MAX(self.progressEvery, 16) / 1000.0, 600);
	self.timeObserver = [self.player addPeriodicTimeObserverForInterval:every queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
		(void)time;
		NeonVideo *me = weakSelf;
		if (me && me.player.rate > 0) [me reportProgress];
	}];
}

- (void)applyPlayback {
	if (self.paused || !self.item) [self.player pause];
	else [self.player playImmediatelyAtRate:self.rate];
}

- (void)load:(NSString *)uri {
	[self forgetItem];
	__weak NeonVideo *weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{ emit(weakSelf.neonTag, MEDIA_LOAD_START, uri); });
	NSURL *url = playableURL(uri);
	if (!url) {
		dispatch_async(dispatch_get_main_queue(), ^{ emit(weakSelf.neonTag, MEDIA_ERROR, @"0\x1fthe video source is not a playable url"); });
		[self.player replaceCurrentItemWithPlayerItem:nil];
		return;
	}
	self.item = [AVPlayerItem playerItemWithURL:url];
	[self.item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:kItemStatus];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ended:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
	[self.player replaceCurrentItemWithPlayerItem:self.item];
	[self applyPlayback];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (context != kItemStatus) {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
		return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		AVPlayerItem *item = self.item;
		if (object != item) return;
		if (item.status == AVPlayerItemStatusReadyToPlay) {
			CGSize size = item.presentationSize;
			emit(self.neonTag, MEDIA_LOAD, [NSString stringWithFormat:@"%g\x1f%g\x1f%g\x1f%g", [self duration], CMTimeGetSeconds(self.player.currentTime), size.width, size.height]);
			[self applyPlayback];
		} else if (item.status == AVPlayerItemStatusFailed) {
			NSError *error = item.error;
			emit(self.neonTag, MEDIA_ERROR, [NSString stringWithFormat:@"%ld\x1f%@", (long)error.code, error.localizedDescription ?: @"the video failed"]);
		}
	});
}

- (void)ended:(NSNotification *)note {
	(void)note;
	if (self.repeats) {
		[self.player seekToTime:kCMTimeZero];
		[self applyPlayback];
		return;
	}
	[self reportProgress];
	emit(self.neonTag, MEDIA_END, @"");
}

- (void)seek:(double)seconds {
	__weak NeonVideo *weakSelf = self;
	[self.player seekToTime:CMTimeMakeWithSeconds(seconds, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
		if (finished) dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf reportProgress]; });
	}];
}

- (void)command:(NSString *)value {
	NSString *name, *argument;
	splitCommand(value, &name, &argument);
	if ([name isEqualToString:@"seek"]) [self seek:argument.doubleValue];
	else if ([name isEqualToString:@"pause"]) [self.player pause];
	else if ([name isEqualToString:@"resume"]) [self.player playImmediatelyAtRate:self.rate];
	else noCommand("Video", name);
}

- (void)setProp:(const char *)name value:(const char *)value {
	if (!strcmp(name, "source")) [self load:@(value)];
	else if (!strcmp(name, "paused")) {
		self.paused = !strcmp(value, "true");
		[self applyPlayback];
	} else if (!strcmp(name, "muted")) self.player.muted = !strcmp(value, "true");
	else if (!strcmp(name, "volume")) self.player.volume = (float)MAX(0, MIN(1, atof(value)));
	else if (!strcmp(name, "rate")) {
		self.rate = (float)atof(value);
		if (self.player.rate > 0) self.player.rate = self.rate;
	} else if (!strcmp(name, "repeat")) self.repeats = !strcmp(value, "true");
	else if (!strcmp(name, "controls")) [self showControls:!strcmp(value, "true")];
	else if (!strcmp(name, "progressUpdateInterval")) {
		self.progressEvery = atof(value);
		[self observeTime];
	} else if (!strcmp(name, "resizeMode")) {
		self.playerLayer.videoGravity = !strcmp(value, "cover") ? AVLayerVideoGravityResizeAspectFill :
			!strcmp(value, "stretch") ? AVLayerVideoGravityResize : AVLayerVideoGravityResizeAspect;
		self.playerView.videoGravity = self.playerLayer.videoGravity;
	} else if (!strcmp(name, "command")) [self command:@(value)];
	else noProp("Video", name);
}

- (void)neonRelease {
	[self stop];
	self.neonTag = 0;
}
- (NSView *)neonNativeTarget { return self.playerView; }
@end

void *niVideoCreate(void) {
	neonRequireRoot("niVideoCreate");
	return (void *)CFBridgingRetain([[NeonVideo alloc] initWithFrame:NSZeroRect]);
}
