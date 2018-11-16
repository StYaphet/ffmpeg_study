//
//  PDDVideoDecoder.m
//  PDDVideoPlayer
//
//  Created by 郝一鹏 on 2018/10/15.
//  Copyright © 2018 郝一鹏. All rights reserved.
//

#import "PDDVideoDecoder.h"

static NSData *copyFrameData(UInt8 *src, int linesize, int width, int height) {
	width = MIN(linesize, width);
	NSMutableData *md = [NSMutableData dataWithLength:width * height];
	Byte *dst = md.mutableBytes;
	for (NSUInteger i = 0; i < height; ++i) {
		memcpy(dst, src, width);
		dst += width;
		src += linesize;
	}
	return md;
}

static NSArray *collectStreams(AVFormatContext *formatCtx, enum AVMediaType codecType)
{
	NSMutableArray *ma = [NSMutableArray array];
	for (NSInteger i = 0; i < formatCtx->nb_streams; i++) {
		if (codecType == formatCtx->streams[i]->codec->codec_type) {
			[ma addObject:@(i)];
		}
	}
	return [ma copy];
}

@implementation PDDFrame

@end

@implementation PDDAudioFrame

@end

@implementation PDDVideoFrame

@end

@implementation PDDBuriedPoint

@end

// AVRational这个结构标识一个分数，num为分数，den为分母。
// PTS，DTS
// AVRational time_base：时基。通过该值可以把PTS，DTS转化为真正的时间。FFMPEG其他结构体中也有这个字段，但是根据我的经验，只有AVStream中的time_base是可用的。PTS*time_base=真正的时间

// AVStream结构体
static void avStreamFPSTimeBase(AVStream *st, CGFloat defaultTimeBase, CGFloat *pFPS, CGFloat *pTimeBase) {
	CGFloat fps, timebase;
	if (st->time_base.den && st->time_base.num) { // 单位为s，精度比较高
		timebase = av_q2d(st->time_base);
	} else if (st->codec->time_base.den && st->codec->time_base.num) { // AVCodecContext->time_base单位同样为秒，不过精度没有AVStream->time_base高，大小为1/framerate
		timebase = av_q2d(st->codec->time_base);
	} else {
		timebase = defaultTimeBase;
	}
	
	if (st->avg_frame_rate.den && st->avg_frame_rate.num) { // 平均帧率
		fps = av_q2d(st->avg_frame_rate);
	} else if (st->r_frame_rate.den && st->r_frame_rate.num) {
		//r_frame_rate: 流的实际基本帧速率。这是可以准确表示所有时间戳的最低帧速率（它是流中所有帧速率的最小公倍数）。 注意，这个值只是一个猜测！ 例如，如果时基为1/90000且所有帧具有大约3600或1800个计时器滴答，则r_frame_rate将为50/1。
		fps = av_q2d(st->r_frame_rate);
	} else {
		fps = 1.0 / timebase;
	}
	
	if (pFPS) {
		*pFPS = fps;
	}
	if (pTimeBase) {
		*pTimeBase = timebase;
	}
}

@interface PDDVideoDecoder () {
	AVFrame *_videoFrame;
	AVFrame *_audioFrame;
	CGFloat _fps;
	CGFloat _decodePosition;
	BOOL _isSubscribe;
	BOOL _isEOF;
	SwrContext *_swrContex;
	void *_swrBuffer;
	NSUInteger _swrBufferSize;
	
	AVPicture _picture;
	BOOL _pictureValid;
	struct SwsContext *_swsContext;
	
	int _subscribeTimeOutTimeInSecs;
	int _readLastestFrameTime;
	
	BOOL _interrupted;
	int _connectionRetry;
}

@end

@implementation PDDVideoDecoder

static int interrupt_callback(void *ctx)
{
	if (!ctx)
		return 0;
	__unsafe_unretained PDDVideoDecoder *p = (__bridge PDDVideoDecoder *)ctx;
	const BOOL r = [p detectInterrupted];
	if (r) NSLog(@"DEBUG: INTERRUPT_CALLBACK!");
	return r;
}

