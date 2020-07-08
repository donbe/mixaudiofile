//
//  JYAudioRecorder.m
//  TestRecord
//
//  Created by donbe on 2020/4/13.
//  Copyright © 2020 donbe. All rights reserved.
//

#import "JYAudioRecorder.h"
#import <UIKit/UIKit.h>


@interface JYAudioRecorder()<AVAudioPlayerDelegate>
{
}
@property(nonatomic,strong)AVAudioEngine *audioEngine;
@property(nonatomic,strong)AVAudioPlayerNode *audioPlayerNode;

@property(nonatomic) AVAudioPlayer *audioPlayer;
@property(nonatomic) AVAudioPlayer *bgmPlayer;

@property(nonatomic) NSTimeInterval pausePoint;

@property(nonatomic,strong,readwrite)NSString *recordFilePath; //录制的音频保存地址
@property(nonatomic)AudioFileID recordFileID;

@property(nonatomic,weak)NSTimer *playTimer;

@property(nonatomic,readwrite)NSTimeInterval recordDuration;
@property(nonatomic,readwrite)BOOL isRec; //录制状态
@property(nonatomic,readwrite)BOOL isPlaying; //播放状态
@property(nonatomic,readwrite)JYAudioRecorderState state; //播放器状态

@property(nonatomic,readwrite)BOOL recordWithHeadphone; //录音时，是否使用了有线耳机录制

@property(nonatomic,strong,nullable)NSError *error; //发生错误后，从这里获取错误信息


@end


@implementation JYAudioRecorder

-(instancetype)initWithSampleRate:(int)sampleRate{
    self = [super init];
    if (self) {
        
        self.bgmVolume = 1.0;
        
        self.recordFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16 sampleRate:sampleRate channels:1 interleaved:true];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionInterruptionNotification:) name:AVAudioSessionInterruptionNotification object:nil];
    }
    return self;
}


#pragma mark -
-(BOOL)startRecord{
    return [self startRecordAtTime:0];
}


