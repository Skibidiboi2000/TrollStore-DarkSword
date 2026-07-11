#import "SandboxEscape.h"
#import "sbx.h"
#import "utils.h"
#import "Logger.h"

@implementation SandboxEscape

+ (BOOL)clearWithError:(NSError **)error {
    LOG_DEBUG("Clearing sandbox...");
    uint64_t selfProc = proc_self();
    int result = sbx_escape(selfProc);
    if (result != 0) {
        LOG_ERROR("sbx_escape returned %d", result);
        if (error) {
            *error = [NSError errorWithDomain:@"SandboxEscape" code:result
                userInfo:@{NSLocalizedDescriptionKey: @"Sandbox escape failed"}];
        }
        return NO;
    }
    LOG_INFO("Sandbox cleared");
    return YES;
}

@end
