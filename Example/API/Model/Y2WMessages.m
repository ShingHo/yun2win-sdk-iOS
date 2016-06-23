//
//  Y2WMessages.m
//  API
//
//  Created by ShingHo on 16/3/2.
//  Copyright © 2016年 SayGeronimo. All rights reserved.
//

#import "Y2WMessages.h"
#import "Y2WSession.h"
#import "MulticastDelegate.h"
#import <objc/runtime.h>
#import "Y2WTextMessage.h"
#import "Y2WImageMessage.h"
#import "FileAppend.h"
#import <AVFoundation/AVFoundation.h>

@interface Y2WMessages ()

@property (nonatomic, retain) MulticastDelegate<Y2WMessagesDelegate> *delegates; //多路委托对象

@property (nonatomic, retain) NSMutableSet *messageList;

@end



@implementation Y2WMessages

#pragma mark - ———— queue ———— -
/**
 *  创建一个串行队列（此队列只做读写操作）
 *
 *  @return 队列实例
 */
static dispatch_queue_t message_readwrite_queue() {
    static dispatch_queue_t message_readwrite_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        message_readwrite_queue = dispatch_queue_create("message_readwrite_queue", DISPATCH_QUEUE_SERIAL);
    });
    
    return message_readwrite_queue;
}

/**
 *  创建一个串行队列（此队列只做代理回调操作）
 *
 *  @return 队列实例
 */
static dispatch_queue_t message_callback_queue() {
    static dispatch_queue_t message_callback_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        message_callback_queue = dispatch_queue_create("message_callback_queue", DISPATCH_QUEUE_SERIAL);
    });
    
    return message_callback_queue;
}




#pragma mark - ———— 初始化 ———— -

- (instancetype)initWithSession:(Y2WSession *)session {
    
    if (self = [super init]) {
        self.session = session;
        self.remote = [[Y2WMessagesRemote alloc] initWithMessages:self];
        MulticastDelegate *delegates = [[MulticastDelegate alloc] init];
        self.delegates = (MulticastDelegate<Y2WMessagesDelegate> *)delegates;
    }
    return self;
}




#pragma mark - ———— Y2WMessagesRemote调用此方法 ———— -

- (void)messagesRemote:(Y2WMessagesRemote *)remote syncMessages:(NSArray *)messages didCompleteWithError:(NSError *)error {
    __weak typeof(self)weakSelf = self;

    for (Y2WBaseMessage *message in messages) {
        
        [self getMessageWithMessage:message didCompletionBlock:^(Y2WBaseMessage *gMessage, NSError *error) {
            if (gMessage) {
                [weakSelf updateMessage:message didCompletionBlock:^(Y2WBaseMessage *uMessage, NSError *error) {
                    [weakSelf onUpdateMessage:message];
                }];
                
            }else {

                [weakSelf addMessage:message didCompletionBlock:^(NSError *error) {
                    [weakSelf onReceiveMessage:message];
                }];
            }
        }];
    }
}





#pragma mark - ———— Y2WMessageDelegateInterface ———— -

- (void)addDelegate:(id<Y2WMessagesDelegate>)delegate {
 
    [self.delegates addDelegate:delegate];
}

- (void)removeDelegate:(id<Y2WMessagesDelegate>)delegate {

    [self.delegates removeDelegate:delegate];
}

- (void)loadMessageWithPage:(Y2WMessagesPage *)page {
    BOOL needSync = NO;
    if (!page) {
        page = [[Y2WMessagesPage alloc] init];
        needSync = YES;
    }
    
    [self getBeforeMessagesFromMessage:[page.messageList firstObject] limit:10 didCompletionBlock:^(NSArray<Y2WBaseMessage *> *messages, NSError *error) {
        
        page.messageList = messages;
        
        if (page.messageList.count) {
            [self loadMessagesFromPage:page didCompleteWithError:nil];
            
        }else {
            NSError *error = [NSError errorWithDomain:@"Y2WMessages"
                                                 code:0
                                             userInfo:@{NSLocalizedDescriptionKey:@"没有消息了"}];
            [self loadMessagesFromPage:nil didCompleteWithError:error];
        }
    }];
    
    
    if (needSync) {
        [self.remote sync];
    }
}

