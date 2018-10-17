//
//  PDDVideoDecoder.h
//  PDDVideoPlayer
//
//  Created by 郝一鹏 on 2018/10/15.
//  Copyright © 2018 郝一鹏. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CVImageBuffer.h>
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
//#include "pixdesc.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, PDDFrameType) {
    PDDAudioFrameType,
    PDDVideoFrameType,
};

@interface PDDBuriedPoint : NSObject

@end

@interface PDDFrame : NSObject

@end

@interface PDDAudioFrame : PDDFrame

@end

@interface PDDVideoFrame : PDDFrame

@end

@interface PDDVideoDecoder : NSObject {
    AVFormatContext *_formatCtx;
    BOOL _isOpenInputSuccess;
    
    PDDBuriedPoint *_buriedPoint;
    
    int totalVideoFrameCount;
    long long decodeVideoFrameWasteTimeMills;
    
    NSArray *_videoStreams;
    NSArray *_audioStreams;
    NSInteger _videoStreamIndex;
    NSInteger _audioStreamIndex;
    AVCodecContex *aaa;
}

@end

NS_ASSUME_NONNULL_END
