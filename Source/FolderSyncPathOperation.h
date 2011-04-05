//
//  LoadMetadataSyncPathOperation.h
//  DropboxSync
//
//  Created by Jesse Grosjean on 8/7/10.
//  Copyright 2010 Hog Bay Software. All rights reserved.
//

#import "PathOperation.h"

//
// This operation is responsible for syncing a folder (not recursive). It fetches server metadata, compares to local metadata
// and schedules individual path operations as needed to complete the sync. This operation doesn't complete until all individual
// operations have completed.
//

@interface FolderSyncPathOperation : PathOperation {
	BOOL loadedMetadata;
	BOOL needsCleanupSync;
	BOOL schedulingOperations;
	NSMutableSet *pathOperations;
	PathController *pathController;
    NSUInteger operationCount;
}

- (id)initWithPath:(NSString *)aLocalPath pathController:(PathController *)aPathController;

@property (assign) BOOL needsCleanupSync;

- (void)pathOperationFinished:(PathOperation *)aPathOperation;

@end