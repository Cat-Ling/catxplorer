#import "CatExplorerAppDelegate.h"
#import "CatExplorerRootViewController.h"

@implementation CatExplorerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    
    CatExplorerRootViewController *rootVC = [[CatExplorerRootViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:rootVC];
    
    // Completely hide navigation bar and toolbar for the shell app
    nav.navigationBarHidden = YES;
    nav.toolbarHidden = YES;
    
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
