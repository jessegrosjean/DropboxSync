//
//  GetPathOperation.m
//  DropboxSync
//
//  Created by Jesse Grosjean on 8/10/10.
//  Copyright 2010 Hog Bay Software. All rights reserved.
//

#import "GetPathOperation.h"
#import "DeleteLocalPathOperation.h"
#import "NSFileManager_Additions.h"
#import "FolderSyncPathOperation.h"
#import "PathController_Private.h"
#import "PutPathOperation.h"
#import "PathController.h"
#import "PathMetadata.h"

@implementation GetPathOperation

- (void)removeTempDownloadPath {
	if (tempDownloadPath) {
		[[NSFileManager defaultManager] removeItemAtPath:tempDownloadPath error:NULL];
		[tempDownloadPath release];
		tempDownloadPath = nil;
	}
}

- (void)dealloc {
	[self removeTempDownloadPath];
	[super dealloc];
}

- (BOOL)isPermanentPlaceholder {
	id <PathControllerDelegate> delegate = self.pathController.delegate;
	
	if ([delegate respondsToSelector:@selector(shouldSyncFile:)]) {
		return ![delegate shouldSyncFile:[serverMetadata.path lastPathComponent]];
	}
	
	return NO;
}

- (void)main {
	NSAssert(serverMetadata != nil, @"");
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	if (serverMetadata.isDirectory) {
		NSError *error;
		if ([fileManager createDirectoryAtPath:localPath withIntermediateDirectories:YES attributes:[NSDictionary dictionaryWithObject:serverMetadata.lastModifiedDate forKey:NSFileModificationDate] error:&error]) {
			[self.pathController enqueuePathChangedNotification:localPath changeType:CreatedPathsKey];
			[self finish];
		} else {
			[self finish:error];
		}
	} else {
		BOOL fileExistsAtPath = [fileManager fileExistsAtPath:localPath];
		if (!fileExistsAtPath) {
			NSError *error;
			if (![fileManager createDirectoryAtPath:[localPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&error]) {
				[self finish:error];
				return;
			}
				  
			if ([fileManager createFileAtPath:localPath contents:nil attributes:[NSDictionary dictionaryWithObject:serverMetadata.lastModifiedDate forKey:NSFileModificationDate]]) {
				[self.pathController enqueuePathChangedNotification:localPath changeType:CreatedPathsKey];
			} else {
				[self finish:error];
				return;
			}
		}
		
		if ([self isPermanentPlaceholder]) {
			self.successPathState = PermanentPlaceholderPathState;
			[self finish];
		} else {
			if (!fileExistsAtPath) {
				[self pathMetadata:YES].pathState = TemporaryPlaceholderPathState;
				[self.pathController enqueuePathChangedNotification:localPath changeType:StateChangedPathsKey];
			}

			[self updatePathActivity:GetPathActivity];
			tempDownloadPath = [[fileManager tempDirectoryUnusedPath] retain];
			NSString *serverPath = [self.pathController localPathToServer:localPath];
			[self.client loadFile:serverPath intoPath:tempDownloadPath];
		}
	}
}

- (void)retryWithError:(NSError *)error {
	[self removeTempDownloadPath];
	[super retryWithError:error];
}

#pragma mark -
#pragma mark DBRestClientDelegate

- (void)restClient:(DBRestClient*)client loadedFile:(NSString*)destPath contentType:(NSString*)contentType metadata:(DBMetadata*)metadata {
	NSAssert([destPath isEqual:tempDownloadPath], @"");
	
	NSDictionary *attributes = [NSDictionary dictionaryWithObject:serverMetadata.lastModifiedDate forKey:NSFileModificationDate];
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSError *error = nil;

	if (![fileManager setAttributes:attributes ofItemAtPath:tempDownloadPath error:&error]) {
		[self finish:error];
		return;
	}

    BOOL isDirectory = NO;
	BOOL localExists = [fileManager fileExistsAtPath:localPath isDirectory:&isDirectory];

	if (localExists) {
		if ([self pathMetadata:YES].pathState != TemporaryPlaceholderPathState) {
			NSDate *localModifiedDate = [[fileManager attributesOfItemAtPath:localPath error:nil] valueForKey:NSFileModificationDate];
			
			if (localModifiedDate == nil || ![localModifiedDate isEqualToDate:[self pathMetadata:YES].lastSyncDate]) {                
				// Conflict, new download doesn't match local version (local must have changed) so create a conflict.
				NSString *conflictPath = [fileManager conflictPathForPath:localPath error:&error];
				
				if (!conflictPath) {
					[self finish:error];
					return;
				} else {
					if (![self.pathController moveItemAtPath:localPath toPath:conflictPath error:&error]) {
						[self finish:error];
					}
				}
			}
			
			/*
			NSData *localData = [NSData dataWithContentsOfMappedFile:localPath];
			NSData *downloadedData = [NSData dataWithContentsOfMappedFile:tempDownloadPath];
			
			if (![localData isEqualToData:downloadedData]) {
				// Conflict, new download doesn't match local version (local must have changed) so create a conflict.
				NSString *conflictPath = [fileManager conflictPathForPath:localPath error:&error];
				
				if (!conflictPath) {
					[self finish:error];
					return;
				} else {
					if (![self.pathController moveItemAtPath:localPath toPath:conflictPath error:&error]) {
						[self finish:error];
					}
				}
			}*/
		}
		// Remove local in prep for copying in new download
		[fileManager removeItemAtPath:localPath error:NULL];
	} else {
		// If local doesn't exist make sure to create directory structure so that new can be copied into place.
		if (![fileManager createDirectoryAtPath:[localPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&error]) {
			[self finish:error];
			return;
		}
	}
    
    if (isDirectory) {
        [self pathMetadata:YES].lastSyncHash = metadata.hash;
    }
    else {
        [self pathMetadata:YES].lastSyncHash = metadata.rev;
    }

	// Copy new download into local file system.
	if ([fileManager copyItemAtPath:tempDownloadPath toPath:localPath error:&error]) {
		if (localExists) {
			[self.pathController enqueuePathChangedNotification:localPath changeType:ModifiedPathsKey];
		} else {
			[self.pathController enqueuePathChangedNotification:localPath changeType:CreatedPathsKey];
		}
		[self finish];
	} else {
		[self finish:error];
	}
}

- (void)restClient:(DBRestClient*)aClient loadFileFailedWithError:(NSError*)error {
	if (error.code == 404) {
		[self deleteLocalPath];
	} else {
		[self retryWithError:error];
	}
}

@end
