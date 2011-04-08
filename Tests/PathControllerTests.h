//
//  PathControllerTests.h
//  DropboxSync
//
//  Created by Jesse Grosjean on 8/15/10.
//  Copyright 2010 Hog Bay Software. All rights reserved.
//

#import <GHUnitIOS/GHUnitIOS.h>
#import "DropboxSDK.h"
#import "PathControllerDelegate.h"

// Application keys
#define CONSUMERKEY @"vzb4wt6wtm514l6"
#define CONSUMERSECRET @"7tdt2pgddt4305w"

// Dropbox Account
#define DROPBOXTESTACCOUNT @"jesse@hogbaysoftware.com"
#define DROPBOXTESTACCOUNTPASSWORD @"kimchi5pass"

// Test folder fixture path (copy from PROJECT/Source/Tests/DropboxTestFolderFixture) and put in your dropbox folder.
//#define TEST_FOLDER_FIXTURE_DROPBOX_PATH @"/Testing/DropboxTestFolderFixture"

#define TEST_FOLDER_FIXTURE_DROPBOX_PATH @"/Hog Bay Software/Operations/SyncTestFixtures/TestFolderUnicode"



@class PathController;

@interface PathControllerTests : GHAsyncTestCase <DBRestClientDelegate, PathControllerDelegate> {
	DBRestClient *client;
	PathController *pathController;
	NSFileManager *fileManager;
	BOOL deleteFailMeansSuccess;
}

@end