- (void)sendMessage:(Y2WBaseMessage *)message {
    __weak typeof(self)weakSelf = self;
    [self addMessage:message didCompletionBlock:^(NSError *error) {
        if (error) {
            [weakSelf sendMessage:message didCompleteWithError:error];
        }else {
            [weakSelf willSendMessage:message];
        }
        if ([weakSelf isUploadFile:message.type]) {
            [weakSelf storeFileMessage:message success:^(Y2WBaseMessage *message) {
                [weakSelf storeMessage:message];
            }];
        }
        else{
            [weakSelf storeMessage:message];
        }
    }];
}

- (void)resendMessage:(Y2WBaseMessage *)message {
    [self sendMessage:message];
}


- (void)storeMessage:(Y2WBaseMessage *)message
{
    if ([message.type isEqualToString:@"singleavcall"] || [message.type isEqualToString:@"groupavcall"]) {
        [self.remote storeAVCallMessage:message];
    }
    else
    {
        [self.remote storeMessages:message success:^(Y2WBaseMessage *message) {
            
            [self.session.sessions.user.userConversations.remote sync];
            [self.remote sync];
            
        } failure:^(NSError *error) {
            message.status = @"storefailed";
            [self sendMessage:message didCompleteWithError:error];
        }];

    }
}



#pragma mark - ———— 所有回调操作（防止顺序不对，统一在一个串行队列执行） ———— -

- (void)loadMessagesFromPage:(Y2WMessagesPage *)page didCompleteWithError:(NSError *)error {
    
    dispatch_barrier_async(message_callback_queue(), ^{
        if ([self.delegates respondsToSelector:@selector(messages:loadMessagesFromPage:didCompleteWithError:)]) {
            [self.delegates messages:self loadMessagesFromPage:page didCompleteWithError:error];
        }
    });
}

- (void)onReceiveMessage:(Y2WBaseMessage *)message {
    
    dispatch_barrier_async(message_callback_queue(), ^{
        if ([self.delegates respondsToSelector:@selector(messages:onRecvMessage:)]) {
            [self.delegates messages:self onRecvMessage:message];
        }
    });
}

- (void)willSendMessage:(Y2WBaseMessage *)message {
    
    dispatch_barrier_async(message_callback_queue(), ^{
        if ([self.delegates respondsToSelector:@selector(messages:willSendMessage:)]) {
            [self.delegates messages:self willSendMessage:message];
        }
    });
}

- (void)sendMessage:(Y2WBaseMessage *)message progress:(CGFloat)progress {
    
    dispatch_barrier_async(message_callback_queue(), ^{
        if ([self.delegates respondsToSelector:@selector(messages:sendMessage:progress:)]) {
            [self.delegates messages:self sendMessage:message progress:progress];
        }
    });
}

- (void)sendMessage:(Y2WBaseMessage *)message didCompleteWithError:(NSError *)error {
    
    dispatch_barrier_async(message_callback_queue(), ^{
        if ([self.delegates respondsToSelector:@selector(messages:sendMessage:didCompleteWithError:)]) {
            [self.delegates messages:self sendMessage:message didCompleteWithError:error];
        }
    });
}

- (void)onUpdateMessage:(Y2WBaseMessage *)message {
    
    dispatch_barrier_async(message_callback_queue(), ^{
        if ([self.delegates respondsToSelector:@selector(messages:onUpdateMessage:)]) {
            [self.delegates messages:self onUpdateMessage:message];
        }
    });
}









#pragma mark - ———— 数据相关 ———— -

- (NSUInteger)count {
    
    return self.messageList.count;
}

- (void)addMessage:(Y2WBaseMessage *)message didCompletionBlock:(void (^)(NSError *error))block {

    dispatch_barrier_async(message_readwrite_queue(), ^{
        if (!self.messageList) self.messageList = [NSMutableSet set];
        [self.messageList addObject:message];
        
        if (block) block(nil);
    });
}

- (void)deleteMessage:(Y2WBaseMessage *)message didCompletionBlock:(void (^)(Y2WBaseMessage *dMessage, NSError *error))block {
    dispatch_barrier_async(message_readwrite_queue(), ^{
        [self getMessageWithMessage:message didCompletionBlock:^(Y2WBaseMessage *gMessage, NSError *error) {
            if (error && block) {
                block(gMessage, error);
                return;
            }
            if (gMessage) {
                [self.messageList removeObject:gMessage];
            }
            if (block) block(gMessage, nil);
        }];
    });
}