- (BOOL)detectInterrupted {
	// 当前时间与读上一帧的时间间隔超过设置的时间，认为被中断了
	if ([[NSDate date] timeIntervalSince1970] - _readLastestFrameTime > _subscribeTimeOutTimeInSecs) {
		return YES;
	}
	return _interrupted;
}

#pragma mark - 打开文件

- (BOOL)openFile:(NSString *)path parameter:(NSDictionary *)parameters error:(NSError * _Nullable __autoreleasing *)error {
	BOOL ret = YES;
	if (path == nil || path.length == 0) {
		return NO;
	}
	
	_connectionRetry = 0;
	totalVideoFrameCount = 0;
	_subscribeTimeOutTimeInSecs = SUBSCRIBE_VIDEO_DATA_TIME_OUT;
	_interrupted = NO;
	_isOpenInputSuccess = NO;
	_isSubscribe = YES;
	_buriedPoint = [[PDDBuriedPoint alloc] init];
	_buriedPoint.bufferStatusRecords = [[NSMutableArray alloc] init];
	_readLastestFrameTime = [[NSDate date] timeIntervalSince1970];
	
	// 注册协议、格式与编码器
	avformat_network_init();
	av_register_all();
	// 开始试图去打开一个直播流的绝对时间
	_buriedPoint.beginOpen = [[NSDate date] timeIntervalSince1970] * 1000;
	int openInputErrCode = [self openInput:path parameter:parameters];
	if (openInputErrCode > 0) {
		_buriedPoint.successOpen = ([[NSDate date] timeIntervalSince1970] * 1000 - _buriedPoint.beginOpen) / 1000.0f;
		_buriedPoint.failOpen = 0.0f;
		_buriedPoint.failOpenType = 1;
		BOOL openVideoStatus = [self openVideoStream];
		BOOL openAudioStatus = [self openAudioStream];
		if (!openVideoStatus || !openAudioStatus) {
			[self closeFile];
			ret = NO;
		}
	} else {
		_buriedPoint.failOpen = ([[NSDate date] timeIntervalSince1970] * 1000 - _buriedPoint.beginOpen) / 1000.0f;
		_buriedPoint.successOpen = 0.0f;
		_buriedPoint.failOpenType = openInputErrCode;
		ret = NO;
	}
	
	_buriedPoint.retryTimes = _connectionRetry;
	
	if (ret) {
		// 在网络的播放器中有可能会拉到长宽都为0 并且pix_fmt是None的流 这个时候我们需要重连
		NSInteger videoWidth = [self frameWidth];
		NSInteger videoHeight = [self frameHeight];
		int retryTimes = 5;
		while (((videoWidth <= 0) || (videoHeight <= 0)) && retryTimes > 0) {
			NSLog(@"because of videoWidth and videoHeight is Zero We will Retry...");
			usleep(500 * 1000);
			_connectionRetry = 0;
			ret = [self openFile:path parameter:parameters error:error]; // 会无限循环吧？
			if(!ret){
				//如果打开失败 则退出
				break;
			}
			retryTimes--;
			videoWidth = [self frameWidth];
			videoHeight = [self frameHeight];
		}
	}
	_isOpenInputSuccess = ret;
	
	return ret;
}

