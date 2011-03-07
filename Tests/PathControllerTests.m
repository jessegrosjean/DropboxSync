//
//  PathControllerGetTest.m
//  DropboxSync
//
//  Created by Jesse Grosjean on 8/15/10.
//  Copyright 2010 Hog Bay Software. All rights reserved.
//

#import "PathControllerTests.h"
#import "NSFileManager_Additions.h"
#import "PathController_Private.h"
#import "PathController.h"
#import "PathMetadata.h"
#include <unistd.h>

#define FILE_ONE @"1 はじめ.txt"
#define FILE_TWO @"2 ū.txt"
#define FOLDER_FOUR @"4 ぜら"

@implementation PathControllerTests

- (id)init {
	self = [super init];
	fileManager = [[NSFileManager defaultManager] retain];
	[DBSession setSharedSession:[[[DBSession alloc] initWithConsumerKey:CONSUMERKEY consumerSecret:CONSUMERSECRET] autorelease]];
	client = [[DBRestClient alloc] initWithSession:[DBSession sharedSession]];
	client.delegate = self;
	return self;
}

- (void)dealloc {
	[fileManager removeItemAtPath:pathController.localRoot error:NULL];
	[fileManager release];
	client.delegate = nil;
	[client release];
	[super dealloc];
}

- (void)link {
	if (!pathController.isLinked) {
		[self prepare:@selector(setUp)];
		[pathController linkWithEmail:DROPBOXTESTACCOUNT password:DROPBOXTESTACCOUNTPASSWORD];
		[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
		GHAssertTrue(pathController.isLinked, nil);
	}
}

- (void)setUp {	
	NSString *localRoot = [[fileManager tempDirectory] stringByAppendingPathComponent:@"UnitTestingWillBeDeleted"];
	[fileManager removeItemAtPath:localRoot error:NULL];
	[fileManager createDirectoryAtPath:localRoot withIntermediateDirectories:NO attributes:nil error:NULL];	
	NSString *serverRoot = [[TEST_FOLDER_FIXTURE_DROPBOX_PATH stringByDeletingLastPathComponent] stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	
	pathController = [[PathController alloc] initWithLocalRoot:localRoot serverRoot:serverRoot pathMetadataStorePath:[[NSFileManager defaultManager] tempDirectoryUnusedPath]];
	pathController.delegate = self;
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pathControllerLinkedNotification:) name:PathControllerLinkedNotification object:pathController];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pathControllerLinkFailedNotification:) name:PathControllerLinkFailedNotification object:pathController];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(beginingSyncNotification:) name:BeginingFolderSyncNotification object:pathController];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(endingSyncNotification:) name:EndingFolderSyncNotification object:pathController];
	
	[self link];
			
	[self prepare];
	[client copyFrom:TEST_FOLDER_FIXTURE_DROPBOX_PATH toPath:pathController.serverRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
		
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
		
	NSArray *contents = [[fileManager contentsOfDirectoryAtPath:pathController.localRoot error:NULL] valueForKey:@"precomposedStringWithCanonicalMapping"];
	NSArray *expectedContents = [[NSArray arrayWithObjects:FILE_ONE, FILE_TWO, @"3.txt", FOLDER_FOUR, nil] valueForKey:@"precomposedStringWithCanonicalMapping"];
	GHAssertEqualObjects(contents, expectedContents, nil);
	
	GHAssertTrue([pathController stateForPath:[pathController.localRoot stringByAppendingPathComponent:FILE_ONE]] == SyncedPathState, nil);
	GHAssertTrue([pathController stateForPath:[pathController.localRoot stringByAppendingPathComponent:FOLDER_FOUR]] == SyncedPathState, nil);
}

- (void)tearDown {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self prepare];
	[client deletePath:pathController.serverRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	[pathController unlink:NO];
	[pathController release];
	pathController = nil;
}

- (BOOL)shouldRunOnMainThread {
	return YES;
}

