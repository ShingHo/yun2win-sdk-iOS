//
//  ConversationViewController.m
//  API
//
//  Created by ShingHo on 16/1/22.
//  Copyright © 2016年 SayGeronimo. All rights reserved.
//

#import "ConversationViewController.h"
#import "GroupViewController.h"
#import "MessageCell.h"
#import "MessageNotiCell.h"
#import "InputView.h"
#import "MessageCellDelegate.h"
#import "ContactPickerConfig.h"
#import "SessionMemberPickerConfig.h"
#import "UserPickerViewController.h"
#import "FileAppend.h"
#import "Y2WTextMessage.h"
#import "LocationViewController.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import "UUAVAudioPlayer.h"
#import "FileTransSelectViewController.h"
#import "FileModel.h"
#import "CommunicationViewController.h"
#import "GroupVideoCommunicationViewController.h"
#import "ReceiveCommunicationViewController.h"
#import <Y2W_RTC_SDK/Y2WRTCManager.h>
#import <Y2W_RTC_SDK/Y2WNetWork.h>
#import "AVCallModel.h"
@interface ConversationViewController ()
<
UITableViewDataSource,
UITableViewDelegate,
InputViewUIDelegate,
InputViewActionDelegate,
InputViewMoreDelegate,
UINavigationControllerDelegate,
UIImagePickerControllerDelegate,
Y2WMessagesDelegate,
MessageCellDelegate,
LocationViewControllerDelegate,
UUAVAudioPlayerDelegate,
FileTransSelectViewControllerDelegate,
UIDocumentInteractionControllerDelegate
>

typedef void(^ImagePickerArr)(UIImage *image,UIImage *thumImage);

@property (nonatomic, retain) Y2WSession *session;

@property (nonatomic, retain) NSMutableArray *messages;

@property (nonatomic, retain) MessageCellConfig *cellConfig;

@property (nonatomic, retain) Y2WMessagesPage *page;


@property (nonatomic, retain) UIImagePickerController *imagePicker;

@property (nonatomic, retain) UITableView *tableView;

@property (nonatomic, retain) InputView *inputView;

@property (nonatomic, strong) ImagePickerArr block;

@property(nonatomic,retain)UIDocumentInteractionController *docController;

@end

static BOOL isTap = NO;


@implementation ConversationViewController

- (void)dealloc {
    NSLog(@"%s--%@",__FUNCTION__,[NSThread currentThread]);

    [self.session.messages removeDelegate:self];
}

- (instancetype)initWithSession:(Y2WSession *)session {

    if (self = [super init]) {
        _session = session;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    [self setUpNavItem];
    [self.view addSubview:self.tableView];
    [self.view addSubview:self.inputView];
    
    [self.session.messages addDelegate:self];
    [self.session.messages loadMessageWithPage:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.tableView.frame = self.view.bounds;
    self.tableView.height = self.inputView.top;
}

- (void)setUpNavItem {
    
    self.navigationItem.title = self.session.name;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"导航栏_返回"] style:UIBarButtonItemStylePlain target:self action:@selector(back)];
    
    if ([self.session.type isEqualToString:@"p2p"]) {
//        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"导航栏_个人信息"] style:UIBarButtonItemStylePlain target:self action:@selector(p2pRightBarButtonItemClick)];
        
    }else if ([self.session.type isEqualToString:@"group"]) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"导航栏_群信息"] style:UIBarButtonItemStylePlain target:self action:@selector(groupRightBarButtonItemClick)];
    }
}




#pragma mark - ———— Response ———— -

- (void)back {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)p2pRightBarButtonItemClick {
    
}

- (void)groupRightBarButtonItemClick {
    GroupViewController *groupViewController = [[GroupViewController alloc] initWithSesstion:self.session];
    [self pushViewController:groupViewController];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.inputView endEditing:YES];
}






#pragma mark - ———— Y2WMessagesDelegate ———— -

- (void)messages:(Y2WMessages *)messages loadMessagesFromPage:(Y2WMessagesPage *)page didCompleteWithError:(NSError *)error {

    if (!_messages) _messages = [NSMutableArray array];

    CGFloat totalCellHeight = 0;
    
    for (Y2WBaseMessage *message in page.messageList) {
        MessageModel *model = [[MessageModel alloc] initWithMessage:message];
        [self updateMessageModel:model];
        [self.messages addObject:model];
        
        totalCellHeight += model.cellHeight;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        if (self.page) {
            [self.tableView reloadData];
            CGFloat contentOffsetY = self.tableView.contentOffset.y + totalCellHeight;
            self.tableView.contentOffset = CGPointMake(0, contentOffsetY);
            
        }else {
            [self.tableView reloadData];
            [self.tableView scrollToBottom:NO];
        }
        
        self.page = page;
    });
}

