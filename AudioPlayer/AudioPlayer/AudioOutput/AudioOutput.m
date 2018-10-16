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
 1. Build AudioComponentDescrition To Build AudioUnit Instance
 2. Build AudioStreamBasicDescription To Set AudioUnit Property
 3. Connect Node Or Set RenderCallback For AudioUnit
 4. Initialize AudioUnit
 5. Initialize AudioUnit
 6. AudioOutputUnitStart
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

- (void)dealloc {
	
	if (_outData) {
		free(_outData);
		_outData = NULL;
	}
	[self destoryAudioUnitGraph];
	[self removeAudioSessionInterruptedObserver];
}

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
	_clientFormat16int.mFormatID = kAudioFormatLinearPCM; // 指定音频的编码格式
	_clientFormat16int.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
	_clientFormat16int.mFramesPerPacket = 1;
	_clientFormat16int.mBytesPerPacket = bytesPerSample * 1 * _channels;
	_clientFormat16int.mBytesPerFrame = bytesPerSample * 1 * _channels;
	_clientFormat16int.mChannelsPerFrame = _channels;
	_clientFormat16int.mBitsPerChannel = 8 * bytesPerSample;
	_clientFormat16int.mSampleRate = _sampleRate;
	
	status = AudioUnitSetProperty(_convertUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &streamFormat, sizeof(streamFormat));
	CheckStatus(status, @"augraph recorder normal unit set client format error", YES);
	// 设定convertUnit输入转换格式跟输出转换格式
	status = AudioUnitSetProperty(_convertUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &_clientFormat16int, sizeof(_clientFormat16int));
	CheckStatus(status, @"augraph recorder normal unit set client format error", YES);
}

- (AudioStreamBasicDescription)nonInterleavedPCMFormatWithChannels:(UInt32)channels {
	
	UInt32 bytesPerSample = sizeof(Float32);
	
	AudioStreamBasicDescription asbd;
	bzero(&asbd, sizeof(asbd));
	asbd.mSampleRate = _sampleRate;
	asbd.mFormatID = kAudioFormatLinearPCM; // 指定音频的编码格式
	asbd.mFormatFlags = kAudioFormatFlagIsNonInterleaved | kAudioFormatFlagsNativeFloatPacked;
	asbd.mChannelsPerFrame = channels;
	asbd.mFramesPerPacket = 1;
	asbd.mBytesPerPacket = bytesPerSample; //根据mFormatFlags设置，kAudioFormatFlagIsNonInterleaved的话就是bytesPerSample，如果是Interleaved，就是 bytesPerSample * channels
	asbd.mBytesPerFrame = bytesPerSample;
	asbd.mBitsPerChannel = 8 * bytesPerSample;
	return asbd;
}

- (void)makeNodeConnections {
	
	OSStatus status = noErr;
	status = AUGraphConnectNodeInput(_auGraph, _convertNode, 0, _ioNode, 0);
	CheckStatus(status, @"Could not connect I/O node input to mixer node input", YES);
	
	AURenderCallbackStruct callbackStruct;
	callbackStruct.inputProc = &InputRenderCallback;
	callbackStruct.inputProcRefCon = (__bridge void*)self;
	
	status = AudioUnitSetProperty(_convertUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callbackStruct, sizeof(callbackStruct));
	CheckStatus(status, @"Could not set render callback on mixer input scope, element 1", YES);
}

- (void)destoryAudioUnitGraph {
	
	AUGraphStop(_auGraph);
	AUGraphUninitialize(_auGraph);
	AUGraphClose(_auGraph);
	AUGraphRemoveNode(_auGraph, _ioNode);
	DisposeAUGraph(_auGraph);
	_ioUnit = NULL;
	_ioNode = 0;
	_auGraph = NULL;
}

- (BOOL)play {
	
	OSStatus status = AUGraphStart(_auGraph);
	CheckStatus(status, @"Could not start AUGraph", YES);
	return YES;
}

- (void)stop
{
	OSStatus status = AUGraphStop(_auGraph);
	CheckStatus(status, @"Could not stop AUGraph", YES);
}

- (void)addAudioSessionInterruptedObserver {
	
	[self removeAudioSessionInterruptedObserver];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onNotificationAudioInterrupted:) name:AVAudioSessionInterruptionNotification object:[AVAudioSession sharedInstance]];
}

- (void)removeAudioSessionInterruptedObserver {
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:AVAudioSessionInterruptionNotification
												  object:nil];
}

- (void)onNotificationAudioInterrupted:(NSNotification *)sender {
	
	AVAudioSessionInterruptionType interruptionType = [[[sender userInfo] objectForKey:AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
	switch (interruptionType) {
		case AVAudioSessionInterruptionTypeBegan:
			[self play];
			break;
		case AVAudioSessionInterruptionTypeEnded:
			[self stop];
			break;
		default:
			break;
	}
}

- (OSStatus)renderData:(AudioBufferList *)ioData atTimeStamp:(const AudioTimeStamp *)timeStamp forElement:(UInt32)element numberFrames:(UInt32)numFrames flag:(AudioUnitRenderActionFlags *)flags {
	
	for (int iBuffer = 0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
		// 将s所指向的某一块内存中的后n个字节的内容全部设置为ch指定的ASCII值
		memset(ioData->mBuffers[iBuffer].mData, 0, ioData->mBuffers[iBuffer].mDataByteSize);
	}
	if (_fillAudioDataDelegate) {
		[_fillAudioDataDelegate fillAudioData:_outData numFrames:numFrames numChannels:_channels];
		for (int iBuffer = 0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
			// memcpy函数的功能是从源src所指的内存地址的起始位置开始拷贝n个字节到目标dest所指的内存地址的起始位置中
			memcpy((SInt16 *)ioData->mBuffers[iBuffer].mData, _outData, ioData->mBuffers[iBuffer].mDataByteSize);
		}
	}
	return noErr;
}

@end

static void CheckStatus(OSStatus status, NSString *message, BOOL fatal)
{
	if(status != noErr)
	{
		char fourCC[16];
		*(UInt32 *)fourCC = CFSwapInt32HostToBig(status);
		fourCC[4] = '\0';
		
		if(isprint(fourCC[0]) && isprint(fourCC[1]) && isprint(fourCC[2]) && isprint(fourCC[3]))
			NSLog(@"%@: %s", message, fourCC);
		else
			NSLog(@"%@: %d", message, (int)status);
		
		if(fatal)
			exit(-1);
	}
}


/**
 @param inRefCon 指定回调的上下文
 @param ioActionFlags 回调上下文的设置，比如没有数据了，设置成kAudioUnitRenderAction_OutputIsSilence
 @param inTimeStamp 回调被执行的时间，但不是绝对时间，而是采样帧的数目
 @param inBusNumber 通道数
 @param inNumberFrames <#inNumberFrames description#>
 @param ioData 具体使用的数据，比如播放文件时，将文件内容填入
 @return <#return value description#>
 */
static OSStatus InputRenderCallback (void *inRefCon,
									 AudioUnitRenderActionFlags *ioActionFlags,
									 const AudioTimeStamp *inTimeStamp,
									 UInt32 inBusNumber,
									 UInt32 inNumberFrames,
									 AudioBufferList *ioData) {
	AudioOutput *audioOutput = (__bridge id)inRefCon;
	return [audioOutput renderData:ioData atTimeStamp:inTimeStamp forElement:inBusNumber numberFrames:inNumberFrames flag:ioActionFlags];
}
