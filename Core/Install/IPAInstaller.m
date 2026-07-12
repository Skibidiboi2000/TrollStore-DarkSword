#import "IPAInstaller.h"
#import "Logger.h"
#include <stdio.h>
#include <unistd.h>
#include <sys/stat.h>

@implementation IPAInstaller

+ (BOOL)installAppBundle:(NSURL *)appBundlePath installedPath:(NSString **)outPath error:(NSError **)error {
    NSString *appName = appBundlePath.lastPathComponent;
    LOG_INFO("Beginning install for: %s", appName.UTF8String);

    NSString *bundleUUID = [[NSUUID UUID] UUIDString];
    NSString *destBase = @"/var/containers/Bundle/Application/";
    NSString *destBundle = [destBase stringByAppendingPathComponent:bundleUUID];
    NSString *destPath = [destBundle stringByAppendingPathComponent:appName];

    // Create destination directory with POSIX — NSFileManager can't write to system paths
    if (mkdir(destBundle.UTF8String, 0755) != 0 && errno != EEXIST) {
        LOG_ERROR("mkdir(%s) failed: %s (errno=%d)", destBundle.UTF8String, strerror(errno), errno);
        if (error) *error = [NSError errorWithDomain:@"IPA" code:errno
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"mkdir failed: %s", strerror(errno)]}];
        return NO;
    }

    const char *src = appBundlePath.path.UTF8String;
    const char *dst = destPath.UTF8String;
    LOG_DEBUG("rename(\"%s\", \"%s\")", src, dst);
    int result = rename(src, dst);
    if (result != 0) {
        LOG_ERROR("rename failed: %s (errno=%d)", strerror(errno), errno);
        if (error) *error = [NSError errorWithDomain:@"IPA" code:errno
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"rename failed: %s", strerror(errno)]}];
        rmdir(destBundle.UTF8String);
        return NO;
    }
    LOG_INFO("Atomic rename succeeded: %s -> %s", src, dst);

    if (outPath) *outPath = destPath;
    return YES;
}

@end
