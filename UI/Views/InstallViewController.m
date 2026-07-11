#import "InstallViewController.h"
#import "Coordinator.h"
#import "Logger.h"

@interface InstallViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UIImageView *statusIcon;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *fileLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIButton *selectButton;
@end

@implementation InstallViewController

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    [self setupUI];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stateChanged)
        name:CoordinatorStateChangedNotification object:nil];
}

- (void)setupUI {
    // Status icon
    self.statusIcon = [[UIImageView alloc] init];
    self.statusIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.statusIcon.tintColor = [UIColor secondaryLabelColor];
    self.statusIcon.image = [UIImage systemImageNamed:@"square.and.arrow.down.on.square"];
    self.statusIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusIcon];

    // Status label
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = [Coordinator shared].stateText;
    self.statusLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];

    // File label
    self.fileLabel = [[UILabel alloc] init];
    self.fileLabel.text = @"Chưa chọn file";
    self.fileLabel.textColor = [UIColor secondaryLabelColor];
    self.fileLabel.textAlignment = NSTextAlignmentCenter;
    self.fileLabel.font = [UIFont systemFontOfSize:15];
    self.fileLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.fileLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.fileLabel];

    // Spinner
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    // Button
    self.selectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.selectButton setTitle:@"Chọn file IPA" forState:UIControlStateNormal];
    self.selectButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    self.selectButton.backgroundColor = [UIColor systemBlueColor];
    [self.selectButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.selectButton.layer.cornerRadius = 12;
    self.selectButton.clipsToBounds = YES;
    [self.selectButton addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.selectButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.selectButton];

    // Auto Layout
    [NSLayoutConstraint activateConstraints:@[
        [self.statusIcon.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.statusIcon.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-80],
        [self.statusIcon.widthAnchor constraintEqualToConstant:80],
        [self.statusIcon.heightAnchor constraintEqualToConstant:80],

        [self.statusLabel.topAnchor constraintEqualToAnchor:self.statusIcon.bottomAnchor constant:16],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.fileLabel.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:8],
        [self.fileLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.fileLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.spinner.topAnchor constraintEqualToAnchor:self.fileLabel.bottomAnchor constant:16],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [self.selectButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-100],
        [self.selectButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.selectButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.selectButton.heightAnchor constraintEqualToConstant:50],
    ]];
}

- (void)buttonTapped {
    LOG_INFO("User tapped 'Select IPA' — presenting document picker");
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[@"public.item"] inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)stateChanged {
    Coordinator *c = [Coordinator shared];
    self.statusLabel.text = c.stateText;

    switch (c.state) {
        case AppStateIdle:
            self.statusIcon.image = [UIImage systemImageNamed:@"square.and.arrow.down.on.square"];
            self.statusIcon.tintColor = [UIColor secondaryLabelColor];
            self.statusLabel.textColor = [UIColor labelColor];
            self.fileLabel.text = @"Chưa chọn file";
            [self.spinner stopAnimating];
            self.selectButton.enabled = YES;
            self.selectButton.backgroundColor = [UIColor systemBlueColor];
            break;
        case AppStateSuccess:
            self.statusIcon.image = [UIImage systemImageNamed:@"checkmark.circle.fill"];
            self.statusIcon.tintColor = [UIColor systemGreenColor];
            self.statusLabel.textColor = [UIColor labelColor];
            [self.spinner stopAnimating];
            self.selectButton.enabled = YES;
            self.selectButton.backgroundColor = [UIColor systemBlueColor];
            break;
        case AppStateError:
            self.statusIcon.image = [UIImage systemImageNamed:@"xmark.octagon.fill"];
            self.statusIcon.tintColor = [UIColor systemRedColor];
            self.statusLabel.textColor = [UIColor systemRedColor];
            [self.spinner stopAnimating];
            self.selectButton.enabled = YES;
            self.selectButton.backgroundColor = [UIColor systemBlueColor];
            break;
        default:
            self.statusIcon.image = [UIImage systemImageNamed:@"gearshape.2.fill"];
            self.statusIcon.tintColor = [UIColor systemBlueColor];
            self.statusLabel.textColor = [UIColor labelColor];
            [self.spinner startAnimating];
            self.selectButton.enabled = NO;
            self.selectButton.backgroundColor = [UIColor grayColor];
            break;
    }
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *fileURL = urls.firstObject;

    // Verify .ipa extension — picker is .item so we check ourselves
    if (![fileURL.pathExtension.lowercaseString isEqualToString:@"ipa"]) {
        self.statusLabel.text = @"Vui lòng chọn file .ipa";
        return;
    }

    LOG_INFO("User picked file: %s", fileURL.lastPathComponent.UTF8String);
    self.fileLabel.text = fileURL.lastPathComponent;
    self.statusLabel.text = @"Đang xử lý...";
    [self.spinner startAnimating];

    // Security-scoped resource handling
    BOOL didStart = [fileURL startAccessingSecurityScopedResource];
    NSURL *tmpDir = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    NSURL *localURL = [tmpDir URLByAppendingPathComponent:fileURL.lastPathComponent];

    NSError *copyError = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:localURL.path]) {
        [[NSFileManager defaultManager] removeItemAtURL:localURL error:nil];
    }
    BOOL copied = [[NSFileManager defaultManager] copyItemAtURL:fileURL toURL:localURL error:&copyError];
    if (didStart) {
        [fileURL stopAccessingSecurityScopedResource];
    }

    if (copied) {
        LOG_INFO("IPA copied to sandbox: %s", localURL.path.UTF8String);
        [[Coordinator shared] startPipelineWithIPAPath:localURL];
    } else {
        LOG_ERROR("'Copy to sandbox failed: %s — falling back to original URL", copyError.localizedDescription.UTF8String);
        [[Coordinator shared] startPipelineWithIPAPath:fileURL];
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    LOG_INFO("User cancelled file picker");
    self.statusLabel.text = @"Đã hủy chọn file";
}

@end
