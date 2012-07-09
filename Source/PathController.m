//
//  PathController.m
//  DropboxSync
//
//  Created by Jesse Grosjean on 8/7/10.
//  Copyright 2010 Hog Bay Software. All rights reserved.
//

#import "PathController.h"
#import "DeleteLocalPathOperation.h"
#import "FolderSyncPathOperation.h"
#import "FullSyncOperation.h"
#import "NSFileManager_Additions.h"
#import "PathController_Private.h"
#import "DeletePathOperation.h"
#import "GetPathOperation.h"
#import "PutPathOperation.h"
#import "NSSet_Additions.h"
#import "PathMetadata.h"

NSInteger sortInPathOrder(NSString *a, NSString *b, void* context) {
    return [a compare:b options:NSNumericSearch | NSCaseInsensitiveSearch];
}

@interface PathControllerManagedObjectContext : NSManagedObjectContext {
	PathController *pathController;
}
@property(nonatomic, assign) PathController *pathController;
@end

@implementation PathController
@synthesize localPathsToNormalizedPaths;
@synthesize normalizedPathsToPathActivity;
@synthesize normalizedPathsToPathMetadatas;

#pragma mark -
#pragma mark Initialization

+ (NSError *)documentsFolderCannotBeRenamedError {
	NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
							  NSLocalizedString(@"The Documents folder can't be renamed. You can rename all other folders and files.", nil),
							  NSLocalizedDescriptionKey, nil];
	return [NSError errorWithDomain:@"" code:1 userInfo:userInfo];
}

#pragma mark -
#pragma mark Init

- (id)initWithLocalRoot:(NSString *)aLocalRoot serverRoot:(NSString *)aServerRoot pathMetadataStorePath:(NSString *)aPathMetadataStorePath {
	self = [super init];
	
	localPathsToNormalizedPaths = [[NSMutableDictionary alloc] init];
	normalizedPathsToPathActivity = [[NSMutableDictionary alloc] init];
	normalizedPathsToPathMetadatas = [[NSMutableDictionary alloc] init];
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	BOOL isDirectory;
	NSError *error;
	
	if (![fileManager fileExistsAtPath:aLocalRoot isDirectory:&isDirectory] || !isDirectory) {
		if (![fileManager createDirectoryAtPath:aLocalRoot withIntermediateDirectories:YES attributes:nil error:&error]) {
			PathControllerLogError(@"Failed to create local directory for %@ %@", self, error);
			[self release];
			return nil;
		}
	}
	
	localRoot = aLocalRoot;
	localRoot = [[localRoot precomposedStringWithCanonicalMapping] retain];
	
	getOperationQueue = [[NSOperationQueue alloc] init];
	getOperationQueue.maxConcurrentOperationCount = 6;
	putOperationQueue = [[NSOperationQueue alloc] init];
    // cant have more than one put operation, as puting a dir, then a subdir - first errors with directory exists
	putOperationQueue.maxConcurrentOperationCount = 1; 
	deleteOperationQueue = [[NSOperationQueue alloc] init];
    // cant have more than one delete operation, as delete ordering is important.
	deleteOperationQueue.maxConcurrentOperationCount = 1;
	folderSyncPathOperationOperationQueue = [[NSOperationQueue alloc] init];
	folderSyncPathOperationOperationQueue.maxConcurrentOperationCount = 1;

	if (!aServerRoot) aServerRoot = [@"/" stringByAppendingPathComponent:[[NSProcessInfo processInfo] processName]];
	self.serverRoot = aServerRoot;

	pathMetadataStorePath = [aPathMetadataStorePath retain];
	
	[self initManagedObjectContext];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(endingSyncNotification:) name:EndingFolderSyncNotification object:self];
	
	return self;
}

#pragma mark -
#pragma mark Dealloc

- (void)dealloc {
	PathControllerLogDebug(@"Dealloc %@", self);
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[localPathsToNormalizedPaths release];
	[normalizedPathsToPathActivity release];
	[normalizedPathsToPathMetadatas release];
	[pendingPathChangedNotificationUserInfo release];
	[manualLinkClient release];
	[localRoot release];
	[serverRoot release];
	[pathMetadataStorePath release];
	[getOperationQueue cancelAllOperations];
	[getOperationQueue release];
	[putOperationQueue cancelAllOperations];
	[putOperationQueue release];
	[deleteOperationQueue cancelAllOperations];
	[deleteOperationQueue release];
	[folderSyncPathOperationOperationQueue cancelAllOperations];
	[folderSyncPathOperationOperationQueue release];
 	[managedObjectModel release];
	[managedObjectContext release];
    [persistentStoreCoordinator release];
	[super dealloc];
}

