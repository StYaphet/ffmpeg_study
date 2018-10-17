//
//  AudioPlayer.h
//  AudioPlayer
//
//  Created by 郝一鹏 on 2018/10/16.
//  Copyright © 2018 郝一鹏. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AudioPlayer : NSObject

- (instancetype)initWithFilePath:(NSString *)filePath;

- (void)start;

- (void)stop;

@end

NS_ASSUME_NONNULL_END
