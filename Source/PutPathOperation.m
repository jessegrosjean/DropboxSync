//
//  PutPathOperation.m
//  DropboxSync
//
//  Created by Jesse Grosjean on 8/10/10.
//  Copyright 2010 Hog Bay Software. All rights reserved.
//

#import "PutPathOperation.h"
#import "NSFileManager_Additions.h"
#import "FolderSyncPathOperation.h"
#import "PathController_Private.h"
#import "PathController.h"
#import "PathMetadata.h"


@implementation PutPathOperation

- (void)removeTempUploadPath {
	if (tempUploadPath) {
		[[NSFileManager defaultManager] removeItemAtPath:tempUploadPath error:NULL];
		[tempUploadPath release];
		tempUploadPath = nil;
	}
}

- (void)dealloc {
	[self removeTempUploadPath];
	[super dealloc];
}

- (void)main {
	NSString *serverPath = [self.pathController localPathToServer:localPath];
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSError *error;

	BOOL isDirectory;
	if ([fileManager fileExistsAtPath:localPath isDirectory:&isDirectory]) {
		if (isDirectory) {
			[self updatePathActivity:PutPathActivity];
			[self.client createFolder:serverPath];
		} else {
			tempUploadPath = [[fileManager tempDirectoryUnusedPath] retain];
			if ([fileManager copyItemAtPath:localPath toPath:tempUploadPath error:&error]) {
				[self updatePathActivity:PutPathActivity];
                
                [self.client uploadFile:[serverPath lastPathComponent] toPath:[serverPath stringByDeletingLastPathComponent] withParentRev:[self pathMetadata:YES].rev fromPath:tempUploadPath];
                
			} else {
				[self finish:error];
			}
		}
	} else {
		[self finish];
	}
}

- (void)retryWithError:(NSError *)error {
	[self removeTempUploadPath];
	[super retryWithError:error];
}

#pragma mark -
#pragma mark DBRestClientDelegate

- (void)restClient:(DBRestClient*)aClient createdFolder:(DBMetadata *)aServerMetadata {
	self.serverMetadata = aServerMetadata;
	[self finish];
}

- (void)restClient:(DBRestClient*)aClient createFolderFailedWithError:(NSError*)error {
	[self retryWithError:error];
}

- (void)restClient:(DBRestClient*)client uploadedFile:(NSString*)destPath from:(NSString*)srcPath metadata:(DBMetadata*)metadata {
	PathMetadata *pathMetadata = [self pathMetadata:YES];

	pathMetadata.pathState = SyncedPathState;
	[self.pathController enqueuePathChangedNotification:localPath changeType:StateChangedPathsKey];
	pathMetadata.lastSyncIsDirectory = NO;
	pathMetadata.lastSyncName = [localPath lastPathComponent];
	pathMetadata.lastSyncDate = [[[NSFileManager defaultManager] attributesOfItemAtPath:srcPath error:NULL] fileModificationDate];
    pathMetadata.lastSyncHash = metadata.rev; // store revision value in hash for a file.
	[pathMetadata.managedObjectContext save:NULL];
    
    self.serverMetadata = metadata;
    
	NSFileManager *fileManager = [NSFileManager defaultManager];
    
	if (pathMetadata != nil && !pathMetadata.isDeleted && [fileManager fileExistsAtPath:localPath]) {
		NSDate *lastSyncDate = pathMetadata.lastSyncDate;
		NSDate *currentDate = [[fileManager attributesOfItemAtPath:localPath error:NULL] fileModificationDate];
		
		if ([lastSyncDate isEqualToDate:currentDate]) {
			[fileManager setAttributes:[NSDictionary dictionaryWithObject:serverMetadata.lastModifiedDate forKey:NSFileModificationDate] ofItemAtPath:localPath error:NULL];
			[self.pathController enqueuePathChangedNotification:localPath changeType:ModifiedPathsKey];
		}
	}
	
	[self finish];
}

- (void)restClient:(DBRestClient*)client uploadFileFailedWithError:(NSError*)error {
    [self retryWithError:error];
}

@end