- (void)endingSyncNotification:(NSNotification *)aNotification {
	UIApplication *application = [UIApplication sharedApplication];

	if (self.isSyncInProgress) {
		return;
	}

	[application setNetworkActivityIndicatorVisible:NO];		
}

#pragma mark -
#pragma mark Attributes

@synthesize localRoot;
@synthesize serverRoot;

- (void)setServerRoot:(NSString *)aRoot {
	NSAssert(serverRoot == nil || !self.isLinked, @"Shouldn't be linked when changing server root");
	
	aRoot = [aRoot stringByReplacingOccurrencesOfString:@"\\" withString:@""];
	aRoot = [aRoot stringByReplacingOccurrencesOfString:@";" withString:@""];
	aRoot = [@"/" stringByAppendingPathComponent:aRoot];
	
	[serverRoot release];
	serverRoot = [[aRoot precomposedStringWithCanonicalMapping] retain];
}

@synthesize delegate;

#pragma mark -
#pragma mark Paths


- (NSString *)serverPathToLocal:(NSString *)serverPath {
	serverPath = [serverPath precomposedStringWithCanonicalMapping];
	NSString *s = [serverPath substringFromIndex:[serverRoot length]];
	return [localRoot stringByAppendingPathComponent:s];
}

- (NSString *)localPathToServer:(NSString *)localPath {
	localPath = [localPath precomposedStringWithCanonicalMapping];
	if ([localPath rangeOfString:localRoot].location == 0) {
		NSString *p = [localPath substringFromIndex:[self.localRoot length]];
		return [serverRoot stringByAppendingPathComponent:p];
	}
	return localPath;
}

- (NSString *)localPathToNormalized:(NSString *)localPath {
	NSString *result = [[localPath stringByReplacingCharactersInRange:NSMakeRange(0, [localRoot length]) withString:@""] normalizedDropboxPath];
	if ([result length] == 0) {
		result = @"/";
	}
	return result;
}

#pragma mark -
#pragma mark Path Modifications

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error {	
	if ([[NSFileManager defaultManager] removeItemAtPath:path error:error]) {
		[self enqueuePathChangedNotification:path changeType:RemovedPathsKey];
		return YES;
	}
	return NO;
}

- (BOOL)removeUnchangedItemsAtPath:(NSString *)aLocalPath error:(NSError **)error removedAll:(BOOL *)removedAll {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	BOOL removedAllResult = NO;
	BOOL isDirectory;
	
	if ([fileManager fileExistsAtPath:aLocalPath isDirectory:&isDirectory]) {
		PathMetadata *pathMetadata = [self pathMetadataForLocalPath:aLocalPath createNewLocalIfNeeded:YES];
        NSDate *localModified = [[fileManager attributesOfItemAtPath:aLocalPath error:error] fileModificationDate];			
        
		NSDate *lastSyncDate = pathMetadata.lastSyncDate;
        
        NSDate* lastParentSync = nil;
        
        // find last time sync happened on a parent directory - need to allow deletes if unsynced items are older than last sync.
        PathMetadata* parentMetaData = pathMetadata.parent;
        while (parentMetaData && !lastParentSync) {
            lastParentSync = parentMetaData.lastSyncDate;
            if (!lastParentSync) {
                parentMetaData = parentMetaData.parent;
            }
        }
		
		if (isDirectory) {
			if (lastSyncDate || [lastParentSync timeIntervalSinceDate:localModified] > 0) {
				for (NSString *each in [fileManager contentsOfDirectoryAtPath:aLocalPath error:NULL]) {
					[self removeUnchangedItemsAtPath:[aLocalPath stringByAppendingPathComponent:each] error:error removedAll:removedAll];
				}
                
				
				if ([[fileManager contentsOfDirectoryAtPath:aLocalPath error:NULL] count] == 0) {
					if ([fileManager removeItemAtPath:aLocalPath error:NULL]) {
						[self enqueuePathChangedNotification:aLocalPath changeType:RemovedPathsKey];
						removedAllResult = YES;
					}
				}
			}
		} else {
			PathState pathState = pathMetadata.pathState;
			
			BOOL isPlaceholder = (pathState == TemporaryPlaceholderPathState || pathState == PermanentPlaceholderPathState);
           
			if (isPlaceholder || (lastSyncDate != nil && [localModified isEqualToDate:lastSyncDate]) || [lastParentSync timeIntervalSinceDate:localModified] > 0) {
				if ([fileManager removeItemAtPath:aLocalPath error:NULL]) {
					[self enqueuePathChangedNotification:aLocalPath changeType:RemovedPathsKey];
					removedAllResult = YES;
				}
			}
		}
	} else {
		removedAllResult = YES;
	}
	
	if (removedAll) {
		*removedAll = removedAllResult;
	}
		
	return YES;
}

