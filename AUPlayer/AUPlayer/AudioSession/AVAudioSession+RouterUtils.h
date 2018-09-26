//
//  AVAudioSession+RouterUtils.h
//  AUPlayer
//
//  Created by 郝一鹏 on 2018/9/27.
//  Copyright © 2018 郝一鹏. All rights reserved.
//
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AVAudioSession (RouterUtils)

- (BOOL)usingBlueTooth;
- (BOOL)usingWiredMicrophone;
- (BOOL)shouldShowEarphoneAlert;

@end

NS_ASSUME_NONNULL_END