- (void)updateMessage:(Y2WBaseMessage *)message didCompletionBlock:(void (^)(Y2WBaseMessage *uMessage, NSError *error))block {
    dispatch_barrier_async(message_readwrite_queue(), ^{
        [self getMessageWithMessage:message didCompletionBlock:^(Y2WBaseMessage *gMessage, NSError *error) {
            if (error && block) {
                block(gMessage, error);
                return;
            }
            if (gMessage) {
                [gMessage updateWithMessage:message];
            }
            if (block) block(gMessage, nil);
        }];
    });
}

- (void)getMessageWithMessage:(Y2WBaseMessage *)message didCompletionBlock:(void (^)(Y2WBaseMessage *gMessage, NSError *error))block {
  
    dispatch_barrier_async(message_readwrite_queue(), ^{
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"messageId LIKE[CD] %@",message.messageId];
        NSSet *messages = [self.messageList filteredSetUsingPredicate:predicate];
        if (block) block(messages.anyObject,nil);
    });
}

/**
 *  获取一条消息之前的消息
 *
 *  @param message 如果是空则取最新的消息，否则只取此消息之前的消息
 *  @param limit   需要获取的最大数量
 *
 *  @return 以创建时间升序排序的数组
 */
- (void)getBeforeMessagesFromMessage:(Y2WBaseMessage *)message limit:(NSUInteger)limit didCompletionBlock:(void (^)(NSArray<Y2WBaseMessage *> *messages, NSError *error))block {
    
    dispatch_barrier_async(message_readwrite_queue(), ^{

        NSSet *messages = [self.messageList copy];
        if (message) {
            NSPredicate *predicate = [NSPredicate predicateWithFormat:@"createdAt < %@",message.createdAt];
            messages = [self.messageList filteredSetUsingPredicate:predicate];
        }
        if (block) block([messages sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:YES]]],nil);
    });
}

/**
 *  获取一条消息之后的消息
 *
 *  @param message 如果是空则取最新的消息，否则只取此消息之后的消息
 *  @param limit   需要获取的最大数量
 *
 *  @return 以创建时间升序排序的数组
 */
- (NSArray *)getAfterMessagesFromMessage:(Y2WBaseMessage *)message limit:(NSUInteger)limit {

    NSSet *messages = [self.messageList copy];
    if (message) {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"createdAt > %@",message.createdAt];
        messages = [self.messageList filteredSetUsingPredicate:predicate];
    }
    
    return [messages sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:YES]]];
}

/**
 *  获取本地最新一条消息（没有发送成功不算）
 *
 *  @param block 结果回调
 */
- (void)getLastMessageDidCompletionBlock:(void (^)(Y2WBaseMessage *message, NSError *error))block {
    dispatch_barrier_async(message_readwrite_queue(), ^{
        if (!self.messageList.count) {
            if (block) block(nil, nil);
            return;
        }
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"status LIKE[CD] %@",@"stored"];
        NSSet *messagesSet = [self.messageList filteredSetUsingPredicate:predicate];
        NSArray *messages = [messagesSet sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:YES]]];
        if (block) block(messages.lastObject, nil);
    });
}

#pragma mark - ———— Helper ———— -
- (BOOL)isUploadFile:(NSString *)type
{
    if ([type isEqualToString:@"text"] || [type isEqualToString:@"system"] ||[type isEqualToString:@"singleavcall"] ||[type isEqualToString:@"groupavcall"] ||[type isEqualToString:@"avcall"]) return NO;
    else    return YES;
}