- (int)openInput:(NSString *)path parameter:(NSDictionary *)parameters {
	// 打开媒体文件源，并设置回调
	AVFormatContext *formatCtx = avformat_alloc_context();
	AVIOInterruptCB int_cb  = {interrupt_callback, (__bridge void *)(self)};
	formatCtx->interrupt_callback = int_cb;
	int openInputErrCode = 0;
	if ((openInputErrCode = [self openFormatInput:&formatCtx path:path parameter:parameters]) != 0) {
		NSLog(@"Video decoder open input file failed... videoSourceURI is %@ openInputErr is %s", path, av_err2str(openInputErrCode));
		if (formatCtx) {
			avformat_free_context(formatCtx);
			return openInputErrCode;
		}
	}
	// 需要调用find_stream_info来获取各个stream的metaData
	// 对于本地文件，获取很快
	// 但对于网络资源，就需要执行一段时间了，解码时间越长，获取数据越多，metaData越准确
	// 一般是通过设置probeSize与max_analyze_duration来给出探测数据量的大小和最大解析数据的长度
	// 通常设置为50 * 1024 和7500，如果到了设置的值还没有解析出来metaData，就进入重试策略
	[self initAnalyzeDurationAndProbesize:formatCtx parameter:parameters];
	int findStreamErrorCode = 0;
	double startFindStreamTimeMills = CFAbsoluteTimeGetCurrent() * 1000;
	if ((findStreamErrorCode = avformat_find_stream_info(formatCtx, NULL)) < 0) {
		// 因为avformat_open_input的注释如下，所以要关闭avformat_close_input
		// Open an input stream and read the header. The codecs are not opened. The stream must be closed with avformat_close_input().
		avformat_close_input(&formatCtx);
		avformat_free_context(formatCtx);
		NSLog(@"Video decoder find stream info failed... find stream ErrCode is %s", av_err2str(findStreamErrorCode));
		return findStreamErrorCode;
	}
	int wasteTimeMills = CFAbsoluteTimeGetCurrent() * 1000 - startFindStreamTimeMills;
	NSLog(@"Find Stream Info waste TimeMills is %d", wasteTimeMills);
	if (formatCtx->streams[0]->codec->codec_id == AV_CODEC_ID_NONE) {
		avformat_close_input(&formatCtx);
		avformat_free_context(formatCtx);
		NSLog(@"Video decoder First Stream Codec ID Is UnKnown...");
		if([self isNeedRetry]){
			return [self openInput:path parameter:parameters];
		} else {
			return -1;
		}
	}
	_formatCtx = formatCtx;
	return 1;
}

- (int)openFormatInput:(AVFormatContext **)formatCtx path:(NSString *)path parameter:(NSDictionary *)parameters {
	const char *videoSourceURI = [path cStringUsingEncoding:NSUTF8StringEncoding];
	AVDictionary *options = NULL;
	NSString *rtmpTcurl = parameters[RTMP_TCURL_KEY];
	if ([rtmpTcurl length] > 0) {
		const char *rtmp_tcrul = [rtmpTcurl cStringUsingEncoding:NSUTF8StringEncoding];
		av_dict_set(&options, "rtmp_tcurl", rtmp_tcrul, 0);
	}
	return avformat_open_input(formatCtx, videoSourceURI, NULL, &options);
}

- (void)initAnalyzeDurationAndProbesize:(AVFormatContext *)formatCtx parameter:(NSDictionary*) parameters {
	
	float probeSize = [parameters[PROBE_SIZE] floatValue];
	formatCtx->probesize = probeSize ?: 50 * 1024;
	NSArray *duration = parameters[MAX_ANALYZE_DURATION_ARRAY];
	if (duration && duration.count > _connectionRetry) {
		formatCtx->max_analyze_duration = [duration[_connectionRetry] floatValue];
	} else {
		float multiplier = 0.5 + (double)pow(2.0, (double)_connectionRetry) * 0.25;
		formatCtx->max_analyze_duration = multiplier * AV_TIME_BASE;
	}
	BOOL fpsProbeSizeConfiged = [parameters[FPS_PROBE_SIZE_CONFIGURED] boolValue];
	if(fpsProbeSizeConfiged){
		formatCtx->fps_probe_size = 3;
	}
}

- (BOOL) isNeedRetry {
	_connectionRetry++;
	return _connectionRetry <= NET_WORK_STREAM_RETRY_TIME;
}