-(BOOL)startRecordAtTime:(NSTimeInterval)time{
    
    if (self.isRec || self.isPlaying) {
        [self writeError:@"正在录制或者播放中"];
        return NO;
    }
    
    self.error = nil;
    
    // 不能大于录制时间
    time = MIN(time, self.recordDuration);
    
    // 解决精度问题
    time = round(time * 100)/100;
    
    // 设置AVAudioSession
    NSError *error;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error:&error];
    assert(error == nil);
    if (error) {
        [self writeError:error.localizedFailureReason];
        return NO;
    }
    
    [[AVAudioSession sharedInstance] setMode:AVAudioSessionModeSpokenAudio error:&error];
    assert(error == nil);
    if (error) {
        [self writeError:error.localizedFailureReason];
        return NO;
    }
    
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    assert(error == nil);
    if (error) {
        [self writeError:error.localizedFailureReason];
        return NO;
    }
    
    
    // 创建播放文件
    AVAudioFile *bgmFile;
    if (self.bgmPath) {
        bgmFile = [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:self.bgmPath] error:&error];
        assert(error == nil);
        if (error) {
            [self writeError:error.localizedFailureReason];
            return NO;
        }
    }
    
    
    
    // 继续录音的情况，计算从多少byte开始截断,并且确保截断不会截断在一个帧的中间
    unsigned int bytePreFrame = self.recordFormat.channelCount * [self bytesOfCommonFormat:self.recordFormat.commonFormat];
    UInt32 truncateByte = ((UInt32)(time * self.recordFormat.sampleRate * bytePreFrame)) / bytePreFrame * bytePreFrame;
    
    
    // 打开文件，处理截断
    if (truncateByte>0) {
        
        // 截断
        if (time < self.recordDuration) {
            BOOL ret = [self truncateFileForFormat:self.recordFormat truncateByte:truncateByte];
            if (!ret) {
                return NO;
            }
        }
        
        // 打开文件
        OSStatus stats = AudioFileOpenURL((__bridge CFURLRef)[NSURL fileURLWithPath:self.recordFilePath], kAudioFileReadWritePermission, kAudioFileWAVEType, &_recordFileID);
        assert(stats==0);
        if (stats !=0) {
            [self writeError:@"打开文件失败"];
            return NO;
        }
        
    }else{
        
        // 创建文件
        OSStatus stats = AudioFileCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:self.recordFilePath], kAudioFileWAVEType, self.recordFormat.streamDescription, kAudioFileFlags_EraseFile, &_recordFileID);
        assert(stats==0);
        if (stats !=0) {
            [self writeError:@"创建文件失败"];
            return NO;
        }
    }
    
    
    // 重新设置录制时间
    self.recordDuration = time;
    
    
    // 创建格式转换器
    AVAudioConverter *audioConverter = [[AVAudioConverter alloc] initFromFormat:[self.audioEngine.inputNode outputFormatForBus:0] toFormat:self.recordFormat];

    self.isRec = YES;
    
    // 安装tap
    __block SInt64 inStartingByte = truncateByte;
    __weak JYAudioRecorder *weakSelf = self;
    [self.audioEngine.inputNode installTapOnBus:0 bufferSize:2048 format:nil block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {

        // 文件可能已经被关闭
        if (weakSelf.recordFileID == nil){
            [self stopRecord];
            [self writeError:@"文件未打开"];
            return;
        }
        
        // 控制最大录音时间
        if (self.maxRecordTime > 0 && weakSelf.recordDuration >= self.maxRecordTime) {
            [self stopRecord];
            return;
        }
        
        // 进行格式换砖
        float ratio = [[buffer format] sampleRate]/weakSelf.recordFormat.sampleRate;
        UInt32 capacity = buffer.frameCapacity/ratio;
        AVAudioPCMBuffer *convertedBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:weakSelf.recordFormat frameCapacity:capacity];
        AVAudioConverterInputBlock inputBlock = ^(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus* outStatus){
            *outStatus = AVAudioConverterInputStatus_HaveData;
            return buffer;
        };
        NSError *error;
        [audioConverter convertToBuffer:convertedBuffer error:&error withInputFromBlock:inputBlock];
        assert(error == nil);
        if (error) {
            [self stopRecord];
            [self writeError:@"格式转换失败"];
            return;
        }
        

        // 这样可以让回调达到每秒20次
        buffer.frameLength = buffer.frameLength/2;
        convertedBuffer.frameLength = convertedBuffer.frameLength/2;
        
        
        // 写文件
        UInt32 length = convertedBuffer.frameLength * weakSelf.recordFormat.channelCount * [weakSelf bytesOfCommonFormat:weakSelf.recordFormat.commonFormat];
        OSStatus status = AudioFileWriteBytes(weakSelf.recordFileID, NO, inStartingByte, &length, convertedBuffer.int16ChannelData[0]);
        assert(status == noErr);
        if (status != noErr){
            [self stopRecord];
            [self writeError:@"文件写入失败"];
            return;
        }
        
        
        // 总写入字节数
        inStartingByte += length;
        
        
        // 计算总录制时长，回调
        weakSelf.recordDuration = inStartingByte / weakSelf.recordFormat.sampleRate / weakSelf.recordFormat.channelCount / [weakSelf bytesOfCommonFormat:weakSelf.recordFormat.commonFormat];
        if ([weakSelf.delegate respondsToSelector:@selector(recorderBuffer:duration:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.delegate recorderBuffer:convertedBuffer duration:weakSelf.recordDuration];
            });
        }
 
    }];
    
    
    // 播放设置
    AVAudioFramePosition startFrame = (time + self.bgmPlayOffset) * bgmFile.fileFormat.sampleRate;
    if (bgmFile && startFrame < [bgmFile length]) {
        
        [self.audioEngine attachNode:self.audioPlayerNode];
        
        // 计算播放的帧数
        AVAudioFrameCount frameCount = (AVAudioFrameCount)([bgmFile length] - startFrame);
        if (self.bgmPlayLength > 0) {
            frameCount = MIN(MAX(0,self.bgmPlayLength - time) * bgmFile.fileFormat.sampleRate, frameCount);
        }
        
        // 连接背景音乐node
        [self.audioEngine connect:self.audioPlayerNode to:self.audioEngine.mainMixerNode format:bgmFile.processingFormat];
        
        // 设置播放区间
        if (frameCount>0) {
            [self.audioPlayerNode scheduleSegment:bgmFile startingFrame:startFrame frameCount:frameCount atTime:nil completionHandler:^{
                NSLog(@"player complete");
            }];
        }
        
        //准备一秒的缓存
        [self.audioPlayerNode prepareWithFrameCount:(AVAudioFrameCount)bgmFile.fileFormat.sampleRate];
    }
    

    if ([JYAudioRecorder detectingHeadphones]) {
        [self.audioEngine connect:self.audioEngine.inputNode to:self.audioEngine.mainMixerNode format:nil];
    }
    
    // 启动引擎
    BOOL result = [self.audioEngine startAndReturnError:&error];
    assert(error == nil && result);
    if (error != nil || !result) {
        [self stopRecord];
        if (error) {
            [self writeError:error.localizedFailureReason];
        }else{
            [self writeError:@"启动录音引擎失败"];
        }
        
        return NO;
    }
    
    // 开始播放
    if (bgmFile && startFrame < [bgmFile length]) {
        self.audioPlayerNode.volume = self.bgmVolume;
        [self.audioPlayerNode play];
    }
    
    // 检测是否插入耳机
    self.recordWithHeadphone = [JYAudioRecorder detectingHeadphones];
    
    return YES;
}