- (void)messages:(Y2WMessages *)messages onRecvMessage:(Y2WBaseMessage *)message {
   
    
    dispatch_async(dispatch_get_main_queue(), ^{
        for (MessageModel *model in self.messages) {
            if ([model.message isEqual:message]) return;
        }
        MessageModel *newModel = [[MessageModel alloc] initWithMessage:message];
        [self updateMessageModel:newModel];
        
        MessageModel *topModel;
        for (MessageModel *model in self.messages) {
            if (model.status != MessageModelStatusNormal) {
                topModel = model;
                break;
            }
        }
        
        if (topModel) {
            NSInteger index= [self.messages indexOfObject:topModel];
            [self.messages insertObject:newModel atIndex:index];
        }else {
            [self.messages addObject:newModel];
        }
        
        [self.tableView reloadData];
        [self.tableView scrollToBottom:YES];
//        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self.messages indexOfObject:newModel] inSection:0];
//        NSLog(@"%@---%@",indexPath,self.messages.description);
//        [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationBottom];
//        [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionBottom animated:YES];
    });
}

- (void)messages:(Y2WMessages *)messages willSendMessage:(Y2WBaseMessage *)message {

    MessageModel *newModel = [[MessageModel alloc] initWithMessage:message];
    [self updateMessageModel:newModel];
    [self.messages addObject:newModel];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self.messages indexOfObject:newModel] inSection:0];
        [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationBottom];
        [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionBottom animated:YES];
//        [self.tableView reloadData];
    });
}

- (void)messages:(Y2WMessages *)messages sendMessage:(Y2WBaseMessage *)message progress:(CGFloat)progress {

    for (MessageModel *model in self.messages) {
        if (![model.message isEqual:message]) continue;
        
        model.message = message;
        [self updateMessageModel:model];
        
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self.messages indexOfObject:model] inSection:0];
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        });
        return;
    }
}

- (void)messages:(Y2WMessages *)messages sendMessage:(Y2WBaseMessage *)message didCompleteWithError:(NSError *)error {
    NSLog(@"%s",__FUNCTION__);

    if (error) {
        NSLog(@"%@",error);
        return;
    }
    
    for (MessageModel *model in self.messages) {
        if (![model.message isEqual:message]) continue;
        
        model.message = message;
        [self updateMessageModel:model];
        
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self.messages indexOfObject:model] inSection:0];
        dispatch_async(dispatch_get_main_queue(), ^{
//            [self.tableView reloadData];
            [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
        });
        return;
    }
}

- (void)messages:(Y2WMessages *)messages onUpdateMessage:(Y2WBaseMessage *)message {
//    NSLog(@"%s",__FUNCTION__);
    dispatch_async(dispatch_get_main_queue(), ^{

        for (MessageModel *model in self.messages) {
//            NSLog(@"%@---%@",model.message,message);
            if (![model.message isEqual:message]) continue;
            
            model.message = message;
            [self updateMessageModel:model];
            
                [self.tableView reloadData];
    //            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self.messages indexOfObject:model] inSection:0];
    //            [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            break;
        }
    });
}




#pragma mark - ———— UITableViewDataSource ———— -

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    
    return self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    MessageModel *model = self.messages[indexPath.row];
    
    MessageCell<MessageCellModelInterface> *cell = [tableView dequeueReusableCellWithIdentifier:model.cellClassName];
    
    [cell setMessageDelegate:self];
    [cell refreshData:model];
    
    return cell;
}


#pragma mark - ———— UITableViewDelegate ———— -

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    MessageModel *model = self.messages[indexPath.row];

    return model.cellHeight;
}


