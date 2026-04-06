#import "CatExplorerAppDelegate.h"
#import "CatExplorerRootViewController.h"

@implementation CatExplorerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    
    // Set RootViewController directly to avoid any UINavigationController overhead/padding
    CatExplorerRootViewController *rootVC = [[CatExplorerRootViewController alloc] init];
    self.window.rootViewController = rootVC;
    
    [self.window makeKeyAndVisible];
    return YES;
}

@end
