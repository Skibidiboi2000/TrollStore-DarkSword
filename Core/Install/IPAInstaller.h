#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IPAInstaller : NSObject
+ (BOOL)installAppBundle:(NSURL *)appBundlePath installedPath:(NSString *_Nonnull*_Nullable)outPath error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