- (void)storeFileMessage:(Y2WBaseMessage *)message success:(void(^)(Y2WBaseMessage *message))success
{
    FileAppend *append;
    FileAppend *thumAppend;
    NSArray *appends;
    if ([message.type isEqualToString:@"image"]) {
        Y2WImageMessage *imgMessage = (Y2WImageMessage *)message;
        append = [FileAppend fileAppendWithFilePath:imgMessage.imagePath name:@"file" fileName:[NSString stringWithFormat:@"IMG_%@.jpeg", @([NSDate timeIntervalSinceReferenceDate])] mimeType:@"image/png"];
        thumAppend = [FileAppend fileAppendWithFilePath:imgMessage.thumImagePath name:@"file" fileName:[NSString stringWithFormat:@"thumIMG_%@.jpeg", @([NSDate timeIntervalSinceReferenceDate])] mimeType:@"image/png"];
        appends = @[append,thumAppend];
    }
    else if([message.type isEqualToString:@"video"])
    {
        Y2WVideoMessage *videoMessage = (Y2WVideoMessage *)message;
        append = [FileAppend fileAppendWithFilePath:videoMessage.videoPath name:@"file" fileName:[NSString stringWithFormat:@"video_%@.mp4", @([NSDate timeIntervalSinceReferenceDate])] mimeType:@"video/mp4"];
        thumAppend = [FileAppend fileAppendWithFilePath:videoMessage.thumImagePath name:@"file" fileName:[NSString stringWithFormat:@"thumIMG_%@.jpeg", @([NSDate timeIntervalSinceReferenceDate])] mimeType:@"image/png"];
        appends = @[append,thumAppend];
    }
    else if ([message.type isEqualToString:@"audio"])
    {
        Y2WAudioMessage *audioMessage = (Y2WAudioMessage *)message;
        append = [FileAppend fileAppendWithFilePath:audioMessage.audioPath name:@"file" fileName:[NSString stringWithFormat:@"audio_%@.aac", @([NSDate timeIntervalSinceReferenceDate])] mimeType:@"audio/mpeg"];
        appends = @[append];
    }
    else if ([message.type isEqualToString:@"location"])
    {
        Y2WLocationMessage *locationMessage = (Y2WLocationMessage *)message;
        thumAppend = [FileAppend fileAppendWithFilePath:locationMessage.thumImagepath name:@"file" fileName:[NSString stringWithFormat:@"thumIMG_%@.jpeg", @([NSDate timeIntervalSinceReferenceDate])] mimeType:@"image/png"];
        appends = @[thumAppend];
    }
    else if ([message.type isEqualToString:@"file"])
    {
        Y2WFileMessage *fileMessage = (Y2WFileMessage *)message;
        append = [FileAppend fileAppendWithFilePath:fileMessage.filePath name:@"file" fileName:[NSString stringWithFormat:@"file_%@", @([NSDate timeIntervalSinceReferenceDate])] mimeType:@"text/html"];
        appends = @[append];
    }
    
    [self.remote uploadFile:appends progress:^(CGFloat fractionCompleted) {
        [self sendMessage:message progress:fractionCompleted];
    } success:^(NSArray *fileArray) {
//        NSLog(@"file 4.21 : %@",fileArray);
        if ([message.type isEqualToString:@"image"]) {
            NSString *src = [URL attachmentsOfContentWithNoHeader:fileArray[0][@"id"]];
            NSString *thumbnail = [URL attachmentsOfContentWithNoHeader:fileArray[1][@"id"]];
            message.content = @{@"src":src,
                                @"thumbnail":thumbnail,
                                @"width":message.content[@"width"],
                                @"height":message.content[@"height"]};
        }
        if ([message.type isEqualToString:@"video"]) {
            NSString *src = [URL attachmentsOfContentWithNoHeader:fileArray[0][@"id"]];
            NSString *thumbnail = [URL attachmentsOfContentWithNoHeader:fileArray[1][@"id"]];
            message.content = @{@"src":src,
                                @"thumbnail":thumbnail,
                                @"width":message.content[@"width"],
                                @"height":message.content[@"height"]};
        }
        if ([message.type isEqualToString:@"location"])
        {
            NSString *thumbnail = [URL attachmentsOfContentWithNoHeader:fileArray[0][@"id"]];
            message.content = @{@"thumbnail":thumbnail,
                                @"width":message.content[@"width"],
                                @"height":message.content[@"height"],
                                @"longitude":message.content[@"longitude"],
                                @"latitude":message.content[@"latitude"]};
        }
        if ([message.type isEqualToString:@"audio"]) {
            NSString *thumbnail = [URL attachmentsOfContentWithNoHeader:fileArray[0][@"id"]];
            message.content = @{@"src":thumbnail,
                                @"second":message.content[@"second"]};

        }
        if ([message.type isEqualToString:@"file"]) {
            NSString *thumbnail = [URL attachmentsOfContentWithNoHeader:fileArray[0][@"id"]];
            message.content = @{@"src":thumbnail,
                                @"name":message.content[@"name"],
                                @"size":message.content[@"size"]};
            
        }
        
        if (success)    success(message);
        
    } failure:^(NSError *error) {
        NSLog(@"error : %@",error);
    }];
}


- (UIImage *)getThumbnailsOfVideo:(NSString *)videoPath
{
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:[NSURL fileURLWithPath:videoPath] options:nil];
    AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    gen.appliesPreferredTrackTransform = YES;
    CMTime time = CMTimeMakeWithSeconds(0, 60); // 参数( 截取的秒数， 视频每秒多少帧)
    NSError *error = nil;
    CMTime actualTime;
    CGImageRef image = [gen copyCGImageAtTime:time actualTime:&actualTime error:&error];
    UIImage *thumb = [[UIImage alloc] initWithCGImage:image];
    CGImageRelease(image);
    return thumb;
}