- (void)testCreatedFolderAndThenRefreshParent {
	NSString *folderPath = [pathController.localRoot stringByAppendingPathComponent:@"my folder"];
	[fileManager createDirectoryAtPath:folderPath withIntermediateDirectories:YES attributes:nil error:NULL];
	
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];

	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	
	NSArray *contents = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:pathController.localRoot error:NULL] valueForKey:@"precomposedStringWithCanonicalMapping"];
	NSArray *expectedContents = [[NSArray arrayWithObjects:FILE_ONE, FILE_TWO, @"3.txt", FOLDER_FOUR, @"my folder", nil] valueForKey:@"precomposedStringWithCanonicalMapping"];
	GHAssertEqualObjects(contents, expectedContents, nil);
}

- (void)testSingleFileLifeCycle {
	NSString *localPath = [pathController.localRoot stringByAppendingPathComponent:@"hello ū world.txt"];
	
	// create
	[@"hello world" writeToFile:localPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	[self prepare];
	[client loadMetadata:[pathController localPathToServer:localPath]];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	GHAssertTrue([fileManager fileExistsAtPath:localPath], nil);
	
	// modify
	[@"hello world, I've changed" writeToFile:localPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	[self prepare];
	[client loadMetadata:[pathController localPathToServer:localPath]];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	GHAssertTrue([fileManager fileExistsAtPath:localPath], nil);

	// delete
	[fileManager removeItemAtPath:localPath error:NULL];
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	GHAssertFalse([fileManager fileExistsAtPath:localPath], nil);
}

- (void)testManyPuts {
	NSMutableArray *paths = [NSMutableArray array];

	for (NSUInteger i = 0; i < 10; i++) {
		[paths addObject:[pathController.localRoot stringByAppendingFormat:@"/add ぜら %i.txt", i]];
	}

	for (NSString *each in paths) {
		[@"adding this file" writeToFile:each atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	}
		
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:100.0];
	
	for (NSString *each in paths) {
		[fileManager removeItemAtPath:each error:NULL];
	}
	
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:100.0];
}

- (void)testHitServerMetadataCache {
	// 1. hit cache
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];	
	NSArray *contents = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:pathController.localRoot error:NULL] valueForKey:@"precomposedStringWithCanonicalMapping"];
	NSArray *expectedContents = [[NSArray arrayWithObjects:FILE_ONE, FILE_TWO, @"3.txt", FOLDER_FOUR, nil] valueForKey:@"precomposedStringWithCanonicalMapping"];
	GHAssertEqualObjects(contents, expectedContents, nil);
	
	// 2. Add file local.
	[@"five\n" writeToFile:[pathController.localRoot stringByAppendingPathComponent:@"5 ぜら.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	
	// 3. Make sure file has been added after sync
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];	
	contents = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:pathController.localRoot error:NULL] valueForKey:@"precomposedStringWithCanonicalMapping"];
	expectedContents = [[NSArray arrayWithObjects:FILE_ONE, FILE_TWO, @"3.txt", FOLDER_FOUR, @"5 ぜら.txt", nil] valueForKey:@"precomposedStringWithCanonicalMapping"];
	GHAssertEqualObjects(contents, expectedContents, nil);
}

- (void)testAdds {
	// 1. Add file on server.
	[self prepare];
	NSString *localTemp = [[NSFileManager defaultManager] tempDirectoryUnusedPath];
	[@"testing..." writeToFile:localTemp atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	[client uploadFile:[@"6 ぜら.txt" precomposedStringWithCanonicalMapping] toPath:pathController.serverRoot fromPath:localTemp];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	[fileManager removeItemAtPath:localTemp error:NULL];

	// 2. Add file local.
	[@"five\n" writeToFile:[pathController.localRoot stringByAppendingPathComponent:@"5 ぜら.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	
	// 3. Sync and make sure local contents is as expected.
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];	
	NSArray *contents = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:pathController.localRoot error:NULL] valueForKey:@"precomposedStringWithCanonicalMapping"];
	NSArray *expectedContents = [[NSArray arrayWithObjects:FILE_ONE, FILE_TWO, @"3.txt", FOLDER_FOUR, @"5 ぜら.txt", @"6 ぜら.txt", nil] valueForKey:@"precomposedStringWithCanonicalMapping"];
	GHAssertEqualObjects(contents, expectedContents, nil);
}

