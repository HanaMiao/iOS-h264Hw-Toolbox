//
//  ViewController.m
//  h264v1
//
//  Created by Ganvir, Manish on 3/31/15.
//  Copyright (c) 2015 Ganvir, Manish. All rights reserved.
//
//ref: http://stackoverflow.com/questions/4149963/this-code-to-write-videoaudio-through-avassetwriter-and-avassetwriterinputs-is
//可以直接设置compress参数

#import "ViewController.h"
#import "H264HwEncoderImpl.h"
@import AVFoundation;
@import VideoToolbox;

@interface ViewController ()
{
    H264HwEncoderImpl *h264Encoder;
    AVCaptureSession *captureSession;
    bool startCalled;
    AVCaptureVideoPreviewLayer *previewLayer;
    NSString *h264File;
    int fd;
    NSFileHandle *fileHandle;
    AVCaptureConnection* connection;
    NSURL * sourceFilePath;
    int outputFrameCount;
    int keyFrameCount;
    int videoAppendCount;
    BOOL videoWriterHasInit;
    AVAssetWriter *videoWriter;
    AVAssetWriterInput * videoWriterInput;
    AVAssetWriterInput * audioWriterInput;
}
@property (weak, nonatomic) IBOutlet UIButton *StartStopButton;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    h264Encoder = [H264HwEncoderImpl alloc];
    [h264Encoder initWithConfiguration];
    startCalled = true;
    outputFrameCount = 0;
    keyFrameCount = 0;
    videoWriterHasInit = NO;
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

// Called when start/stop button is pressed
- (IBAction)OnStartStop:(id)sender {
    [self carolWork];
    return;
    if (startCalled)
    {
        [self startCamera];
        startCalled = false;
        [_StartStopButton setTitle:@"Stop" forState:UIControlStateNormal];
    }
    else
    {
        [_StartStopButton setTitle:@"Start" forState:UIControlStateNormal];
        startCalled = true;
        [self stopCamera];
        [h264Encoder End];
    }
    
}

- (void) startCamera
{
    // make input device
    
    NSError *deviceError;
    
    AVCaptureDevice *cameraDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    
    AVCaptureDeviceInput *inputDevice = [AVCaptureDeviceInput deviceInputWithDevice:cameraDevice error:&deviceError];
    
    // make output device
    
    AVCaptureVideoDataOutput *outputDevice = [[AVCaptureVideoDataOutput alloc] init];
    
    NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
    
    NSNumber* val = [NSNumber
                     numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange];
    NSDictionary* videoSettings =
    [NSDictionary dictionaryWithObject:val forKey:key];
    outputDevice.videoSettings = videoSettings;
    
    [outputDevice setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    
    // initialize capture session
    
    captureSession = [[AVCaptureSession alloc] init];
    
    [captureSession addInput:inputDevice];
    [captureSession addOutput:outputDevice];
    
    // begin configuration for the AVCaptureSession
    [captureSession beginConfiguration];
    
    // picture resolution
    [captureSession setSessionPreset:[NSString stringWithString:AVCaptureSessionPreset640x480]];
    
    connection = [outputDevice connectionWithMediaType:AVMediaTypeVideo];
    [self setRelativeVideoOrientation];
    
    NSNotificationCenter* notify = [NSNotificationCenter defaultCenter];
    
    [notify addObserver:self
               selector:@selector(statusBarOrientationDidChange:)
                   name:@"StatusBarOrientationDidChange"
                 object:nil];
    
    
    [captureSession commitConfiguration];
    
    // make preview layer and add so that camera's view is displayed on screen
    
    previewLayer = [AVCaptureVideoPreviewLayer    layerWithSession:captureSession];
    [previewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];

    previewLayer.frame = self.view.bounds;
    [self.view.layer addSublayer:previewLayer];
    
    // go!
    
    [captureSession startRunning];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    h264File = [documentsDirectory stringByAppendingPathComponent:@"test.h264"];
    [fileManager removeItemAtPath:h264File error:nil];
    [fileManager createFileAtPath:h264File contents:nil attributes:nil];
    
    // Open the file using POSIX as this is anyway a test application
    //fd = open([h264File UTF8String], O_RDWR);
    fileHandle = [NSFileHandle fileHandleForWritingAtPath:h264File];
    
    [h264Encoder initEncode:480 height:640];
    h264Encoder.delegate = self;
    
    
    
}
- (void)statusBarOrientationDidChange:(NSNotification*)notification {
    [self setRelativeVideoOrientation];
}

- (void)setRelativeVideoOrientation {
      switch ([[UIDevice currentDevice] orientation]) {
        case UIInterfaceOrientationPortrait:
#if defined(__IPHONE_8_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_8_0
        case UIInterfaceOrientationUnknown:
#endif
            connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            connection.videoOrientation =
            AVCaptureVideoOrientationPortraitUpsideDown;
            break;
        case UIInterfaceOrientationLandscapeLeft:
            connection.videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
            break;
        case UIInterfaceOrientationLandscapeRight:
            connection.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
            break;
        default:
            break;
    }
}
- (void) stopCamera
{
    [captureSession stopRunning];
    [previewLayer removeFromSuperlayer];
    //close(fd);
    [fileHandle closeFile];
    fileHandle = NULL;
}
-(void) captureOutput:(AVCaptureOutput*)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection*)connection

