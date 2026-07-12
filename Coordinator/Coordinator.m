#import "Coordinator.h"
#import "darksword.h"
#import "sbx.h"
#import "utils.h"
#import "offsets.h"
#import "KRWEngine.h"
#import "choma_helpers.h"
#import "choma_trustcache.h"
#import "KernelPatcher.h"
#import "TrustCacheManager.h"
#import "IPAParser.h"
#import "IPAInstaller.h"
#import "SpringBoardExecutor.h"
#import "Logger.h"

static BOOL offsetsAreValid(void) {
    if (off_inpcb_inp_depend6_inp6_icmp6filt == 0) return NO;
    if (off_socket_so_usecount == 0) return NO;
    if (off_socket_so_proto == 0) return NO;
    if (off_protosw_pr_input == 0) return NO;
    if (off_proc_p_flag == 0) return NO;
    return YES;
}

NSNotificationName const CoordinatorStateChangedNotification = @"CoordinatorStateChangedNotification";

@interface Coordinator ()
@property (nonatomic, strong) dispatch_queue_t pipelineQueue;
@end

@implementation Coordinator

+ (instancetype)shared {
    static Coordinator *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initPrivate];
    });
    return instance;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _state = AppStateIdle;
        _installedApps = [NSMutableArray array];
        _pipelineQueue = dispatch_queue_create("com.trollstore.pipeline", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (instancetype)init { return nil; }

- (BOOL)isProcessing {
    switch (self.state) {
        case AppStateIdle:
        case AppStateSuccess:
        case AppStateError:
            return NO;
        default:
            return YES;
    }
}

- (BOOL)isError {
    return self.state == AppStateError;
}

- (NSString *)stateText {
    switch (self.state) {
        case AppStateIdle: return @"Sẵn sàng";
        case AppStateExploiting: return @"Đang chạy Kernel Exploit...";
        case AppStateExtractingCDHash: return @"Đang phân tích IPA...";
        case AppStateInjectingTrustCache: return @"Đang ghi Trust Cache vào Kernel...";
        case AppStateInstalling: return @"Đang cài đặt IPA...";
        case AppStateRefreshingUI: return @"Đang làm mới SpringBoard...";
        case AppStateSuccess: return @"Cài đặt thành công!";
        case AppStateError: return [NSString stringWithFormat:@"Lỗi: %@", self.logMessage ?: @""];
    }
}

- (void)setState:(AppState)state {
    _state = state;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:CoordinatorStateChangedNotification object:self];
    });
}

