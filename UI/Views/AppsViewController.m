#import "AppsViewController.h"
#import "Coordinator.h"

@interface AppsViewController ()
@property (nonatomic, strong) NSMutableArray<NSString *> *apps;
@end

@implementation AppsViewController

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Ứng dụng";
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadApps)
        name:CoordinatorStateChangedNotification object:nil];
    self.apps = [Coordinator shared].installedApps;
}

- (void)reloadApps {
    self.apps = [Coordinator shared].installedApps;
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.apps.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];

    if (self.apps.count == 0) {
        cell.textLabel.text = @"Chưa có ứng dụng nào";
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.imageView.image = nil;
        return cell;
    }

    NSString *appName = self.apps[indexPath.row];
    cell.textLabel.text = appName;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.textLabel.textAlignment = NSTextAlignmentNatural;
    cell.imageView.image = [UIImage systemImageNamed:@"app.fill"];
    cell.imageView.tintColor = [UIColor grayColor];
    return cell;
}

@end
