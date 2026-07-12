#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SpringBoardExecutor : NSObject
+ (BOOL)refreshIconsForInstalledApp:(NSString *)appBundlePath error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