- (void)startPipelineWithIPAPath:(NSURL *)ipaPath {
    LOG_INFO("Starting pipeline — IPA: %s", ipaPath.lastPathComponent.UTF8String);

    // Initialize kernel offsets BEFORE anything else
    offsets_init();

    if (!offsetsAreValid()) {
        LOG_ERROR("Kernel offsets are ZERO — aborting pipeline to prevent kernel panic");
        dispatch_async(dispatch_get_main_queue(), ^{
            self.logMessage = @"Kernel offsets not resolved — device not supported or XPF failed. Aborted safely.";
            self.state = AppStateError;
        });
        return;
    }
    LOG_INFO("Kernel offsets validated — icmp6filt=0x%x so_usecount=0x%x so_proto=0x%x pr_input=0x%x p_flag=0x%x",
             off_inpcb_inp_depend6_inp6_icmp6filt, off_socket_so_usecount,
             off_socket_so_proto, off_protosw_pr_input, off_proc_p_flag);

#ifndef __clang_analyzer__
    init_offsets();
#endif

    dispatch_async(self.pipelineQueue, ^{
        // === Step 0: Extract IPA once ===
        NSURL *tmpDir = [NSURL fileURLWithPath:NSTemporaryDirectory()];
        tmpDir = [tmpDir URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        [[NSFileManager defaultManager] createDirectoryAtURL:tmpDir withIntermediateDirectories:YES attributes:nil error:nil];

        NSError *extractError = nil;
        if (![IPAParser unzipIPAAt:ipaPath to:tmpDir error:&extractError]) {
            LOG_ERROR("Unzip failed: %s", extractError.localizedDescription.UTF8String);
            [self failWithMessage:@"Giải nén IPA thất bại"];
            [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
            return;
        }
        LOG_INFO("IPA extracted to: %s", tmpDir.path.UTF8String);

        NSURL *payloadDir = [tmpDir URLByAppendingPathComponent:@"Payload"];
        NSURL *appBundle = [IPAParser findAppBundleInPayload:payloadDir];
        if (!appBundle) {
            LOG_ERROR("No .app bundle in Payload");
            [self failWithMessage:@"Không tìm thấy .app trong IPA"];
            [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
            return;
        }
        LOG_INFO("Found app bundle: %s", appBundle.lastPathComponent.UTF8String);
        NSString *appName = appBundle.lastPathComponent;

        // === Step 1: Exploit ===
        dispatch_async(dispatch_get_main_queue(), ^{ self.state = AppStateExploiting; });

        LOG_DEBUG("Running ds_run()...");
        if (ds_run() != 0) {
            LOG_ERROR("ds_run failed");
            [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
            [self failWithMessage:@"Kernel exploit thất bại"];
            return;
        }
        LOG_INFO("Kernel exploit succeeded — KRW established");

        // === Step 2: Sandbox Escape ===
        LOG_DEBUG("Getting proc_self...");
        uint64_t selfProc = proc_self();
        LOG_DEBUG("proc_self = 0x%llx", selfProc);
        if (sbx_escape(selfProc) != 0) {
            LOG_ERROR("sbx_escape failed");
            [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
            [self failWithMessage:@"Sandbox escape thất bại"];
            return;
        }
        LOG_INFO("Sandbox escaped");

        // === Step 3: P_PLATFORM ===
        LOG_DEBUG("Setting P_PLATFORM...");
        NSError *ppError = nil;
        if (![KernelPatcher setPlatformBinaryWithError:&ppError]) {
            LOG_ERROR("P_PLATFORM failed: %s", ppError.localizedDescription.UTF8String);
            [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
            [self failWithMessage:ppError.localizedDescription ?: @"P_PLATFORM thất bại"];
            return;
        }
        LOG_INFO("P_PLATFORM set on self proc");

        // === Step 4: Extract CDHash ===
        dispatch_async(dispatch_get_main_queue(), ^{ self.state = AppStateExtractingCDHash; });

        LOG_DEBUG("Extracting CDHash from app bundle...");
        NSError *parseError = nil;
        NSData *cdhash = [IPAParser extractCDHashFromAppBundle:appBundle error:&parseError];
        if (!cdhash) {
            LOG_ERROR("CDHash extraction failed: %s", parseError.localizedDescription.UTF8String);
            [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
            [self failWithMessage:parseError.localizedDescription ?: @"CDHash extraction thất bại"];
            return;
        }
        LOG_INFO("CDHash extracted (%d bytes)", (int)cdhash.length);

        // === Step 5: Inject Trust Cache ===
        dispatch_async(dispatch_get_main_queue(), ^{ self.state = AppStateInjectingTrustCache; });

        LOG_DEBUG("Injecting CDHash into kernel trust cache...");
        NSError *tcError = nil;
        if (![TrustCacheManager injectTrustCacheWithCdhash:cdhash error:&tcError]) {
            LOG_ERROR("Trust cache injection failed: %s", tcError.localizedDescription.UTF8String);
            [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
            [self failWithMessage:tcError.localizedDescription ?: @"Trust cache injection thất bại"];
            return;
        }
        LOG_INFO("Trust cache injection done");

        // === Step 6: Install IPA ===
        dispatch_async(dispatch_get_main_queue(), ^{ self.state = AppStateInstalling; });

        LOG_DEBUG("Installing app bundle...");
        NSString *installedPath = nil;
        NSError *installError = nil;
        if (![IPAInstaller installAppBundle:appBundle installedPath:&installedPath error:&installError]) {
            LOG_ERROR("Install failed: %s", installError.localizedDescription.UTF8String);
            [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
            [self failWithMessage:installError.localizedDescription ?: @"Cài đặt thất bại"];
            return;
        }
        LOG_INFO("App installed to: %s", installedPath.UTF8String);

        // Clean up extraction temp — app bundle already renamed to system container
        [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];

        if (appName) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.installedApps insertObject:appName atIndex:0];
            });
        }

        // === Step 7: Refresh icons with exact path ===
        dispatch_async(dispatch_get_main_queue(), ^{ self.state = AppStateRefreshingUI; });

        LOG_DEBUG("Running uicache via SpringBoard RemoteCall...");
        NSError *sbError = nil;
        if (![SpringBoardExecutor refreshIconsForInstalledApp:installedPath error:&sbError]) {
            LOG_ERROR("uicache failed: %s", sbError.localizedDescription.UTF8String);
            [self failWithMessage:sbError.localizedDescription ?: @"Làm mới SpringBoard thất bại"];
            return;
        }
        LOG_INFO("uicache done — pipeline complete");
        dispatch_async(dispatch_get_main_queue(), ^{ self.state = AppStateSuccess; });
    });
}

- (void)failWithMessage:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.logMessage = msg;
        self.state = AppStateError;
    });
}

@end
