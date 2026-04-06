#import "CatExplorerRootViewController.h"
#import <WebKit/WebKit.h>

@interface CatExplorerRootViewController () <WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIView *statusBarBackgroundView;
@property (nonatomic, strong) NSString *baseDomain;
@end

@implementation CatExplorerRootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.edgesForExtendedLayout = UIRectEdgeAll;
    
    [self setupStatusBarView];
    [self setupWebView];
    [self loadURLFromConfig];
}

- (void)setupStatusBarView {
    CGFloat statusBarHeight = 0;
    if (@available(iOS 13.0, *)) {
        UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
        statusBarHeight = window.windowScene.statusBarManager.statusBarFrame.size.height;
    } else {
        statusBarHeight = UIApplication.sharedApplication.statusBarFrame.size.height;
    }
    
    self.statusBarBackgroundView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, statusBarHeight)];
    self.statusBarBackgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.statusBarBackgroundView.backgroundColor = [UIColor clearColor];
    self.statusBarBackgroundView.userInteractionEnabled = NO;
    [self.view addSubview:self.statusBarBackgroundView];
}

- (void)setupWebView {
    WKUserContentController *userContentController = [[WKUserContentController alloc] init];
    [userContentController addScriptMessageHandler:self name:@"colorUpdate"];
    
    NSString *jsSource = @"(function() {"
    "  function updateColor() {"
    "    var color = '';"
    "    var meta = document.querySelector('meta[name=\"theme-color\"]');"
    "    if (meta) { color = meta.content; }"
    "    else { color = window.getComputedStyle(document.body).backgroundColor; }"
    "    window.webkit.messageHandlers.colorUpdate.postMessage(color);"
    "  }"
    "  var observer = new MutationObserver(updateColor);"
    "  observer.observe(document.head, { childList: true, subtree: true, attributes: true });"
    "  window.addEventListener('load', updateColor);"
    "  updateColor();"
    "})();";
    
    WKUserScript *script = [[WKUserScript alloc] initWithSource:jsSource injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
    [userContentController addUserScript:script];
    
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.userContentController = userContentController;
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.webView.allowsBackForwardNavigationGestures = YES;
    
    [self.view insertSubview:self.webView belowSubview:self.statusBarBackgroundView];
}

- (void)loadURLFromConfig {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"config" ofType:@"json"];
    if (path) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *urlString = json[@"url"];
        if (urlString) {
            NSURL *url = [NSURL URLWithString:urlString];
            self.baseDomain = url.host;
            [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
        }
    }
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    
    // 1. Handle non-http(s) schemes (mailto, tel, etc.)
    if (![url.scheme isEqualToString:@"http"] && ![url.scheme isEqualToString:@"https"]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    // 2. Check for common download extensions
    NSArray *downloadExtensions = @[@"zip", @"pdf", @"rar", @"dmg", @"ipa", @"deb", @"exe"];
    if ([downloadExtensions containsObject:url.pathExtension.lowercaseString]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    // 3. Handle external domains
    if (self.baseDomain && url.host && ![url.host containsString:self.baseDomain]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    decisionHandler(WKNavigationActionPolicyAllow);
}

#pragma mark - WKUIDelegate

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
    // If target="_blank", it will trigger this. Check domain here too.
    NSURL *url = navigationAction.request.URL;
    if (self.baseDomain && url.host && ![url.host containsString:self.baseDomain]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } else {
        [webView loadRequest:navigationAction.request];
    }
    return nil;
}

#pragma mark - Status Bar & Colors

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"colorUpdate"]) {
        UIColor *color = [self colorFromHexString:(NSString *)message.body];
        if (color) {
            [UIView animateWithDuration:0.3 animations:^{
                self.statusBarBackgroundView.backgroundColor = color;
            }];
            [self setNeedsStatusBarAppearanceUpdate];
        }
    }
}

- (UIColor *)colorFromHexString:(NSString *)hexString {
    if ([hexString hasPrefix:@"rgb"]) {
        NSScanner *scanner = [NSScanner scannerWithString:hexString];
        [scanner setCharactersToBeSkipped:[NSCharacterSet characterSetWithCharactersInString:@"rgba(), "]];
        int r, g, b; [scanner scanInt:&r]; [scanner scanInt:&g]; [scanner scanInt:&b];
        return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
    }
    unsigned rgbValue = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hexString];
    if ([hexString hasPrefix:@"#"]) [scanner setScanLocation:1];
    [scanner scanHexInt:&rgbValue];
    return [UIColor colorWithRed:((rgbValue & 0xFF0000) >> 16)/255.0 green:((rgbValue & 0xFF00) >> 8)/255.0 blue:(rgbValue & 0xFF)/255.0 alpha:1.0];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    CGFloat r, g, b, a;
    [self.statusBarBackgroundView.backgroundColor getRed:&r green:&g blue:&b alpha:&a];
    double brightness = (r * 299 + g * 587 + b * 114) / 1000;
    return (brightness < 0.5) ? UIStatusBarStyleLightContent : UIStatusBarStyleDefault;
}

- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (BOOL)prefersStatusBarHidden { return NO; }

@end