#pragma mark - ———— UIImagePickerControllerDelegate ———— -

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    [picker dismissViewControllerAnimated:YES completion:^{
        
        NSString* mediaType = [info objectForKey:UIImagePickerControllerMediaType];
        //判断是静态图像还是视频
        if ([mediaType isEqualToString:(NSString *)kUTTypeImage]) {
            UIImage *image = info[UIImagePickerControllerOriginalImage];
            Y2WImageMessage *message = [self.session.messages messageWithImage:image];
            [self.session.messages sendMessage:message];
        }
        else
        {
            
            NSURL* mediaURL = [info objectForKey:UIImagePickerControllerMediaURL];
            ALAssetsLibrary *assetsLibrary = [[ALAssetsLibrary alloc] init];
            [assetsLibrary writeVideoAtPathToSavedPhotosAlbum:mediaURL completionBlock:^(NSURL *assetURL, NSError *error) {
                if (!error) {
                    NSLog(@"captured video saved with no error.%@",assetURL);
                    
                    AVURLAsset *avAsset = [AVURLAsset URLAssetWithURL:assetURL options:nil];
                    NSArray *compatiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:avAsset];
                    if ([compatiblePresets containsObject:AVAssetExportPresetLowQuality])
                    {
                        
                        AVAssetExportSession *exportSession = [[AVAssetExportSession alloc]initWithAsset:avAsset presetName:AVAssetExportPresetPassthrough];
                        NSString *videoName = [NSString stringWithFormat:@"video_%@.mp4",@([NSDate timeIntervalSinceReferenceDate])];
                        NSString *exportPath = [NSString getDocumentPathInbox:videoName];
                        exportSession.outputURL = [NSURL fileURLWithPath:exportPath];
                        exportSession.outputFileType = AVFileTypeMPEG4;
                        [exportSession exportAsynchronouslyWithCompletionHandler:^{
                            
                            switch ([exportSession status]) {
                                case AVAssetExportSessionStatusFailed:
                                    NSLog(@"Export failed: %@", [[exportSession error] localizedDescription]);
                                    break;
                                case AVAssetExportSessionStatusCancelled:
                                    NSLog(@"Export canceled");
                                    break;
                                case AVAssetExportSessionStatusCompleted:
                                {
                                    NSLog(@"转换成功");
                                    Y2WVideoMessage *message = [self.session.messages messageWithVideoPath:exportPath];
                                    [self.session.messages sendMessage:message];
                                    break;
                                }
                                default:
                                    break;
                            }
                        }];
                    }
                    
                }else
                {
                    NSLog(@"error occured while saving the video:%@", error);
                }
            }];
        }

    }];
}

#pragma mark - ———— LocationViewControllerDelegate ———— -
- (void)onSendLocation:(LocationPoint *)locationPoint
{
    NSLog(@"---%@",locationPoint);
    Y2WLocationMessage *message = [self.session.messages messageWithLocationPoint:locationPoint];
    [self.session.messages sendMessage:message];
}

#pragma mark - ———— InputViewUIDelegate ———— -
//will
- (void)inputView:(InputView *)inputView didChangeTop:(CGFloat)top{
    self.tableView.frame = self.view.bounds;
    self.tableView.height = top;
    [self.tableView scrollToBottom:YES];
}

- (void)inputView:(InputView *)inputView showKeyboard:(CGFloat)show {
    self.tableView.userInteractionEnabled = !show;
}

- (void)inputView:(InputView *)inputView onSendText:(NSString *)text {

    Y2WTextMessage *message = [self.session.messages messageWithText:text];
    
    [self.session.messages sendMessage:message];
}
- (void)inputView:(InputView *)inputView onSendVoice:(NSString *)voicePath time:(NSInteger)timer
{
//    NSLog(@"voice : %@\n%ld",voicePath,timer);
    Y2WAudioMessage *message = [self.session.messages messageWithAudioPath:voicePath timer:timer];
    [self.session.messages sendMessage:message];
}

