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
    return ds_kread64(addr);
}
- (uint32_t)kread32:(uint64_t)addr {
    return ds_kread32(addr);
}
- (void)kwrite64:(uint64_t)addr value:(uint64_t)value {
    ds_kwrite64(addr, value);
}
- (void)kwrite32:(uint64_t)addr value:(uint32_t)value {
    ds_kwrite32(addr, value);
}
- (void)kwrite8:(uint64_t)addr value:(uint8_t)value {
    ds_kwrite8(addr, value);
}

@end
