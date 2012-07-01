//
//  NHUnitIPhoneAppDelegate.m
//  DropboxSync
//
//  Created by Nick Hingston on 29/06/2012.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "NHUnitIPhoneAppDelegate.h"
#import <DropboxSDK/DropboxSDK.h>

@implementation NHUnitIPhoneAppDelegate

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    if ([[url scheme] hasPrefix:@"db-"]) {
        return [[DBSession sharedSession] handleOpenURL:url];
    }
    else {
        return [super application:application openURL:url sourceApplication:sourceApplication annotation:annotation];
    }
}

- (id) mainViewController {
    return navigationController_;
}

@end