- (BOOL)pasteItemToPath:(NSString *)path error:(NSError **)error {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *srcPath = [[[UIPasteboard generalPasteboard] URL] path];
	NSString *dstPath = [path stringByAppendingPathComponent:[srcPath lastPathComponent]];
	
	dstPath = [fileManager conflictPathForPath:dstPath includeMessage:NO error:error];
	
	if (dstPath) {
		if ([fileManager copyItemAtPath:srcPath toPath:dstPath error:error]) {
			[self enqueuePathChangedNotification:path changeType:CreatedPathsKey];
			return YES;
		}
	}
	
	return NO;
}

- (BOOL)createFolderAtPath:(NSString *)path error:(NSError **)error {
	if (![[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:error]) {
		return NO;
	}
	
	[self enqueuePathChangedNotification:path changeType:CreatedPathsKey];
	return YES;
}

- (BOOL)createFileAtPath:(NSString *)path content:(NSData *)contents error:(NSError **)error {
	if (![[NSFileManager defaultManager] createFileAtPath:path contents:contents attributes:nil]) {
		return NO;
	}
	[self enqueuePathChangedNotification:path changeType:CreatedPathsKey];
	return YES;
}

- (BOOL)moveItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath error:(NSError **)error {
	if ([fromPath isEqualToString:localRoot] || [toPath isEqualToString:localRoot]) {
		if (*error) {
			*error = [PathController documentsFolderCannotBeRenamedError];
		}
		return NO;
	}
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	if ([fileManager my_moveItemAtPath:fromPath toPath:toPath error:error]) {
		[self enqueuePathChangedNotification:[NSDictionary dictionaryWithObjectsAndKeys:fromPath, FromPathKey, toPath, ToPathKey, nil] changeType:MovedPathsKey];
		return YES;
	}
	
	return NO;
}

- (void)postQueuedPathChangedNotifications {
	[[NSNotificationCenter defaultCenter] postNotificationName:PathsChangedNotification object:self userInfo:pendingPathChangedNotificationUserInfo];
	[pendingPathChangedNotificationUserInfo autorelease];
	pendingPathChangedNotificationUserInfo = nil;
}

- (void)enqueuePathChangedNotification:(id)value changeType:(NSString *)changeTypeKey {
	if ([value isKindOfClass:[NSDictionary class]]) {
		NSAssert([changeTypeKey isEqualToString:MovedPathsKey], @"");
	}
	
	if (!pendingPathChangedNotificationUserInfo) {
		pendingPathChangedNotificationUserInfo = [[NSMutableDictionary alloc] init];
		[self performSelector:@selector(postQueuedPathChangedNotifications) withObject:nil afterDelay:0.0];
	}
	
	NSMutableSet *values = [pendingPathChangedNotificationUserInfo objectForKey:changeTypeKey];
	if (!values) {
		values = [NSMutableSet set];
		[pendingPathChangedNotificationUserInfo setObject:values forKey:changeTypeKey];
	}
	if (value) {
        [values addObject:value];
    }
}

#pragma mark -
#pragma mark Path Syncing

- (void)enqueueFolderSyncPathRequest:(NSString *)localPath {
	NSAssert(localPath != nil, @"");
	
	if (self.isLinked) {
		[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(performFolderSyncPathRequest:) object:localPath];
		[self performSelector:@selector(performFolderSyncPathRequest:) withObject:localPath afterDelay:0];
	}
}


- (void)performFolderSyncPathRequest:(NSString *)localPath {
	if (self.isLinked) {
		localPath = [localPath precomposedStringWithCanonicalMapping];
		[folderSyncPathOperationOperationQueue addOperation:[[[FolderSyncPathOperation alloc] initWithPath:localPath pathController:self] autorelease]];
	}
}

- (void)enqueueFullSync {
    if (self.isLinked) {
		[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(performFullSync) object:nil];
		[self performSelector:@selector(performFullSync) withObject:nil afterDelay:0];
	}
}


- (void)performFullSync {
	if (self.isLinked) {
		[folderSyncPathOperationOperationQueue addOperation:[[[FullSyncOperation alloc] initWithPathController:self] autorelease]];
	}
}
- (BOOL)saveState {
	NSError *error;
	if (![managedObjectContext save:&error]) {
		PathControllerLogError(@"Failed to save managed object context %@", error);
		return NO;
	}
	return YES;
}

- (BOOL)isSyncInProgress {
	for (NSOperation *each in [folderSyncPathOperationOperationQueue operations]) {
		if (!each.isFinished) {
			return YES;
		}
	}
	return NO;
}

- (void)cancelSyncInProgress {
	[getOperationQueue cancelAllOperations];
	[putOperationQueue cancelAllOperations];
	[deleteOperationQueue cancelAllOperations];
	[folderSyncPathOperationOperationQueue cancelAllOperations];
}

- (PathState)stateForPath:(NSString *)localPath {
	PathMetadata *pathMetadata = [self pathMetadataForLocalPath:localPath createNewLocalIfNeeded:NO];
	if (pathMetadata) {
		return pathMetadata.pathState;
	}
	return UnsyncedPathState;
}

- (NSError *)errorForPath:(NSString *)localPath {
	return [self pathMetadataForLocalPath:localPath createNewLocalIfNeeded:NO].pathError;
}

- (PathActivity)pathActivityForPath:(NSString *)localPath {
	NSString *normalizedPath = [self localPathToNormalized:localPath];
	NSNumber *pathActivity = [normalizedPathsToPathActivity objectForKey:normalizedPath];
	if (!pathActivity) {
		pathActivity = [NSNumber numberWithInt:NoPathActivity];
		[normalizedPathsToPathActivity setObject:pathActivity forKey:normalizedPath];
	}
	return [pathActivity intValue];
}

- (void)setPathActivity:(PathActivity)aPathActivity forPath:(NSString *)aLocalPath {
	NSString *normalizedPath = [self localPathToNormalized:aLocalPath];
	[normalizedPathsToPathActivity setObject:[NSNumber numberWithInt:aPathActivity] forKey:normalizedPath];
	[self enqueuePathChangedNotification:aLocalPath changeType:ActivityChangedPathsKey];
}


- (void)initManagedObjectContext {
	NSError *error;
	NSURL *modelURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"PathMetadata" ofType:@"momd"]];
	NSURL *storeURL = [NSURL fileURLWithPath:pathMetadataStorePath];
	managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];    
	persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:managedObjectModel];
	if (![persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
		abort();
	}    
	managedObjectContext = [[PathControllerManagedObjectContext alloc] init];
	[managedObjectContext setPersistentStoreCoordinator:persistentStoreCoordinator];
	[managedObjectContext setUndoManager:nil];
	managedObjectContext.pathController = self;
	
	NSFetchRequest *fetchRequest = [[[NSFetchRequest alloc] init] autorelease];
	NSEntityDescription *entity = [NSEntityDescription entityForName:@"PathMetadata" inManagedObjectContext:managedObjectContext];
	[fetchRequest setEntity:entity];
	for (PathMetadata *each in [managedObjectContext executeFetchRequest:fetchRequest error:NULL]) {
		[normalizedPathsToPathMetadatas setObject:each forKey:each.normalizedPath];
	}
}

