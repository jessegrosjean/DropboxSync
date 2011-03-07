//
//  PathControllerGetTest.h
//  DropboxSync
//
//  Created by Jesse Grosjean on 8/15/10.
//  Copyright 2010 Hog Bay Software. All rights reserved.
//

#import <GHUnitIOS/GHUnitIOS.h>
#import "DropboxSDK.h"
#import "PathControllerDelegate.h"

// Application keys
#define CONSUMERKEY @""
#define CONSUMERSECRET @""

// Dropbox Account
#define DROPBOXTESTACCOUNT @""
#define DROPBOXTESTACCOUNTPASSWORD @""

// Text folder fixture path (copy from
#define TEST_FOLDER_FIXTURE_DROPBOX_PATH @"/Testing/DropboxTestFolderFixture"

@class PathController;

@interface PathControllerTests : GHAsyncTestCase <DBRestClientDelegate, PathControllerDelegate> {
	DBRestClient *client;
	PathController *pathController;
	NSFileManager *fileManager;
	BOOL deleteFailMeansSuccess;
}

@end