-(void)stopRecord{
    if (self.isRec) {
        
        [self.audioEngine disconnectNodeOutput:self.audioEngine.inputNode];
        
        if (self.audioPlayerNode.playing) {
            [self.audioPlayerNode stop];
        }
        
        @try { // 避免因为之前没有connect node导致的闪退
            [self.audioEngine disconnectNodeInput:self.audioPlayerNode];
            [self.audioEngine disconnectNodeOutput:self.audioPlayerNode];
            [self.audioEngine detachNode:self.audioPlayerNode];
        } @catch (NSException *exception) {
            NSLog(@"%@",exception);
        }
        
        self.audioPlayerNode = nil;
        
        [self.audioEngine stop];
        [self.audioEngine.inputNode removeTapOnBus:0];
        self.audioEngine = nil;
        
        AudioFileClose(self.recordFileID);
        self.recordFileID = nil;
        
        [[AVAudioSession sharedInstance] setActive:NO error:nil];
        
        self.isRec = NO;
    }
}

// 这是一个默认的
- (NSString *)recordFilePath {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [dir stringByAppendingString:@"/recording_file_200422.wav"];
}

#pragma  mark -

-(BOOL)play{
    return [self playAtTime:0];
}

-(BOOL)playAtTime:(NSTimeInterval)time{
        
    if (time > self.recordDuration) {
        return NO;
    }
    
    if (self.isRec) {
        return NO;
    }

    if (self.recordFilePath == nil) {
        return NO;
    }
    
    self.error = nil;
    
    if (!self.isPlaying) {
        NSError *error;
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
        assert(error == nil);
        if (error) {
            [self writeError:error.localizedFailureReason];
            return NO;
        }

        [[AVAudioSession sharedInstance] setActive:YES error:&error];
        assert(error == nil);
        if (error) {
            [self writeError:error.localizedFailureReason];
            return NO;
        }
        
        self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:self.recordFilePath] error:&error];
        assert(error == nil);
        if (error) {
            [self writeError:error.localizedFailureReason];
            return NO;
        }
        
        self.bgmPlayer = nil;
        if (self.bgmPath) {
            self.bgmPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:self.bgmPath] error:&error];
            assert(error == nil);
            if (error) {
                [self writeError:error.localizedFailureReason];
                return NO;
            }
        }
        
        self.audioPlayer.delegate = self;
        self.bgmPlayer.delegate = self;
        
        self.bgmPlayer.volume = self.bgmVolume;
    }
    

    self.audioPlayer.currentTime = time;
    self.bgmPlayer.currentTime = time + self.bgmPlayOffset;
    
    if (!self.audioPlayer.isPlaying) {
        // 同步两个播放器
        NSTimeInterval shortStartDelay = 0.01;
        NSTimeInterval shortBGMStartDelay = [JYAudioRecorder bgmLatency];
        NSTimeInterval now = self.audioPlayer.deviceCurrentTime;
        
        [self.audioPlayer playAtTime: now + shortStartDelay];
        [self.bgmPlayer playAtTime: now + shortStartDelay + shortBGMStartDelay];
        
    }
    
    self.isPlaying = YES;
    [self startTimer];
    
    return YES;
}

