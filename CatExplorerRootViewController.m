#import "CatExplorerRootViewController.h"
#import <WebKit/WebKit.h>

@interface CatExplorerRootViewController () <WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIView *statusBarBackgroundView;
@property (nonatomic, strong) NSString *baseDomain;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, assign) BOOL pullToRefreshEnabled;
@property (nonatomic, assign) BOOL externalNavigationInDefaultBrowser;
@property (nonatomic, strong) NSDictionary *customHeaders;
@property (nonatomic, assign) CGFloat statusBarHeight;
@property (nonatomic, strong) NSArray *scriptEntries; // Pre-loaded from scripts.json
@end

@implementation CatExplorerRootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    
    // Use the full screen including notch areas
    self.edgesForExtendedLayout = UIRectEdgeAll;
    
    [self loadConfigAndSetup];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    // Ensure the webView and status bar always fill the current view bounds exactly
    self.webView.frame = self.view.bounds;
    
    CGRect statusBarFrame = self.statusBarBackgroundView.frame;
    statusBarFrame.size.width = self.view.bounds.size.width;
    statusBarFrame.size.height = self.statusBarHeight;
    self.statusBarBackgroundView.frame = statusBarFrame;
    
    // Push page content below the status bar so it isn't hidden behind the overlay
    self.webView.scrollView.contentInset = UIEdgeInsetsMake(self.statusBarHeight, 0, 0, 0);
    self.webView.scrollView.scrollIndicatorInsets = UIEdgeInsetsMake(self.statusBarHeight, 0, 0, 0);
}

- (void)loadConfigAndSetup {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"config" ofType:@"json"];
    NSDictionary *json = @{};
    if (path) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    }
    
    NSString *urlString = json[@"url"] ?: @"https://www.google.com";
    self.pullToRefreshEnabled = json[@"pullToRefresh"] ? [json[@"pullToRefresh"] boolValue] : YES;
    self.externalNavigationInDefaultBrowser = json[@"external_navigation_in_default_browser"] ? [json[@"external_navigation_in_default_browser"] boolValue] : YES;
    self.customHeaders = json[@"headers"] ?: @{};
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSString *host = url.host.lowercaseString;
    if ([host hasPrefix:@"www."]) {
        self.baseDomain = [host substringFromIndex:4];
    } else {
        self.baseDomain = host;
    }
    
    [self loadScriptEntries];
    [self setupStatusBarView];
    [self setupWebViewWithJSON:json];
    
    if (self.pullToRefreshEnabled) {
        [self setupRefreshControl];
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [self.customHeaders enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [request setValue:obj forHTTPHeaderField:key];
    }];
    
    [self.webView loadRequest:request];
}

#pragma mark - Script Loading (site-conditional)

- (void)loadScriptEntries {
    // scripts.json is generated at build time by gen_scripts.sh
    // Format: [{"file":"js/domain/mode/name.js","domain":"domain","mode":"strict|wildcard"}, ...]
    NSString *path = [[NSBundle mainBundle] pathForResource:@"scripts" ofType:@"json"];
    if (!path) {
        self.scriptEntries = @[];
        return;
    }
    
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSArray *entries = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![entries isKindOfClass:[NSArray class]]) {
        self.scriptEntries = @[];
        return;
    }
    
    // Pre-load all JS source code into memory so we don't hit disk on every navigation
    NSMutableArray *loaded = [NSMutableArray array];
    NSString *bundlePath = [NSBundle mainBundle].bundlePath;
    
    for (NSDictionary *entry in entries) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        
        NSString *relPath = entry[@"file"];
        NSString *domain  = entry[@"domain"];
        NSString *mode    = entry[@"mode"];
        if (!relPath || !domain || !mode) continue;
        
        NSString *fullPath = [bundlePath stringByAppendingPathComponent:relPath];
        NSString *source = [NSString stringWithContentsOfFile:fullPath encoding:NSUTF8StringEncoding error:nil];
        if (source.length > 0) {
            [loaded addObject:@{
                @"domain": domain,
                @"mode":   mode,
                @"source": source,
                @"name":   relPath.lastPathComponent
            }];
            NSLog(@"[CatExplorer] Loaded script: %@ (%@ / %@)", relPath.lastPathComponent, domain, mode);
        } else {
            NSLog(@"[CatExplorer] Warning: could not read script at '%@'", relPath);
        }
    }
    
    self.scriptEntries = loaded;
    NSLog(@"[CatExplorer] %lu site-conditional script(s) ready", (unsigned long)loaded.count);
}

- (void)injectScriptsForURL:(NSURL *)url inWebView:(WKWebView *)webView {
    NSString *host = url.host.lowercaseString;
    if (!host) return;
    
    for (NSDictionary *entry in self.scriptEntries) {
        NSString *domain = entry[@"domain"];
        NSString *mode   = entry[@"mode"];
        BOOL match = NO;
        
        if ([mode isEqualToString:@"all"]) {
            // Global scripts — always inject
            match = YES;
        } else if ([mode isEqualToString:@"strict"]) {
            // Exact match: host must be the domain or www.<domain>
            match = [host isEqualToString:domain] ||
                    [host isEqualToString:[@"www." stringByAppendingString:domain]];
        } else if ([mode isEqualToString:@"wildcard"]) {
            // Wildcard: host is the domain itself or any subdomain (*.domain)
            match = [host isEqualToString:domain] ||
                    [host hasSuffix:[@"." stringByAppendingString:domain]];
        }
        
        if (match) {
            [webView evaluateJavaScript:entry[@"source"] completionHandler:^(id result, NSError *error) {
                if (error) {
                    NSLog(@"[CatExplorer] Script '%@' error on %@: %@", entry[@"name"], host, error.localizedDescription);
                }
            }];
        }
    }
}

