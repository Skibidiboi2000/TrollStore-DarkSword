#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IPAInstaller : NSObject
+ (BOOL)installIPAPath:(NSURL *)ipaPath error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
