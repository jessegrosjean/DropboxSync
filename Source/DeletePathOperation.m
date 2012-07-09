//
//  DeletePathOperation.m
//  DropboxSync
//
//  Created by Jesse Grosjean on 8/11/10.
//  Copyright 2010 Hog Bay Software. All rights reserved.
//

#import "DeletePathOperation.h"
#import "PathController_Private.h"
#import "PathController.h"

@implementation DeletePathOperation

- (BOOL)isDeleteOperation {
	return YES;
}

- (void)main {
	[self.client deletePath:[self.pathController localPathToServer:localPath]];
}

- (void)restClient:(DBRestClient*)aClient deletedPath:(NSString *)aServerPath {
	[self.pathController deletePathMetadataForLocalPath:localPath];
	self.createPathMetadataOnFinish = NO;
	[self finish];
}

- (void)restClient:(DBRestClient*)aClient deletePathFailedWithError:(NSError*)error {
    if (error.code == 404) { // does not exist already
        [self.pathController deletePathMetadataForLocalPath:localPath];
        self.createPathMetadataOnFinish = NO;
    }
    else {
        [self retryWithError:error];
    }
}

@end