- (void)moreInputViewDidSelectItem:(MoreItem *)item {
    if ([item.title isEqualToString:@"图片"]) {
        if(![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) return;
        self.imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        self.imagePicker.mediaTypes = @[(NSString *)kUTTypeImage];
        [self presentViewController:self.imagePicker animated:YES completion:nil];
    }
    if ([item.title isEqualToString:@"拍照"]) {
        if(![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) return;
        self.imagePicker.sourceType = UIImagePickerControllerSourceTypeCamera;
        self.imagePicker.mediaTypes = @[(NSString *)kUTTypeImage];
        [self presentViewController:self.imagePicker animated:YES completion:nil];
    }
    if ([item.title isEqualToString:@"小视频"]) {
        if(![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) return;
        self.imagePicker.sourceType = UIImagePickerControllerSourceTypeCamera;
        self.imagePicker.mediaTypes = @[(NSString *)kUTTypeMovie];
        self.imagePicker.videoMaximumDuration = 15;
        self.imagePicker.showsCameraControls = YES;
        [self presentViewController:self.imagePicker animated:YES completion:nil];
    }
    if ([item.title isEqualToString:@"位置"]) {
        LocationViewController *location = [[LocationViewController alloc]init];
        location.delegate = self;
        [self.navigationController pushViewController:location animated:YES];
    }
    if ([item.title isEqualToString:@"文档"]) {
        FileTransSelectViewController *fileSelect = [[FileTransSelectViewController alloc]init];
        fileSelect.delegate = self;
        [self.navigationController pushViewController:fileSelect animated:YES];
    }
    if ([item.title isEqualToString:@"语音通话"]) {
        if ([self.session.type isEqualToString:@"p2p"]) {
//            CommunicationViewController *communication = [[CommunicationViewController alloc]init];
//            [self presentViewController:communication animated:YES completion:nil];
            
            [self openRTCForSuccess:^(Y2WRTCChannel *channel) {
                
                AVCallModel *model = [[AVCallModel alloc]initWithChannel:channel.channelId Session:self.session.sessionId CommunicationType:@"audio" sender:[Y2WUsers getInstance].getCurrentUser.userId receivers:@[self.session.targetID] AVCallType:SingleAVCall];
                Y2WAVCallMessage *message = [self.session.messages messageWithAVCall:model];
                [self.session.messages sendMessage:message];
                
                CommunicationViewController *comm = [[CommunicationViewController alloc]initWithChannel:channel CommType:commAudio];
                [self presentViewController:comm animated:YES completion:nil];
                
            } failure:^(NSError *error) {
                
            }];

        }
        else
        {
            SessionMemberPickerConfig *config = [[SessionMemberPickerConfig alloc]initWithSession:self.session];
            UserPickerViewController *userPickerVC = [[UserPickerViewController alloc] initWithConfig:config];
            [userPickerVC selectMembersCompletion:^(NSArray<NSObject<MemberModelInterface> *> *members) {
                
                [self openRTCForSuccess:^(Y2WRTCChannel *channel) {
                    
                    AVCallModel *model = [[AVCallModel alloc]initWithChannel:channel.channelId Session:self.session.sessionId CommunicationType:@"audio" sender:[Y2WUsers getInstance].getCurrentUser.userId receivers:[self getMemberIds:members] AVCallType:GroupAVCall];
                    Y2WAVCallMessage *message = [self.session.messages messageWithAVCall:model];
                    [self.session.messages sendMessage:message];
                    
                    GroupVideoCommunicationViewController *video = [[GroupVideoCommunicationViewController alloc]initWithChannel:channel SessionId:self.session.sessionId commType:commAudio];
                    [self presentViewController:video animated:YES completion:nil];
                    
                } failure:^(NSError *error) {
                    NSLog(@"openRTC---%@",error);
                }];
                
            } cancel:nil];
            
            [self pushViewController:userPickerVC];

        }

    }
    if ([item.title isEqualToString:@"视频通话"]) {
        
        if ([self.session.type isEqualToString:@"p2p"]) {
            
            [self openRTCForSuccess:^(Y2WRTCChannel *channel) {
                
                AVCallModel *model = [[AVCallModel alloc]initWithChannel:channel.channelId Session:@"" CommunicationType:@"video" sender:[Y2WUsers getInstance].getCurrentUser.userId receivers:@[self.session.targetID] AVCallType:SingleAVCall];
                Y2WAVCallMessage *message = [self.session.messages messageWithAVCall:model];
                [self.session.messages sendMessage:message];
                
                CommunicationViewController *comm = [[CommunicationViewController alloc]initWithChannel:channel CommType:commVideo];
                [self presentViewController:comm animated:YES completion:nil];
                
            } failure:^(NSError *error) {
                
            }];
            
        }
        else
        {
            SessionMemberPickerConfig *config = [[SessionMemberPickerConfig alloc]initWithSession:self.session];
            UserPickerViewController *userPickerVC = [[UserPickerViewController alloc] initWithConfig:config];
            [userPickerVC selectMembersCompletion:^(NSArray<NSObject<MemberModelInterface> *> *members) {
               
                [self openRTCForSuccess:^(Y2WRTCChannel *channel) {
                    
                    AVCallModel *model = [[AVCallModel alloc]initWithChannel:channel.channelId Session:self.session.sessionId CommunicationType:@"video" sender:[Y2WUsers getInstance].getCurrentUser.userId receivers:[self getMemberIds:members] AVCallType:GroupAVCall];
                    Y2WAVCallMessage *message = [self.session.messages messageWithAVCall:model];
                    [self.session.messages sendMessage:message];
                    
                    GroupVideoCommunicationViewController *video = [[GroupVideoCommunicationViewController alloc]initWithChannel:channel SessionId:self.session.sessionId commType:commVideo];
                    [self presentViewController:video animated:YES completion:nil];
                    
                } failure:^(NSError *error) {
                    NSLog(@"openRTC---%@",error);
                }];
                
            } cancel:nil];
            
            [self pushViewController:userPickerVC];
        }

    }
}





- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    for (MessageModel *model in _messages) {
        [model cleanCache];
        [model calculateContent:size.width];
    }
    
    [coordinator animateAlongsideTransition:^(id <UIViewControllerTransitionCoordinatorContext> context) {
      
         dispatch_async(dispatch_get_main_queue(), ^{
             [self.tableView reloadData];
         });
     } completion:nil];
}



#pragma mark - MessageCellDeleagte
- (void)onLongPressCell:(Y2WBaseMessage *)message inView:(UIView *)view
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"操作" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *copyAction = [UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self copyMessage:message];
    }];
    UIAlertAction *quoteAction = [UIAlertAction actionWithTitle:@"引用" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self quoteMessage:message];
    }];
    UIAlertAction *transmitAction = [UIAlertAction actionWithTitle:@"转发" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self transmitMessage:message];
    }];
    UIAlertAction *revokeAction = [UIAlertAction actionWithTitle:@"撤回" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self revokeMessage:message];
    }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:copyAction];
    if ([message.type isEqualToString:@"text"])
    {
        [alert addAction:quoteAction];
    }
    [alert addAction:transmitAction];
    [alert addAction:cancelAction];
    if ([message.sender isEqualToString:[[Y2WUsers getInstance]getCurrentUser].userId]) {
        [alert addAction:revokeAction];
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)onTapBubbleView:(Y2WBaseMessage *)message
{
    if ([message.type isEqualToString:@"image"]) {

    }
    if ([message.type isEqualToString:@"video"]) {
        Y2WVideoMessage *videoMessage = (Y2WVideoMessage *)message;
        if (!videoMessage.videoPath.length) {
            [self.session.messages.remote downLoadFileWithMessage:message progress:^(CGFloat fractionCompleted) {
                
            } success:^(Y2WBaseMessage *message) {
                
            } failure:^(NSError *error) {
                
            }];
        }else
        {
            NSURL *videoPathURL=[NSURL fileURLWithPath:videoMessage.videoPath];
            MPMoviePlayerViewController *movie = [[MPMoviePlayerViewController alloc]initWithContentURL:videoPathURL];
            movie.moviePlayer.shouldAutoplay = YES;
            movie.moviePlayer.movieSourceType = MPMovieSourceTypeFile;
            [self presentMoviePlayerViewControllerAnimated:movie];
        }
    }
    if ([message.type isEqualToString:@"location"]) {
        Y2WLocationMessage *locationMessage = (Y2WLocationMessage *)message;
        LocationPoint *locationPoint = [[LocationPoint alloc]initWithMessage:locationMessage];
        LocationViewController *location = [[LocationViewController alloc]initWithLocationPoint:locationPoint];
        [self.navigationController pushViewController:location animated:YES];
    }
    if ([message.type isEqualToString:@"audio"]) {
        UUAVAudioPlayer *player = [UUAVAudioPlayer sharedInstance];
        player.delegate = self;
        Y2WAudioMessage *audioMessage = (Y2WAudioMessage *)message;
        if (!isTap) {
            if (!audioMessage.audioPath.length) {
                [self.session.messages.remote downLoadFileWithMessage:message progress:^(CGFloat fractionCompleted) {
                    
                } success:^(Y2WBaseMessage *message) {
                    Y2WAudioMessage *audioMessage = (Y2WAudioMessage *)message;
                    NSData *data = [NSData dataWithContentsOfFile:audioMessage.audioPath];
                    [player playSongWithData:data];
                } failure:^(NSError *error) {
                    
                }];
            }
            else
            {
                NSData *data = [NSData dataWithContentsOfFile:audioMessage.audioPath];
                [player playSongWithData:data];
            }
        }
        else
        {
            [player stopSound];
        }
        
    }
    if ([message.type isEqualToString:@"file"]) {
        NSLog(@"打开文件");
        Y2WFileMessage *fileMessage = (Y2WFileMessage *)message;
        if (!fileMessage.filePath.length) {
            [self.session.messages.remote downLoadFileWithMessage:message progress:^(CGFloat fractionCompleted) {
                
            } success:^(Y2WBaseMessage *message) {
                
            } failure:^(NSError *error) {
                
            }];
        }else
        {
            _docController = [UIDocumentInteractionController interactionControllerWithURL:[NSURL fileURLWithPath:fileMessage.filePath]];//为该对象初始化一个加载路径
            _docController.delegate =self;//设置代理
            //直接显示预览
            //    [_docController presentPreviewAnimated:YES];
            CGRect navRect =self.navigationController.navigationBar.frame;
            navRect.size =CGSizeMake(1500.0f,40.0f);
            //显示包含预览的菜单项
            [_docController presentOptionsMenuFromRect:navRect inView:self.view animated:YES];
        }

    }
}

