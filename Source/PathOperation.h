//
//  SyncPathOperation.h
//  DropboxSync
//
//  Created by Jesse Grosjean on 8/7/10.
//  Copyright 2010 Hog Bay Software. All rights reserved.
//

#import <DropboxSDK/DropboxSDK.h>
#import "PathMetadata.h"

//
// Base for all path sync operations.
//

@class FolderSyncPathOperation;

@interface PathOperation : NSOperation <DBRestClientDelegate> {
	BOOL isExecuting;
	BOOL isFinished;
	BOOL updatedLastSyncHashOnFinish;
	BOOL createPathMetadataOnFinish;
	PathState successPathState;
	DBRestClient *client;
	NSString *localPath;
	DBMetadata *serverMetadata;
	NSUInteger retriesRemaining;
	FolderSyncPathOperation *folderSyncPathOperation;
}

+ (PathOperation *)pathOperationWithPath:(NSString *)aLocalPath serverMetadata:(DBMetadata *)aServerMetadata;

- (id)initWithPath:(NSString *)aLocalPath serverMetadata:(DBMetadata *)aServerMetadata;

@property (readonly) BOOL isExecuting;
@property (readonly) BOOL isFinished;
@property (assign) BOOL createPathMetadataOnFinish;;
@property (assign) PathState successPathState;
@property (readonly) DBRestClient *client;
@property (nonatomic, retain) DBMetadata *serverMetadata;
@property (readonly) PathController *pathController;
@property (readonly) PathControllerLogLevel logLevel;
@property (nonatomic, retain) FolderSyncPathOperation *folderSyncPathOperation;

- (void)log:(NSString *)aString level:(PathControllerLogLevel)level prettyFunction:(const char *)prettyFunction line:(NSUInteger)line;
- (PathMetadata *)pathMetadata:(BOOL)createIfNeccessary;
- (void)updatePathActivity:(PathActivity)pathActivity;
- (void)deleteLocalPath;

- (void)finish;
- (void)retryWithError:(NSError *)error;
- (void)retrySelector:(SEL)aSelector withError:(NSError *)error;
- (void)finish:(NSError *)error;

@end
