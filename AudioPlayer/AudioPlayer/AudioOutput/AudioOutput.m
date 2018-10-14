//
//  AudioOutput.m
//  AudioPlayer
//
//  Created by 郝一鹏 on 2018/10/11.
//  Copyright © 2018 郝一鹏. All rights reserved.
//

/*
 setup AudioSession
1. setup AudioSession Category
2. set listener
 	interrupt listener
 	audioRoute Change Listener
 	hardware output Volume listener
3. set IO BufferDuration
4. Active AudioSession
 
 setup AudioUnit
 1. Build AudioComponentDescrition To
 */

#import "AudioOutput.h"
#import <AudioToolbox/AudioToolbox.h>
#import <Accelerate/Accelerate.h>
#import "ELAudioSession.h"
#import "CommonUtil.h"

static const AudioUnitElement inputElement = 1;
static OSStatus InputRenderCallback (void *inRefCon,
									 AudioUnitRenderActionFlags *ioActionFlags,
									 const AudioTimeStamp *inTimeStamp,
									 UInt32 inBusNumber,
									 UInt32 inNumberFrames,
									 AudioBufferList *ioData);

static void CheckStatus(OSStatus status, NSString *message, BOOL fatal);

@interface AudioOutput () {
	SInt16 *_outData;
}

@property (nonatomic, assign) AUGraph auGraph;
@property (nonatomic, assign) AUNode ioNode;
@property (nonatomic, assign) AudioUnit ioUnit;
@property (nonatomic, assign) AUNode convertNode;
@property (nonatomic, assign) AudioUnit convertUnit;

@property (readwrite, copy) id<FillDataDelegate> fillAudioDataDelegate;

@end

const float SMAudioIOBufferDurationSmall = 0.0058f;

@implementation AudioOutput

- (instancetype)initWithChannels:(NSInteger)channels sampleRate:(NSInteger)sampleRate bytesPerSample:(NSInteger)bytePerSample fillDataDelegate:(id<FillDataDelegate>)fillAudioDataDelegate {
	
	self = [super init];
	if (self) {
		[[ELAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback];
		[[ELAudioSession sharedInstance] setPreferredSampleRate:sampleRate];
		[[ELAudioSession sharedInstance] setActive:YES];
		[[ELAudioSession sharedInstance] setPreferredLatency:SMAudioIOBufferDurationSmall * 4];
		[[ELAudioSession sharedInstance] addRouteChangeListener];
		[self addAudioSessionInterruptedObserver];
		_outData = (SInt16 *)calloc(8192, sizeof(SInt16));
		_fillAudioDataDelegate = fillAudioDataDelegate;
		_sampleRate = sampleRate;
		_channels = channels;
		[self createAudioUnitGraph];
	}
	return self;
}

- (void)createAudioUnitGraph {
	OSStatus status = noErr;
	status = NewAUGraph(&_auGraph);
	CheckStatus(status, @"Could not create a new AUGraph", YES);
	[self addAudioUnitNodes];
	
	status = AUGraphOpen(_auGraph);
	CheckStatus(status, @"Could not open AUGraph", YES);
	
	[self getUnitsFromNode];
	[self setAudioUnitProperties];
	[self makeNodeConnections];
	CAShow(_auGraph);
	
	status = AUGraphInitialize(_auGraph);
	CheckStatus(status, @"Could not initialize AUGraph", YES);
}

- (void)addAudioUnitNodes {
	
	OSStatus status = noErr;
	AudioComponentDescription ioDescription;
	bzero(&ioDescription, sizeof(ioDescription));
	ioDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
	ioDescription.componentType = kAudioUnitType_Output;
	ioDescription.componentSubType = kAudioUnitSubType_RemoteIO;
	status = AUGraphAddNode(_auGraph, &ioDescription, &_ioNode);
	CheckStatus(status, @"Could not add I/O node to AUGraph", YES);
	
	AudioComponentDescription convertDescription;
	bzero(&convertDescription, sizeof(convertDescription));
	ioDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
	ioDescription.componentType = kAudioUnitType_FormatConverter;
	ioDescription.componentSubType = kAudioUnitSubType_AUConverter;
	status = AUGraphAddNode(_auGraph, &ioDescription, &_convertNode);
	CheckStatus(status, @"Could not add Convert node to AUGraph", YES);
}

- (void)getUnitsFromNode {
	
	OSStatus status = noErr;
	status = AUGraphNodeInfo(_auGraph, _ioNode, NULL, &_ioUnit);
	CheckStatus(status, @"Could not retrieve node info for I/O node", YES);
	
	status = AUGraphNodeInfo(_auGraph, _convertNode, NULL, &_convertUnit);
	CheckStatus(status, @"Could not retrieve node info for Convert node", YES);
}

- (void)setAudioUnitProperties {
	OSStatus status = noErr;
	AudioStreamBasicDescription streamFormat = [self nonInterleavedPCMFormatWithChannels:_channels];
	status = AudioUnitSetProperty(_ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, inputElement, &streamFormat, sizeof(streamFormat));
	
	AudioStreamBasicDescription _clientFormat16int;
	UInt32 bytesPerSample = sizeof(SInt16);
	bzero(&_clientFormat16int, sizeof(_clientFormat16int));
	_clientFormat16int.mFormatID = 
	
	
}

- (AudioStreamBasicDescription)nonInterleavedPCMFormatWithChannels:(UInt32)channels {
	
	
}

@end
