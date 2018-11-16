//
//  PDDAudioOutput.h
//  PDDVideoPlayer
//
//  Created by 郝一鹏 on 2018/11/13.
//  Copyright © 2018 郝一鹏. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FillDataDelegate <NSObject>

- (NSInteger)fillAudioData:(SInt16 *)sampleBuffer numFrames:(NSInteger)frameNum numChannels:(NSInteger)channels;

@end

@interface PDDAudioOutput : NSObject

@property (nonatomic, assign) Float64 sampleRate;
@property (nonatomic, assign) Float64 channels;

- (instancetype)initWithChannels:(NSInteger)channels sampleRate:(NSInteger)sampleRate bytesPerSample:(NSInteger)bytesPerSample fillDataDelegate:(id<FillDataDelegate>)fillAudioDataDelegate;

- (BOOL)play;

- (BOOL)pause;

@end

NS_ASSUME_NONNULL_END