#pragma mark - ———— FileTransSelectViewControllerDelegate ———— -
- (void)sendFileModel:(FileModel *)model
{
    Y2WFileMessage *message = [self.session.messages messageWithFilePath:model];
    [self.session.messages sendMessage:message];
}

#pragma mark - ———— UIDocumentInteractionControllerDelegate ———— -
-(UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller
{
    return self;
}

- (UIView *)documentInteractionControllerViewForPreview:(UIDocumentInteractionController *)controller
{
    return self.view;
}

- (CGRect)documentInteractionControllerRectForPreview:(UIDocumentInteractionController *)controller
{
    return  self.view.frame;
}

#pragma mark - ———— Helper ———— -

- (void)updateMessageModel:(MessageModel *)model {
    model.cellConfig = self.cellConfig;
    [model cleanCache];
    [model calculateContent:self.tableView.width];
}

- (void)copyMessage:(Y2WBaseMessage *)message
{
    if ([message.type isEqualToString:@"text"]) {
        if (message.text.length) {
            UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
            [pasteboard setString:message.text];
        }
    }
    else if ([message.type isEqualToString:@"image"])
    {
        
    }

}

- (void)quoteMessage:(Y2WBaseMessage *)message
{
    if (message.text.length) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        Y2WUser *sender = [[Y2WUsers getInstance] getUserWithUserId:message.sender];
        NSString *pasteString = [NSString stringWithFormat:@"「%@: %@」\n—————————",sender.name,message.text];
        [pasteboard setString:pasteString];
    }
}

