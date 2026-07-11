#import "KRWEngine.h"
#import "darksword.h"
#import "Logger.h"

@implementation KRWEngine

+ (instancetype)shared {
    static KRWEngine *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (uint64_t)kread64:(uint64_t)addr {
    @try { return ds_kread64(addr); }
    @catch (NSException *e) {
        LOG_ERROR("KRW kread64 exception at 0x%llx: %s", addr, e.reason.UTF8String);
        return 0;
    }
}
- (uint32_t)kread32:(uint64_t)addr {
    @try { return ds_kread32(addr); }
    @catch (NSException *e) {
        LOG_ERROR("KRW kread32 exception at 0x%llx: %s", addr, e.reason.UTF8String);
        return 0;
    }
}
- (void)kwrite64:(uint64_t)addr value:(uint64_t)value {
    @try { ds_kwrite64(addr, value); }
    @catch (NSException *e) {
        LOG_ERROR("KRW kwrite64 exception at 0x%llx: %s", addr, e.reason.UTF8String);
    }
}
- (void)kwrite32:(uint64_t)addr value:(uint32_t)value {
    @try { ds_kwrite32(addr, value); }
    @catch (NSException *e) {
        LOG_ERROR("KRW kwrite32 exception at 0x%llx: %s", addr, e.reason.UTF8String);
    }
}
- (void)kwrite8:(uint64_t)addr value:(uint8_t)value {
    @try { ds_kwrite8(addr, value); }
    @catch (NSException *e) {
        LOG_ERROR("KRW kwrite8 exception at 0x%llx: %s", addr, e.reason.UTF8String);
    }
}

@end
