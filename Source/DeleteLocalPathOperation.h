//
//  DeleteLocalPathOperation.h
//  DropboxSync
//
//  Created by Jesse Grosjean on 8/11/10.
//  Copyright 2010 Hog Bay Software. All rights reserved.
//

#import "PathOperation.h"
#import "DropboxSDK.h"

//
// Operation to (safely, ie don't delete unsynced data) delete local path.
//

@interface DeleteLocalPathOperation : PathOperation {

}

@end