{
    //CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer( sampleBuffer );
    
    //CGSize imageSize = CVImageBufferGetEncodedSize( imageBuffer );
    
    // also in the 'mediaSpecific' dict of the sampleBuffer
    
    NSLog( @"frame captured at ");
    [h264Encoder encode:sampleBuffer];
    
}

#pragma mark -  H264HwEncoderImplDelegate delegare

- (void)gotSpsPps:(NSData*)sps pps:(NSData*)pps
{
    NSLog(@"gotSpsPps %d %d", (int)[sps length], (int)[pps length]);
    //[sps writeToFile:h264File atomically:YES];
    //[pps writeToFile:h264File atomically:YES];
   // write(fd, [sps bytes], [sps length]);
    //write(fd, [pps bytes], [pps length]);
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1; //string literals have implicit trailing '\0'
    NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
    [fileHandle writeData:ByteHeader];
    [fileHandle writeData:sps];
    [fileHandle writeData:ByteHeader];
    [fileHandle writeData:pps];

}
- (void)gotEncodedData:(NSData*)data isKeyFrame:(BOOL)isKeyFrame
{
    NSString * log = [NSString stringWithFormat:@"gotEncodedData %d ====> %d", (int)[data length], outputFrameCount++];
    if (isKeyFrame) {
        log  = [log stringByAppendingString:[NSString stringWithFormat:@" (key:%d)", keyFrameCount++]];
    }
    NSLog(@"%@", log);
    //static int framecount = 1;
   // [data writeToFile:h264File atomically:YES];
    //write(fd, [data bytes], [data length]);
    if (fileHandle != NULL)
    {
        const char bytes[] = "\x00\x00\x00\x01";
        size_t length = (sizeof bytes) - 1; //string literals have implicit trailing '\0'
        NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
        
        /*NSData *UnitHeader;
        if(isKeyFrame)
        {
            char header[2];
            header[0] = '\x65';
            UnitHeader = [NSData dataWithBytes:header length:1];
            framecount = 1;
        }
        else
        {
            char header[4];
            header[0] = '\x41';
            //header[1] = '\x9A';
            //header[2] = framecount;
            UnitHeader = [NSData dataWithBytes:header length:1];
            framecount++;
        }*/
        [fileHandle writeData:ByteHeader];
        //[fileHandle writeData:UnitHeader];
        [fileHandle writeData:data];
    }
}