- (void)testLocalAddAfterInitialLocalSync {
	[pathController unlink:NO];

	// 2. Add file local.
	[@"five\n" writeToFile:[pathController.localRoot stringByAppendingPathComponent:@"5.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];

	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];	

	[self link];
	
	// 3. Sync and make sure local contents is as expected.
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];	
	NSArray *contents = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:pathController.localRoot error:NULL] valueForKey:@"precomposedStringWithCanonicalMapping"];
	NSArray *expectedContents = [[NSArray arrayWithObjects:FILE_ONE, FILE_TWO, @"3.txt", FOLDER_FOUR, @"5.txt", nil] valueForKey:@"precomposedStringWithCanonicalMapping"];
	GHAssertEqualObjects(contents, expectedContents, nil);
}

- (void)testAddConflict {
	// 1. Add 6.txt on server
	[self prepare];
	NSString *localTemp = [[NSFileManager defaultManager] tempDirectoryUnusedPath];
	[@"testing..." writeToFile:localTemp atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	[client uploadFile:@"6.txt" toPath:pathController.serverRoot fromPath:localTemp];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	[fileManager removeItemAtPath:localTemp error:NULL];
	
	// 2. Add 6.txt on local
	[self prepare];
	[@"local add\n" writeToFile:[pathController.localRoot stringByAppendingPathComponent:@"6.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];

	// 3. Assert that local conflict was created.
	NSArray *contents = [[fileManager contentsOfDirectoryAtPath:pathController.localRoot error:NULL] valueForKey:@"precomposedStringWithCanonicalMapping"];
	NSArray *knownContents = [[NSArray arrayWithObjects:FILE_ONE, FILE_TWO, @"3.txt", FOLDER_FOUR, @"5.txt", @"6.txt", nil] valueForKey:@"precomposedStringWithCanonicalMapping"];
	for (NSString *each in contents) {
		GHAssertTrue([knownContents containsObject:each] || [each rangeOfString:@"conflicted copy"].location != NSNotFound, nil);
	}
}


- (void)testDeletes {
	// 1. Delete 3.txt on server.
	[self prepare];
	[client deletePath:[pathController.serverRoot stringByAppendingPathComponent:@"3.txt"]];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	
	// 2. Delete 2 ū.txt on client, and sync
	[self prepare];
	[[NSFileManager defaultManager] removeItemAtPath:[[pathController.localRoot stringByAppendingPathComponent:FILE_TWO] precomposedStringWithCanonicalMapping] error:NULL];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];

	NSArray *contents = [[fileManager contentsOfDirectoryAtPath:pathController.localRoot error:NULL] valueForKey:@"precomposedStringWithCanonicalMapping"];
	NSArray *expectedContents = [[NSArray arrayWithObjects:FILE_ONE, FOLDER_FOUR, nil] valueForKey:@"precomposedStringWithCanonicalMapping"];
	GHAssertEqualObjects(contents, expectedContents, nil);
	
	NSString *localDeletedPath2 = [[pathController.localRoot stringByAppendingPathComponent:FILE_TWO] precomposedStringWithCanonicalMapping];
	NSString *localDeletedPath3 = [[pathController.localRoot stringByAppendingPathComponent:@"3.txt"] precomposedStringWithCanonicalMapping];
	GHAssertFalse([fileManager fileExistsAtPath:localDeletedPath2], nil);
	GHAssertFalse([fileManager fileExistsAtPath:localDeletedPath3], nil);
	GHAssertNil([pathController pathMetadataForLocalPath:localDeletedPath2 createNewLocalIfNeeded:NO], nil);
	GHAssertNil([pathController pathMetadataForLocalPath:localDeletedPath3 createNewLocalIfNeeded:NO], nil);
}

- (void)testServerModify {
	// 1. Modify file on server
	[self prepare];
	NSString *localTemp = [[NSFileManager defaultManager] tempDirectoryUnusedPath];
	[@"one\ntwo\n" writeToFile:localTemp atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	[client uploadFile:[FILE_TWO precomposedStringWithCanonicalMapping] toPath:pathController.serverRoot fromPath:localTemp];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	[fileManager removeItemAtPath:localTemp error:NULL];
	
	sleep(4); // seems neccessary, otherwise new get doesn't get new version.
	
	// 2. Sync
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];	
	
	NSString *string = [NSString stringWithContentsOfFile:[pathController.localRoot stringByAppendingPathComponent:FILE_TWO] encoding:NSUTF8StringEncoding error:NULL];
	GHAssertEqualObjects(@"one\ntwo\n", string, nil);
}

- (void)testLocalModify {
	[@"one\ntwo\n" writeToFile:[pathController.localRoot stringByAppendingPathComponent:FILE_TWO] atomically:YES encoding:NSUTF8StringEncoding error:NULL];

	// 1. Sync
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];	

	// 2. Get from server
	[self prepare];
	NSString *localTemp = [[NSFileManager defaultManager] tempDirectoryUnusedPath];
	[client loadFile:[[pathController.serverRoot stringByAppendingPathComponent:FILE_TWO] precomposedStringWithCanonicalMapping] intoPath:localTemp];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	[fileManager removeItemAtPath:localTemp error:NULL];
	
	NSString *string = [NSString stringWithContentsOfFile:[pathController.localRoot stringByAppendingPathComponent:FILE_TWO] encoding:NSUTF8StringEncoding error:NULL];
	GHAssertEqualObjects(@"one\ntwo\n", string, nil);
}

- (void)testSyncFolderWithUnsyncedParent {
	NSString *testPath = [pathController.localRoot stringByAppendingPathComponent:[FOLDER_FOUR stringByAppendingPathComponent:@"boo"]];
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:testPath];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	NSArray *contents = [fileManager contentsOfDirectoryAtPath:testPath error:NULL];
	GHAssertTrue([contents containsObject:@"hello.txt"], nil);
}

