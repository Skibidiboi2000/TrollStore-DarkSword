#import "AppDelegate.h"
#import "InstallViewController.h"
#import "AppsViewController.h"
#import "SettingsViewController.h"
#import "Logger.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    log_init();
    LOG_INFO("App launched");

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    InstallViewController *installVC = [[InstallViewController alloc] init];
    installVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Install" image:[UIImage systemImageNamed:@"square.and.arrow.down.fill"] tag:0];

    AppsViewController *appsVC = [[AppsViewController alloc] init];
    appsVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Apps" image:[UIImage systemImageNamed:@"square.grid.2x2.fill"] tag:1];

    SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
    settingsVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings" image:[UIImage systemImageNamed:@"gearshape.fill"] tag:2];

    UITabBarController *tabBar = [[UITabBarController alloc] init];
    tabBar.viewControllers = @[appsVC, installVC, settingsVC];

    self.window.rootViewController = tabBar;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