- (BOOL)openVideoStream {
	_videoStreamIndex = -1;
	// 获取所有的视频流
	_videoStreams = collectStreams(_formatCtx, AVMEDIA_TYPE_VIDEO);
	for (NSNumber *index in _videoStreams) {
		const NSUInteger iStream = index.integerValue;
		// 获取解码器
		// 只能这样获取，因为stream里边是不能直接获取codec_id的
		// 只能先获取各个流的解码器上下文，然后通过avcodec_find_decoder，根据解码器上下文的codec_id来获取解码器
		AVCodecContext *codecCtx = _formatCtx->streams[iStream]->codec;
		AVCodec *codec = avcodec_find_decoder(codecCtx->codec_id);
		if (!codec) {
			NSLog(@"Find Video Decoder Failed codec_id %d CODEC_ID_H264 is %d", codecCtx->codec_id, CODEC_ID_H264);
			return NO;
		}
		int openCodecErrCode = 0;
		// 打开解码器
		// avcodec_open2 是非线程安全的
		if ((openCodecErrCode = avcodec_open2(codecCtx, codec, NULL)) < 0) {
			NSLog(@"open Video Codec Failed openCodecErr is %s", av_err2str(openCodecErrCode));
			return NO;
		}
		
		_videoFrame = avcodec_alloc_frame();
		if (!_videoFrame) {
			NSLog(@"Alloc Video Frame Failed...");
			avcodec_close(codecCtx);
			return NO;
		}
		
		_videoStreamIndex = iStream;
		_videoCodecCtx = codecCtx;
		
		// 确定帧率
		AVStream *st = _formatCtx->streams[_videoStreamIndex];
		avStreamFPSTimeBase(st, 0.04, &_fps, &_videoTimeBase);
		break;
	}
	return YES;
}

- (BOOL)openAudioStream {
	_audioStreamIndex = -1;
	_audioStreams = collectStreams(_formatCtx, AVMEDIA_TYPE_AUDIO);
	for (NSNumber *index in _audioStreams) {
		const NSUInteger iStream = [index integerValue];
		AVCodecContext *codecCtx = _formatCtx->streams[iStream]->codec;
		AVCodec *codec = avcodec_find_decoder(codecCtx->codec_id);
		if(!codec){
			NSLog(@"Find Audio Decoder Failed codec_id %d CODEC_ID_AAC is %d", codecCtx->codec_id, CODEC_ID_AAC);
			return NO;
		}
		int openCodecErrCode = 0;
		if ((openCodecErrCode = avcodec_open2(codecCtx, codec, NULL)) < 0) {
			NSLog(@"Open Audio Codec Failed openCodecErr is %s", av_err2str(openCodecErrCode));
			return NO;
		}
		
		SwrContext *swrContext = NULL;
		if (![self audioCodecIsSupported:codecCtx]) { // 如果采样格式不是signed 16 bits，就需要转换格式
			NSLog(@"because of audio Codec Is Not Supported so we will init swresampler...");
			/**
			 * 初始化resampler
			 * @param s               Swr context, can be NULL
			 * @param out_ch_layout   output channel layout (AV_CH_LAYOUT_*)
			 * @param out_sample_fmt  output sample format (AV_SAMPLE_FMT_*).
			 * @param out_sample_rate output sample rate (frequency in Hz)
			 * @param in_ch_layout    input channel layout (AV_CH_LAYOUT_*)
			 * @param in_sample_fmt   input sample format (AV_SAMPLE_FMT_*).
			 * @param in_sample_rate  input sample rate (frequency in Hz)
			 * @param log_offset      logging level offset
			 * @param log_ctx         parent logging context, can be NULL
			 */
			swrContext = swr_alloc_set_opts(NULL, av_get_default_channel_layout(codecCtx->channels), AV_SAMPLE_FMT_S16, codecCtx->sample_rate, av_get_default_channel_layout(codecCtx->channels), codecCtx->sample_fmt, codecCtx->sample_rate, 0, NULL);
			if (!swrContext || swr_init(swrContext)) { // swr_init 返回值0代表成功
				if (swrContext) {
					swr_free(&swrContext);
				}
				avcodec_close(codecCtx); // 是啊比了就需要清理资源
				NSLog(@"init resampler failed...");
				return NO;
			}
			
			_audioFrame = avcodec_alloc_frame();
			if (!_audioFrame) {
				NSLog(@"Alloc Audio Frame Failed...");
				if (swrContext)
					swr_free(&swrContext);
				avcodec_close(codecCtx);
				return NO;
			}
			
			_audioStreamIndex = iStream;
			_audioCodecCtx = codecCtx;
			_swrContex = swrContext;
			
			AVStream *st = _formatCtx->streams[_audioStreamIndex];
			avStreamFPSTimeBase(st, 0.025, 0, &_audioTimeBase);
			break;
		}
	}
	return YES;
}

