//
//  AUGraphPlayer.h
//  AUPlayer
//
//  Created by 郝一鹏 on 2018/9/27.
//  Copyright © 2018 郝一鹏. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AUGraphPlayer : NSObject

- (instancetype)initWithFilePath:(NSString *)path;

- (BOOL)play;

- (void)stop;

- (void)setInputSource:(BOOL)isAcc;

@end

NS_ASSUME_NONNULL_END