- (NSString *)getThumnailsPath:(UIImage *)image
{
    NSString *thumImgName = [NSString stringWithFormat:@"thumIMG_%@.jpeg", @([NSDate timeIntervalSinceReferenceDate])];
    NSString *thumImgPath = [NSString getDocumentPathInbox:thumImgName];
    NSData *thumImgData = UIImageJPEGRepresentation(image,0.1);
    [thumImgData writeToFile:thumImgPath atomically:YES];
    return thumImgPath;
}

- (NSString *)storeLocalFileWithPath:(NSString *)filePath type:(NSString *)type
{
    NSString *fileName;
    if ([type isEqualToString:@"audio"]) {
        fileName = [NSString stringWithFormat:@"audio_%@.aac",@([NSDate timeIntervalSinceReferenceDate])];
    }
    NSString *path = [NSString getDocumentPath:fileName Type:type];
    NSData *data = [NSData dataWithContentsOfFile:filePath];
    [data writeToFile:path atomically:YES];
    return path;
}

#pragma mark - ———— 消息构造 ———— -

- (Y2WBaseMessage *)createMessage:(id)data {
    
    Y2WBaseMessage *message = [[Y2WBaseMessage alloc]init];
    message.sessionId = self.session.sessionId;
    message.sender = self.session.sessions.user.userId;
    message.type = @"text";
    message.status = @"storing";
    message.content = @{@"text": data};
    return message;
}

- (Y2WTextMessage *)messageWithText:(NSString *)text {
    
    Y2WTextMessage *message = [[Y2WTextMessage alloc]init];
    message.sessionId = self.session.sessionId;
    message.sender = self.session.sessions.user.userId;
    message.type = @"text";
    message.status = @"storing";
    message.content = @{@"text": text};
    message.messageId = [NSUUID UUID].UUIDString;
    return message;
}

- (Y2WImageMessage *)messageWithImage:(UIImage *)image
{
    Y2WImageMessage *message = [[Y2WImageMessage alloc]init];
    message.sessionId = self.session.sessionId;
    message.sender = self.session.sessions.user.userId;
    message.type = @"image";
    message.status = @"storing";
//    message.content = @{@"text": text};
    
    NSString *imgName = [NSString stringWithFormat:@"IMG_%@.jpeg", @([NSDate timeIntervalSinceReferenceDate])];
    NSString *imgPath = [NSString getDocumentPathInbox:imgName];
    NSData *imgData = UIImageJPEGRepresentation(image,0.5);
    [imgData writeToFile:imgPath atomically:YES];
    
    NSString *thumImgName = [NSString stringWithFormat:@"thumIMG_%@.jpeg", @([NSDate timeIntervalSinceReferenceDate])];
    NSString *thumImgPath = [NSString getDocumentPathInbox:thumImgName];
    NSData *thumImgData = UIImageJPEGRepresentation(image,0.1);
    [thumImgData writeToFile:thumImgPath atomically:YES];

    message.imagePath = imgPath;
    message.thumImagePath = thumImgPath;
    message.messageId = [NSUUID UUID].UUIDString;
    message.content = @{@"src":imgPath,
                        @"thumbnail":thumImgPath,
                        @"width":[NSString stringWithFormat:@"%lf",image.size.width*0.1],
                        @"height":[NSString stringWithFormat:@"%lf",image.size.height*0.1]};
    
    return message;
}

- (Y2WVideoMessage *)messageWithVideoPath:(NSString *)videoPath
{
    Y2WVideoMessage *message = [[Y2WVideoMessage alloc]init];
    message.sessionId = self.session.sessionId;
    message.sender = self.session.sessions.user.userId;
    message.type = @"video";
    message.status = @"storing";
    
    message.videoPath = videoPath;
    UIImage *image = [self getThumbnailsOfVideo:videoPath];
//    if (image == nil) return nil;
    NSString *thumImgPath = [self getThumnailsPath:image];

    message.thumImagePath = thumImgPath;
    message.content = @{@"src":videoPath,
                        @"thumbnail":thumImgPath,
                        @"width":[NSString stringWithFormat:@"%lf",image.size.width],
                        @"height":[NSString stringWithFormat:@"%lf",image.size.height]};
    
    return message;
}

