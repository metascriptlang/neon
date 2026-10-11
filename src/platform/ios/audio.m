#import "modules.h"
#import <AVFoundation/AVFoundation.h>

enum { REPLY_EVENT = 9, SOUND_EVENT = 13, RECORDING_EVENT = 14 };

static void answer(NSString *requestId, NSString *value) {
	dispatch_async(dispatch_get_main_queue(), ^{
		niAppEmit(REPLY_EVENT, [@[requestId, value] componentsJoinedByString:NIField]);
	});
}

static NSString *flag(BOOL value) { return value ? @"1" : @"0"; }

static NSString *millis(double seconds) {
	return isfinite(seconds) ? [NSString stringWithFormat:@"%.0f", MAX(seconds, 0) * 1000] : @"0";
}

static NSArray<NSString *> *fieldsOf(NSString *name, NSString *arg, NSUInteger count) {
	NSArray<NSString *> *fields = [arg componentsSeparatedByString:NIField];
	if (fields.count != count) {
		NSLog(@"Neon %@: expected %lu fields, got %lu: %@", name, (unsigned long)count, (unsigned long)fields.count, arg);
		abort();
	}
	return fields;
}

static NSString *shortURI(NSString *uri) {
	return uri.length > 80 ? [[uri substringToIndex:80] stringByAppendingString:@"…"] : uri;
}

static NSString *audioExtension(NSString *mime) {
	if ([mime isEqualToString:@"audio/wav"] || [mime isEqualToString:@"audio/x-wav"] || [mime isEqualToString:@"audio/wave"]) return @"wav";
	if ([mime isEqualToString:@"audio/mpeg"] || [mime isEqualToString:@"audio/mp3"]) return @"mp3";
	if ([mime isEqualToString:@"audio/mp4"] || [mime isEqualToString:@"audio/x-m4a"] || [mime isEqualToString:@"audio/m4a"] || [mime isEqualToString:@"audio/aac"]) return @"m4a";
	if ([mime isEqualToString:@"audio/x-caf"]) return @"caf";
	if ([mime isEqualToString:@"audio/aiff"] || [mime isEqualToString:@"audio/x-aiff"]) return @"aiff";
	return nil;
}

static NSURL *soundURL(NSString *uri, NSString **problem) {
	if (![uri hasPrefix:@"data:"]) {
		NSURL *url = [uri hasPrefix:@"/"] ? [NSURL fileURLWithPath:uri] : [NSURL URLWithString:uri];
		if (!url) *problem = @"the uri is not a url";
		else if (url.isFileURL && ![NSFileManager.defaultManager fileExistsAtPath:url.path]) *problem = @"no such file";
		else return url;
		return nil;
	}
	NSRange comma = [uri rangeOfString:@","];
	NSString *header = comma.location == NSNotFound ? @"" : [uri substringToIndex:comma.location];
	if (![header hasSuffix:@";base64"]) {
		*problem = @"only base64 data: uris are supported";
		return nil;
	}
	NSString *mime = [[header substringFromIndex:5] componentsSeparatedByString:@";"].firstObject;
	NSString *extension = audioExtension(mime);
	if (!extension) {
		*problem = [NSString stringWithFormat:@"unsupported audio type %@", mime];
		return nil;
	}
	NSData *bytes = [[NSData alloc] initWithBase64EncodedString:[uri substringFromIndex:comma.location + 1] options:NSDataBase64DecodingIgnoreUnknownCharacters];
	if (!bytes) {
		*problem = @"the data: uri is not valid base64";
		return nil;
	}
	NSString *name = [NSString stringWithFormat:@"neon-sound-%lx-%lu.%@", (unsigned long)uri.hash, (unsigned long)bytes.length, extension];
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
	if (![NSFileManager.defaultManager fileExistsAtPath:path] && ![bytes writeToFile:path atomically:YES]) {
		*problem = @"cannot write the decoded audio";
		return nil;
	}
	return [NSURL fileURLWithPath:path];
}