-(void)pausePlay{
    if (self.isPlaying) {
        
        [self.audioPlayer stop];
        [self.bgmPlayer stop];
        
        [self stopTimer];
        
        _isPlaying = NO;
        self.state = JYAudioRecorderStatePause;
    }
}

-(void)resumePlay{
    if (self.state == JYAudioRecorderStatePause) {
        
        [self.audioPlayer prepareToPlay];
        [self.bgmPlayer prepareToPlay];
        [self.audioPlayer play];
        [self.bgmPlayer play];
        
        [self startTimer];
        
        _isPlaying = YES;
        self.state = JYAudioRecorderStatePlaying;
    }
}

-(void)stopPlay{
    if (self.isPlaying) {
        
        [self.audioPlayer stop];
        [self.bgmPlayer stop];
        
        [[AVAudioSession sharedInstance] setActive:NO error:nil];
        
        self.isPlaying = NO;
        [self stopTimer];
    }
}


#pragma mark - get/set
-(void)setIsRec:(BOOL)isRec{
    if (isRec != _isRec) {
        _isRec = isRec;
        
        if (isRec) {
            self.state = JYAudioRecorderStateRecording;
            if ([self.delegate respondsToSelector:@selector(recorderStart)]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate recorderStart];
                });
            }
        }else{
            self.state = JYAudioRecorderStateNormal;
            if ([self.delegate respondsToSelector:@selector(recorderFinish)]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate recorderFinish];
                });
            }
        }
    }
}

-(void)setIsPlaying:(BOOL)isPlaying{
    if (_isPlaying != isPlaying) {
        _isPlaying = isPlaying;
        
        if (isPlaying) {
            self.state = JYAudioRecorderStatePlaying;
            if ([self.delegate respondsToSelector:@selector(recorderPlayingStart)]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate recorderPlayingStart];
                });
            }
        }else{
            self.state = JYAudioRecorderStateNormal;
            if ([self.delegate respondsToSelector:@selector(recorderPlayingFinish)]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate recorderPlayingFinish];
                });
            }
        }
        
    }
}

-(void)setState:(JYAudioRecorderState)state{
    if (state != _state) {
        _state = state;
        if ([self.delegate respondsToSelector:@selector(recorderStateChange:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate recorderStateChange:state];
            });
        }
    }
}

-(NSTimeInterval)currentPlayTime{
    return self.audioPlayer.currentTime;
}


-(AVAudioEngine *)audioEngine{
    if (_audioEngine == nil) {
        _audioEngine = [AVAudioEngine new];
    }
    return _audioEngine;
}

-(AVAudioPlayerNode *)audioPlayerNode{
    if (_audioPlayerNode == nil) {
        _audioPlayerNode = [AVAudioPlayerNode new];
    }
    return _audioPlayerNode;
}

