//
//  FullSyncOperation.m
//  DropboxSync
//
//  Created by Nick Hingston on 05/07/2012.
//  Copyright (c) 2012 Mothership Software Ltd. All rights reserved.
//

#import "FullSyncOperation.h"
#import "DeleteLocalPathOperation.h"
#import "FolderSyncPathOperation.h"
#import "PathController_Private.h"
#import "DeletePathOperation.h"
#import "GetPathOperation.h"
#import "PutPathOperation.h"
#import "NSSet_Additions.h"
#import "PathController.h"
#import <DropboxSDK/DropboxSDK.h>
#include <sys/stat.h>
#include <dirent.h>
#import <DropboxSDK/DBDeltaEntry.h>

@interface PathController (FullSyncOperationPrivate)
- (NSOperationQueue *)getOperationQueue;
- (NSOperationQueue *)putOperationQueue;
- (NSOperationQueue *)deleteOperationQueue;
- (NSOperationQueue *)folderSyncPathOperationOperationQueue;
@end

@implementation FullSyncOperation
@synthesize cursor = _cursor;

- (id)initWithPathController:(PathController *)aPathController {
	self = [super initWithPath:aPathController.localRoot serverMetadata:nil];
    if (self) {
        
        localPath = [aPathController.localRoot retain];
        
        folderSyncPathOperation = self; // don't retain
        createPathMetadataOnFinish = NO;
        pathController = [aPathController retain];
        pathOperations = [[NSMutableSet alloc] init];
        _deltaEntries = [[NSMutableArray alloc] initWithCapacity:2048];
      //  self.cursor = [[NSUserDefaults standardUserDefaults] objectForKey:@"DropboxSDKDeltaCursor"];
    }
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

- (id<PathControllerSyncOperationDelegate>)folderSyncPathOperation {
	return self;
}

- (void)main {
	[self updatePathActivity:GetPathActivity];
	[self.client loadDelta:self.cursor];
}

- (void)start {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(start) withObject:nil waitUntilDone:NO];
        return;
    }
	
	[[NSNotificationCenter defaultCenter] postNotificationName:BeginingFullSyncNotification object:pathController];
	
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
	
	if (!loadedDelta) {
		[super cancel];
	}
}

- (void)finish:(NSError *)error {
	PathController *aPathController = pathController;
	[super finish:error];
    if (!error) {
        [[NSUserDefaults standardUserDefaults] setObject:self.cursor forKey:@"DropboxSDKDeltaCursor"];
        [[NSNotificationCenter defaultCenter] postNotificationName:EndingFullSyncNotification object:aPathController];
    }
    else {
        [[NSNotificationCenter defaultCenter] postNotificationName:EndingFullSyncNotification object:aPathController userInfo:[NSDictionary dictionaryWithObject:error forKey:@"error"]];
    }
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
	if ([delegate respondsToSelector:@selector(syncProgress:fromPathController:)]) {
        [delegate syncProgress:((CGFloat)(operationCount - [pathOperations count])) / operationCount fromPathController:self.pathController];
	}
    
	[self finishIfSyncOperationsAreFinished];
}

- (void)createFolderOnServer {
	[self.client createFolder:[pathController localPathToServer:localPath]];
}

