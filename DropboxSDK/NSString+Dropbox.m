//
//  NSString+Dropbox.m
//  DropboxSDK
//
//  Created by Brian Smith on 7/19/10.
//  Copyright 2010 Dropbox, Inc. All rights reserved.
//

#import "NSString+Dropbox.h"


@implementation NSString (Dropbox)

- (NSString*)normalizedDropboxPath {
	NSString *lowercaseString = [self lowercaseString];
	NSString *precomposedStringWithCanonicalMapping = [lowercaseString precomposedStringWithCanonicalMapping];
	return precomposedStringWithCanonicalMapping;
}

- (BOOL)isEqualToDropboxPath:(NSString*)otherPath {
    return [[self normalizedDropboxPath] isEqualToString:[otherPath normalizedDropboxPath]];
}

@end
