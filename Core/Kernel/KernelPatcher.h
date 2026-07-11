#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KernelPatcher : NSObject
+ (BOOL)setPlatformBinaryWithError:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
