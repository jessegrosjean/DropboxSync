//
//  PathControllerDelegate.h
//  DropboxLib
//
//  Created by Jesse Grosjean on 3/7/11.
//  Copyright 2011 Hog Bay Software. All rights reserved.
//


@protocol PathControllerDelegate <NSObject>

// Return yes if the file should be synced, no if not. If not then a local empy placeholder file will be created
// for the file and the path state will be set to PermanentPlaceholderPathState
- (BOOL)shouldSyncFile:(NSString *)file;

@end
