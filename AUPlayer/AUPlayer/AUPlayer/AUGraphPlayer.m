//
//  AUGraphPlayer.m
//  AUPlayer
//
//  Created by 郝一鹏 on 2018/9/27.
//  Copyright © 2018 郝一鹏. All rights reserved.
//

#import "AUGraphPlayer.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import "ELAudioSession.h"

static void CheckStatus(OSStatus status, NSString *message, BOOL fatal) {
	
	if (status != noErr) {
		char fourCC[16];
		// Converts a 32-bit integer from big-endian format to the host’s native byte order.
		*(UInt32 *)fourCC = CFSwapInt32BigToHost(status);
		// 利用status生成一个错误信息字符串
		fourCC[4] = '\0';
		// 判断字符c是否为可打印字符（含空格）
		if (isprint(fourCC[0]) && isprint(fourCC[1]) && isprint(fourCC[2]) && isprint(fourCC[3])) {
			NSLog(@"%@: %s", message, fourCC);
		} else {
			NSLog(@"%@: %d", message, (int)status);
		}
		if (fatal) {
			exit(-1);
		}
	}
}

@implementation AUGraphPlayer {
	
	AUGraph _mPlayerGraph;
	AUNode _mPlayerNode;
	AUNode _mSplitterNode;
	AudioUnit _mSplitterUnit;
	AUNode _mAccMixerNode;
	AudioUnit _mAccMixerUnit;
	AUNode _mVocalMixerNode;
	AudioUnit _mVocalMixerUnit;
	AudioUnit _mPlayerUnit;
	AUNode _mPlayerIONode;
	AudioUnit _mPlayerIOUnit;
	NSURL *_playPath;
}

- (instancetype)initWithFilePath:(NSString *)path {
	
	self = [super init];
	if (self) {
		[[ELAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord];
		[[ELAudioSession sharedInstance] setPreferredSampleRate:44100];
		[[ELAudioSession sharedInstance] setActive:YES];
		[[ELAudioSession sharedInstance] addRouteChangeListener];
		[self addAudioSessionInterruptedObserver];
		_playPath = [NSURL URLWithString:path];
		[self initializerPlayGraph];
	}
	return self;
}

- (BOOL)play {
	
	OSStatus status = AUGraphStart(_mPlayerGraph);
	CheckStatus(status, @"Could not start AUGraph", YES);
	return YES;
}

- (void)stop {
	
	Boolean isRunning = false;
	OSStatus status = AUGraphIsRunning(_mPlayerGraph, &isRunning);
	if (isRunning) {
		status = AUGraphStop(_mPlayerGraph);
		CheckStatus(status, @"Could not stop AUGraph", YES);
	}
}

- (void)setInputSource:(BOOL)isAcc {
	
	
}

#pragma mark - private method

- (void)initializerPlayGraph {
	
	
}

- (void)addAudioSessionInterruptedObserver {
	
	
}

@end
