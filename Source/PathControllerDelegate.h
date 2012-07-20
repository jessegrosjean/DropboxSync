//
//  PathControllerDelegate.h
//  DropboxLib
//
//  Created by Jesse Grosjean on 3/7/11.
//  Copyright 2011 Hog Bay Software. All rights reserved.
//

typedef enum {
    PathConflictResolutionDuplicateLocal = 1,  // create a unique named copy locally, and upload to server
    PathConflictResolutionLocal          = 2,  // overwrite server version
    PathConflictResolutionServer         = 3,  // overwrite local
} PathControllerConflictResolutionType;


@protocol PathControllerDelegate <NSObject>

// Return yes if the file should be synced, no if not. If not then a local empy placeholder file will be created
// for the file and the path state will be set to PermanentPlaceholderPathState
- (BOOL)shouldSyncFile:(NSString *)file;
- (void)syncProgress:(CGFloat)progress fromPathController:(id)aPathController;

@optional
- (PathControllerConflictResolutionType) conflictResolutionTypeForLocalPath:(NSString*) path;

@end
