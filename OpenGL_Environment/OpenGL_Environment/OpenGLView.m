//
//  OpenGLView.m
//  OpenGL_Environment
//
//  Created by 郝一鹏 on 2018/10/14.
//  Copyright © 2018 郝一鹏. All rights reserved.
//

#import "OpenGLView.h"
#import <OpenGLES/ES2/gl.h>

@implementation OpenGLView {
	dispatch_queue_t _contextQueue;
	GLuint _frameBuffer;
	GLuint _renderBuffer;
}

+ (Class)layerClass {
	return [CAEAGLLayer class];
}

- (id)initWithFrame:(CGRect)frame {
	if (self = [super initWithFrame:frame]) {
		CAEAGLLayer *eaglLayer = (CAEAGLLayer *)[self layer];
		NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:NO], kEAGLDrawablePropertyRetainedBacking, kEAGLColorFormatRGB565, kEAGLDrawablePropertyColorFormat, nil];
		[eaglLayer setOpaque:YES];
		[eaglLayer setDrawableProperties:dict];
		
		_contextQueue = dispatch_queue_create("com.pandada.video_player.videoRenderQueue", NULL);
		
		dispatch_sync(_contextQueue, ^{
			// 1. 创建OpenGL ES上下文
			EAGLContext *_context;
			_context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
			// 2.绑定操作
			[EAGLContext setCurrentContext:_context];
			
			// 3. 创建帧缓冲区
			glGenFramebuffers(1, &_frameBuffer);
			glGenRenderbuffers(1, &_renderBuffer);
			glBindFramebuffer(GL_FRAMEBUFFER, _frameBuffer);
			glBindRenderbuffer(GL_RENDERBUFFER, _renderBuffer);
			[_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];
//			glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingHeight);
			glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _renderBuffer);
			GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
			if (status != GL_FRAMEBUFFER_COMPLETE) {;
				//
				glTexImage2D(<#GLenum target#>, <#GLint level#>, <#GLint internalformat#>, <#GLsizei width#>, <#GLsizei height#>, <#GLint border#>, <#GLenum format#>, <#GLenum type#>, <#const GLvoid *pixels#>)
			}
			
		});
	}
	return self;
}

@end
