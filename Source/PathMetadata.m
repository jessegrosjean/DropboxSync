//
//  PathMetadata.m
//  DropboxSync
//
//  Created by Jesse Grosjean on 8/7/10.
//  Copyright 2010 Hog Bay Software. All rights reserved.
//

#import "PathMetadata.h"
#import "PathController.h"
#import "PathOperation.h"


@interface PathController (PathMetadataPrivate)
- (void)setPathMetadata:(PathMetadata *)aPathMetadata forNormalizedPath:(NSString *)aNormalizedPath;
@end

@implementation PathMetadata

+ (PathMetadata *)pathMetadataWithNormalizedName:(NSString *)aNormalizedName managedObjectContext:(NSManagedObjectContext *)aManagedObjectContext {
	PathMetadata *pathMetadata = [NSEntityDescription insertNewObjectForEntityForName:@"PathMetadata" inManagedObjectContext:aManagedObjectContext]; 
	[pathMetadata setPrimitiveValue:aNormalizedName forKey:@"normalizedName"];
	return pathMetadata;
}

#pragma mark -
#pragma mark Dealloc

- (void)didTurnIntoFault {
	[pathError release];
	[normalizedPath release];
	[super didTurnIntoFault];
}

- (void)awakeFromFetch {
	[super awakeFromFetch];
	[self.pathController setPathMetadata:self forNormalizedPath:self.normalizedPath];
}

- (BOOL)isRoot {
	return self.parent == nil;
}

@dynamic normalizedName;

- (NSString *)normalizedPath {
	if (!normalizedPath) {
		NSString *aPath = nil;
		if (self.parent) {
			aPath = [self.parent.normalizedPath stringByAppendingPathComponent:self.normalizedName];
		} else {
			aPath = [@"/" stringByAppendingPathComponent:self.normalizedName];
		}
		[normalizedPath release];
		normalizedPath = [aPath retain];
	}
	return normalizedPath;
}

- (PathController *)pathController {
	return [(PathControllerManagedObjectContext *)self.managedObjectContext pathController];
}

@synthesize pathError;

- (void)setPathError:(NSError *)anError {
	[pathError autorelease];
	pathError = [anError retain];
}

#pragma mark -
#pragma mark Children

@dynamic parent;
@dynamic children;

- (NSSet* )allDescendantsWithSelf {
	NSMutableSet *results = [NSMutableSet set];
	for (PathMetadata *each in self.children) {
		[results unionSet:each.allDescendantsWithSelf];
	}
	[results addObject:self];
	return results;
}

#pragma mark -
#pragma mark Last Sync Metadata

- (PathState)pathState {
	[self willAccessValueForKey:@"pathState"];
	BOOL result = pathState;
	[self didAccessValueForKey:@"pathState"];
	return result;
}

- (void)setPathState:(PathState)newState {
	[self willChangeValueForKey:@"pathState"];
	if (pathState != newState) {
		pathState = newState;
	}
	[self didChangeValueForKey:@"pathState"];
}

@dynamic lastSyncName;
@dynamic lastSyncDate;
@dynamic lastSyncHash;
@dynamic lastSyncIsDirectory;

- (BOOL)lastSyncIsDirectory {
	[self willAccessValueForKey:@"lastSyncIsDirectory"];
	BOOL result = lastSyncIsDirectory;
	[self didAccessValueForKey:@"lastSyncIsDirectory"];
	return result;
}

- (void)setLastSyncIsDirectory:(BOOL)aBool {
	[self willChangeValueForKey:@"lastSyncIsDirectory"];
	lastSyncIsDirectory = aBool;
	[self didChangeValueForKey:@"lastSyncIsDirectory"];	
}

@end

@implementation PathController (PathMetadataPrivate)

- (void)setPathMetadata:(PathMetadata *)aPathMetadata forNormalizedPath:(NSString *)aNormalizedPath {
	[normalizedPathsToPathMetadatas setObject:aPathMetadata forKey:aNormalizedPath];
}

@end