- (void)setupStatusBarView {
    CGFloat statusBarHeight = 0;
    if (@available(iOS 13.0, *)) {
        UIWindowScene *windowScene = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                windowScene = (UIWindowScene *)scene;
                break;
            }
        }
        if (!windowScene) {
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    windowScene = (UIWindowScene *)scene;
                    break;
                }
            }
        }
        if (windowScene) {
            statusBarHeight = windowScene.statusBarManager.statusBarFrame.size.height;
        }
    } else {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        statusBarHeight = UIApplication.sharedApplication.statusBarFrame.size.height;
        #pragma clang diagnostic pop
    }
    if (statusBarHeight <= 0) statusBarHeight = 20;
    self.statusBarHeight = statusBarHeight;

    self.statusBarBackgroundView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, statusBarHeight)];
    self.statusBarBackgroundView.backgroundColor = [UIColor clearColor];
    self.statusBarBackgroundView.userInteractionEnabled = NO;
    [self.view addSubview:self.statusBarBackgroundView];
}

- (void)setupWebViewWithJSON:(NSDictionary *)json {
    WKUserContentController *userContentController = [[WKUserContentController alloc] init];
    [userContentController addScriptMessageHandler:self name:@"colorUpdate"];
    
    // Built-in: theme-color observer for status bar tinting
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
    
    // Use view.bounds and handle resizing in viewDidLayoutSubviews
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    
    NSString *customUA = json[@"userAgent"];
    if (customUA && customUA.length > 0) {
        self.webView.customUserAgent = customUA;
    }
    
    // Crucial for true full-screen (covers notch/home bar)
    self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.webView.allowsBackForwardNavigationGestures = YES;
    
    [self.view insertSubview:self.webView belowSubview:self.statusBarBackgroundView];
}

- (void)setupRefreshControl {
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(handleRefresh:) forControlEvents:UIControlEventValueChanged];
    self.webView.scrollView.refreshControl = self.refreshControl;
    self.webView.scrollView.alwaysBounceVertical = YES;
}

- (void)handleRefresh:(UIRefreshControl *)refreshControl {
    [self.webView reload];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (self.pullToRefreshEnabled) {
        [self.refreshControl endRefreshing];
    }
    
    // Inject site-conditional scripts after each page load
    [self injectScriptsForURL:webView.URL inWebView:webView];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (self.pullToRefreshEnabled) {
        [self.refreshControl endRefreshing];
    }
    if (error.code == NSURLErrorCancelled) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Load Error" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Retry" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self.webView reload];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    BOOL isUserClick = (navigationAction.navigationType == WKNavigationTypeLinkActivated);
    
    // Non-HTTP schemes (app links like youtube://, tel:, mailto:, etc.)
    // Only open externally if the user explicitly tapped a link — never for
    // embedded resources, redirects, or programmatic navigations.
    if (![url.scheme isEqualToString:@"http"] && ![url.scheme isEqualToString:@"https"]) {
        if (isUserClick) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    
    // Apply custom headers where possible
    if ([navigationAction.request isKindOfClass:[NSMutableURLRequest class]]) {
        NSMutableURLRequest *request = (NSMutableURLRequest *)navigationAction.request;
        [self.customHeaders enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            if (![request valueForHTTPHeaderField:key]) {
                [request setValue:obj forHTTPHeaderField:key];
            }
        }];
    }

    // Download-type extensions — only intercept user-initiated clicks
    if (isUserClick) {
        NSArray *downloadExtensions = @[@"zip", @"pdf", @"rar", @"dmg", @"ipa", @"deb", @"exe"];
        if ([downloadExtensions containsObject:url.pathExtension.lowercaseString]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            decisionHandler(WKNavigationActionPolicyCancel);
            return;
        }
    }

    // External domain gate — ONLY for user-initiated link taps.
    // Embedded iframes, sub-resources, JS redirects, video embeds, etc. from
    // external domains are allowed to load normally inside the webview.
    if (isUserClick && self.baseDomain && url.host && self.externalNavigationInDefaultBrowser) {
        NSString *targetHost = url.host.lowercaseString;
        if ([targetHost rangeOfString:self.baseDomain options:NSCaseInsensitiveSearch].location == NSNotFound) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            decisionHandler(WKNavigationActionPolicyCancel);
            return;
        }
    }

    decisionHandler(WKNavigationActionPolicyAllow);
}

#pragma mark - WKUIDelegate

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
    // target=_blank links — always user-initiated
    NSURL *url = navigationAction.request.URL;
    if (self.externalNavigationInDefaultBrowser && self.baseDomain && url.host && [url.host.lowercaseString rangeOfString:self.baseDomain options:NSCaseInsensitiveSearch].location == NSNotFound) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } else {
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        [self.customHeaders enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            [request setValue:obj forHTTPHeaderField:key];
        }];
        [webView loadRequest:request];
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