- (BOOL) isOpenInputSuccess
{
	return _isOpenInputSuccess;
}

#pragma mark - 解码

- (BOOL)audioCodecIsSupported:(AVCodecContext *)audioCodecCtx {
	if (audioCodecCtx->sample_fmt == AV_SAMPLE_FMT_S16) {
		return true;
	}
	return false;
}

- (NSArray *)decodeFrames:(CGFloat)minDuration decodeVideoErrorState:(int *)decodeVideoErrorState
{
	if (_videoStreamIndex == -1 && _audioStreamIndex == -1) {
		return nil;
	}
	NSMutableArray *result = [NSMutableArray array];
	AVPacket packet;
	CGFloat decodeDuration = 0;
	BOOL finished = NO;
	while (!finished) {
//		返回流的下一帧。 此函数返回存储在文件中的内容，并不验证解码器的有效帧是什么。 它会将存储在文件中的内容分成帧，并为每个调用返回一个。 它不会在有效帧之间省略无效数据，以便为解码器提供可能的最大解码信息。
//		如果pkt-> buf为NULL，则数据包有效直到下一个av_read_frame（）或直到avformat_close_input（）。 否则数据包无限期有效。 在这两种情况下，必须在不再需要时使用av_free_packet释放数据包。 对于视频，数据包只包含一个帧。 对于音频，如果每个帧具有已知的固定大小（例如PCM或ADPCM数据），则它包含整数个帧。 如果音频帧具有可变大小（例如MPEG音频），则它包含一个帧。
//		pkt> pts，pkt-> dts和pkt-> duration始终设置为AVStream.time_base单位中的正确值（如果格式不能提供，则猜测）。 如果视频格式具有B帧，则pkt-> pts可以是AV_NOPTS_VALUE，因此如果不解压缩有效载荷，最好依赖pkt-> dts。
		if (av_read_frame(_formatCtx, &packet) < 0) {
			_isEOF = YES;
			break;
		}
	}
	int pktSize = packet.size;
	int pktStreamIndex = packet.stream_index;
	if (pktStreamIndex == _videoStreamIndex) { // 一个packet只能是视频包或者音频包
		double startDecodeTimeMills = CFAbsoluteTimeGetCurrent() * 1000;
		PDDVideoFrame *frame = [self decodeVideo:packet packetSize:pktSize decodeVideoErrorState:decodeVideoErrorState];
		int wasteTimeMills = CFAbsoluteTimeGetCurrent() * 1000 - startDecodeTimeMills;
		decodeVideoFrameWasteTimeMills += wasteTimeMills;
		if (frame) {
			totalVideoFrameCount ++;
			[result addObject:frame];
			decodeDuration += frame.duration;
			// 如果解出来的视频帧的时长超过了，那么就先不解下一帧
			if (decodeDuration > minDuration) {
				finished = YES;
			}
		} else if (pktStreamIndex == _audioStreamIndex) {
			while (pktSize > 0) {
				int gotframe = 0;
//				一些解码器可以在单个AVPacket中支持多个帧。然后，这样的解码器将仅解码第一帧，并且返回值将小于分组大小。在这种情况下，必须使用包含剩余数据的AVPacket再次调用avcodec_decode_audio4以便解码第二帧等...即使没有返回帧，也需要将数据包与剩余数据一起馈送到解码器，直到它完全消耗或发生错误。
//				某些解码器（标有CODEC_CAP_DELAY的解码器）在输入和输出之间有延迟。这意味着对于某些数据包，它们不会立即产生解码输出，需要在解码结束时刷新以获得所有解码数据。通过使用avpkt-> data设置为NULL并且avpkt-> size设置为0的数据包调用此函数来完成刷新，直到它停止返回样本为止。即使那些未标记为CODEC_CAP_DELAY的解码器也是安全的，然后不会返回任何样本。
				int len = avcodec_decode_audio4(_audioCodecCtx, _audioFrame, &gotframe, &packet);
				if (len < 0) { // 返回值小于0即为出错了
					NSLog(@"decode audio error, skip packet");
					break;
				}
				if (gotframe) { // 如果没有帧可以解码则为零，否则为非零。 请注意，此字段设置为零并不表示发生了错误。 对于设置了CODEC_CAP_DELAY的解码器，不保证给定的解码调用产生帧。
					PDDAudioFrame *frame = [self handleAudioFrame];
					if (frame) {
						[result addObject:frame];
						if (_videoStreamIndex == -1) {
							_decodePosition = frame.position;
							decodeDuration += frame.duration;
							if (decodeDuration > minDuration) {
								finished = YES;
							}
						}
					}
					if (len == 0) {
						break;
					}
					pktSize -= len;
				}
			}
		} else {
			NSLog(@"We Can Not Process Stream Except Audio And Video Stream...");
		}
		av_free(&packet);
	}
	return result;
}

