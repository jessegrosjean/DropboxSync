//
//  GetPathOperation.h
//  DropboxSync
//
//  Created by Jesse Grosjean on 8/10/10.
//  Copyright 2010 Hog Bay Software. All rights reserved.
//

#import "PathOperation.h"

//
// Get server file and add (or update) local.
//

@interface GetPathOperation : PathOperation {
	NSString *tempDownloadPath;
}

@end