#pragma mark -
#pragma mark Linking

- (BOOL)isLinked {
	return [[DBSession sharedSession] isLinked];
}


- (void)unlink:(BOOL)discardSessionKeys {
	NSError *error;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSArray *contents = [fileManager contentsOfDirectoryAtPath:localRoot error:&error];
	BOOL removedAll;

	[self cancelSyncInProgress];
	
	for (NSString *each in contents) {
		each = [localRoot stringByAppendingPathComponent:each];	
		[self removeUnchangedItemsAtPath:each error:NULL removedAll:&removedAll];
		[self deletePathMetadataForLocalPath:each];
	}	
	
	NSMutableSet *persistentStorePaths = [NSMutableSet set];
	for (NSPersistentStore *each in [persistentStoreCoordinator persistentStores]) {
		[persistentStorePaths addObject:[[persistentStoreCoordinator URLForPersistentStore:each] path]];
	}
	
	[[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:managedObjectContext];
	
	[managedObjectContext release];
	managedObjectContext = nil;
	[persistentStoreCoordinator release];
	persistentStoreCoordinator = nil;
	[managedObjectModel release];
	managedObjectModel = nil;

	[normalizedPathsToPathActivity removeAllObjects];
	[localPathsToNormalizedPaths removeAllObjects];
	[normalizedPathsToPathMetadatas removeAllObjects];

	for (NSString *each in persistentStorePaths) {
		[fileManager removeItemAtPath:each error:NULL];
	}

	if (discardSessionKeys) {
		[[DBSession sharedSession] unlinkAll];
	}
	
	[[NSUserDefaults standardUserDefaults] synchronize];
	
	[self initManagedObjectContext];
}

#pragma mark -
#pragma mark Logging

@synthesize logLevel;

- (void)log:(NSString *)aString level:(PathControllerLogLevel)level prettyFunction:(const char *)prettyFunction line:(NSUInteger)line {
	if (level < logLevel) {
		return;
	}
	
	NSString *levelString = nil;
	
	switch (level) {
		case PathControllerLogLevelDebug:
			levelString = @"DEBUG";
			break;
		case PathControllerLogLevelInfo:
			levelString = @"INFO";
			break;
		case PathControllerLogLevelWarn:
			levelString = @"WARN";
			break;
		case PathControllerLogLevelError:
			levelString = @"ERROR";
			break;
	}
	
	//if (logLocation) {
	//	NSLog(@"[%@] %s(%d) %@", levelString, prettyFunction, line, aString);
	//} else {
		NSLog(@"[%@] %@", levelString, aString);
	//}
}

#pragma mark -
#pragma mark Path Metadata

- (PathMetadata *)pathMetadataForLocalPath:(NSString *)localPath createNewLocalIfNeeded:(BOOL)createIfNeeded {
	NSString *normalizedPath = [self localPathToNormalized:localPath];
	PathMetadata *pathMetadata = [normalizedPathsToPathMetadatas objectForKey:normalizedPath];
	
	if (!pathMetadata && createIfNeeded) {
		NSString *normalizedName = [normalizedPath lastPathComponent];
		pathMetadata = [PathMetadata pathMetadataWithNormalizedName:normalizedName managedObjectContext:managedObjectContext];
		
		if (![normalizedName isEqualToString:@"/"]) {
			PathMetadata *parent = [self pathMetadataForLocalPath:[localPath stringByDeletingLastPathComponent] createNewLocalIfNeeded:YES];
			[parent addChildrenObject:pathMetadata];
		}
		
		[normalizedPathsToPathMetadatas setObject:pathMetadata forKey:normalizedPath];
	}
	
	return pathMetadata;
}

- (void)uncachPathMetadata:(PathMetadata *)aPathMetadata {	
	for (PathMetadata *each in aPathMetadata.children) {
		[self uncachPathMetadata:each];
	}
	[normalizedPathsToPathMetadatas removeObjectForKey:aPathMetadata.normalizedPath];
}

- (void)deletePathMetadataForLocalPath:(NSString *)localPath {
	PathMetadata *pathMetadata = [self pathMetadataForLocalPath:localPath createNewLocalIfNeeded:NO];
	if (pathMetadata) {
		[self uncachPathMetadata:pathMetadata];
		[managedObjectContext deleteObject:pathMetadata];
	}
	
	// localPathsToNormalizedPaths; // not getting cleaned out
	// localPathsToPathActivity
}


@end

@implementation PathControllerManagedObjectContext
@synthesize pathController;
@end

NSString *BeginingFolderSyncNotification = @"BeginingFolderSyncNotification";
NSString *EndingFolderSyncNotification = @"EndingFolderSyncNotification";

NSString *PathsChangedNotification = @"PathsChangedNotification";
NSString *MovedPathsKey = @"MovedPathsKey";
NSString *CreatedPathsKey = @"CreatedPathsKey";
NSString *RemovedPathsKey = @"RemovedPathsKey";
NSString *ModifiedPathsKey = @"ModifiedPathsKey";
NSString *StateChangedPathsKey = @"StateChangedPathsKey";
NSString *ActivityChangedPathsKey = @"ActivityChangedPathsKey";

NSString *PathKey = @"PathKey";
NSString *FromPathKey = @"FromPathKey";
NSString *ToPathKey = @"ToPathKey";