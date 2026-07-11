#import "KernelPatcher.h"
#import "KRWEngine.h"
#import "offsets.h"
#import "utils.h"
#import "Logger.h"

@implementation KernelPatcher

+ (BOOL)setPlatformBinaryWithError:(NSError **)error {
    uint64_t pFlagOffset = off_proc_p_flag;
    uint64_t selfProc = proc_self();
    uint64_t pFlagAddr = selfProc + pFlagOffset;

    LOG_DEBUG("P_PLATFORM: proc=0x%llx offset=%llx addr=0x%llx", selfProc, pFlagOffset, pFlagAddr);

    uint32_t flags = [[KRWEngine shared] kread32:pFlagAddr];
    LOG_DEBUG("Old p_flag = 0x%08x", flags);
    flags |= 0x80000000; // P_PLATFORM
    [[KRWEngine shared] kwrite32:pFlagAddr value:flags];
    LOG_INFO("P_PLATFORM set (new flags = 0x%08x)", flags);

    return YES;
}

@end
