//
//  NSFileManager_Additions.m
//  DropboxSync
//
//  Created by Jesse Grosjean on 6/9/10.
//  Copyright 2010 Hog Bay Software. All rights reserved.
//


#import "NSFileManager_Additions.h"
#import "NSString+Dropbox.h"
#import "NSSet_Additions.h"

@implementation NSFileManager (DropboxSyncAdditions)

- (NSString *)tempDirectory {
	NSString *tempDirectory = NSTemporaryDirectory();
	NSError *error;
	
	if (![self createDirectoryAtPath:tempDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
		NSLog(@"Unable to find or create temp directory:\n%@", error);
	}
	
	return tempDirectory;
}

- (NSString *)tempDirectoryUnusedPath {
	return [[self tempDirectory] stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
}

- (BOOL)my_moveItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath error:(NSError **)error {
	if ([fromPath isEqualToDropboxPath:toPath]) {
		NSString *unusedPath = [self tempDirectoryUnusedPath];
		if ([self moveItemAtPath:fromPath toPath:unusedPath error:error]) {
			if ([self moveItemAtPath:unusedPath toPath:toPath error:error]) {
				return YES;
			}
		}
		return NO;
	} else {
		return [self moveItemAtPath:fromPath toPath:toPath error:error];
	}
}

- (NSString *)conflictPathForPath:(NSString *)aPath error:(NSError **)error {
	return [self conflictPathForPath:aPath includeMessage:YES error:error];
}

- (NSString *)conflictPathForPath:(NSString *)aPath includeMessage:(BOOL)includeMessage error:(NSError **)error {
	NSString *directory = [aPath stringByDeletingLastPathComponent];
	NSString *filename = [aPath lastPathComponent];
	
	if (![self createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) {
		return nil;
	}
	
	NSArray *normalizedContents = [[self contentsOfDirectoryAtPath:directory error:error] valueForKey:@"normalizedDropboxPath"];
	NSSet *normalizedContentsSet = [NSSet setWithArray:normalizedContents];
	NSString *conflictName = [normalizedContentsSet conflictNameForNameInNormalizedSet:filename includeMessage:includeMessage];
	
	return [directory stringByAppendingPathComponent:conflictName];
}

@end
