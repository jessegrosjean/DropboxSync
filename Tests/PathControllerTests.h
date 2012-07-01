//
//  PathControllerTests.h
//  DropboxSync
//
//  Created by Jesse Grosjean on 8/15/10.
//  Copyright 2010 Hog Bay Software. All rights reserved.
//

#import <GHUnitIOS/GHUnitIOS.h>
#import <DropboxSDK/DropboxSDK.h>
#import "PathControllerDelegate.h"

// Application keys
#define CONSUMERKEY @"APP_ID"
#define CONSUMERSECRET @"APP_SECRET"


// Test folder fixture path (copy from PROJECT/Source/Tests/DropboxTestFolderFixture) and put in your dropbox folder.
#define TEST_FOLDER_FIXTURE_DROPBOX_PATH @"/Testing/DropboxTestFolderFixture"

@class PathController;
@class PathMetadata;
@interface PathControllerTests : GHAsyncTestCase <DBRestClientDelegate, PathControllerDelegate, DBSessionDelegate> {
	DBRestClient *client;
	PathController *pathController;
	NSFileManager *fileManager;
	BOOL deleteFailMeansSuccess;
    
    PathMetadata* _fileOneMetadata;
    PathMetadata* _fileTwoMetadata;
    
}

@end