#import "SpringBoardExecutor.h"
#import "RemoteCall.h"
#import "RemoteSystem.h"
#import "Logger.h"

@implementation SpringBoardExecutor

+ (BOOL)refreshIconsForInstalledApp:(NSString *)appBundlePath error:(NSError **)error {
    LOG_DEBUG("Initializing RemoteCall to SpringBoard...");
    RemoteCall *rc = [[RemoteCall alloc] initWithProcess:@"SpringBoard" useMigFilterBypass:YES];
    if (!rc) {
        LOG_ERROR("RemoteCall init failed");
        if (error) *error = [NSError errorWithDomain:@"SB" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"RemoteCall init failed"}];
        return NO;
    }
    LOG_DEBUG("RemoteCall created, running uicache for: %s", appBundlePath.UTF8String);

    // Escape single quotes to prevent shell injection from malicious filename
    NSString *escapedPath = [appBundlePath stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    NSString *cmd = [NSString stringWithFormat:@"/usr/bin/uicache -p '%@'", escapedPath];
    int result = rc_run_system(rc, cmd.UTF8String);
    if (result != 0) {
        LOG_ERROR("uicache returned %d", result);
        if (error) *error = [NSError errorWithDomain:@"SB" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"uicache failed"}];
        return NO;
    }
    LOG_INFO("uicache completed successfully");
    return YES;
}

@end
