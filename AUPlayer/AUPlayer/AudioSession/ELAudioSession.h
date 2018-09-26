//
//  ELAudioSession.h
//  AUPlayer
//
//  Created by 郝一鹏 on 2018/9/27.
//  Copyright © 2018 郝一鹏. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

extern const NSTimeInterval AUSAudioSessionLatency_Background;
extern const NSTimeInterval AUSAudioSessionLatency_Default;
extern const NSTimeInterval AUSAudioSessionLatency_LowLatency;

NS_ASSUME_NONNULL_BEGIN

@interface ELAudioSession : NSObject

+ (ELAudioSession *)sharedInstance;

@property (nonatomic, strong) AVAudioSession *audioSession;
@property (nonatomic, assign) Float64 preferredSampleRate;
@property (nonatomic, assign, readonly) Float64 currentSampleRate;
@property (nonatomic, assign) NSTimeInterval preferredLatency;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, copy) NSString *category;

- (void)addRouteChangeListener;

@end

NS_ASSUME_NONNULL_END