- (Y2WFileMessage *)messageWithFilePath:(FileModel *)model
{
    Y2WFileMessage *message = [[Y2WFileMessage alloc]init];
    message.sessionId = self.session.sessionId;
    message.sender = self.session.sessions.user.userId;
    message.type = @"file";
    message.status = @"storing";
    
    message.filePath = model.path;
    NSData *file = [NSData dataWithContentsOfFile:model.path];
    message.fileSize = file.length;
    message.content = @{@"src":model.path,
                        @"name":model.title,
                        @"size":@(file.length)};
    
    return message;
}

- (Y2WLocationMessage *)messageWithLocationPoint:(LocationPoint *)locationPoint
{
    Y2WLocationMessage *message = [[Y2WLocationMessage alloc]init];
    message.sessionId = self.session.sessionId;
    message.sender = self.session.sessions.user.userId;
    message.type = @"location";
    message.status = @"storing";
    
    message.thumImagepath = locationPoint.imagePath;
    message.longitude = locationPoint.coordinate.longitude;
    message.latitude = locationPoint.coordinate.latitude;
    message.title = locationPoint.title;
    message.content = @{@"thumbnail":message.thumImagepath,
                        @"width":@(200),
                        @"height":@(120),
                        @"longitude":@(locationPoint.coordinate.longitude),
                        @"latitude":@(locationPoint.coordinate.latitude)};
    return message;
}

- (Y2WAudioMessage *)messageWithAudioPath:(NSString *)audioPath timer:(NSInteger)audioTimer
{
    
    Y2WAudioMessage *message = [[Y2WAudioMessage alloc]init];
    message.sessionId = self.session.sessionId;
    message.sender = self.session.sessions.user.userId;
    message.type = @"audio";
    message.status = @"storing";
    
    NSString *path = [self storeLocalFileWithPath:audioPath type:message.type];
    message.audioPath = path;
    message.audioTimer = audioTimer;
    message.content = @{@"src":path,
                        @"second":@(audioTimer)};
    return message;
}

- (Y2WAVCallMessage *)messageWithAVCall:(AVCallModel *)model
{
    Y2WAVCallMessage *message = [[Y2WAVCallMessage alloc]init];
    message.sessionId = self.session.sessionId;
    message.sender = self.session.sessions.user.userId;
    message.type = model.avcall;
    message.status = @"storing";
    
    message.content = @{@"type":model.avcall,
                        @"content":@{@"senderId":model.senderId,
                                     @"receiversIds":model.receiverIds,
                                     @"avcalltype":model.type,
                                     @"channelId":model.channelId,
                                     @"sessionId":model.sessionId}
                        };
    return message;
}
@end








@interface Y2WMessagesRemote ()

@property (nonatomic, weak) Y2WMessages *messages;

@property (nonatomic, copy) NSString *timeStamp;

@property (nonatomic, assign) BOOL syncMaximum;     // 每次同步任务的最大次数

@property (nonatomic, assign) BOOL synchronizing;   // 是否正在同步中

@property (nonatomic, assign) BOOL anotherTask;     // 是否有新任务

@end



@implementation Y2WMessagesRemote
@synthesize timeStamp = _timeStamp;

- (instancetype)initWithMessages:(Y2WMessages *)messages {
    
    if (self = [super init]) {
        self.messages = messages;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncNotification:) name:Y2WMessageDidChangeNotification object:nil];
    }
    return self;
}

- (void)syncNotification:(NSNotification *)noti {
    NSDictionary *dict = noti.object;

    if (![[dict[@"sessionId"] uppercaseString] isEqualToString:self.messages.session.sessionId.uppercaseString]) return;
    if (![dict[@"sessionType"] isEqualToString:self.messages.session.type]) return;
    
    [self sync];
}


- (void)getLastMessageDidCompletionBlock:(void (^)(NSArray *))success failure:(void (^)(NSError *))failure {
    
    if (!self.messages.session.sessionId) {
        if (failure) failure([NSError errorWithDomain:@"sessionId为空" code:0 userInfo:nil]);
        return;
    }
    
    [HttpRequest GETWithURL:[URL acquireMessages:self.messages.session.sessionId] parameters:@{@"limit":@"20"} success:^(id data) {
        NSMutableArray *messages = [NSMutableArray array];
        for (NSDictionary *dic in data[@"entries"]) {
            Y2WBaseMessage *message = [Y2WBaseMessage createMessageWithDict:dic];
            [messages addObject:message];
        }
        if (success) success(messages);
        
    } failure:^(id msg) {
        if (failure) failure([NSError errorWithDomain:msg code:0 userInfo:nil]);
    }];
}



