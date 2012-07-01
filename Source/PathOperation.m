//
//  SyncPathOperation.m
//  DropboxSync
//
//  Created by Jesse Grosjean on 8/7/10.
//  Copyright 2010 Hog Bay Software. All rights reserved.
//

#import "PathOperation.h"
#import "FolderSyncPathOperation.h"
#import "PathController_Private.h"
#import "PathController.h"
#import "PathMetadata.h"

#define RETRY_COUNT 3

@implementation PathOperation

+ (PathOperation *)pathOperationWithPath:(NSString *)aLocalPath serverMetadata:(DBMetadata *)aServerMetadata {
	return [[[[self class] alloc] initWithPath:aLocalPath serverMetadata:aServerMetadata] autorelease];
}

- (id)initWithPath:(NSString *)aLocalPath serverMetadata:(DBMetadata *)aServerMetadata {
	self = [super init];
	successPathState = SyncedPathState;
	localPath = [aLocalPath retain];
	serverMetadata = [aServerMetadata retain];
	retriesRemaining = RETRY_COUNT;
	createPathMetadataOnFinish = YES;
	updatedLastSyncHashOnFinish = YES;
	return self;
}

- (void)dealloc {
	PathControllerLogDebug(@"Dealloc %@", self);
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[localPath release];
	[serverMetadata release];
	[client release];
	[super dealloc];
}

- (NSString *)description {
	return [[super description] stringByAppendingFormat:@" %@", [self.pathController localPathToNormalized:localPath]];
}

- (BOOL)isConcurrent {
    return YES;
}

@synthesize isExecuting;
@synthesize isFinished;
@synthesize createPathMetadataOnFinish;
@synthesize successPathState;
@synthesize client;

- (DBRestClient *)client {
	if (!client) {
		client = [[DBRestClient alloc] initWithSession:[DBSession sharedSession]];
		client.delegate = self;
	}
	return client;
}

@synthesize serverMetadata;

- (PathController *)pathController {
	return self.folderSyncPathOperation.pathController;
}

- (PathControllerLogLevel)logLevel {
	return self.pathController.logLevel;
}

@synthesize folderSyncPathOperation;

- (void)start {
	if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(start) withObject:nil waitUntilDone:NO];
        return;
    }
	
	if (self.isCancelled) {
		[self finish];
	} else {
		[self willChangeValueForKey:@"isExecuting"];
		isExecuting = YES;
		[self didChangeValueForKey:@"isExecuting"];
		PathControllerLogInfo(@"Executing %@", self);
		[self main];
	}
}

- (void)cancel {
	if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(cancel) withObject:nil waitUntilDone:NO];
        return;
    }
	
	if (self.isExecuting) {
		return;
	}
	
	[super cancel];
	[client cancelAllRequests];
	PathControllerLogInfo(@"Canceled %@", self);	
	[self finish];
}

- (void)log:(NSString *)aString level:(PathControllerLogLevel)level prettyFunction:(const char *)prettyFunction line:(NSUInteger)line {
	[self.pathController log:aString level:level prettyFunction:prettyFunction line:line];
}

- (PathMetadata *)pathMetadata:(BOOL)createIfNeccessary {
	return [folderSyncPathOperation.pathController pathMetadataForLocalPath:localPath createNewLocalIfNeeded:createIfNeccessary];
}

- (void)updatePathActivity:(PathActivity)pathActivity {
	[folderSyncPathOperation.pathController setPathActivity:pathActivity forPath:localPath];
}

- (void)deleteLocalPath {
	BOOL removedAll;
	NSError *error = nil;
	if (![self.pathController removeUnchangedItemsAtPath:localPath error:&error removedAll:&removedAll]) {
		[self finish:error];
	} else {
		[self.pathController deletePathMetadataForLocalPath:localPath];
		self.createPathMetadataOnFinish = NO;
		if (!removedAll) {
			self.folderSyncPathOperation.needsCleanupSync = YES;
		}		
		[self finish];
	}
}

- (void)finish {
	[self finish:nil];
}

- (void)retryWithError:(NSError *)error {
	[self retrySelector:@selector(main) withError:error];
}

- (void)retrySelector:(SEL)aSelector withError:(NSError *)error {
	if (retriesRemaining > 0) {
		retriesRemaining--;
		PathControllerLogInfo(@"Retry #%i %@", RETRY_COUNT - retriesRemaining, self);
		NSTimeInterval delay = (RETRY_COUNT - retriesRemaining) * 0.5;
		[self performSelector:aSelector withObject:nil afterDelay:delay];
	} else {
		[self finish:error];
	}
}

- (void)updatedPathMetadata:(NSError *)error {
	PathMetadata *pathMetadata = [self pathMetadata:createPathMetadataOnFinish];	
	
	if (error) {
		if (!pathMetadata.isDeleted) {
			pathMetadata.pathError = error;
			pathMetadata.pathState = SyncErrorPathState;
		}
		[folderSyncPathOperation.pathController enqueuePathChangedNotification:localPath changeType:StateChangedPathsKey];
		PathControllerLogError(@"Finishing With Error %@ %@", self, error);
	} else {
		if (!pathMetadata.isDeleted) {
			if (serverMetadata) {
				pathMetadata.lastSyncName = [localPath lastPathComponent];
				if (updatedLastSyncHashOnFinish) {
					pathMetadata.lastSyncHash = serverMetadata.hash;
				}
				pathMetadata.lastSyncDate = serverMetadata.lastModifiedDate;
				pathMetadata.lastSyncIsDirectory = serverMetadata.isDirectory;
                if (!serverMetadata.isDirectory) {
                    pathMetadata.lastSyncHash = serverMetadata.rev; 
                }
			}
			pathMetadata.pathState = successPathState;
			[folderSyncPathOperation.pathController enqueuePathChangedNotification:localPath changeType:StateChangedPathsKey];
		}
		PathControllerLogInfo(@"Finishing %@", self);
	}
	
	[folderSyncPathOperation.pathController saveState];
}

- (void)finish:(NSError *)error {
	client.delegate = nil;
	[client autorelease];
	client = nil;

	if (!self.isCancelled) {
		[self updatedPathMetadata:error];
	}

	[self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];
    isExecuting = NO;
    isFinished = YES;
	[self updatePathActivity:NoPathActivity];
	[folderSyncPathOperation pathOperationFinished:self];
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}

@end
