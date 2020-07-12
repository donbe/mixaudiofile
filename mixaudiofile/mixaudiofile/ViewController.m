//
//  ViewController.h
//  mixaudiofile
//
//  Created by donbe on 2020/7/8.
//

#import "ViewController.h"
#import "JYAudioRecorder.h"
#import <AVFoundation/AVFoundation.h>
#import <mobileffmpeg/MobileFFmpegConfig.h>
#import <mobileffmpeg/MobileFFprobe.h>


@interface ViewController ()<JYAudioRecorderDelegate>

@property(nonatomic,strong)JYAudioRecorder *recorder;
@property(nonatomic,strong)UIScrollView *scrollView;
@property(nonatomic)int waveformindex;

@property(nonatomic,strong)NSData *buff;

@end

@implementation ViewController


- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor whiteColor];
    
    // 请求授权
    if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] != AVAuthorizationStatusAuthorized) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
            
        }];
    }
    
    
   
    
    [self addButtonWith:@"开始录音" frame:CGRectMake(80, 120, 100, 50) action:@selector(recordBtnAction)];
    [self addButtonWith:@"停止录音" frame:CGRectMake(200, 120, 100, 50) action:@selector(stopBtnAction)];

    [self addButtonWith:@"合成背景音" frame:CGRectMake(80, 190, 100, 50) action:@selector(mixBtnAction)];
    [self addButtonWith:@"播放合成音" frame:CGRectMake(200, 190, 100, 50) action:@selector(playBtnAction)];
    
    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 650, [[UIApplication sharedApplication].windows firstObject].frame.size.width, 50)];
    [self.view addSubview:self.scrollView];
    self.scrollView.backgroundColor = [UIColor cyanColor];
}

-(void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
}

-(void)recordBtnAction{
    [self.recorder startRecord];
}

-(void)stopBtnAction{
    [self.recorder stopRecord];
}

-(void)mixBtnAction{
    NSString *i1 =  [[[NSBundle mainBundle] URLForResource:@"123" withExtension:@"mp3"] relativePath];
    NSString *i2 = self.recorder.recordFilePath;
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = [paths objectAtIndex:0];
    NSString *output = [docDir stringByAppendingString:@"/output.mp3"];
    
    
    NSLog(@"%@",self.recorder.recordFilePath);
    int rc = [MobileFFmpeg execute: [NSString stringWithFormat:@" -y -i %@ -i %@ -filter_complex amerge %@",i1,i2,output]];

    if (rc == RETURN_CODE_SUCCESS) {
        NSLog(@"Command execution completed successfully.\n");
    } else if (rc == RETURN_CODE_CANCEL) {
        NSLog(@"Command execution cancelled by user.\n");
    } else {
        NSLog(@"Command execution failed with rc=%d and output=%@.\n", rc, [MobileFFmpegConfig getLastCommandOutput]);
    }
    
}

-(void)playBtnAction{
    int rc = [MobileFFmpegConfig getLastReturnCode];
    NSString *output = [MobileFFmpegConfig getLastCommandOutput];

//    if (rc == RETURN_CODE_SUCCESS) {
//        NSLog(@"Command execution completed successfully.\n");
//    } else if (rc == RETURN_CODE_CANCEL) {
//        NSLog(@"Command execution cancelled by user.\n");
//    } else {
//        NSLog(@"Command execution failed with rc=%d and output=%@.\n", rc, output);
//    }
    NSLog(@"Command execution failed with rc=%d and output=%@.\n", rc, output);
}


#pragma mark -
-(JYAudioRecorder *)recorder{
    if (_recorder == nil) {
        // iphone11机型，采样率低的话，会有电流声
        int sample = 16000;
        _recorder = [[JYAudioRecorder alloc] initWithSampleRate:sample];
        _recorder.delegate = self;
    }
    return _recorder;
}

#pragma mark - private
- (void)addButtonWith:(NSString *)title frame:(CGRect)frame action:(SEL)action {
    UIButton *record = [[UIButton alloc] initWithFrame:frame];
    record.layer.borderColor = [UIColor blackColor].CGColor;
    record.layer.borderWidth = 0.5;
    [record setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [record setTitle:title forState:UIControlStateNormal];
    [record addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [record setTitleColor:[UIColor redColor] forState:UIControlStateHighlighted];
    [self.view addSubview:record];
}

#pragma mark -
-(void)recorderStart{

    NSLog(@"开始录制");
}

-(void)recorderFinish{
    NSLog(@"结束录制");
}

-(void)recorderPlayingStart{
    NSLog(@"开始播放");
}

-(void)recorderPlayingFinish{
    NSLog(@"结束播放");
}

-(void)recorderBuffer:(AVAudioPCMBuffer *)buffer duration:(NSTimeInterval)duration{
    NSLog(@"recorderBuffer %f", duration);
}

-(void)recorderPlayingTime:(NSTimeInterval)time duration:(NSTimeInterval)duration{
    NSLog(@"play time: %f / %f",time,duration);
}

-(void)recorderStateChange:(JYAudioRecorderState)state{
    NSLog(@"recorderStateChange:%ld",(long)state);
}

-(void)mp32wav:(NSString *)inpath outfile:(NSString *)outpath{
    
}
@end