- (void)sync {
    // 如果没有添加messages的代理则不做操作
    if (!self.messages.delegates.count) return;
    
    // 如果消息管理对象没有实现回调则不操作
    if (![self.messages respondsToSelector:@selector(messagesRemote:syncMessages:didCompleteWithError:)]) return;

    // 如果已经有新任务则不继续操作
    if (self.anotherTask) return;
    
    // 如果正在同步中则添加新任务后返回不再继续操作
    if (self.synchronizing) {
        self.anotherTask = YES;
        return;
    }
    
    // 开始同步
    self.synchronizing = YES;
    
    // 从时间戳开始获取一次消息
    [HttpRequest GETWithURL:[URL acquireMessages:self.messages.session.sessionId]
                  timeStamp:self.timeStamp
                 parameters:@{@"limit":@"10"}
                    success:^(NSDictionary *data) {

                        NSMutableArray *messages = [NSMutableArray array];
                        NSArray *entries = data[@"entries"];
                        NSUInteger count = [data[@"total_count"] integerValue] - entries.count;
                        
                        for (NSDictionary *dic in entries) {
                            Y2WBaseMessage *message = [Y2WBaseMessage createMessageWithDict:dic];
                            message.status = @"stored";
                            if (message != nil) [messages addObject:message];
                        }
                        
                        [messages sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:YES]]];
                        if (messages.count) {
                            self.timeStamp = [messages.lastObject createdAt];
                            [self.messages messagesRemote:self syncMessages:messages didCompleteWithError:nil];
                        }
                        
                        
                        BOOL continueSync = count || self.anotherTask;
                        
                        self.synchronizing = NO;
                        self.anotherTask = NO;

                        // 如果需要就再同步一次消息
                        if (continueSync) [self sync];
                        
                        // 如果同步结束就同步一次用户会话
                        if (!count) [self.messages.session.sessions.user.userConversations.remote sync];
                        
                        // todo members时间戳不同就同步一次
                        if (self.messages.session) {
                            [self.messages.session.updatedAt isEqualToString:data[@"sessionUpdatedAt"]];
//                            [self.messages.session]
                        }
                        
                    } failure:^(NSError *error) {
                        
                        self.synchronizing = NO;
                        [self.messages messagesRemote:self syncMessages:nil didCompleteWithError:error];
                    }];
}



- (void)storeMessages:(Y2WBaseMessage *)message success:(void (^)(Y2WBaseMessage *message))success failure:(void (^)(NSError *))failure {
    
    NSDictionary *parameters = @{@"type":message.type,@"content":[message.content toJsonString],@"sender":message.sender};
    
    [HttpRequest POSTWithURL:[URL acquireMessages:message.sessionId] parameters:parameters success:^(id data) {
        [message updateWithDict:data];
        NSString *temp_sessionId = [NSString stringWithFormat:@"%@_%@",self.messages.session.type,self.messages.session.sessionId];
        [[Y2WUsers getInstance].getCurrentUser.bridge updateSessionWithSession:self.messages.session];
        [[Y2WUsers getInstance].getCurrentUser.bridge sendMessageWithSession:self.messages.session Content:@[@{@"type":@0},@{@"type":@1,@"sessionId":temp_sessionId}]];

        if (success) success(message);
        
    } failure:failure];
}

- (void)storeAVCallMessage:(Y2WBaseMessage *)message
{
    NSString *temp_sessionId = [NSString stringWithFormat:@"%@_%@",self.messages.session.type,self.messages.session.sessionId];
    [[Y2WUsers getInstance].getCurrentUser.bridge updateSessionWithSession:self.messages.session];
    [[Y2WUsers getInstance].getCurrentUser.bridge sendMessageWithSession:self.messages.session Content:@[@{@"type":@0},@{@"type":@1,@"sessionId":temp_sessionId},message.content]];
}

