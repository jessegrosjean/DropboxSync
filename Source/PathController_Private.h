//
//  PathController_Private.h
//  DropboxLib
//
//  Created by Jesse Grosjean on 3/7/11.
//  Copyright 2011 Hog Bay Software. All rights reserved.
//

#import "PathController.h"

@interface PathController ()

@property (nonatomic, retain) NSMutableDictionary* localPathsToNormalizedPaths;
@property (nonatomic, retain) NSMutableDictionary* normalizedPathsToPathActivity;
@property (nonatomic, retain) NSMutableDictionary* normalizedPathsToPathMetadatas;

- (NSString *)serverPathToLocal:(NSString *)serverPath;
- (NSString *)localPathToServer:(NSString *)localPath;	
- (NSString *)localPathToNormalized:(NSString *)localPath;

- (BOOL)saveState;
- (void)setPathActivity:(PathActivity)aPathActivity forPath:(NSString *)aLocalPath;
- (PathMetadata *)pathMetadataForLocalPath:(NSString *)localPath createNewLocalIfNeeded:(BOOL)createIfNeeded;
- (void)deletePathMetadataForLocalPath:(NSString *)localPath;
- (void)initManagedObjectContext;
- (void)postQueuedPathChangedNotifications;

@end