- (PDDVideoFrame *)decodeVideo:(AVPacket)packet packetSize:(int)pktSize decodeVideoErrorState:(int *)decodeVideoErrorState {
	PDDVideoFrame *frame = nil;
	while (pktSize > 0) {
		int gotframe = 0;
		int len = avcodec_decode_video2(_videoCodecCtx, _videoFrame, &gotframe, &packet);
		if (len < 0) {
			NSLog(@"decode video error, skip packet %s", av_err2str(len));
			*decodeVideoErrorState = 1;
			break;
		}
		if (gotframe) {
			frame = [self handleVideoFrame];
		}
		
		if(packet.flags == 1){
			//IDR Frame
			NSLog(@"IDR Frame %f", frame.position);
		} else if (packet.flags == 0) {
			//NON-IDR Frame
			NSLog(@"===========NON-IDR Frame=========== %f", frame.position);
		}
		if (0 == len)
			break;
		pktSize -= len;
	}
	return frame;
}

- (PDDVideoFrame *)handleVideoFrame {
	if (!_videoFrame->data[0]) {
		return nil;
	}
	PDDVideoFrame *frame = [[PDDVideoFrame alloc] init];
	if (_videoCodecCtx->pix_fmt == AV_PIX_FMT_YUV420P || _videoCodecCtx->pix_fmt == AV_PIX_FMT_YUVJ420P) {
		// 用VideoFrame的width与height不行吗？
		frame.luma = copyFrameData(_videoFrame->data[0],
								   _videoFrame->linesize[0],
								   _videoCodecCtx->width,
								   _videoCodecCtx->height);
		
		frame.chromaB = copyFrameData(_videoFrame->data[1],
									  _videoFrame->linesize[1],
									  _videoCodecCtx->width / 2,
									  _videoCodecCtx->height / 2);
		
		frame.chromaR = copyFrameData(_videoFrame->data[2],
									  _videoFrame->linesize[2],
									  _videoCodecCtx->width / 2,
									  _videoCodecCtx->height / 2);
	} else {
		// 不是指定格式的，需要转换
		if (!_swsContext && ![self setupScaler]) {
			NSLog(@"fail setup video scaler");
			return nil;
		}
		sws_scale(_swsContext, (const uint8_t **)_videoFrame->data, _videoFrame->linesize, 0, _videoCodecCtx->height, _picture.data, _picture.linesize);
		frame.luma = copyFrameData(_picture.data[0],
								   _picture.linesize[0],
								   _videoCodecCtx->width,
								   _videoCodecCtx->height);
		
		frame.chromaB = copyFrameData(_picture.data[1],
									  _picture.linesize[1],
									  _videoCodecCtx->width / 2,
									  _videoCodecCtx->height / 2);
		
		frame.chromaR = copyFrameData(_picture.data[2],
									  _picture.linesize[2],
									  _videoCodecCtx->width / 2,
									  _videoCodecCtx->height / 2);
	}
	frame.width = _videoCodecCtx->width;
	frame.height = _videoCodecCtx->height;
	frame.linesize = _videoFrame->linesize[0];
	frame.type = PDDVideoFrameType;
	frame.position = av_frame_get_best_effort_timestamp(_videoFrame) * _videoTimeBase;
	const int64_t frameDuration = av_frame_get_pkt_duration(_videoFrame);
	if (frameDuration) {
		frame.duration = frameDuration * _videoTimeBase;
		// 乘以0.5的原因，When decoding, this signals how much the picture must be delayed. extra_delay = repeat_pict / (2*fps)
		frame.duration += _videoFrame->repeat_pict *  _videoTimeBase * 0.5;
	} else {
		frame.duration = 1.0 / _fps;
	}
	return frame;
}