- (void)scheduleFolderSyncOperations {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
    
    NSSet* shadowPaths = [NSSet setWithArray:[pathController.normalizedPathsToPathMetadatas allKeys]];
    
    // find all local files and check if changed
    NSError* error = nil;
    NSDirectoryEnumerator* dirEnumerator = [fileManager enumeratorAtURL:[NSURL fileURLWithPath:localPath]  
                                             includingPropertiesForKeys:nil 
                                                                options:0 
                                            errorHandler:nil];
    
    
    // find all localy modified and added
    NSMutableSet* localAdds = [NSMutableSet set];
    NSMutableSet* localModified = [NSMutableSet set];
    NSMutableSet* localDeletes = [NSMutableSet setWithSet:shadowPaths];
    [localDeletes removeObject:@"/"];

    NSMutableDictionary* normalizedToPathLookup = [NSMutableDictionary dictionary];
    
    BOOL ignoreRequest = [pathController.delegate respondsToSelector:@selector(shouldSyncFile:)];
    for (NSURL* url in dirEnumerator) {
        NSString* name = nil;

        [url getResourceValue:&name forKey:NSURLNameKey error:&error];
        
        if (ignoreRequest && ![pathController.delegate shouldSyncFile:name]) continue;
        
        NSNumber* isDir = nil;
        [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:&error];
    
        NSString* theLocalPath = [url path];
        NSString* path = [pathController localPathToNormalized:theLocalPath];
        NSString* normalizedPath = [path normalizedDropboxPath];
        
        [normalizedToPathLookup setObject:theLocalPath forKey:normalizedPath];
        PathMetadata* pathMetadata = [pathController pathMetadataForLocalPath:theLocalPath createNewLocalIfNeeded:NO];
        
        if (!pathMetadata) {
            [localAdds addObject:normalizedPath];
        }
        else {
            NSDate* modDate = nil;
            [url getResourceValue:&modDate forKey:NSURLContentModificationDateKey error:&error];
            
            if (![modDate isEqualToDate:[pathMetadata lastSyncDate]]) {
        
                if ([isDir boolValue]) {
                    pathMetadata.lastSyncDate = modDate; 
                }
                else {
                    [localModified addObject:normalizedPath];
                }
            }
        }
        
        [localDeletes removeObject:normalizedPath];
    }
    
    NSMutableSet* serverAdds = [NSMutableSet set];
    NSMutableSet* serverModified = [NSMutableSet set];
    NSMutableSet* serverDeletes = [NSMutableSet set];

    NSMutableDictionary* pathToDBMetadataLookup = [NSMutableDictionary dictionary];
    
    for (DBDeltaEntry* entry in _deltaEntries) {
        
        NSString* normalizedPath = [entry lowercasePath];
        
        DBMetadata* metadata = [entry metadata];
        
        if (!metadata)   {
            [serverDeletes addObject:normalizedPath];
        }
        else {
            [pathToDBMetadataLookup setObject:metadata forKey:normalizedPath];
            
            PathMetadata* pathMetadata = [pathController pathMetadataForLocalPath:[localPath stringByAppendingPathComponent:normalizedPath] createNewLocalIfNeeded:NO];
            if (!pathMetadata) {
                if ([metadata isDirectory]) {
                    [serverAdds addObject:normalizedPath];
                }
                else {
                    [serverAdds addObject:normalizedPath];
                }
            }
            else if (![metadata isDirectory] && ![metadata.rev isEqualToString:[pathMetadata rev]]) {
                [serverModified addObject:normalizedPath];
            }
        }
    }
    
    if (_shouldReset) {
        NSMutableSet* resetDeletes = [[shadowPaths mutableCopy] autorelease];
        [resetDeletes removeObject:@"/"];
        for (DBDeltaEntry* entry in _deltaEntries) {
            if ([entry metadata]) {
                [resetDeletes removeObject:entry.lowercasePath];
            }
        }
        
        [serverDeletes unionSet:resetDeletes];
        [serverDeletes minusSet:localAdds];
    }
    
    NSMutableSet *conflictAdds = [serverAdds setIntersectingSet:localAdds];
    [conflictAdds unionSet:[serverModified setIntersectingSet:localModified]];
    
   
   	for (NSString *each in conflictAdds) {
           BOOL isDirectory = NO;
           NSString* path = [normalizedToPathLookup objectForKey:each];
           if ([fileManager fileExistsAtPath:path isDirectory:&isDirectory] && !isDirectory) {
               PathControllerConflictResolutionType conflictResolutionType = [pathController conflictResolutionTypeForLocalPath:path];
               
               if (conflictResolutionType == PathConflictResolutionDuplicateLocal) {
                   
                   NSString* name = [path lastPathComponent];
                   NSString* parentPath = [path stringByDeletingLastPathComponent];
                   NSSet* usedNames = [NSSet setWithArray:[fileManager contentsOfDirectoryAtPath:parentPath error:&error]];
                   
                   NSString *conflictName = [[usedNames conflictNameForNameInNormalizedSet:name] precomposedStringWithCanonicalMapping];
                   NSString *toPath = [parentPath stringByAppendingPathComponent:conflictName];
                   
                   if ([fileManager moveItemAtPath:path toPath:toPath error:&error]) {
                       NSString *normalizedConflictPath = [toPath normalizedDropboxPath];
                       // create path metadata?
                       [localAdds removeObject:each];
                       [localAdds addObject:normalizedConflictPath];
                       [normalizedToPathLookup setObject:toPath forKey:normalizedConflictPath];
                       [pathController enqueuePathChangedNotification:[NSDictionary dictionaryWithObjectsAndKeys:path, FromPathKey, toPath, ToPathKey, nil] changeType:MovedPathsKey];
                   } else {
                       PathControllerLogError(@"Failed to move conflicting local add %@", error);
                   }
               }
               else if (conflictResolutionType == PathConflictResolutionLocal) {
                   PathMetadata* pathMetadata = [pathController pathMetadataForLocalPath:path createNewLocalIfNeeded:NO];
                   DBMetadata* dbMetadata = [pathToDBMetadataLookup objectForKey:each];
                   pathMetadata.lastSyncHash = dbMetadata.rev;
                   
                   [serverAdds removeObject:each];
                   [serverModified removeObject:each];
               }
               else if (conflictResolutionType == PathConflictResolutionServer) {
                   PathMetadata* pathMetadata = [pathController pathMetadataForLocalPath:path createNewLocalIfNeeded:NO];
                   pathMetadata.lastSyncDate = [[fileManager attributesOfItemAtPath:path error:nil] fileModificationDate];
                   
                   [localAdds removeObject:each];
                   [localModified removeObject:each];
               }
           }
           else {
               PathControllerLogDebug(@"ignoring directory conflict %@", each);
               [localAdds removeObject:each];
               [serverAdds removeObject:each];
           }
   	}

    
    NSString* lastDelete = nil;
	// Schedule Local Delete Operations
	for (NSString *each in [[serverDeletes allObjects] sortedArrayUsingFunction:sortInPathOrder context:NULL]) {
		if ([localDeletes containsObject:each]) {
			[pathController deletePathMetadataForLocalPath:[normalizedToPathLookup objectForKey:each]];
		} else {
            // ensure we only delete the container dir
            if (!(lastDelete && [each hasPrefix:lastDelete])) {
                [self schedulePathOperation:[DeleteLocalPathOperation pathOperationWithPath:[normalizedToPathLookup objectForKey:each] serverMetadata:[pathToDBMetadataLookup objectForKey:each]] onQueue:[pathController deleteOperationQueue]];
                lastDelete = each;
            }
		}
	}

	lastDelete = nil;
	// Schedule Server Delete Operations
	for (NSString *each in [[localDeletes allObjects] sortedArrayUsingFunction:sortInPathOrder context:NULL]) {
		if ([serverDeletes containsObject:each]) {
			[pathController deletePathMetadataForLocalPath:[normalizedToPathLookup objectForKey:each]];
		} else {
            // ensure we only delete the container dir
            if (!(lastDelete && [each hasPrefix:lastDelete])) {
                [self schedulePathOperation:[DeletePathOperation pathOperationWithPath:[localPath stringByAppendingPathComponent:each] serverMetadata:[pathToDBMetadataLookup objectForKey:each]] onQueue:[pathController deleteOperationQueue]];
                lastDelete = each;
            }
		}
	}
	
	// Schedule Get Operations
	NSMutableSet *gets = [NSMutableSet set];
	[gets unionSet:serverAdds];
	[gets unionSet:serverModified];
	for (NSString *each in [[gets allObjects] sortedArrayUsingFunction:sortInPathOrder context:NULL]) {
		NSString *eachPath = [normalizedToPathLookup objectForKey:each];
		DBMetadata *eachServerMetadata = [pathToDBMetadataLookup objectForKey:each];
		
		if (!eachPath) {
			// File doesn't exist locally yet.
			eachPath = [localPath stringByAppendingPathComponent:eachServerMetadata.path];
			// create local file.
			// set each server metadata to be 	TemporaryPlaceholderPathState | PermanentPlaceholderPathState
			
		}
		
		[self schedulePathOperation:[GetPathOperation pathOperationWithPath:eachPath serverMetadata:eachServerMetadata] onQueue:[pathController getOperationQueue]];
	}
	
	// Schedule Put Operations
	NSMutableSet *puts = [NSMutableSet set];
	[puts unionSet:localAdds];
	[puts unionSet:localModified];
	for (NSString *each in [[puts allObjects] sortedArrayUsingFunction:sortInPathOrder context:NULL]) {
		NSString *eachPath = [normalizedToPathLookup objectForKey:each];
		DBMetadata *eachServerMetadata = [pathToDBMetadataLookup objectForKey:each];
		[self schedulePathOperation:[PutPathOperation pathOperationWithPath:eachPath serverMetadata:eachServerMetadata] onQueue:[pathController putOperationQueue]];
	}
	
	schedulingOperations = NO;
    
    operationCount = 0;
    operationCount += [serverDeletes count];
    operationCount += [localDeletes count];
    operationCount += [gets count];
    operationCount += [puts count];
	[self finishIfSyncOperationsAreFinished];
}

#pragma mark -
#pragma mark DBRestClientDelegate

- (void)restClient:(DBRestClient*)client loadedDeltaEntries:(NSArray *)entries reset:(BOOL)shouldReset cursor:(NSString *)cursor hasMore:(BOOL)hasMore {
    NSPredicate* rootDirPredicate = [NSPredicate predicateWithFormat:@"lowercasePath == %@",@"/"];
    NSArray* rootPathArray = [entries filteredArrayUsingPredicate:rootDirPredicate];
    
    DBDeltaEntry* delta = [rootPathArray lastObject];
    
    self.serverMetadata = [delta metadata];
    
    [_deltaEntries addObjectsFromArray:entries];
    if (hasMore) {
        [self.client loadDelta:cursor];
    }
    else {
        self.cursor = cursor;
        _shouldReset = shouldReset;
        loadedDelta = YES;
        [self scheduleFolderSyncOperations];
    }
}

- (void)restClient:(DBRestClient*)client loadDeltaFailedWithError:(NSError *)error {
    [self retryWithError:error];
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

