//
//  ViewController.m
//  AUPlayer
//
//  Created by 郝一鹏 on 2018/9/26.
//  Copyright © 2018 郝一鹏. All rights reserved.
//

#import "ViewController.h"
#import "CommonUtils.h"
#import "AUGraphPlayer.h"

@interface ViewController ()

@property (nonatomic, assign) BOOL isAcc;

@end

@implementation ViewController
{
	AUGraphPlayer *_graphPlayer;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
	_isAcc = NO;
}
- (IBAction)playMusic:(id)sender {
	
	if (_graphPlayer) {
		[_graphPlayer stop];
	}
	
	NSString *filePath = [CommonUtils bundlePath:@"0fe2a7e9c51012210eaaa1e2b103b1b1.m4a"];
	_graphPlayer = [[AUGraphPlayer alloc] initWithFilePath:filePath];
	[_graphPlayer play];
}

- (IBAction)stopMusic:(id)sender {
	NSLog(@"Stop Music...");
	[_graphPlayer stop];
}

- (IBAction)switchMusic:(id)sender {
	_isAcc = !_isAcc;
	[_graphPlayer setInputSource:_isAcc];
}

@end