// --- Sound ---

@interface NeonSound : NSObject
@property(nonatomic, copy) NSString *soundId;
@property(nonatomic, copy) NSString *uri;
@property(nonatomic, copy) NSString *loadRequest;
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerItem *item;
@property(nonatomic, strong) id timeObserver;
@property(nonatomic, strong) id endObserver;
@property(nonatomic) BOOL observingStatus;
@property(nonatomic) BOOL loaded;
@property(nonatomic) BOOL playing;
@property(nonatomic) BOOL looping;
@property(nonatomic) BOOL shouldPlay;
@property(nonatomic) float volume;
@property(nonatomic) BOOL muted;
@property(nonatomic) float rate;
@property(nonatomic) double startMillis;
@property(nonatomic) double intervalMillis;
@end

static NSMutableDictionary<NSString *, NeonSound *> *g_sounds;
static void *kNeonSoundStatus = &kNeonSoundStatus;

@implementation NeonSound

- (double)durationSeconds {
	double seconds = self.item ? CMTimeGetSeconds(self.item.duration) : 0;
	return isfinite(seconds) ? seconds : 0;
}

- (NSString *)statusAt:(double)seconds finished:(BOOL)finished {
	BOOL buffering = self.loaded && self.player.timeControlStatus == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate;
	return [@[flag(self.loaded), flag(self.loaded && self.playing), flag(buffering),
		millis(self.loaded ? seconds : 0), millis(self.loaded ? [self durationSeconds] : 0), flag(finished), flag(self.looping),
		[NSString stringWithFormat:@"%g", self.volume], flag(self.muted), [NSString stringWithFormat:@"%g", self.rate], @""]
		componentsJoinedByString:NIField];
}

- (NSString *)status {
	return [self statusAt:CMTimeGetSeconds(self.player.currentTime) finished:NO];
}

- (void)emit:(NSString *)status {
	niAppEmit(SOUND_EVENT, [@[self.soundId, status] componentsJoinedByString:NIField]);
}

- (void)observeTime {
	if (self.timeObserver) [self.player removeTimeObserver:self.timeObserver];
	__weak NeonSound *weakSelf = self;
	CMTime every = CMTimeMakeWithSeconds(MAX(self.intervalMillis, 16) / 1000.0, 600);
	self.timeObserver = [self.player addPeriodicTimeObserverForInterval:every queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
		NeonSound *me = weakSelf;
		if (me.loaded && me.playing) [me emit:[me status]];
	}];
}

- (void)applyPlayback {
	if (self.playing) [self.player playImmediatelyAtRate:self.rate];
	else [self.player pause];
}

- (void)ended {
	if (self.looping) {
		[self.player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
		[self applyPlayback];
		[self emit:[self statusAt:0 finished:YES]];
		return;
	}
	self.playing = NO;
	[self.player pause];
	[self emit:[self statusAt:[self durationSeconds] finished:YES]];
}

- (void)load:(NSURL *)url {
	self.item = [AVPlayerItem playerItemWithURL:url];
	self.player = [AVPlayer playerWithPlayerItem:self.item];
	self.player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
	self.observingStatus = YES;
	[self.item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:kNeonSoundStatus];
	__weak NeonSound *weakSelf = self;
	self.endObserver = [NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:self.item
		queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [weakSelf ended]; }];
	[self observeTime];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (context != kNeonSoundStatus) {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
		return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{ [self itemStatusChanged:object]; });
}

