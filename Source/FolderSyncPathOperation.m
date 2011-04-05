//
//  LoadMetadataSyncPathOperation.m
//  DropboxSync
//
//  Created by Jesse Grosjean on 8/7/10.
//  Copyright 2010 Hog Bay Software. All rights reserved.
//

#import "FolderSyncPathOperation.h"
#import "DeleteLocalPathOperation.h"
#import "FolderSyncPathOperation.h"
#import "PathController_Private.h"
#import "DeletePathOperation.h"
#import "GetPathOperation.h"
#import "PutPathOperation.h"
#import "NSSet_Additions.h"
#import "PathController.h"
#import "DropboxSDK.h"
#include <sys/stat.h>
#include <dirent.h>


@interface PathController (FolderSyncPathOperationPrivate)
- (NSOperationQueue *)getOperationQueue;
- (NSOperationQueue *)putOperationQueue;
- (NSOperationQueue *)deleteOperationQueue;
- (NSOperationQueue *)folderSyncPathOperationOperationQueue;
@end

@implementation FolderSyncPathOperation

- (id)initWithPath:(NSString *)aLocalPath pathController:(PathController *)aPathController {
	self = [super initWithPath:aLocalPath serverMetadata:nil];
	folderSyncPathOperation = self; // don't retain
	pathController = [aPathController retain];
	pathOperations = [[NSMutableSet alloc] init];
	return self;
}

- (void)dealloc {
	folderSyncPathOperation = nil; // set nil before super can release
	[pathController release];
	NSAssert([pathOperations retainCount] > 0, @"");
	[pathOperations release];
	[super dealloc];
}

@synthesize needsCleanupSync;
@synthesize pathController;

- (FolderSyncPathOperation *)folderSyncPathOperation {
	return self;
}

- (void)main {
	[self updatePathActivity:GetPathActivity];
	[self.client loadMetadata:[pathController localPathToServer:localPath] withHash:[self pathMetadata:NO].lastSyncHash];
}

- (void)start {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(start) withObject:nil waitUntilDone:NO];
        return;
    }
	
	[[NSNotificationCenter defaultCenter] postNotificationName:BeginingFolderSyncNotification object:pathController];
	
	[super start];
}

- (void)cancel {
	if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(cancel) withObject:nil waitUntilDone:NO];
        return;
    }

	[[[pathOperations copy] autorelease] makeObjectsPerformSelector:@selector(cancel)];
	needsCleanupSync = NO;
	updatedLastSyncHashOnFinish = NO;
	
	if (!loadedMetadata) {
		[super cancel];
	}
}

- (void)finish:(NSError *)error {
	PathController *aPathController = pathController;
	[super finish:error];
	[[NSNotificationCenter defaultCenter] postNotificationName:EndingFolderSyncNotification object:aPathController];
}

- (void)finishIfSyncOperationsAreFinished {
	if ([pathOperations count] == 0 && !schedulingOperations) {
		if (needsCleanupSync) {
			needsCleanupSync = NO;
			[self main];
			return;
		}

		[self finish];
	}
}

#pragma mark -
#pragma mark Folder Sync

- (void)schedulePathOperation:(PathOperation *)aPathOperation onQueue:(NSOperationQueue *)operationQueue {
	aPathOperation.folderSyncPathOperation = self;
	[pathOperations addObject:aPathOperation];
	[operationQueue addOperation:aPathOperation];
}

- (void)pathOperationFinished:(PathOperation *)aPathOperation {
	if (aPathOperation == self) return;
	
	NSAssert([pathOperations containsObject:aPathOperation], @"");
	aPathOperation.folderSyncPathOperation = nil;
	[pathOperations removeObject:aPathOperation];
    
    id <PathControllerDelegate> delegate = self.pathController.delegate;
	BOOL showProgress = [delegate respondsToSelector:@selector(syncProgress:fromPathController:)];
    // Call path controller delegate to show sync progress        
    if (showProgress) 
        [delegate syncProgress: ((float) (operationCount - [pathOperations count]))/operationCount
            fromPathController: self.pathController];
    
	[self finishIfSyncOperationsAreFinished];
}

- (void)createFolderOnServer {
	[self.client createFolder:[pathController localPathToServer:localPath]];
}

