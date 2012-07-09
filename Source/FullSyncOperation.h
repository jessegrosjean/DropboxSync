//
//  FullSyncOperation.h
//  DropboxSync
//
//  Created by Nick Hingston on 05/07/2012.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PathController.h"
#import "PathOperation.h"

@interface FullSyncOperation : PathOperation<PathControllerSyncOperationDelegate> {
    NSString* _cursor;
    
    BOOL loadedDelta;
    
    NSMutableArray* _deltaEntries;
    BOOL _shouldReset;
    
    
    BOOL needsCleanupSync;
    BOOL schedulingOperations;
    NSMutableSet *pathOperations;
    PathController *pathController;
    NSUInteger operationCount;
}

- (id)initWithPathController:(PathController *)aPathController;

@property (nonatomic, assign) BOOL needsCleanupSync;
@property (nonatomic, retain) NSString* cursor;

- (void)pathOperationFinished:(PathOperation *)aPathOperation;
@end