- (void)testLocalRootRecreatedAfterServerRootDeletedWithNoLocalChanges {
	[self prepare];
	[client deletePath:pathController.serverRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];		
	
	deleteFailMeansSuccess = YES;
}

- (void)testLocalChangedNotDestroyedByServerDelete {
	[@"changed\n" writeToFile:[pathController.localRoot stringByAppendingPathComponent:FILE_ONE] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	[@"new\n" writeToFile:[pathController.localRoot stringByAppendingPathComponent:@"new.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	[fileManager createDirectoryAtPath:[pathController.localRoot stringByAppendingPathComponent:[FOLDER_FOUR stringByAppendingPathComponent:@"boo2"]] withIntermediateDirectories:YES attributes:nil error:NULL];
	[@"newtwo\n" writeToFile:[pathController.localRoot stringByAppendingPathComponent:[FOLDER_FOUR stringByAppendingPathComponent:@"boo2/anothernew.txt"]] atomically:YES encoding:NSUTF8StringEncoding error:NULL];

	[self prepare];
	[client deletePath:pathController.serverRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];	
	
	NSArray *contents = [[fileManager contentsOfDirectoryAtPath:pathController.localRoot error:NULL] valueForKey:@"precomposedStringWithCanonicalMapping"];
	NSArray *expectedContents = [[NSArray arrayWithObjects:FILE_ONE, FOLDER_FOUR, @"new.txt", nil] valueForKey:@"precomposedStringWithCanonicalMapping"];
	GHAssertEqualObjects(contents, expectedContents, nil);
	GHAssertTrue([fileManager fileExistsAtPath:[pathController.localRoot stringByAppendingPathComponent:[FOLDER_FOUR stringByAppendingPathComponent:@"boo2/anothernew.txt"]]], nil);
}

- (void)testLocalChangedNotDestroyedWhenUnlinking {
	[@"changed\n" writeToFile:[pathController.localRoot stringByAppendingPathComponent:FILE_ONE] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	[@"new\n" writeToFile:[pathController.localRoot stringByAppendingPathComponent:@"new.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	[fileManager createDirectoryAtPath:[pathController.localRoot stringByAppendingPathComponent:[FOLDER_FOUR stringByAppendingPathComponent:@"boo2"]] withIntermediateDirectories:YES attributes:nil error:NULL];
	[@"newtwo\n" writeToFile:[pathController.localRoot stringByAppendingPathComponent:[FOLDER_FOUR stringByAppendingPathComponent:@"boo2/anothernew.txt"]] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	
	[pathController unlink:NO];
	
	NSArray *contents = [[fileManager contentsOfDirectoryAtPath:pathController.localRoot error:NULL] valueForKey:@"precomposedStringWithCanonicalMapping"];
	NSArray *expectedContents = [[NSArray arrayWithObjects:FILE_ONE, FOLDER_FOUR, @"new.txt", nil] valueForKey:@"precomposedStringWithCanonicalMapping"];
	GHAssertEqualObjects(contents, expectedContents, nil);
	GHAssertTrue([fileManager fileExistsAtPath:[pathController.localRoot stringByAppendingPathComponent:[FOLDER_FOUR stringByAppendingPathComponent:@"boo2/anothernew.txt"]]], nil);
	
	[self link];
}

- (void)testTurnSimulateiOSClockBackOneHour {
	NSString *testPath = [pathController.localRoot stringByAppendingPathComponent:@"test.txt"];
	NSDate *iOSTime = [NSDate dateWithTimeIntervalSinceNow:-3600];
	[@"" writeToFile:testPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	[fileManager setAttributes:[NSDictionary dictionaryWithObject:iOSTime forKey:NSFileModificationDate] ofItemAtPath:testPath error:NULL];
	
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	
	[@"test\n" writeToFile:testPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	iOSTime = [iOSTime dateByAddingTimeInterval:2];
	[fileManager setAttributes:[NSDictionary dictionaryWithObject:iOSTime forKey:NSFileModificationDate]ofItemAtPath:testPath error:NULL];
	 
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];

	[self prepare];
	NSString *localTemp = [fileManager tempDirectoryUnusedPath];
	[client loadFile:[[pathController.serverRoot stringByAppendingPathComponent:@"test.txt"] precomposedStringWithCanonicalMapping] intoPath:localTemp];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	NSString *string = [NSString stringWithContentsOfFile:localTemp encoding:NSUTF8StringEncoding error:NULL];
	[fileManager removeItemAtPath:localTemp error:NULL];

	GHAssertEqualObjects(@"test\n", string, nil);	
}

- (void)testSyncDeletedFolder {
	NSString *serverTestPath = [[pathController.serverRoot stringByAppendingPathComponent:FOLDER_FOUR] precomposedStringWithCanonicalMapping];
	NSString *localTestPath = [[pathController.localRoot stringByAppendingPathComponent:FOLDER_FOUR] precomposedStringWithCanonicalMapping];

	[self prepare];
	[pathController enqueueFolderSyncPathRequest:localTestPath];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	
	[self prepare];
	[client deletePath:serverTestPath];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];

	[self prepare];
	[pathController enqueueFolderSyncPathRequest:localTestPath];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];

	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];

	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	
	GHAssertFalse([fileManager fileExistsAtPath:localTestPath], nil);
}

- (void)testSyncNewFolderWithPreviouslyDeletedMetadata {
	NSString *normalizedPath = @"a/b/c/d/e";
	NSString *serverPath = [pathController.serverRoot stringByAppendingPathComponent:normalizedPath];
	NSString *localPath = [pathController.localRoot stringByAppendingPathComponent:normalizedPath];
	
	[fileManager createDirectoryAtPath:localPath withIntermediateDirectories:YES attributes:nil error:NULL];

	[self prepare];
	[pathController enqueueFolderSyncPathRequest:localPath];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];

	GHAssertTrue([fileManager fileExistsAtPath:localPath], nil);

	[self prepare];
	[client deletePath:serverPath];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:localPath];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	
	GHAssertFalse([fileManager fileExistsAtPath:localPath], nil);

	[fileManager createDirectoryAtPath:localPath withIntermediateDirectories:YES attributes:nil error:NULL];

	[self prepare];
	[pathController enqueueFolderSyncPathRequest:localPath];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	
	GHAssertTrue([fileManager fileExistsAtPath:localPath], nil);
}

- (void)testLocalEditsToDeletedFile {
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:[pathController.localRoot stringByAppendingPathComponent:FOLDER_FOUR]];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];

	[self prepare];
	[pathController enqueueFolderSyncPathRequest:[pathController.localRoot stringByAppendingPathComponent:[FOLDER_FOUR stringByAppendingPathComponent:@"boo"]]];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];

	[@"changed\n" writeToFile:[pathController.localRoot stringByAppendingPathComponent:[FOLDER_FOUR stringByAppendingPathComponent:@"boo/hello.txt"]] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	 
	[self prepare];
	[client deletePath:[[pathController.serverRoot stringByAppendingPathComponent:[FOLDER_FOUR stringByAppendingPathComponent:@"boo/hello.txt"]] precomposedStringWithCanonicalMapping]];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];

	[self prepare];
	[pathController enqueueFolderSyncPathRequest:[pathController.localRoot stringByAppendingPathComponent:[FOLDER_FOUR stringByAppendingPathComponent:@"boo"]]];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	
	NSArray *contents = [fileManager contentsOfDirectoryAtPath:[pathController.localRoot stringByAppendingPathComponent:[FOLDER_FOUR stringByAppendingPathComponent:@"boo"]] error:NULL];
	NSArray *expectedContents = [NSArray arrayWithObjects:@"hello.txt", nil];
	GHAssertEqualObjects(contents, expectedContents, nil);
}

