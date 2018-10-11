//
//  ELAudioSession.m
//  AUPlayer
//
//  Created by 郝一鹏 on 2018/9/27.
//  Copyright © 2018 郝一鹏. All rights reserved.
//

#import "ELAudioSession.h"
#import "AVAudioSession+RouterUtils.h"

@implementation ELAudioSession

+ (ELAudioSession *)sharedInstance {
	
	static ELAudioSession *instance = NULL;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		instance = [[ELAudioSession alloc] init];
	});
	return instance;
}

- (instancetype)init {
	
	self = [super init];
	if (self) {
		_preferredSampleRate = _currentSampleRate = 44100.0;
		_audioSession = [AVAudioSession sharedInstance];
	}
	return self;
}

- (void)setCategory:(NSString *)category {
	
	// 根据我们需要硬件设备提供的能力设置类别。
	_category = [category copy];
	NSError *error = nil;
	if (![self.audioSession setCategory:_category error:&error]) {
		NSLog(@"Could note set category on audio session: %@", error.localizedDescription);
	}
}

- (void)setActive:(BOOL)active {
	
	_active = active;
	NSError *error = nil;
	// 设置采样频率，让硬件设备按照设置的采样频率来采集或者播放音频
	if (![self.audioSession setPreferredSampleRate:self.preferredSampleRate error:&error]) {
		NSLog(@"Error when setting sample rate on audio session: %@", error.localizedDescription);
	}
	if (![self.audioSession setActive:_active error:&error]) {
		NSLog(@"Error when setting active state of audio session: %@", error.localizedDescription);
	}
	_currentSampleRate = [self.audioSession sampleRate];
}

- (void)setPreferredLatency:(NSTimeInterval)preferredLatency {
	
	// 设置IO的buffer，buffer越小说明延迟越低
	_preferredLatency = preferredLatency;
	NSError *error = nil;
	if (![self.audioSession setPreferredIOBufferDuration:_preferredLatency error:&error]) {
		NSLog(@"Error when setting preferred I/O buffer duration");
	}
}

- (void)addRouteChangeListener {
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(onNotificationAudioRouteChange:)
												 name:AVAudioSessionRouteChangeNotification
											   object:nil];
	[self adjustOnRouteChange];
}

#pragma mark - notification observer

- (void)onNotificationAudioRouteChange:(NSNotification *)notification {
	
	[self adjustOnRouteChange];
}

- (void)adjustOnRouteChange {
	
	AVAudioSessionRouteDescription *currentRoute = [self.audioSession currentRoute];
	if (currentRoute) {
		if ([self.audioSession usingWiredMicrophone]) {
			// do nothing
		} else {
			if (![self.audioSession usingBlueTooth]) {
				[self.audioSession overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
			}
		}
	}
}

@end