- (void)transmitMessage:(Y2WBaseMessage *)message
{
    ContactPickerConfig *config = [[ContactPickerConfig alloc] init];
    UserPickerViewController *userPickerVC = [[UserPickerViewController alloc] initWithConfig:config];
    [userPickerVC selectMembersCompletion:^(NSArray<NSObject<MemberModelInterface> *> *members) {
        for (NSObject<MemberModelInterface> *member in members) {
            Y2WContact *transmitContact = [[Y2WUsers getInstance].getCurrentUser.contacts getContactWithUID:member.uid];
            [transmitContact getSessionDidCompletion:^(Y2WSession *session, NSError *error) {
                Y2WBaseMessage *transmitMessage = [session.messages messageWithText:message.text];
                [session.messages sendMessage:transmitMessage];
            }];
        }
    } cancel:nil];
    [self pushViewController:userPickerVC];
}

- (void)revokeMessage:(Y2WBaseMessage *)message
{
    Y2WBaseMessage *uMessage = message;
    uMessage.sessionId = self.session.sessionId;
    uMessage.type = @"system";
    uMessage.content = @{@"text":[NSString stringWithFormat:@"%@回撤了一条信息",[Y2WUsers getInstance].getCurrentUser.name]};
    uMessage.text = [NSString stringWithFormat:@"%@回撤了一条信息",[Y2WUsers getInstance].getCurrentUser.name];
//    message.status = @"storing";
    [self.session.messages.remote updataMessage:uMessage session:self.session success:^(Y2WBaseMessage *message) {
        
    } failure:^(NSError *error) {
        NSLog(@"revokeMessage : %@",error);
    }];

}

