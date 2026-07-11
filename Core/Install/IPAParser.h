#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IPAParser : NSObject
+ (NSData *)extractCDHashFromIPAAt:(NSURL *)ipaPath error:(NSError **)error;
+ (BOOL)unzipIPAAt:(NSURL *)source to:(NSURL *)dest error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