- (void)scheduleFolderSyncOperations {
	//NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	// Map shadow names & attributes
	NSMutableSet *shadowNames = [NSMutableSet set];
	NSMutableDictionary *nameToPathMetadataLookup = [NSMutableDictionary dictionary];
	for (PathMetadata *each in [pathController pathMetadataForLocalPath:localPath createNewLocalIfNeeded:NO].children) {
		[nameToPathMetadataLookup setObject:each forKey:each.normalizedName];
		
		if (each.lastSyncDate != nil) {
			[shadowNames addObject:each.normalizedName];
		} else {
			NSAssert(each.pathState == SyncErrorPathState, @"shadow without lastSyncDate that isn't in error state.");
		}
	}
	
	// Map local names and look for local changes.	
	NSMutableDictionary *nameToLocalPathLookup = [NSMutableDictionary dictionary];
	NSMutableDictionary *nameToCaseSensitiveNameLookup = [NSMutableDictionary dictionary];
	NSMutableSet *localTypeChanges = [NSMutableSet set];
	NSMutableSet *localModifieds = [NSMutableSet set];
	NSMutableSet *localNames = [NSMutableSet set];
	
	const char *localPathFileSystemRepresentation = [localPath fileSystemRepresentation];
	char pathBuffer[strlen(localPathFileSystemRepresentation) + FILENAME_MAX + 1];
	DIR *dip = opendir(localPathFileSystemRepresentation);
	struct stat fileInfo;
	struct dirent *dit;	
	
	if (dip != NULL) {
		while ((dit = readdir(dip)) != NULL) {
			if (0 == strcmp(".", dit->d_name) || 0 == strcmp("..", dit->d_name))
				continue;
			
			NSString *each = [[fileManager stringWithFileSystemRepresentation:dit->d_name length:dit->d_namlen] precomposedStringWithCanonicalMapping];
			NSString *eachPath = [localPath stringByAppendingPathComponent:each];
			NSString *eachNormalizedName = [each lowercaseString];
			
			[nameToCaseSensitiveNameLookup setObject:each forKey:eachNormalizedName];
			[nameToLocalPathLookup setObject:eachPath forKey:eachNormalizedName];
			[localNames addObject:eachNormalizedName];		
			
			PathMetadata *eachLocalMetadata = [nameToPathMetadataLookup objectForKey:eachNormalizedName];
			BOOL localIsDirectory = dit->d_type == DT_DIR;
			
			if (eachLocalMetadata) {
				if (eachLocalMetadata.lastSyncIsDirectory != localIsDirectory) {
					[localTypeChanges addObject:each];
				}
				
				if (!localIsDirectory) {
					memset(pathBuffer, '\0', sizeof(pathBuffer));
					strcpy(pathBuffer, localPathFileSystemRepresentation);
					strcat(pathBuffer, "/");
					strcat(pathBuffer, (char*)dit->d_name);
					
					if (0 == lstat(pathBuffer, &fileInfo)) {
						if (eachLocalMetadata) {
							if ([eachLocalMetadata.lastSyncDate timeIntervalSince1970] != fileInfo.st_mtime) {
								[localModifieds addObject:eachNormalizedName];
							}
						}			
					}
				}
			}
		}
		
		closedir(dip);
	}

	// Map server names & attributes
	NSMutableDictionary *nameToDBMetadataLookup = [NSMutableDictionary dictionary];
	NSMutableSet *serverNames = [NSMutableSet set];
	if (serverMetadata) {
		for (DBMetadata *each in serverMetadata.contents) {
			NSString *normalizedName = each.path.lastPathComponent.normalizedDropboxPath;
			[nameToDBMetadataLookup setObject:each forKey:normalizedName];
			[serverNames addObject:normalizedName];
		}
	} else {
		[serverNames unionSet:shadowNames];
	}
	
	// Detect and propogate case changes in names
	for (NSString *each in shadowNames) {
		NSString *eachLocalName = [nameToCaseSensitiveNameLookup objectForKey:each];
		NSString *eachShadowName = [[nameToPathMetadataLookup objectForKey:each] lastSyncName];
		NSString *eachServerName = [[[nameToDBMetadataLookup objectForKey:each] path] lastPathComponent];
		
		if (eachLocalName != nil && eachShadowName != nil && eachServerName != nil) {
			if (![eachLocalName isEqualToString:eachServerName]) {
				if (![eachServerName isEqualToString:eachShadowName]) {
					PathControllerLogInfo(@"#### Should rename local from: %@ to: %@", eachLocalName, eachServerName, nil);
					// server changed, update local.
				} else {
					PathControllerLogInfo(@"#### Should rename server from: %@ to: %@", eachServerName, eachLocalName, nil);
					// local changed, update server.
				}
			}
		}
	}	
	
	// Determine adds, deletes
	NSMutableSet *localAdds = [localNames setMinusSet:shadowNames];
	NSMutableSet *deletedLocal = [shadowNames setMinusSet:localNames];
	NSMutableSet *serverAdds = [serverNames setMinusSet:shadowNames];
	NSMutableSet *deletedServer = [shadowNames setMinusSet:serverNames];
	
	// Determine server modifieds and server type changes
	NSMutableSet *serverModifieds = [NSMutableSet set];
	NSMutableSet *serverTypeChanges = [NSMutableSet set];
	for (NSString *each in serverNames) {
		PathMetadata *eachPathMetadata = [nameToPathMetadataLookup objectForKey:each];
		DBMetadata *eachServerMetadata = [nameToDBMetadataLookup objectForKey:each];
		if (eachPathMetadata != nil && eachServerMetadata != nil) {
			NSDate *serverModified = eachServerMetadata.lastModifiedDate;
			NSDate *lastSyncDate = eachPathMetadata.lastSyncDate;
			if (![serverModified isEqualToDate:lastSyncDate]) {
				[serverModifieds addObject:each];
			}
			
			BOOL serverIsDirectory = eachServerMetadata.isDirectory;
			if (serverIsDirectory != eachPathMetadata.lastSyncIsDirectory) {
				[serverTypeChanges addObject:each];
			}
		}
	}
	
	// Addjust adds and deletes for type changes (if path type changes then delete it and re-add it to resolve)
	[deletedLocal unionSet:localTypeChanges];
	[localAdds unionSet:localTypeChanges];
	[deletedServer unionSet:serverTypeChanges];
	[serverAdds unionSet:serverTypeChanges];
	
	// Resolve conflicting adds (same new filename added to both local and server
	NSMutableSet *conflictAdds = [serverAdds setIntersectingSet:localAdds];
	NSMutableSet *usedNames = [NSMutableSet set];
	[usedNames unionSet:localNames];
	[usedNames unionSet:localAdds];
	[usedNames unionSet:serverAdds];
	
	for (NSString *each in conflictAdds) {
		NSString *fromPath = [nameToLocalPathLookup objectForKey:each];
		NSString *conflictName = [[usedNames conflictNameForNameInNormalizedSet:[fromPath lastPathComponent]] precomposedStringWithCanonicalMapping];
		NSString *toPath = [[fromPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:conflictName];
		NSError *error;
		
		if ([fileManager moveItemAtPath:fromPath toPath:toPath error:&error]) {
			NSString *normalizedConflictName = [conflictName normalizedDropboxPath];
			// create path metadata?
			[localAdds removeObject:each];
			[usedNames addObject:conflictName];
			[localAdds addObject:normalizedConflictName];
			[nameToLocalPathLookup setObject:toPath forKey:normalizedConflictName];
			[pathController enqueuePathChangedNotification:[NSDictionary dictionaryWithObjectsAndKeys:fromPath, FromPathKey, toPath, ToPathKey, nil] changeType:MovedPathsKey];
		} else {
			PathControllerLogError(@"Failed to move conflicting local add %@", error);
		}
	}
	
	// Schedule Local Delete Operations
	for (NSString *each in [[deletedServer allObjects] sortedArrayUsingFunction:sortInPathOrder context:NULL]) {
		if ([deletedLocal containsObject:each]) {
			[pathController deletePathMetadataForLocalPath:[nameToLocalPathLookup objectForKey:each]];
		} else {
			[self schedulePathOperation:[DeleteLocalPathOperation pathOperationWithPath:[nameToLocalPathLookup objectForKey:each] serverMetadata:[nameToDBMetadataLookup objectForKey:each]] onQueue:[pathController deleteOperationQueue]];
		}
	}
	
	// Schedule Server Delete Operations
	for (NSString *each in [[deletedLocal allObjects] sortedArrayUsingFunction:sortInPathOrder context:NULL]) {
		if ([deletedServer containsObject:each]) {
			[pathController deletePathMetadataForLocalPath:[nameToLocalPathLookup objectForKey:each]];
		} else {
			[self schedulePathOperation:[DeletePathOperation pathOperationWithPath:[localPath stringByAppendingPathComponent:each] serverMetadata:[nameToDBMetadataLookup objectForKey:each]] onQueue:[pathController deleteOperationQueue]];
		}
	}
	
	// Schedule Get Operations
	NSMutableSet *gets = [NSMutableSet set];
	[gets unionSet:serverAdds];
	[gets unionSet:serverModifieds];
	for (NSString *each in [[gets allObjects] sortedArrayUsingFunction:sortInPathOrder context:NULL]) {
		NSString *eachPath = [nameToLocalPathLookup objectForKey:each];
		DBMetadata *eachServerMetadata = [nameToDBMetadataLookup objectForKey:each];
		
		if (!eachPath) {
			// File doesn't exist locally yet.
			eachPath = [localPath stringByAppendingPathComponent:[eachServerMetadata.path lastPathComponent]];
			// create local file.
			// set each server metadata to be 	TemporaryPlaceholderPathState | PermanentPlaceholderPathState
			
		}
		
		[self schedulePathOperation:[GetPathOperation pathOperationWithPath:eachPath serverMetadata:eachServerMetadata] onQueue:[pathController getOperationQueue]];
	}
	
	// Schedule Put Operations
	NSMutableSet *puts = [NSMutableSet set];
	[puts unionSet:localAdds];
	[puts unionSet:localModifieds];
	for (NSString *each in [[puts allObjects] sortedArrayUsingFunction:sortInPathOrder context:NULL]) {
		NSString *eachPath = [nameToLocalPathLookup objectForKey:each];
		DBMetadata *eachServerMetadata = [nameToDBMetadataLookup objectForKey:each];
		[self schedulePathOperation:[PutPathOperation pathOperationWithPath:eachPath serverMetadata:eachServerMetadata] onQueue:[pathController putOperationQueue]];
	}
	
	schedulingOperations = NO;
    
    operationCount = 0;
    operationCount += [deletedServer count];
    operationCount += [deletedLocal count];
    operationCount += [gets count];
    operationCount += [puts count];
	
	[self finishIfSyncOperationsAreFinished];
}

#pragma mark -
#pragma mark DBRestClientDelegate

- (void)restClient:(DBRestClient*)aClient loadedMetadata:(DBMetadata*)aServerMetadata {	
	loadedMetadata = YES;
	
	self.serverMetadata = aServerMetadata;
	
	if (serverMetadata.isDeleted) { // has existed, and is now delted on server
		NSError *error;
		BOOL removedAll;
		
		if ([pathController removeUnchangedItemsAtPath:localPath error:&error removedAll:&removedAll]) {
			[self.pathController deletePathMetadataForLocalPath:localPath];
			[pathController saveState];
			
			if (removedAll) {
				if ([localPath isEqualToString:pathController.localRoot]) {
					if (![[NSFileManager defaultManager] createDirectoryAtPath:localPath withIntermediateDirectories:YES attributes:nil error:&error]) {
						[self finish:error];
						return;
					}
				}
				self.createPathMetadataOnFinish = NO;
				[self finish];
			} else {
				[self createFolderOnServer];
			}
		} else {
			[self finish:error];
		}
	} else {
		[self scheduleFolderSyncOperations];
	}
}

- (void)restClient:(DBRestClient*)client metadataUnchangedAtPath:(NSString*)path {	
	loadedMetadata = YES;
	
	PathControllerLogInfo(@"Metadata Unchanged %@", [self.pathController localPathToServer:localPath]);
	self.serverMetadata = nil;
	[self scheduleFolderSyncOperations];
}

- (void)restClient:(DBRestClient*)aClient loadMetadataFailedWithError:(NSError*)error {
	loadedMetadata = YES;
	
	if ([error code] == 404) { // has never existed on server.
		[self createFolderOnServer];
		return;
	}
	[self retryWithError:error];
}

- (void)restClient:(DBRestClient*)aClient createdFolder:(DBMetadata *)aServerMetadata {
	self.serverMetadata = aServerMetadata;
	[self scheduleFolderSyncOperations];
}

- (void)restClient:(DBRestClient*)aClient createFolderFailedWithError:(NSError*)error {
	[self retrySelector:@selector(createFolderOnServer) withError:error];
}

@end

@implementation PathController (FolderSyncPathOperationPrivate)

- (NSOperationQueue *)getOperationQueue {
	return getOperationQueue;
}

- (NSOperationQueue *)putOperationQueue {
	return putOperationQueue;
}

- (NSOperationQueue *)deleteOperationQueue {
	return deleteOperationQueue;
}

- (NSOperationQueue *)folderSyncPathOperationOperationQueue {
	return folderSyncPathOperationOperationQueue;
}

@end