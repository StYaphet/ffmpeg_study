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
	
	AUNode _mPlayerIONode;
	AudioUnit _mPlayerIOUnit;
	
	AUNode _mPlayerNode;
	AudioUnit _mPlayerUnit;
	
	AUNode _mSplitterNode;
	AudioUnit _mSplitterUnit;
	
	AUNode _mAccMixerNode;
	AudioUnit _mAccMixerUnit;
	
	AUNode _mVocalMixerNode;
	AudioUnit _mVocalMixerUnit;
	
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
	
	OSStatus status = noErr;
	// 1.构造AUGraph
	status = NewAUGraph(&_mPlayerGraph);
	CheckStatus(status, @"Could not create a new AUGraph", YES);
	// 2.1 添加IONode
	AudioComponentDescription ioDescription;
	bzero(&ioDescription, sizeof(ioDescription));
	ioDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
	ioDescription.componentType = kAudioUnitType_Output;
	ioDescription.componentSubType = kAudioUnitSubType_RemoteIO;
	status = AUGraphAddNode(_mPlayerGraph, &ioDescription, &_mPlayerIONode);
	CheckStatus(status, @"Could not add I/O node to AUGraph", YES);
	// 2.2 添加playerNode
	AudioComponentDescription playerDescription;
	bzero(&playerDescription, sizeof(playerDescription));
	playerDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
	playerDescription.componentType = kAudioUnitType_Generator;
	playerDescription.componentSubType = kAudioUnitSubType_AudioFilePlayer;
	status = AUGraphAddNode(_mPlayerGraph, &playerDescription, &_mPlayerNode);
	CheckStatus(status, @"Could not add Player node to AUGraph", YES);
	// 2.3 添加splitter
	AudioComponentDescription splitterDescription;
	bzero(&splitterDescription, sizeof(splitterDescription));
	splitterDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
	splitterDescription.componentType = kAudioUnitType_FormatConverter;
	splitterDescription.componentSubType = kAudioUnitSubType_Splitter;
	status = AUGraphAddNode(_mPlayerGraph, &splitterDescription, &_mSplitterNode);
	CheckStatus(status, @"Could not add Splitter node to AUGraph", YES);
	// 2.4 添加两个Mixer
	AudioComponentDescription mixerDescription;
	bzero(&mixerDescription, sizeof(mixerDescription));
	mixerDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
	mixerDescription.componentType = kAudioUnitType_Mixer;
	mixerDescription.componentSubType = kAudioUnitSubType_MultiChannelMixer;
	status = AUGraphAddNode(_mPlayerGraph, &mixerDescription, &_mVocalMixerNode);
	CheckStatus(status, @"Could not add VocalMixer node to AUGraph", YES);
	status = AUGraphAddNode(_mPlayerGraph, &mixerDescription, &_mAccMixerNode);
	CheckStatus(status, @"Could not add VocalMixer node to AUGraph", YES);
	
	// 3. 打开Graph，只有真正打开了Graph才会实例化每一个Node
	status = AUGraphOpen(_mPlayerGraph);
	CheckStatus(status, @"Could not open AUGraph", YES);
	// 4.1 获取出IONode的AudioUnit
	status = AUGraphNodeInfo(_mPlayerGraph, _mPlayerIONode, NULL, &_mPlayerIOUnit);
	CheckStatus(status, @"Could not retrieve node info for I/O node", YES);
	// 4.2 获取出PlayerNode的AudioUnit
	status = AUGraphNodeInfo(_mPlayerGraph, _mPlayerNode, NULL, &_mPlayerUnit);
	CheckStatus(status, @"Could not retrieve node info for Player node", YES);
	// 4.3 获取出Splitter的AudioUnit
	status = AUGraphNodeInfo(_mPlayerGraph, _mSplitterNode, NULL, &_mSplitterUnit);
	CheckStatus(status, @"Could not retrieve node info for Splitter node", YES);
	// 4.4 获取出VocalMixer的AudioUnit
	status = AUGraphNodeInfo(_mPlayerGraph, _mVocalMixerNode, NULL, &_mVocalMixerUnit);
	CheckStatus(status, @"Could not retrieve node info for VocalMixer node", YES);
	// 4.5 q获取出AccMixer的AudioUnit
	status = AUGraphNodeInfo(_mPlayerGraph, _mAccMixerNode, NULL, &_mAccMixerUnit);
	CheckStatus(status, @"Could not retrieve node info for AccMixer node", YES);
	
	// 5. 给AudioUnit设置参数
	AudioStreamBasicDescription stereoStreamFormat;
	UInt32 bytePerSample = sizeof(Float32);
	bzero(&stereoStreamFormat, sizeof(stereoStreamFormat));
	stereoStreamFormat.mFormatID = kAudioFormatLinearPCM; // 指定音频的编码格式
	stereoStreamFormat.mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved; // 描述声音表示格式的参数，每个sample的表示格式是Float格式，左右声道非交错存放
	stereoStreamFormat.mBytesPerPacket = bytePerSample;
	stereoStreamFormat.mFramesPerPacket = 1;
	stereoStreamFormat.mBytesPerFrame = bytePerSample;
	stereoStreamFormat.mChannelsPerFrame = 2;
	stereoStreamFormat.mBitsPerChannel = 8 * bytePerSample;
	stereoStreamFormat.mSampleRate = 48000.0;
	status = AudioUnitSetProperty(_mPlayerIOUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &stereoStreamFormat, sizeof(stereoStreamFormat));
	CheckStatus(status, @"set remote IO output element stream format ", YES);
	status = AudioUnitSetProperty(_mPlayerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &stereoStreamFormat, sizeof(&stereoStreamFormat)); // 为什么这里公用一个stereoStreamFromat？
	
	// 5.2 配置Splitter的属性
	status = AudioUnitSetProperty(_mSplitterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &stereoStreamFormat, sizeof(stereoStreamFormat)); // 为什么inElement的值设置为0？
	CheckStatus(status, @"Could not Set StreamFormat for Splitter Unit", YES);
	status = AudioUnitSetProperty(_mSplitterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input,
								  0, &stereoStreamFormat, sizeof(stereoStreamFormat));
	CheckStatus(status, @"Could not Set StreamFormat for Splitter Unit", YES);
	
	//5.3 配置VocalMixerUnit的属性
	status = AudioUnitSetProperty(_mVocalMixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output,
								  0, &stereoStreamFormat, sizeof(stereoStreamFormat));
	CheckStatus(status, @"Could not Set StreamFormat for VocalMixer Unit", YES);
	status = AudioUnitSetProperty(_mVocalMixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input,
								  0, &stereoStreamFormat, sizeof(stereoStreamFormat));
	CheckStatus(status, @"Could not Set StreamFormat for VocalMixer Unit", YES);
	int mixerElementCount = 1;
	status = AudioUnitSetProperty(_mVocalMixerUnit, kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, 0,
								  &mixerElementCount, sizeof(mixerElementCount));
	//5.4 配置AccMixerUnit的属性
	status = AudioUnitSetProperty(_mAccMixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output,
								  0, &stereoStreamFormat, sizeof(stereoStreamFormat));
	CheckStatus(status, @"Could not Set StreamFormat for AccMixer Unit", YES);
	status = AudioUnitSetProperty(_mAccMixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input,
								  0, &stereoStreamFormat, sizeof(stereoStreamFormat));
	CheckStatus(status, @"Could not Set StreamFormat for AccMixer Unit", YES);
	mixerElementCount = 2;
	status = AudioUnitSetProperty(_mAccMixerUnit, kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, 0,
								  &mixerElementCount, sizeof(mixerElementCount));
	
	[self setInputSource:NO];
	
	// 6. 连接起Node来
	AUGraphConnectNodeInput(_mPlayerGraph, _mPlayerNode, 0, _mSplitterNode, 0);
	CheckStatus(status, @"Player Node Connect To Splitter", YES);
	AUGraphConnectNodeInput(_mPlayerGraph, _mSplitterNode, 0, _mVocalMixerNode, 0);
	CheckStatus(status, @"Player Node Connect To VocalMixerNode", YES);
	AUGraphConnectNodeInput(_mPlayerGraph, _mSplitterNode, 1, _mAccMixerNode, 0);
	CheckStatus(status, @"Player Node Connect To AccMixerNode", YES);
	AUGraphConnectNodeInput(_mPlayerGraph, _mVocalMixerNode, 0, _mAccMixerNode, 1);
	CheckStatus(status, @"Player Node Connect To AccMixerNod", YES);
	AUGraphConnectNodeInput(_mPlayerGraph, _mAccMixerNode, 0, _mPlayerIONode, 0);
	CheckStatus(status, @"Player Node Connect To PlayerIONode", YES);
	
	// 7. 初始化Graph
	status = AUGraphInitialize(_mPlayerGraph);
	CheckStatus(status, @"Couldn't Initialize the graph", YES);
	// 8. 显示Graph结构
	CAShow(_mPlayerGraph);
	// 9. 只有对Graph进行Initialize之后才可以设置AudioPlayer的参数
	[self setUpFilePlayer];
}

- (void)setUpFilePlayer {
	
	
}

- (void)addAudioSessionInterruptedObserver {
	
	
}

@end