- (void)gotCompressedSampleBuffer:(CMSampleBufferRef) sampleBuffer
{
    if(!videoWriterHasInit)
    {
        videoWriterHasInit = !videoWriterHasInit;
        [videoWriter startWriting];
        [videoWriter startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
    }
    while (!videoWriterInput.readyForMoreMediaData) {
        //wait;
        NSLog(@"gotCompressedSampleBuffer: not ready yet");
    }
    if (![videoWriterInput appendSampleBuffer:sampleBuffer]) {
        NSLog(@"audioWriterInput Error: %@", videoWriter.error);
        NSAssert(NO, @"videoWriterInput append fail!");
    }else{
        NSLog(@"=====> %d", videoAppendCount++);
    }
}

- (void)prepareWriter
{
    NSArray * paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString * documentsDirectory = [paths objectAtIndex:0];
    
    NSString * finalPath = [documentsDirectory stringByAppendingPathComponent:@"final.mp4"];
    NSError * error = nil;
    [[NSFileManager defaultManager] removeItemAtURL:[NSURL fileURLWithPath:finalPath] error:nil];
    if ([[NSFileManager defaultManager] fileExistsAtPath:finalPath]) {
        NSAssert(NO, @"can't be");
    }
    videoWriter = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:finalPath] fileType:AVFileTypeMPEG4 error:&error];
    NSParameterAssert(videoWriter);
    
    NSDictionary * videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                   AVVideoCodecH264, AVVideoCodecKey,
                                   @(480), AVVideoWidthKey,
                                   @(640), AVVideoHeightKey,
                                   nil];
    
    videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:nil];
    if ([videoWriter canAddInput:videoWriterInput]) {
        [videoWriter addInput:videoWriterInput];
    }
    
    //TODO: setting
    NSDictionary * audioSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithUnsignedInt:kAudioFormatMPEG4AAC], AVFormatIDKey,
                                    @(1), AVNumberOfChannelsKey,
                                    @(44100), AVSampleRateKey,
                                    nil];
    audioWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:nil];
    if ([videoWriter canAddInput:audioWriterInput]) {
        [videoWriter addInput:audioWriterInput];
    }
}

- (void)carolStart
{
    [self prepareWriter];
    [self prepareSourceFile];
    //create output file: result.h264
    outputFrameCount = 0;
    videoAppendCount = 0;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    h264File = [documentsDirectory stringByAppendingPathComponent:@"result.h264"];
    [fileManager removeItemAtPath:h264File error:nil];
    [fileManager createFileAtPath:h264File contents:nil attributes:nil];

    fileHandle = [NSFileHandle fileHandleForWritingAtPath:h264File];
    
    //init h264Encoder
    [h264Encoder initEncode:480 height:640];
    h264Encoder.delegate = self;
}

- (void)prepareSourceFile
{
    NSString *originPath=[[NSBundle mainBundle] pathForResource:@"daemon" ofType:@"mp4"];
    NSString *destPath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)objectAtIndex:0] stringByAppendingPathComponent:@"caroTest.mp4"];
    [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
    
    NSError *error = nil;
    [[NSFileManager defaultManager] copyItemAtURL:[NSURL fileURLWithPath:originPath] toURL:[NSURL fileURLWithPath:destPath] error:nil];
    if (error) {
        NSLog(@"copy file fail: %@", [error description]);
        return;
    }else{
        NSFileHandle * documentFile = [NSFileHandle fileHandleForReadingAtPath:destPath];
        NSLog(@"copy file success (file size: %lld )\n %@", [documentFile seekToEndOfFile], destPath);
        [documentFile closeFile];
    }
    sourceFilePath = [NSURL fileURLWithPath:destPath];
}

- (void)carolStop
{
    [h264Encoder End];
    NSLog(@">>>>>>> final file size ( %lld ) >>>>>", [fileHandle seekToEndOfFile]);
    [fileHandle closeFile];
    fileHandle = NULL;
}