- (void)UUAVAudioPlayerBeiginLoadVoice
{
    
}
- (void)UUAVAudioPlayerBeiginPlay
{
    isTap = YES;
}
- (void)UUAVAudioPlayerDidFinishPlay
{
    isTap = NO;

}

- (void)openRTCForSuccess:(void(^)(Y2WRTCChannel *channel))success failure:(void(^)(NSError *error))failure
{
    Y2WRTCManager *manager = [[Y2WRTCManager alloc] init];
    manager.memberId = [Y2WUsers getInstance].getCurrentUser.userId; //uid
    manager.token = [Y2WUsers getInstance].getCurrentUser.imToken; //token
    [manager createChannel:^(NSError *error, Y2WRTCChannel *channel) {
        if (error) {
            NSLog(@"%@",error);
            
            failure(error);
            return ;
        }
        success(channel);
        
    }];
}

- (NSArray *)getMemberIds:(NSArray *)members
{
    NSMutableArray *memberIds = [NSMutableArray array];
    for (NSObject<MemberModelInterface> *member in members) {
        [memberIds addObject:member.uid];
    }
    return memberIds;
}

#pragma mark - ———— getter ———— -

- (UITableView *)tableView {
    if (!_tableView) {
        _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
        _tableView.backgroundColor = [UIColor colorWithHexString:@"E3EFEF"];
        _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        _tableView.tableFooterView = [[UIView alloc] init];
        _tableView.canCancelContentTouches = NO;
        _tableView.delaysContentTouches = NO;
        _tableView.delegate = self;
        _tableView.dataSource = self;
        [_tableView registerClass:[MessageCell class] forCellReuseIdentifier:NSStringFromClass([MessageCell class])];
        [_tableView registerClass:[MessageNotiCell class] forCellReuseIdentifier:NSStringFromClass([MessageNotiCell class])];
    }
    return _tableView;
}

- (InputView *)inputView {
    if (!_inputView) {
        _inputView = [[InputView alloc] initWithFrame:CGRectMake(0, self.view.height - 45, self.view.width, 45)];
        _inputView.backgroundColor = [UIColor whiteColor];
        _inputView.UIDelegate = self;
        _inputView.ActionDelegate = self;
        _inputView.MoreDelegate = self;
        
        
        MoreItem *item = [[MoreItem alloc] init];
        item.title = @"图片";
        item.image = [UIImage imageNamed:@"输入框-图片"];
        
        MoreItem *item_camera = [[MoreItem alloc]init];
        item_camera.title = @"拍照";
        item_camera.image = [UIImage imageNamed:@"输入框-图片"];
        
        MoreItem *item1 = [[MoreItem alloc] init];
        item1.title = @"小视频";
        item1.image = [UIImage imageNamed:@"输入框-图片"];
        
        MoreItem *item2 = [[MoreItem alloc] init];
        item2.title = @"位置";
        item2.image = [UIImage imageNamed:@"输入框-位置"];
        
        MoreItem *item3 = [[MoreItem alloc] init];
        item3.title = @"文档";
        item3.image = [UIImage imageNamed:@"输入框-文档"];
        
        MoreItem *item4 = [[MoreItem alloc] init];
        item4.title = @"语音通话";
        item4.image = [UIImage imageNamed:@"输入框-语音通话"];
        
        MoreItem *item5 = [[MoreItem alloc] init];
        item5.title = @"视频通话";
        item5.image = [UIImage imageNamed:@"输入框-视频通话"];
        
        _inputView.moreInputView.items = @[item,item_camera,item1,item2,item3,item4,item5];
    }
    return _inputView;
}

- (UIImagePickerController *)imagePicker {
    if (!_imagePicker) {
        _imagePicker = [[UIImagePickerController alloc] init];
        _imagePicker.delegate = self;
    }
    return _imagePicker;
}

- (MessageCellConfig *)cellConfig {
    if (!_cellConfig) {
        _cellConfig = [[MessageCellConfig alloc] init];
    }
    return _cellConfig;
}

@end