#pragma mark - AVAudioPlayerDelegate
-(void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag{
    NSLog(@"audioPlayerDidFinishPlaying");
    if (player == self.audioPlayer) {
        [self stopPlay];
    }
}

-(void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error{
    NSLog(@"audioPlayerDecodeErrorDidOccur");
    if (player == self.audioPlayer) {
        [self stopPlay];
    }
}

#pragma mark - AVAudioSessionInterruptionNotification
-(void)audioSessionInterruptionNotification:(NSNotification *)notification{
    AVAudioSessionInterruptionType type = [notification.userInfo[AVAudioSessionInterruptionTypeKey] intValue];
    if (type == AVAudioSessionInterruptionTypeBegan) {
        NSLog(@"Interruption Began");
        [self stopRecord];
        [self stopPlay];
    }else{
        NSLog(@"Interruption end");
    }
}

#pragma mark - NStimer
- (void)startTimer{
    [self stopTimer];
    self.playTimer = [NSTimer scheduledTimerWithTimeInterval:0.025 target:self selector:@selector(playTimerCB) userInfo:nil repeats:YES];
}

- (void)stopTimer {
    [self.playTimer invalidate];
    self.playTimer = nil;
}

-(void)playTimerCB{
    if ([self.delegate respondsToSelector:@selector(recorderPlayingTime:duration:)]) {
        [self.delegate recorderPlayingTime:self.audioPlayer.currentTime duration:self.audioPlayer.duration];
        if (self.bgmPlayLength > 0 && self.bgmPlayer.currentTime > self.bgmPlayOffset+self.bgmPlayLength) {
            [self.bgmPlayer stop];
        }
    }
}

#pragma mark - public
- (BOOL)truncateFile:(NSTimeInterval)time {
    
    // 不能大于录制时间
    time = MIN(time, self.recordDuration);
    
    // 解决精度问题
    time = round(time * 100)/100;
    
    // 继续录音的情况，计算从多少byte开始截断,并且确保截断不会截断在一个帧的中间
    unsigned int bytePreFrame = self.recordFormat.channelCount * [self bytesOfCommonFormat:self.recordFormat.commonFormat];
    UInt32 truncateByte = ((UInt32)(time * self.recordFormat.sampleRate * bytePreFrame)) / bytePreFrame * bytePreFrame;
    
    // 截断
    BOOL ret = [self truncateFileForFormat:self.recordFormat truncateByte:truncateByte];
    if (!ret) {
        return NO;
    }
    
    // 重新设置录制时间
    self.recordDuration = time;
    
    return YES;
}

#pragma mark - help

- (BOOL)truncateFileForFormat:(AVAudioFormat *)format truncateByte:(UInt32)truncateByte {
    OSStatus stats = AudioFileOpenURL((__bridge CFURLRef)[NSURL fileURLWithPath:self.recordFilePath], kAudioFileReadPermission, kAudioFileWAVEType, &_recordFileID);
    assert(stats==0);
    if (stats != 0) {
        [self writeError:@"打开录音文件失败"];
        return NO;
    }
    
    // 临时创建一个文件
    AudioFileID tmpfileid;
    // 设置录音文件地址
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *tmpFilePath = [dir stringByAppendingString:@"/recording_tempfile.wav"];
    stats = AudioFileCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:tmpFilePath], kAudioFileWAVEType, format.streamDescription, kAudioFileFlags_EraseFile, &tmpfileid);
    assert(stats==0);
    if (stats != 0) {
        [self writeError:@"创建临时文件失败"];
        return NO;
    }
    
    // 如果一次性缓存太多，会闪退
    const int bytesPreLoop = 32000*5; // 每次拷贝字节数
    int loopCount = ceil(truncateByte / 1.0 / bytesPreLoop); //总拷贝次数
    char buf[bytesPreLoop]; //缓存
    UInt32 startpos = 0; //开始拷贝的位置
    UInt32 numofbytes = 0; //结束拷贝的位置
    
    for (int i=0; i<loopCount; i++) {
        
        startpos = i*bytesPreLoop;
        numofbytes = MIN(bytesPreLoop, truncateByte-startpos);
        
        AudioFileReadBytes(_recordFileID, NO, startpos, &numofbytes, buf);
        AudioFileWriteBytes(tmpfileid, NO, startpos, &numofbytes, buf);
    }
    
    AudioFileClose(_recordFileID);
    AudioFileClose(tmpfileid);
    
    //删除源文件
    NSError *err;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtPath:self.recordFilePath error:&err];
    assert(err==nil);
    if (err) {
        [self writeError:@"删除文件失败"];
        return NO;
    }
    
    //移动文件
    [fileManager moveItemAtPath:tmpFilePath toPath:self.recordFilePath error:&err];
    assert(err==nil);
    if (err) {
        [self writeError:@"移动文件失败"];
        return NO;
    }
    
    return YES;
    
}


