#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, AppState) {
    AppStateIdle,
    AppStateExploiting,
    AppStateExtractingCDHash,
    AppStateInjectingTrustCache,
    AppStateInstalling,
    AppStateRefreshingUI,
    AppStateSuccess,
    AppStateError
};

extern NSNotificationName const CoordinatorStateChangedNotification;

@interface Coordinator : NSObject
@property (nonatomic, assign) AppState state;
@property (nonatomic, strong) NSString *logMessage;
@property (nonatomic, strong) NSMutableArray<NSString *> *installedApps;

+ (instancetype)shared;
- (BOOL)isProcessing;
- (BOOL)isError;
- (NSString *)stateText;
- (void)startPipelineWithIPAPath:(NSURL *)ipaPath;
@end
