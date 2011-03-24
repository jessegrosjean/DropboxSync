//
//  PathController.h
//  DropboxSync
//
//  Created by Jesse Grosjean on 8/7/10.
//  Copyright 2010 Hog Bay Software. All rights reserved.
//

#import <CoreData/CoreData.h>
#import "PathControllerDelegate.h"
#import "DropboxSDK.h"

//
// PathController is the public API for Dropbox sync.
// See README.markdown for general use guidelines.
//

enum {
	UnsyncedPathState = 1, // Path exists locally, but never been synced to server.
	SyncedPathState, // Path is synced with server.
	SyncErrorPathState, // Path had sync error on last sync request.
	TemporaryPlaceholderPathState, // Temporary placeholder for a file that's being synced to iOS.
	PermanentPlaceholderPathState // Placeholder for a file that you never want synced to iOS, such as a big .mov
};
typedef NSUInteger PathState;

enum {
	NoPathActivity,
	RefreshPathActivity, // Refreshing folder to see if contents changed.
	GetPathActivity, // Sync is currently getting file at path from dropbox.
	PutPathActivity // Sync is currently putting local file to path on dropbox.
};
typedef NSUInteger PathActivity;

enum {
	PathControllerLogLevelDebug = 0,
	PathControllerLogLevelInfo,
	PathControllerLogLevelWarn,
	PathControllerLogLevelError
};
typedef NSUInteger PathControllerLogLevel;

@class PathMetadata;
@class PathControllerManagedObjectContext;

NSInteger sortInPathOrder(NSString *a, NSString *b, void* context);

@interface PathController : NSObject <DBRestClientDelegate, DBLoginControllerDelegate, DBSessionDelegate> {
	NSString *localRoot;
	NSString *serverRoot;
	NSString *pathMetadataStorePath;
	NSMutableDictionary *localPathsToNormalizedPaths;
	NSMutableDictionary *normalizedPathsToPathActivity;
	NSMutableDictionary *normalizedPathsToPathMetadatas;
	NSMutableDictionary *pendingPathChangedNotificationUserInfo;
	NSOperationQueue *getOperationQueue;
	NSOperationQueue *putOperationQueue;
	NSOperationQueue *deleteOperationQueue;
	NSOperationQueue *folderSyncPathOperationOperationQueue;
	DBRestClient *manualLinkClient;
    NSManagedObjectModel *managedObjectModel;
    NSPersistentStoreCoordinator *persistentStoreCoordinator;
    PathControllerManagedObjectContext *managedObjectContext;
	id <PathControllerDelegate> delegate;
	PathControllerLogLevel logLevel;
}

+ (NSError *)documentsFolderCannotBeRenamedError;

#pragma mark -
#pragma mark Init

- (id)initWithLocalRoot:(NSString *)aLocalRoot serverRoot:(NSString *)aServerRoot pathMetadataStorePath:(NSString *)aPathMetadataStorePath;

#pragma mark -
#pragma mark Attributes

@property(readonly) NSString *localRoot;
@property(nonatomic, retain) NSString *serverRoot;
//@property(nonatomic, assign) id <PathControllerDelegate> delegate;

#pragma mark -
#pragma mark Path Modifications

- (BOOL)createFolderAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)createFileAtPath:(NSString *)path content:(NSData *)contents error:(NSError **)error;
- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)removeUnchangedItemsAtPath:(NSString *)aLocalPath error:(NSError **)error removedAll:(BOOL *)removedAll;
- (BOOL)pasteItemToPath:(NSString *)path error:(NSError **)error;
- (BOOL)moveItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath error:(NSError **)error;
- (void)enqueuePathChangedNotification:(id)value changeType:(NSString *)changeTypeKey;

#pragma mark -
#pragma mark Path Syncing

- (void)enqueueFolderSyncPathRequest:(NSString *)localPath;
- (BOOL)isSyncInProgress;
- (void)cancelSyncInProgress;
- (PathState)stateForPath:(NSString *)localPath;
- (NSError *)errorForPath:(NSString *)localPath;
- (PathActivity)pathActivityForPath:(NSString *)localPath;

#pragma mark -
#pragma mark Linking

@property(readonly) BOOL isLinked;
- (void)linkWithEmail:(NSString *)email password:(NSString *)password;
- (void)unlink:(BOOL)discardSessionKeys;

#pragma mark -
#pragma mark Logging

@property (nonatomic, assign) PathControllerLogLevel logLevel;
- (void)log:(NSString *)aString level:(PathControllerLogLevel)level prettyFunction:(const char *)prettyFunction line:(NSUInteger)line;

@end

extern NSString *BeginingFolderSyncNotification;
extern NSString *EndingFolderSyncNotification;
extern NSString *PathControllerLinkedNotification;
extern NSString *PathControllerLinkFailedNotification;

// Path notifications
extern NSString *PathsChangedNotification;
extern NSString *MovedPathsKey;
extern NSString *CreatedPathsKey;
extern NSString *ModifiedPathsKey;
extern NSString *RemovedPathsKey;
extern NSString *StateChangedPathsKey;
extern NSString *ActivityChangedPathsKey;

// Path notification userInfo keys
extern NSString *PathKey;
extern NSString *FromPathKey;
extern NSString *ToPathKey;

#define PathControllerLogDebug(...) if (self.logLevel <= PathControllerLogLevelDebug) [self log:[NSString stringWithFormat:__VA_ARGS__, nil] level:PathControllerLogLevelDebug prettyFunction:__PRETTY_FUNCTION__ line:__LINE__];
#define PathControllerLogInfo(...) if (self.logLevel <= PathControllerLogLevelInfo) [self log:[NSString stringWithFormat:__VA_ARGS__, nil] level:PathControllerLogLevelInfo prettyFunction:__PRETTY_FUNCTION__ line:__LINE__];
#define PathControllerLogWarn(...) if (self.logLevel <= PathControllerLogLevelWarn) [self log:[NSString stringWithFormat:__VA_ARGS__, nil] level:PathControllerLogLevelWarn prettyFunction:__PRETTY_FUNCTION__ line:__LINE__];
#define PathControllerLogError(...) if (self.logLevel <= PathControllerLogLevelError) [self log:[NSString stringWithFormat:__VA_ARGS__, nil] level:PathControllerLogLevelError prettyFunction:__PRETTY_FUNCTION__ line:__LINE__];
