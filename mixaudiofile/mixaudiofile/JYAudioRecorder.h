//
//  JYAudioRecorder.h
//  TestRecord
//
//  Created by donbe on 2020/4/13.
//  Copyright © 2020 donbe. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN


typedef NS_ENUM(NSInteger, JYAudioRecorderState) {
    JYAudioRecorderStateNormal,             // 初始状态
    JYAudioRecorderStateRecording,          // 录制中
    JYAudioRecorderStatePlaying,            // 播放中
    JYAudioRecorderStatePause,              // 播放暂停中
};


@protocol JYAudioRecorderDelegate <NSObject>

@optional


/// 录制时，麦克风输出回调
/// @param buffer  缓存
/// @param duration  录制的时长
-(void)recorderBuffer:(AVAudioPCMBuffer * _Nonnull)buffer duration:(NSTimeInterval)duration;

/// 播放时，时间回调
/// @param time 正在播放的时间点
/// @param duration 总时间
-(void)recorderPlayingTime:(NSTimeInterval)time duration:(NSTimeInterval)duration;

/// 播放开始
-(void)recorderPlayingStart;

/// 播放结束
-(void)recorderPlayingFinish;

/// 录制开始
-(void)recorderStart;

/// 录制结束
-(void)recorderFinish;


/// 状态发生变化
/// @param state 当前状态
-(void)recorderStateChange:(JYAudioRecorderState)state;

@end



@interface JYAudioRecorder : NSObject

@property(nonatomic,strong)AVAudioFormat *recordFormat; //录音保存格式，默认44100，AVAudioPCMFormatInt16，单通道
@property(nonatomic,strong,readonly)NSString *recordFilePath; //录制的音频保存地址

@property(nonatomic,strong)NSString *bgmPath; //背景音地址
@property(nonatomic)float bgmVolume; //背景音音量，默认0.4
@property(nonatomic)NSTimeInterval bgmPlayOffset; //背景音跳过的秒数
@property(nonatomic)NSTimeInterval bgmPlayLength; //背景音播放的秒数


@property(nonatomic,readonly)BOOL isRec; //录制状态
@property(nonatomic,readonly)BOOL isPlaying; //播放状态
@property(nonatomic,readonly)JYAudioRecorderState state; //播放器状态
@property(nonatomic,readonly)BOOL recordWithHeadphone; //录音时，是否使用了有线耳机录制


@property(nonatomic,readonly)NSTimeInterval recordDuration; //录制时长
@property(nonatomic,readonly)NSTimeInterval currentPlayTime; //当前播放时间点

@property(nonatomic)NSTimeInterval maxRecordTime; //最大录制时长，超过这个长度将停止录音

@property(atomic,weak)id<JYAudioRecorderDelegate> delegate;

@property(readonly, nonatomic,strong,nullable)NSError *error; //发生错误后，从这里获取错误信息


/// 初始化
/// @param sampleRate 采样率，只有16000采样率会有降噪效果
-(instancetype)initWithSampleRate:(int)sampleRate;

// 从头开始录音
-(BOOL)startRecord;

// 从某个时间点往后继续录音
-(BOOL)startRecordAtTime:(NSTimeInterval)time;

// 停止录音
-(void)stopRecord;

#pragma mark -
// 播放录音
-(BOOL)play;

// 从某个时间点往后继续播放
-(BOOL)playAtTime:(NSTimeInterval)time;

// 停止播放录音
-(void)stopPlay;

// 暂停播放录音
-(void)pausePlay;

// 继续播放
-(void)resumePlay;

// 截断已录制的音频
- (BOOL)truncateFile:(NSTimeInterval)time;

#pragma mark -
// 给背景音加的延迟秒数
+(NSTimeInterval)bgmLatency;

/// 判断是否插入有线耳机
+(BOOL)detectingHeadphones;

@end

NS_ASSUME_NONNULL_END