- (void)testPermanentPlaceholderPathState {
	NSString *pagesPath = [pathController.localRoot stringByAppendingPathComponent:[FOLDER_FOUR stringByAppendingPathComponent:@"test.pages"]];
	
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:[pagesPath stringByDeletingLastPathComponent]];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	
	GHAssertTrue([pathController stateForPath:pagesPath] == PermanentPlaceholderPathState, nil);
	GHAssertTrue([fileManager fileExistsAtPath:pagesPath], nil);
}

- (void)testTranslations {
	NSString *subPath = @"onE/Two/Tree.txt";
	NSString *localPath = [pathController.localRoot stringByAppendingPathComponent:subPath];
	NSString *serverPath = [pathController.serverRoot stringByAppendingPathComponent:subPath];
	NSString *normalizedPath = [[@"/" stringByAppendingPathComponent:subPath] normalizedDropboxPath];
	
	GHAssertEqualStrings([pathController localPathToNormalized:localPath], normalizedPath, nil);
	GHAssertEqualStrings([pathController localPathToServer:localPath], serverPath, nil);
	GHAssertEqualStrings([pathController serverPathToLocal:serverPath], localPath, nil);
	GHAssertEqualStrings([pathController localPathToNormalized:pathController.localRoot], @"/", nil);
}

