#import "IPAInstaller.h"
#import "IPAParser.h"
#import "Logger.h"
#include <stdio.h>

@implementation IPAInstaller

+ (BOOL)installIPAPath:(NSURL *)ipaPath error:(NSError **)error {
    LOG_INFO("Beginning install for: %s", ipaPath.lastPathComponent.UTF8String);

    // 1. Extract IPA to tmp
    NSURL *tmpDir = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    tmpDir = [tmpDir URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:tmpDir withIntermediateDirectories:YES attributes:nil error:nil];

    LOG_DEBUG("Unzipping IPA to: %s", tmpDir.path.UTF8String);
    if (![IPAParser unzipIPAAt:ipaPath to:tmpDir error:error]) {
        LOG_ERROR("Unzip failed");
        [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
        return NO;
    }

    // 2. Find .app
    NSURL *payloadDir = [tmpDir URLByAppendingPathComponent:@"Payload"];
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:payloadDir.path error:nil];
    NSString *appDir = nil;
    for (NSString *name in contents) {
        if ([name hasSuffix:@".app"]) { appDir = name; break; }
    }
    if (!appDir) {
        if (error) *error = [NSError errorWithDomain:@"IPA" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Missing .app in Payload"}];
        [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
        return NO;
    }
    NSURL *appPath = [payloadDir URLByAppendingPathComponent:appDir];

    // 3. Create bundle directory in system
    NSString *bundleUUID = [[NSUUID UUID] UUIDString];
    NSString *destBundle = [NSString stringWithFormat:@"/var/containers/Bundle/Application/%@/", bundleUUID];
    [[NSFileManager defaultManager] createDirectoryAtPath:destBundle withIntermediateDirectories:YES attributes:nil error:nil];

    // 4. Atomic rename
    const char *src = appPath.path.UTF8String;
    const char *dst = [[destBundle stringByAppendingString:appDir] UTF8String];
    LOG_DEBUG("rename(\"%s\", \"%s\")", src, dst);
    int result = rename(src, dst);
    if (result != 0) {
        LOG_ERROR("rename failed: %s (errno=%d)", strerror(errno), errno);
        if (error) *error = [NSError errorWithDomain:@"IPA" code:errno
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"rename failed: %s", strerror(errno)]}];
        [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
        return NO;
    }
    LOG_INFO("Atomic rename succeeded: %s -> %s", src, dst);

    [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
    LOG_INFO("Install complete");
    return YES;
}

@end
