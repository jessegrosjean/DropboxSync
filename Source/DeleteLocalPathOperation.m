//
//  DeleteLocalPathOperation.m
//  DropboxSync
//
//  Created by Jesse Grosjean on 8/11/10.
//  Copyright 2010 Hog Bay Software. All rights reserved.
//

#import "DeleteLocalPathOperation.h"
#import "FolderSyncPathOperation.h"
#import "PathController.h"
#import "PathMetadata.h"

@implementation DeleteLocalPathOperation

- (void)main {
	[self deleteLocalPath];
}

@end