- (PDDAudioFrame *)handleAudioFrame
{
	if (!_audioFrame->data[0]) {
		return nil;
	}
	
	const NSUInteger numChannels = _audioCodecCtx->channels;
	NSInteger numFrames;
	
	void *audioData;
	if (_swsContext) {
		const NSUInteger ratio = 2;
		const int bufSize = av_samples_get_buffer_size(NULL, (int)numChannels, (int)(_audioFrame->nb_samples * ratio), AV_SAMPLE_FMT_S16, 1);
		if (!_swrBuffer || _swrBufferSize < bufSize) {
			_swrBufferSize = bufSize;
			_swrBuffer = realloc(_swrBuffer, _swrBufferSize);
		}
		Byte *outbuf[2] = {_swrBuffer, 0};
		numFrames = swr_convert(_swrContex, outbuf, (int)(_audioFrame->nb_samples * ratio), (const uint8_t **)_audioFrame->data, _audioFrame->nb_samples);
		if (numFrames < 0) {
			NSLog(@"fail resample audio");
			return nil;
		}
		audioData = _swrBuffer;
	} else {
		if (_audioCodecCtx->sample_fmt != AV_SAMPLE_FMT_S16) {
			NSLog(@"Audio format is invalid");
			return nil;
		}
		audioData = _audioFrame->data[0];
		numFrames = _audioFrame->nb_samples;
	}
	const NSUInteger numElements = numFrames * numChannels;
	NSMutableData *pcmData = [NSMutableData dataWithLength:numElements * sizeof(SInt16)];
	memcpy(pcmData.mutableBytes, audioData, numElements * sizeof(SInt16));
	PDDAudioFrame *frame = [[PDDAudioFrame alloc] init];
	frame.position = av_frame_get_best_effort_timestamp(_audioFrame) * _audioTimeBase;
	frame.duration = av_frame_get_pkt_duration(_audioFrame) * _audioTimeBase;
	frame.samples = pcmData;
	frame.type = PDDAudioFrameType;
	//    NSLog(@"Add Audio Frame position is %.3f", frame.position);
	return frame;
}

- (void) triggerFirstScreen
{
	if (_buriedPoint.failOpenType == 1) {
		_buriedPoint.firstScreenTimeMills = ([[NSDate date] timeIntervalSince1970] * 1000 - _buriedPoint.beginOpen) / 1000.0f;
	}
}

