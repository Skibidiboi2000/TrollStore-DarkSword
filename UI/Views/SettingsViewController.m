#import "SettingsViewController.h"
#import "Coordinator.h"

@interface SettingsViewController ()
@property (nonatomic, strong) UISwitch *persistenceSwitch;
@end

@implementation SettingsViewController

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Cài đặt";
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload)
        name:CoordinatorStateChangedNotification object:nil];

    self.persistenceSwitch = [[UISwitch alloc] init];
    self.persistenceSwitch.on = YES;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2; // iOS version, device
        case 1: return 1; // persistence toggle
        case 2: return 1; // kernel state
        case 3: return 1; // version
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"Hệ thống";
        case 1: return @"Tùy chọn";
        case 2: return @"Exploit";
        case 3: return @"Giới thiệu";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) return @"Bảo lưu quyền root sau khi reboot (yêu cầu exploit lại)";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"cell"];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Phiên bản iOS";
            cell.detailTextLabel.text = [[UIDevice currentDevice] systemVersion];
        } else {
            cell.textLabel.text = @"Thiết bị";
            cell.detailTextLabel.text = [[UIDevice currentDevice] model];
        }
    } else if (indexPath.section == 1) {
        cell.textLabel.text = @"Persistence (Beta)";
        cell.accessoryView = self.persistenceSwitch;
    } else if (indexPath.section == 2) {
        cell.textLabel.text = @"Trạng thái Kernel";
        Coordinator *c = [Coordinator shared];
        if (c.state == AppStateError) {
            cell.detailTextLabel.text = @"Lỗi";
            cell.detailTextLabel.textColor = [UIColor systemRedColor];
        } else if (c.state == AppStateIdle) {
            cell.detailTextLabel.text = @"Chưa kích hoạt";
            cell.detailTextLabel.textColor = [UIColor systemRedColor];
        } else {
            cell.detailTextLabel.text = @"Đã KRW";
            cell.detailTextLabel.textColor = [UIColor systemGreenColor];
        }
    } else if (indexPath.section == 3) {
        cell.textLabel.text = @"Phiên bản";
        cell.detailTextLabel.text = @"1.0.0 (DarkSword)";
    }

    return cell;
}

- (void)reload {
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationNone];
}

@end