- (void)itemStatusChanged:(AVPlayerItem *)item {
	if (item != self.item || !self.loadRequest) return;
	if (item.status == AVPlayerItemStatusFailed) {
		NSString *reason = item.error.localizedDescription ?: @"the player failed";
		[self answerLoad:[NSString stringWithFormat:@"!Sound.loadAsync: cannot load %@: %@", shortURI(self.uri), reason]];
		[self releasePlayer];
		[g_sounds removeObjectForKey:self.soundId];
		return;
	}
	if (item.status != AVPlayerItemStatusReadyToPlay) return;
	[self stopObservingStatus];
	self.player.volume = self.volume;
	self.player.muted = self.muted;
	__weak NeonSound *weakSelf = self;
	void (^ready)(BOOL) = ^(BOOL finished) {
		dispatch_async(dispatch_get_main_queue(), ^{
			NeonSound *me = weakSelf;
			if (!me || !me.loadRequest) return;
			me.loaded = YES;
			me.playing = me.shouldPlay;
			[me applyPlayback];
			[me answerLoad:[me statusAt:me.startMillis / 1000.0 finished:NO]];
		});
	};
	if (self.startMillis > 0) {
		[self.player seekToTime:CMTimeMakeWithSeconds(self.startMillis / 1000.0, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:ready];
	} else ready(YES);
}

- (void)answerLoad:(NSString *)reply {
	NSString *requestId = self.loadRequest;
	self.loadRequest = nil;
	if (requestId) answer(requestId, reply);
}

- (void)stopObservingStatus {
	if (!self.observingStatus) return;
	self.observingStatus = NO;
	[self.item removeObserver:self forKeyPath:@"status" context:kNeonSoundStatus];
}

- (void)releasePlayer {
	[self stopObservingStatus];
	if (self.timeObserver) [self.player removeTimeObserver:self.timeObserver];
	if (self.endObserver) [NSNotificationCenter.defaultCenter removeObserver:self.endObserver];
	self.timeObserver = nil;
	self.endObserver = nil;
	[self.player pause];
	[self.player replaceCurrentItemWithPlayerItem:nil];
	self.player = nil;
	self.item = nil;
	self.loaded = NO;
	self.playing = NO;
}

@end

static NSString *soundLoad(NSString *arg) {
	NSArray<NSString *> *fields = fieldsOf(@"sound.load", arg, 10);
	if (!g_sounds) g_sounds = [NSMutableDictionary dictionary];
	NeonSound *previous = g_sounds[fields[1]];
	if (previous) {
		[previous answerLoad:@"!Sound.loadAsync: the sound was loaded again before it finished loading"];
		[previous releasePlayer];
		[g_sounds removeObjectForKey:fields[1]];
	}
	NSString *problem = nil;
	NSURL *url = soundURL(fields[2], &problem);
	if (!url) return [NSString stringWithFormat:@"!Sound.loadAsync: cannot load %@: %@", shortURI(fields[2]), problem];
	NeonSound *sound = [NeonSound new];
	sound.soundId = fields[1];
	sound.uri = fields[2];
	sound.loadRequest = fields[0];
	sound.shouldPlay = [fields[3] isEqualToString:@"1"];
	sound.volume = (float)MAX(0, MIN(1, fields[4].doubleValue));
	sound.looping = [fields[5] isEqualToString:@"1"];
	sound.muted = [fields[6] isEqualToString:@"1"];
	sound.startMillis = MAX(0, fields[7].doubleValue);
	sound.rate = (float)fields[8].doubleValue;
	sound.intervalMillis = fields[9].doubleValue;
	g_sounds[sound.soundId] = sound;
	[sound load:url];
	return @"";
}

static NSString *soundCommand(NSString *name, NSString *arg) {
	NSArray<NSString *> *fields = fieldsOf(name, arg, 2);
	NSString *command = [name substringFromIndex:@"sound.".length];
	NSArray<NSString *> *known = @[@"play", @"pause", @"stop", @"seek", @"volume", @"loop", @"mute", @"rate", @"interval", @"status", @"unload"];
	if (![known containsObject:command]) {
		NSLog(@"Neon niAppCall: unknown command %@", name);
		abort();
	}
	NeonSound *sound = g_sounds[fields[0]];
	if (!sound || !sound.loaded) return [NSString stringWithFormat:@"!Sound: no loaded sound %@", fields[0]];
	double value = fields[1].doubleValue;
	if ([command isEqualToString:@"play"]) {
		sound.playing = YES;
		[sound applyPlayback];
	} else if ([command isEqualToString:@"pause"]) {
		sound.playing = NO;
		[sound applyPlayback];
	} else if ([command isEqualToString:@"stop"]) {
		sound.playing = NO;
		[sound applyPlayback];
		[sound.player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
		return [sound statusAt:0 finished:NO];
	} else if ([command isEqualToString:@"seek"]) {
		double seconds = MAX(0, value) / 1000.0;
		[sound.player seekToTime:CMTimeMakeWithSeconds(seconds, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
		return [sound statusAt:seconds finished:NO];
	} else if ([command isEqualToString:@"volume"]) {
		sound.volume = (float)MAX(0, MIN(1, value));
		sound.player.volume = sound.volume;
	} else if ([command isEqualToString:@"loop"]) {
		sound.looping = value != 0;
	} else if ([command isEqualToString:@"mute"]) {
		sound.muted = value != 0;
		sound.player.muted = sound.muted;
	} else if ([command isEqualToString:@"rate"]) {
		sound.rate = (float)value;
		if (sound.playing) [sound applyPlayback];
	} else if ([command isEqualToString:@"interval"]) {
		sound.intervalMillis = value;
		[sound observeTime];
	} else if ([command isEqualToString:@"unload"]) {
		[sound releasePlayer];
		[g_sounds removeObjectForKey:fields[0]];
		return [sound statusAt:0 finished:NO];
	}
	return [sound status];
}

// --- Audio session ---

static BOOL g_allowsRecording;

static NSString *audioMode(NSString *arg) {
	NSArray<NSString *> *fields = fieldsOf(@"audio.mode", arg, 2);
	BOOL recording = [fields[0] isEqualToString:@"1"];
	BOOL silent = [fields[1] isEqualToString:@"1"];
	AVAudioSession *session = AVAudioSession.sharedInstance;
	NSError *error = nil;
	BOOL done = recording
		? [session setCategory:AVAudioSessionCategoryPlayAndRecord mode:AVAudioSessionModeDefault
			options:AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionAllowBluetoothHFP error:&error]
		: [session setCategory:silent ? AVAudioSessionCategoryPlayback : AVAudioSessionCategorySoloAmbient mode:AVAudioSessionModeDefault options:0 error:&error];
	if (done) done = [session setActive:YES error:&error];
	if (!done) return [NSString stringWithFormat:@"!Audio.setAudioModeAsync: %@", error.localizedDescription ?: @"the audio session refused the mode"];
	g_allowsRecording = recording;
	return @"";
}

// --- Recording ---

@interface NeonRecording : NSObject
@property(nonatomic, copy) NSString *recordingId;
@property(nonatomic, strong) AVAudioRecorder *recorder;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) double intervalMillis;
@property(nonatomic) double lastSeconds;
@property(nonatomic) BOOL done;
@end

static NSMutableDictionary<NSString *, NeonRecording *> *g_recordings;

@implementation NeonRecording

- (double)seconds {
	if (!self.done && self.recorder.isRecording) self.lastSeconds = self.recorder.currentTime;
	return self.lastSeconds;
}

- (NSString *)status {
	return [@[flag(!self.done), flag(!self.done && self.recorder.isRecording), flag(self.done), millis([self seconds]),
		self.recorder.url.absoluteString ?: @"", @""] componentsJoinedByString:NIField];
}

- (void)schedule {
	[self.timer invalidate];
	self.timer = nil;
	if (!self.recorder.isRecording) return;
	__weak NeonRecording *weakSelf = self;
	self.timer = [NSTimer timerWithTimeInterval:MAX(self.intervalMillis, 16) / 1000.0 repeats:YES block:^(NSTimer *timer) {
		NeonRecording *me = weakSelf;
		if (me.recorder.isRecording) niAppEmit(RECORDING_EVENT, [@[me.recordingId, [me status]] componentsJoinedByString:NIField]);
	}];
	[NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}

@end

static NSString *recordingPrepare(NSString *arg) {
	NSArray<NSString *> *fields = fieldsOf(@"recording.prepare", arg, 7);
	if (!g_allowsRecording) return @"!Recording not allowed on iOS. Enable with Audio.setAudioModeAsync({ allowsRecordingIOS: true })";
	if (![NSBundle.mainBundle objectForInfoDictionaryKey:@"NSMicrophoneUsageDescription"]) {
		return @"!Recording: add NSMicrophoneUsageDescription to the app's Info.plist";
	}
	if (!g_recordings) g_recordings = [NSMutableDictionary dictionary];
	NeonRecording *previous = g_recordings[fields[1]];
	if (previous) {
		[previous.timer invalidate];
		[previous.recorder stop];
		[g_recordings removeObjectForKey:fields[1]];
	}
	NSString *extension = fields[2].length == 0 ? @".m4a" : [fields[2] hasPrefix:@"."] ? fields[2] : [@"." stringByAppendingString:fields[2]];
	NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
	NSString *folder = [caches stringByAppendingPathComponent:@"Audio"];
	[NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
	NSString *path = [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"recording-%@%@", NSUUID.UUID.UUIDString, extension]];
	NSDictionary *settings = @{
		AVFormatIDKey: @(kAudioFormatMPEG4AAC),
		AVSampleRateKey: @(fields[3].doubleValue),
		AVNumberOfChannelsKey: @(fields[4].integerValue),
		AVEncoderBitRateKey: @(fields[5].integerValue),
	};
	NSError *error = nil;
	AVAudioRecorder *recorder = [[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:path] settings:settings error:&error];
	if (!recorder) return [NSString stringWithFormat:@"!Recording: cannot prepare the recorder: %@", error.localizedDescription ?: @"unknown error"];
	if (![recorder prepareToRecord]) return @"!Recording: cannot prepare the recorder";
	NeonRecording *recording = [NeonRecording new];
	recording.recordingId = fields[1];
	recording.recorder = recorder;
	recording.intervalMillis = fields[6].doubleValue;
	g_recordings[recording.recordingId] = recording;
	return [recording status];
}

static NSString *recordingCommand(NSString *name, NSString *arg) {
	NSArray<NSString *> *fields = fieldsOf(name, arg, 2);
	NSString *command = [name substringFromIndex:@"recording.".length];
	if (![@[@"start", @"pause", @"stop", @"status", @"interval"] containsObject:command]) {
		NSLog(@"Neon niAppCall: unknown command %@", name);
		abort();
	}
	NeonRecording *recording = g_recordings[fields[0]];
	if (!recording) return [NSString stringWithFormat:@"!Recording: no prepared recording %@", fields[0]];
	if ([command isEqualToString:@"start"]) {
		if (![recording.recorder record]) return @"!Recording: the recorder could not start";
		[recording schedule];
	} else if ([command isEqualToString:@"pause"]) {
		[recording seconds];
		[recording.recorder pause];
		[recording schedule];
	} else if ([command isEqualToString:@"stop"]) {
		[recording seconds];
		[recording.timer invalidate];
		recording.timer = nil;
		[recording.recorder stop];
		recording.done = YES;
		[g_recordings removeObjectForKey:fields[0]];
	} else if ([command isEqualToString:@"interval"]) {
		recording.intervalMillis = fields[1].doubleValue;
		[recording schedule];
	}
	return [recording status];
}

NSString *niAudioCall(NSString *name, NSString *arg) {
	if ([name isEqualToString:@"sound.load"]) return soundLoad(arg);
	if ([name hasPrefix:@"sound."]) return soundCommand(name, arg);
	if ([name isEqualToString:@"audio.mode"]) return audioMode(arg);
	if ([name isEqualToString:@"recording.prepare"]) return recordingPrepare(arg);
	if ([name hasPrefix:@"recording."]) return recordingCommand(name, arg);
	NSLog(@"Neon niAppCall: unknown command %@", name);
	abort();
}
