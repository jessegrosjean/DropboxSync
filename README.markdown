DropboxSync is designed to keep a local folder hierarchy on iOS synced with a Dropbox folder hierarchy. The goal is to work like Dropbox on other platforms… ie the client application works with files on the file system, and they are magically synced in the background.

## Operation

Unfortunately DropboxSync can't be quite as magic from an application developers perspective as Dropbox on the Desktop. In particular you are responsible for controlling the sync process through calls to enqueueFolderSyncPathRequest after you've made local changes to files in a directory, or when you want to refresh a directory from the server.

PathController maintains state on synced paths and fires notifications when those paths are modified as part of the sync process. PathController also provides a set of "Path Modifications" methods that fire those same events. The idea is that you can use those method when making your local filesystem notifications, and then your views can get a universal set of file changed notifications no matter if it's your code, or the sync code that's updating the paths.

## Requirements

DropboxSync uses a slightly (DBRestClient>didParseMetadata) modified version of the Dropbox SDK that fixes a bug with wifi hotspot paywall pages.

DropboxSync uses Coredata to store local metadata used by the sync process.

## Limitations

DropboxSync doesn't handle local renaming of synced folders well. Renames are synced as Delete/Add on server. For files this works, but for directories there are no checks on place to see if server directories contents have been modified, and so a local rename will just delete those files. I just disable local folder rename in my app, a better solution would be to make to the Dropboxe API Rename command.

## Running Tests

Before running tests you must set your application keys and dropbox password in PathControllerTests.h. You also need to copy the DropboxTestFolderFixture (in Tests) to you Dropbox account and then update PathControllerTests.h with that path.

## Basic usage

    // 1. Set Dropbox shared session with keys from app using API
    [DBSession setSharedSession:[[[DBSession alloc] initWithConsumerKey:CONSUMERKEY consumerSecret:CONSUMERSECRET] autorelease]];

    // 2. Create path controller.
    PathController *pathController = [[PathController alloc] initWithLocalRoot:LOCAL_ROOT serverRoot:SERVER_ROOT pathMetadataStorePath:METADATA_STORE];

    // 3. If isn't already linked then link
    if (!pathController.isLinked) {
    	[pathController linkWithEmail:DROPBOX_ACCOUNT password:DROPBOX_PASSWORD];
    }

    // 4. Sync top level (not recursive) local root with server root.
    [pathController enqueueFolderSyncPathRequest:pathController.localRoot];