- (void)testCaseSensitiveRename {
	[@"case test" writeToFile:[pathController.localRoot stringByAppendingPathComponent:@"Apple.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
		
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	GHAssertTrue([fileManager fileExistsAtPath:[pathController.localRoot stringByAppendingPathComponent:@"Apple.txt"]], nil);
	
	// XXX causes sync request...
	[pathController moveItemAtPath:[pathController.localRoot stringByAppendingPathComponent:@"Apple.txt"] toPath:[pathController.localRoot stringByAppendingPathComponent:@"applE.txt"] error:NULL];
	GHAssertTrue([fileManager fileExistsAtPath:[pathController.localRoot stringByAppendingPathComponent:@"applE.txt"]], nil);

	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];
	GHAssertTrue([fileManager fileExistsAtPath:[pathController.localRoot stringByAppendingPathComponent:@"applE.txt"]], nil);
}

- (void)testDeleteShouldNotLeaveDanglingPathMetadata {
	[fileManager removeItemAtPath:[pathController.localRoot stringByAppendingPathComponent:FILE_ONE] error:NULL];
	
	[self prepare];
	[pathController enqueueFolderSyncPathRequest:pathController.localRoot];
	[self waitForStatus:kGHUnitWaitStatusSuccess timeout:10000.0];

	GHAssertNil([pathController pathMetadataForLocalPath:[pathController.localRoot stringByAppendingPathComponent:FILE_ONE] createNewLocalIfNeeded:NO], nil);
}

- (void)beginingSyncNotification:(NSNotification *)aNotification { }

- (void)endingSyncNotification:(NSNotification *)aNotification {
	[self notify:kGHUnitWaitStatusSuccess forSelector:waitSelector_];
}

- (void)pathControllerLinkedNotification:(NSNotification *)aNotification {
	[self notify:kGHUnitWaitStatusSuccess forSelector:waitSelector_];
}

- (void)pathControllerLinkFailedNotification:(NSNotification *)aNotification {
	[self notify:kGHUnitWaitStatusFailure forSelector:waitSelector_];
}

- (void)restClient:(DBRestClient*)client loadedMetadata:(DBMetadata*)metadata {
	if (metadata.isDeleted) {
		[self notify:kGHUnitWaitStatusFailure forSelector:waitSelector_];
	} else {
		[self notify:kGHUnitWaitStatusSuccess forSelector:waitSelector_];
	}
}

- (void)restClient:(DBRestClient*)client metadataUnchangedAtPath:(NSString*)path {
	[self notify:kGHUnitWaitStatusSuccess forSelector:waitSelector_];
}

- (void)restClient:(DBRestClient*)client loadMetadataFailedWithError:(NSError*)error {
	NSLog(@"loadMetadataFailedWithError %@", error);
	[self notify:kGHUnitWaitStatusFailure forSelector:waitSelector_];
}

- (void)restClient:(DBRestClient*)client deletedPath:(NSString *)path {
	[self notify:kGHUnitWaitStatusSuccess forSelector:waitSelector_];
}

- (void)restClient:(DBRestClient *)client deletePathFailedWithError:(NSError *)error {
	if (deleteFailMeansSuccess) {
		[self notify:kGHUnitWaitStatusSuccess forSelector:waitSelector_];
	} else {
		NSLog(@"deletePathFailedWithError %@", error);
		[self notify:kGHUnitWaitStatusFailure forSelector:waitSelector_];
	}
}

- (void)restClient:(DBRestClient*)client loadedFile:(NSString*)destPath {
	[self notify:kGHUnitWaitStatusSuccess forSelector:waitSelector_];
}

- (void)restClient:(DBRestClient*)client loadFileFailedWithError:(NSError*)error {
	NSLog(@"loadFileFailedWithError %@", error);
	[self notify:kGHUnitWaitStatusFailure forSelector:waitSelector_];
}

- (void)restClient:(DBRestClient*)client uploadedFile:(NSString*)srcPath {
	[self notify:kGHUnitWaitStatusSuccess forSelector:waitSelector_];
}

- (void)restClient:(DBRestClient*)client uploadFileFailedWithError:(NSError*)error {
	NSLog(@"uploadFileFailedWithError %@", error);
	[self notify:kGHUnitWaitStatusFailure forSelector:waitSelector_];
}

- (void)restClient:(DBRestClient*)client copiedPath:(NSString *)from_path toPath:(NSString *)to_path {
	[self notify:kGHUnitWaitStatusSuccess forSelector:waitSelector_];
}

- (void)restClient:(DBRestClient*)client copyPathFailedWithError:(NSError*)error {
	NSLog(@"copyPathFailedWithError %@", error);
	[self notify:kGHUnitWaitStatusFailure forSelector:waitSelector_];
}

#pragma mark PathController Delegate.

- (BOOL)shouldSyncFile:(NSString *)file {
	if ([[file pathExtension] isEqualToString:@"pages"]) {
		return NO;
	}
	return YES;
}


@end
