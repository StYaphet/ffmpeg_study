//
//  AudioPlayer.m
//  AudioPlayer
//
//  Created by 郝一鹏 on 2018/10/16.
//  Copyright © 2018 郝一鹏. All rights reserved.
//

#import "AudioPlayer.h"
#import "AudioOutput.h"
#import "accompany_decoder_controller.h"

@interface AudioPlayer () <FillDataDelegate>

@end

@implementation AudioPlayer {
	AudioOutput *_audioOutput;
	AccompanyDecoderController *_decoderController;
}

- (instancetype)initWithFilePath:(NSString *)filePath {
	self = [super init];
	if (self) {
		_decoderController = new AccompanyDecoderController();
		_decoderController->init([filePath cStringUsingEncoding:NSUTF8StringEncoding], 0.2);
		NSInteger channels = _decoderController->getChannels();
		NSInteger sampleRate = _decoderController->getAudioSampleRate();
		NSInteger bytesPerSample = 2; // 这个是怎么来的
		_audioOutput = [[AudioOutput alloc] initWithChannels:channels sampleRate:sampleRate bytesPerSample:bytesPerSample fillDataDelegate:self];
	}
	return self;
}

- (void)start {
	
	if (_audioOutput) {
		[_audioOutput play];
	}
}

- (void)stop {
	if (_audioOutput) {
		[_audioOutput stop];
		_audioOutput = nil;
	}
	if (_decoderController != NULL) {
		_decoderController->destroy();
		delete _decoderController;
		_decoderController = NULL;
	}
}

- (NSInteger)fillAudioData:(SInt16 *)sampleBuffer numFrames:(NSInteger)frameNum numChannels:(NSInteger)channels {
	
	memset(sampleBuffer, 0, frameNum * channels * sizeof(SInt16));
	if (_decoderController) {
		_decoderController->readSamples(sampleBuffer, (int)(frameNum * channels));
	}
	return 1;
}

@end
