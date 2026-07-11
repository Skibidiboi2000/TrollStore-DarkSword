#import "SpringBoardExecutor.h"
#import "RemoteCall.h"
#import "RemoteSystem.h"
#import "Logger.h"

@implementation SpringBoardExecutor

+ (BOOL)refreshIconsWithError:(NSError **)error {
    LOG_DEBUG("Initializing RemoteCall to SpringBoard...");
    RemoteCall *rc = [[RemoteCall alloc] initWithProcess:@"SpringBoard" useMigFilterBypass:YES];
    if (!rc) {
        LOG_ERROR("'RemoteCall init failed");
        if (error) *error = [NSError errorWithDomain:@"SB" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"RemoteCall init failed"}];
        return NO;
    }
    LOG_DEBUG("'RemoteCall created, running uicache...");

    int result = rc_run_system(rc, "/usr/bin/uicache -p /var/containers/Bundle/Application/");
    if (result != 0) {
        LOG_ERROR("uicache via RemoteCall returned %d", result);
        if (error) *error = [NSError errorWithDomain:@"SB" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"uicache via RemoteCall failed"}];
        return NO;
    }
    LOG_INFO("uicache completed successfully");
    return YES;
}

@end