-(void)print_wav_head_info{
    
    NSData *d = [[NSFileManager defaultManager] contentsAtPath:self.recordFilePath];
    
    // RIFF
    const char *bs = (char *)d.bytes;
    for (int i=0; i<4; i++) {
        printf("%c",bs[0]);
        bs++;
    }
    printf("\r");
    
    int *bsi = (int *)bs;
    printf("chunk size: %d",bsi[0]);
    
    bs+=8;
    
    // fmt
    printf("\r");
    printf("\r");
    for (int i=0; i<4; i++) {
        printf("%c",bs[0]);
        bs++;
    }
    
    bsi = (int *)bs;
    printf("\r");
    printf("sub chunk size: %d",bsi[0]);
    bs+=20;
    
    // FLLR
    printf("\r");
    printf("\r");
    for (int i=0; i<4; i++) {
        printf("%c",bs[0]);
        bs++;
    }
    
    bsi = (int *)bs;
    printf("\r");
    printf("FLLR chunk size: %d",bsi[0]);
    bs+=4;
    bs+=4044;
    
    
    // data
    printf("\r");
    printf("\r");
    for (int i=0; i<4; i++) {
        printf("%c",bs[0]);
        bs++;
    }
    
    bsi = (int *)bs;
    printf("\r");
    printf("data chunk size: %d",bsi[0]);
}

+(BOOL)isIphoneX{
    BOOL isPhoneX = NO;
         if (@available(iOS 11.0, *)) {
             isPhoneX = [[UIApplication sharedApplication].windows firstObject].safeAreaInsets.bottom > 0.0;
        }
    return isPhoneX;
}

-(unsigned int)bytesOfCommonFormat:(AVAudioCommonFormat)format{
    switch (format) {
        case AVAudioPCMFormatInt16:
            return 2;
        case AVAudioPCMFormatInt32:
            return 4;
        case AVAudioPCMFormatFloat32:
            return 4;
        case AVAudioPCMFormatFloat64:
            return 8;
        default:
            assert(0);
            return 2;
    }
}



/// 判断是否插入有线耳机
+(BOOL)detectingHeadphones{
    AVAudioSessionRouteDescription *currentRoute = [AVAudioSession sharedInstance].currentRoute;
    if (currentRoute == nil) {
        return NO;
    }
    
    for (AVAudioSessionPortDescription *desc in currentRoute.outputs) {
        if ([desc.portType isEqualToString:AVAudioSessionPortHeadphones]) {
            return YES;
        }
    }
    return NO;
}


/// 设置错误信息
/// @param msg 具体错误信息
-(void)writeError:(NSString *)msg{
    self.error = [NSError errorWithDomain:@"JYAudioRecorderError" code:-1 userInfo:@{NSLocalizedDescriptionKey : msg ? msg : @""}];
}

#pragma mark -
-(void)dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    NSLog(@"recorder dealloc");
}

#pragma mark -
+(NSTimeInterval)bgmLatency{
    return [self isIphoneX] ? 0.17 : 0.20;
}

@end