- (void)updataMessage:(Y2WBaseMessage *)message session:(Y2WSession *)session success:(void (^)(Y2WBaseMessage *))success failure:(void (^)(NSError *))failure
{
//    NSLog(@"message : %@",message);
//    NSLog(@"url : %@",[URL aboutMessage:message.messageId Session:message.sessionId]);

    [HttpRequest PUTWithURL:[URL aboutMessage:message.messageId Session:message.sessionId] parameters:@{@"sender":message.sender,@"content":message.text,@"type":message.type} success:^(id data) {
        [self sync];
        NSString *temp_sessionId = [NSString stringWithFormat:@"%@_%@",session.type,session.sessionId];
        [[Y2WUsers getInstance].getCurrentUser.bridge updateSessionWithSession:session];
        [[Y2WUsers getInstance].getCurrentUser.bridge sendMessageWithSession:session Content:@[@{@"type":@0},@{@"type":@1,@"sessionId":temp_sessionId}]];
    } failure:^(NSError *error) {
//        NSLog(@"%@",error);
        if (failure) {
            failure(error);
        }
    }];
}

- (void)uploadFile:(NSArray *)fileAppends
          progress:(ProgressBlock)progress
           success:(void (^)(NSArray *))success
           failure:(void (^)(NSError *))failure
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        dispatch_semaphore_t dispatchSemaphore = dispatch_semaphore_create(0);
        __block NSMutableArray *fileArray = [NSMutableArray array];
        __block NSError *failureError = nil;
        __block CGFloat totleProgress = 0;
        for (FileAppend *fileAppend in fileAppends) {

            [HttpRequest UPLOADWithURL:[URL attachments] parameters:@{@"fileName":fileAppend.fileName} fileAppend:fileAppend progress:^(CGFloat fractionCompleted) {

                if (totleProgress <= 0.8) {
                    totleProgress = fractionCompleted*0.8;
                }
                else{
                    totleProgress = 0.8+fractionCompleted*0.2;
                }
                progress(totleProgress);
            } success:^(id data) {
                [fileArray addObject:data];
                dispatch_semaphore_signal(dispatchSemaphore);
                
            } failure:^(NSError *error) {
                
                failureError = error;
                dispatch_semaphore_signal(dispatchSemaphore);
            }];
            
            dispatch_semaphore_wait(dispatchSemaphore, DISPATCH_TIME_FOREVER);
            
            if (failureError) {
                if (failure) failure(failureError);
                return;
            }
        }

        if (success) success(fileArray);
    });

    
}

- (void)downLoadFileWithMessage:(Y2WBaseMessage *)message progress:(ProgressBlock)progress success:(void (^)(Y2WBaseMessage *))success failure:(void (^)(NSError *))failure
{
    [HttpRequest DOWNLOADWithURL:[NSString stringWithFormat:@"%@%@?access_token=%@",[URL baseURL],message.content[@"src"],[[Y2WUsers getInstance].getCurrentUser token]] parameters:nil progress:^(CGFloat fractionCompleted) {
        progress(fractionCompleted);
        
    } success:^(NSURL *path) {
        
        if ([message.type isEqualToString:@"video"]) {
            Y2WVideoMessage *videoMessage = (Y2WVideoMessage *)message;
            NSString *tempPath = [NSString stringWithFormat:@"%@",path];
            videoMessage.videoPath = [tempPath substringFromIndex:7];
        }
        if ([message.type isEqualToString:@"audio"]) {
            Y2WAudioMessage *audioMessage = (Y2WAudioMessage *)message;
            NSString *tempPath = [[NSString stringWithFormat:@"%@",path] substringFromIndex:7];
            NSData *data = [NSData dataWithContentsOfFile:tempPath];
            NSString *fileName =[NSString stringWithFormat:@"audio_%@.aac",@([NSDate timeIntervalSinceReferenceDate])];
            NSString *path = [NSString getDocumentPath:fileName Type:audioMessage.type];
            [data writeToFile:path atomically:YES];
            audioMessage.audioPath = path;
        }
        success(message);
        
    } failure:^(NSError *error) {
        failure(error);
    }];
}

#pragma mark - ———— setter ———— -

- (void)setTimeStamp:(NSString *)timeStamp {
    _timeStamp = timeStamp;
    [[NSUserDefaults standardUserDefaults] setObject:timeStamp forKey:[self timeStampKey]];
    [[NSUserDefaults standardUserDefaults] synchronize];
}


#pragma mark - ———— getter ———— -

- (NSString *)timeStamp {
    if (!_timeStamp) {
//        _timeStamp = [[NSUserDefaults standardUserDefaults] objectForKey:[self timeStampKey]];
        _timeStamp = _timeStamp ?: @"1990-01-01T00:00:00";
    }
    return _timeStamp;
}

- (NSString *)timeStampKey {
    return [@"messagesTimeStampKey" stringByAppendingFormat:@"%@%@",self.messages.session.sessions.user.userId,self.messages.session.sessionId];
}


@end