- (BOOL)setupScaler {
	
	[self closeScaler];
	_pictureValid = avpicture_alloc(&_picture, PIX_FMT_YUV420P, _videoCodecCtx->width, _videoCodecCtx->height) == 0;
	if (!_pictureValid) {
		return NO;
	}
	_swsContext = sws_getCachedContext(_swsContext, _videoCodecCtx->width, _videoCodecCtx->height, _videoCodecCtx->pix_fmt, _videoCodecCtx->width, _videoCodecCtx->height, PIX_FMT_YUV420P, SWS_FAST_BILINEAR, NULL, NULL, NULL);
	return _swsContext != NULL;
}

- (void) addBufferStatusRecord:(NSString*) statusFlag
{
	if ([@"F" isEqualToString:statusFlag] && [[_buriedPoint.bufferStatusRecords lastObject] hasPrefix:@"F_"]) {
		return;
	}
	float timeInterval = ([[NSDate date] timeIntervalSince1970] * 1000 - _buriedPoint.beginOpen) / 1000.0f;
	[_buriedPoint.bufferStatusRecords addObject:[NSString stringWithFormat:@"%@_%.3f", statusFlag, timeInterval]];
}

- (void)closeFile {
	NSLog(@"Enter closeFile...");
	if (_buriedPoint.failOpenType == 1) {
		_buriedPoint.duration = ([[NSDate date] timeIntervalSince1970] * 1000 - _buriedPoint.beginOpen) / 1000.0f;
		[self interrupt];
		[self closeAudioStream];
		[self closeVideoStream];
	}
}

- (void)interrupt {
	_subscribeTimeOutTimeInSecs = -1;
	_interrupted = YES;
	_isSubscribe = NO;
}

- (void)closeAudioStream {
	_audioStreamIndex = -1;
	if (_swrBuffer) {
		free(_swrBuffer);
		_swrBuffer = NULL;
		_swrBufferSize = 0;
	}
	
	if (_swrContex) {
		swr_free(&_swrContex);
		_swrContex = NULL;
	}
	
	if (_audioFrame) {
		av_free(_audioFrame);
		_audioFrame = NULL;
	}
	
	if (_audioCodecCtx) {
		avcodec_close(_audioCodecCtx);
		_audioCodecCtx = NULL;
	}
}

- (void)closeVideoStream {
	_videoStreamIndex = -1;
	[self closeScaler];
}

- (void)closeScaler {
	if (_swsContext) {
		sws_freeContext(_swsContext);
		_swsContext = NULL;
	}
	
	
}

- (PDDBuriedPoint*)getBuriedPoint
{
	return _buriedPoint;
}

- (NSUInteger)frameWidth {
	return _videoCodecCtx ?_videoCodecCtx->width : 0;
}

- (NSUInteger)frameHeight {
	return _videoCodecCtx ?_videoCodecCtx->height : 0;
}

- (NSUInteger) channels;
{
	return _audioCodecCtx ? _audioCodecCtx->channels : 0;
}

- (CGFloat) sampleRate;
{
	return _audioCodecCtx ? _audioCodecCtx->sample_rate : 0;
}

- (BOOL) validVideo;
{
	return _videoStreamIndex != -1;
}

- (BOOL) validAudio;
{
	return _audioStreamIndex != -1;
}

- (CGFloat) getVideoFPS;
{
	return _fps;
}

- (BOOL) isEOF;
{
	return _isEOF;
}

- (BOOL) isSubscribed;
{
	return _isSubscribe;
}

- (CGFloat) getDuration;
{
	if(_formatCtx){
		if(_formatCtx->duration == AV_NOPTS_VALUE){
			return -1;
		}
		return _formatCtx->duration / AV_TIME_BASE;
	}
	return -1;
}

- (void) dealloc;
{
	NSLog(@"VideoDecoder Dealloc...");
}

@end
