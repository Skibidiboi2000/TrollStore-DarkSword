#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IPAParser : NSObject
+ (BOOL)unzipIPAAt:(NSURL *)source to:(NSURL *)dest error:(NSError **)error;
+ (NSURL *)findAppBundleInPayload:(NSURL *)payloadDir;
+ (nullable NSData *)extractCDHashFromAppBundle:(NSURL *)appBundlePath error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
