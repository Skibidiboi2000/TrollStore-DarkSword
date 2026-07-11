#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KRWEngine : NSObject
+ (instancetype)shared;
- (uint64_t)kread64:(uint64_t)addr;
- (uint32_t)kread32:(uint64_t)addr;
- (void)kwrite64:(uint64_t)addr value:(uint64_t)value;
- (void)kwrite32:(uint64_t)addr value:(uint32_t)value;
- (void)kwrite8:(uint64_t)addr value:(uint8_t)value;
@end

NS_ASSUME_NONNULL_END
