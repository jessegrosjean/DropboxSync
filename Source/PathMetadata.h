//
//  PathMetadata.h
//  DropboxSync
//
//  Created by Jesse Grosjean on 8/7/10.
//  Copyright 2010 Hog Bay Software. All rights reserved.
//

#import <CoreData/CoreData.h>
#import "PathController.h"

//
// Maintains persistent metadata about a paths sync state such as last sync date and last sync hash.
//

@class PathController;
@class PathOperation;
@class PathMetadata;

@interface PathMetadata : NSManagedObject {
	PathState pathState;
	BOOL lastSyncIsDirectory;
	NSString *normalizedPath;
	NSError *pathError;
}

+ (PathMetadata *)pathMetadataWithNormalizedName:(NSString *)aNormalizedName managedObjectContext:(NSManagedObjectContext *)aManagedObjectContext;

@property(readonly) BOOL isRoot;
@property(readonly) NSString *normalizedName;
@property(readonly) NSString *normalizedPath; // transient
@property(readonly) PathController *pathController; // transient
@property(nonatomic, retain) NSError *pathError; // transient

#pragma mark -
#pragma mark Children

@property(readonly) PathMetadata* parent;
@property(nonatomic, retain) NSSet* children;
@property(readonly) NSSet* allDescendantsWithSelf;

#pragma mark -
#pragma mark Last Sync Metadata

@property(nonatomic, assign) PathState pathState;
@property(nonatomic, retain) NSString *lastSyncName;
@property(nonatomic, retain) NSDate *lastSyncDate;
@property(nonatomic, retain) NSString *lastSyncHash;
@property(nonatomic, assign) BOOL lastSyncIsDirectory;

@end

@interface NSManagedObject (Children)
- (void)addChildrenObject:(PathMetadata *)aChild;
- (void)removeChildrenObject:(PathMetadata *)aChild;
@end