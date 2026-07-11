#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ChoMAWrapper : NSObject
+ (nullable NSData *)extractCDHash:(NSString *)machOPath;
@end

NS_ASSUME_NONNULL_END