- (void)carolWork
{
    [self carolStart];
    
    //读sample
    AVAsset *asset = [AVAsset assetWithURL:sourceFilePath];
    NSError * error = nil;
    AVAssetReader * assetReader = [AVAssetReader assetReaderWithAsset:asset error:&error];
    if (error) {
        NSLog(@"Error creating Asset Reader: %@", [error description]);
    }
    //video
    NSArray *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    __block AVAssetTrack *videoTrack = (AVAssetTrack *)[videoTracks firstObject];
    float frameRate = videoTrack.nominalFrameRate;
    CMTimeScale timeScale = videoTrack.naturalTimeScale;
    NSLog(@"frameRate : %f", frameRate);
    NSLog(@"timeScale : %d", timeScale);
    NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
    NSNumber* val = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange];
    NSDictionary* videoSettings = [NSDictionary dictionaryWithObject:val forKey:key];
    AVAssetReaderTrackOutput *videoTrackOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:videoTrack outputSettings:videoSettings];
    
    if ([assetReader canAddOutput:videoTrackOutput]) {
        [assetReader addOutput:videoTrackOutput];
    }
    
    BOOL ifAudio = NO;
    AVAssetReaderTrackOutput *audioTrackOutput = nil;
    if (ifAudio) {
        //audio
        NSArray *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
        __block AVAssetTrack *audioTrack = (AVAssetTrack *)[audioTracks firstObject];
        float audioFrameRate = audioTrack.nominalFrameRate;
        NSLog(@"audioframeRate : %f", audioFrameRate);
        //NSDictionary* audioSetting = [NSDictionary dictionaryWithObject:val forKey:key];
        audioTrackOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:audioTrack outputSettings:nil];
        
        if ([assetReader canAddOutput:audioTrackOutput]) {
            [assetReader addOutput:audioTrackOutput];
        }
    }
    
    BOOL didStart = [assetReader startReading];
    NSAssert(didStart, @"Why don't start?");
    
    NSLog(@"================ start ==================");
    int sampleCount = 0;
    int descardSampleCount = 0;
    
    
    if (!ifAudio) {
        while (assetReader.status == AVAssetReaderStatusReading) {
            CMSampleBufferRef sampleBuffer = [videoTrackOutput copyNextSampleBuffer];
            if(!videoWriterHasInit)
            {
                videoWriterHasInit = !videoWriterHasInit;
                [videoWriter startWriting];
                [videoWriter startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
            }
            if (sampleBuffer) {
                sampleCount++;
                [h264Encoder encode:sampleBuffer];
            }else if (assetReader.status == AVAssetReaderStatusFailed){
                NSLog(@"Asset Reader failed with error: %@", [[assetReader error] description]);
            } else if (assetReader.status == AVAssetReaderStatusCompleted){
                NSLog(@"Reached the end of the video.");
                NSLog(@"========== end ====== total SampleCount %d ======= discard : %d =======", sampleCount, descardSampleCount);
            }else{
                NSLog(@"========== end ====== total SampleCount %d ======= discard : %d =======", sampleCount, descardSampleCount);
                break;
            }
        }
    }else{
        //先编视频再遍音频
        CMSampleBufferRef vSampleBuffer = [audioTrackOutput copyNextSampleBuffer];
        if(!videoWriterHasInit)
        {
            videoWriterHasInit = !videoWriterHasInit;
            [videoWriter startWriting];
            [videoWriter startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(vSampleBuffer)];
        }
        while (YES) {
            if (assetReader.status != AVAssetReaderStatusReading) {
                break;
            }
            if (vSampleBuffer) {
                sampleCount++;
                [h264Encoder encode:vSampleBuffer];
                vSampleBuffer = [audioTrackOutput copyNextSampleBuffer];
                
//                if (sampleCount%5 == 0) {
//                    descardSampleCount ++;
//                    continue;
//                }else{
//                    [h264Encoder encode:vSampleBuffer];
//                }
                
            }else{
                if (assetReader.status == AVAssetReaderStatusFailed){
                    NSLog(@"Asset Reader failed with error: %@", [[assetReader error] description]);
                } else if (assetReader.status == AVAssetReaderStatusCompleted){
                    NSLog(@"Reached the end of the video.");
                }
                NSLog(@"========== read video end ====== total SampleCount %d ======= discard : %d =======", sampleCount, descardSampleCount);
                break;
            }
        }
        NSLog(@"0000000000000000000000000000000000000000");
        int audioSampleCount = 0;
        
        CMSampleBufferRef aSampleBuffer = [audioTrackOutput copyNextSampleBuffer];
        if(!videoWriterHasInit)
        {
            videoWriterHasInit = !videoWriterHasInit;
            [videoWriter startWriting];
            [videoWriter startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(aSampleBuffer)];
        }
        
        //音频
        while (YES) {
            if (assetReader.status != AVAssetReaderStatusReading) {
                break;
            }
            if (aSampleBuffer) {
                if (!audioWriterInput.readyForMoreMediaData) {
                    continue;
                }
                if (![audioWriterInput appendSampleBuffer:aSampleBuffer]) {
                    NSLog(@"audioWriterInput Error: %@", videoWriter.error);
                    return;
                }else{
                    audioSampleCount++;
                    aSampleBuffer = [audioTrackOutput copyNextSampleBuffer];
                }
            }else{
                if (assetReader.status == AVAssetReaderStatusFailed){
                    NSLog(@"Asset Reader failed with error: %@", [[assetReader error] description]);
                } else if (assetReader.status == AVAssetReaderStatusCompleted){
                    NSLog(@"Reached the end of the video.");
                    NSLog(@"========== read audio end ====== total SampleCount %d =======", audioSampleCount);
                }
                break;
            }
        }

    }
    
    [self carolStop];
}

@end
