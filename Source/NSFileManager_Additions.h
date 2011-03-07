//
//  NSFileManager_Additions.h
//  DropboxSync
//
//  Created by Jesse Grosjean on 10/8/10.
//  Copyright 2010 Hog Bay Software. All rights reserved.
//


#import <Foundation/Foundation.h>

@interface NSFileManager (DropboxSyncAdditions)

- (NSString *)tempDirectory;
- (NSString *)tempDirectoryUnusedPath;
- (BOOL)my_moveItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath error:(NSError **)error;
- (NSString *)conflictPathForPath:(NSString *)aPath error:(NSError **)error;
- (NSString *)conflictPathForPath:(NSString *)aPath includeMessage:(BOOL)includeMessage error:(NSError **)error;

@end
