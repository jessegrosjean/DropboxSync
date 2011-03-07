//
//  PutPathOperation.h
//  DropboxSync
//
//  Created by Jesse Grosjean on 8/10/10.
//  Copyright 2010 Hog Bay Software. All rights reserved.
//

#import "PathOperation.h"

//
// Put local file to path on server.
//

@interface PutPathOperation : PathOperation {
	NSString *tempUploadPath;
}

@end
