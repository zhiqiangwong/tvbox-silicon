#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>

#if HAS_QUICKJS
#include "quickjs.h"
#endif

#if HAS_FFMPEG
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#endif

#if HAS_APPLE_PYTHON
extern char *TVPythonRequest(const char *resources, const char *request);
#endif

#if HAS_APPLE_JVM
#include <jni.h>
extern char *TVAppleRuntimeRequest(const char *resourcePath, const char *requestJSON);
#endif

typedef int (*NodeStartFunc)(int argc, char *argv[]);

@interface TestEntryViewController : UIViewController
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UITextView *logTextView;
@property(nonatomic, strong) UIButton *runButton;
@property(nonatomic, strong) UIButton *exportButton;
@property(nonatomic, copy) NSString *latestReportJSON;
@end

@implementation TestEntryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:1.0];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.text = @"映匣 iOS 16 独立运行库验证入口";
    self.titleLabel.textColor = UIColor.whiteColor;
    self.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.numberOfLines = 0;
    [self.view addSubview:self.titleLabel];

    self.logTextView = [[UITextView alloc] init];
    self.logTextView.translatesAutoresizingMaskIntoConstraints = NO;
    self.logTextView.backgroundColor = [UIColor colorWithRed:0.12 green:0.14 blue:0.18 alpha:1.0];
    self.logTextView.textColor = [UIColor colorWithRed:0.85 green:0.90 blue:0.95 alpha:1.0];
    self.logTextView.font = [UIFont fontWithName:@"Menlo" size:12] ?: [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.logTextView.editable = NO;
    self.logTextView.layer.cornerRadius = 10;
    self.logTextView.clipsToBounds = YES;
    [self.view addSubview:self.logTextView];

    self.runButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.runButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.runButton setTitle:@"重新执行真实自检" forState:UIControlStateNormal];
    self.runButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.runButton.backgroundColor = [UIColor colorWithRed:0.20 green:0.45 blue:0.90 alpha:1.0];
    [self.runButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.runButton.layer.cornerRadius = 8;
    [self.runButton addTarget:self action:@selector(startDiagnostics) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.runButton];

    self.exportButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.exportButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.exportButton setTitle:@"复制 JSON 报告" forState:UIControlStateNormal];
    self.exportButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.exportButton.backgroundColor = [UIColor colorWithRed:0.18 green:0.55 blue:0.34 alpha:1.0];
    [self.exportButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.exportButton.layer.cornerRadius = 8;
    [self.exportButton addTarget:self action:@selector(copyReport) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.exportButton];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.topAnchor constraintEqualToAnchor:guide.topAnchor constant:16],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:20],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-20],

        [self.logTextView.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:14],
        [self.logTextView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:20],
        [self.logTextView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-20],
        [self.logTextView.bottomAnchor constraintEqualToAnchor:self.runButton.topAnchor constant:-14],

        [self.runButton.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:20],
        [self.runButton.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-16],
        [self.runButton.heightAnchor constraintEqualToConstant:46],

        [self.exportButton.leadingAnchor constraintEqualToAnchor:self.runButton.trailingAnchor constant:12],
        [self.exportButton.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-20],
        [self.exportButton.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-16],
        [self.exportButton.heightAnchor constraintEqualToConstant:46],
        [self.exportButton.widthAnchor constraintEqualToAnchor:self.runButton.widthAnchor]
    ]];

    [self startDiagnostics];
}

- (void)copyReport {
    if (self.latestReportJSON.length > 0) {
        UIPasteboard.generalPasteboard.string = self.latestReportJSON;
        [self.exportButton setTitle:@"已复制到剪贴板" forState:UIControlStateNormal];
    }
}

- (void)startDiagnostics {
    self.logTextView.text = @"正在后台线程执行真实运行库自检...\n";
    self.runButton.enabled = NO;
    NSThread *worker = [[NSThread alloc] initWithTarget:self selector:@selector(runDiagnosticsWorker) object:nil];
    worker.stackSize = 8 * 1024 * 1024;
    [worker start];
}

- (NSDictionary *)probeQuickJS {
#if HAS_QUICKJS
    JSRuntime *rt = JS_NewRuntime();
    if (!rt) return @{@"status": @"failed", @"detail": @"JS_NewRuntime returned NULL"};
    JSContext *ctx = JS_NewContext(rt);
    if (!ctx) {
        JS_FreeRuntime(rt);
        return @{@"status": @"failed", @"detail": @"JS_NewContext returned NULL"};
    }
    const char *script = "JSON.stringify({engine:'QuickJS', sum: 16 + 26, ok: true})";
    JSValue val = JS_Eval(ctx, script, strlen(script), "<probe>", JS_EVAL_TYPE_GLOBAL);
    const char *cstr = JS_ToCString(ctx, val);
    NSString *output = cstr ? @(cstr) : @"<null>";
    if (cstr) JS_FreeCString(ctx, cstr);
    JS_FreeValue(ctx, val);
    JS_FreeContext(ctx);
    JS_FreeRuntime(rt);
    BOOL ok = [output containsString:@"\"sum\":42"];
    return @{@"status": ok ? @"passed" : @"failed", @"output": output};
#else
    return @{@"status": @"not_compiled", @"detail": @"Built without HAS_QUICKJS"};
#endif
}

- (NSDictionary *)probeFFmpeg {
#if HAS_FFMPEG
    unsigned avfVer = avformat_version();
    unsigned avcVer = avcodec_version();
    unsigned avuVer = avutil_version();
    const AVInputFormat *mkv = av_find_input_format("matroska");
    const AVInputFormat *hls = av_find_input_format("hls");
    const AVCodec *h264 = avcodec_find_decoder(AV_CODEC_ID_H264);
    const AVCodec *hevc = avcodec_find_decoder(AV_CODEC_ID_HEVC);
    BOOL ok = (mkv != NULL && h264 != NULL && hevc != NULL);
    return @{
        @"status": ok ? @"passed" : @"failed",
        @"avformatVersion": @(avfVer),
        @"avcodecVersion": @(avcVer),
        @"avutilVersion": @(avuVer),
        @"matroskaDemuxer": @(mkv != NULL),
        @"hlsDemuxer": @(hls != NULL),
        @"h264Decoder": @(h264 != NULL),
        @"hevcDecoder": @(hevc != NULL)
    };
#else
    return @{@"status": @"not_compiled", @"detail": @"Built without HAS_FFMPEG"};
#endif
}

- (NSDictionary *)probeNodeMobile:(NSString *)bundlePath {
    NSString *fwPath = [bundlePath stringByAppendingPathComponent:@"Frameworks/NodeMobile.framework/NodeMobile"];
    if (![NSFileManager.defaultManager fileExistsAtPath:fwPath]) {
        return @{@"status": @"not_bundled", @"detail": @"Frameworks/NodeMobile.framework not present in this build"};
    }
    void *handle = dlopen(fwPath.UTF8String, RTLD_NOW);
    if (!handle) {
        const char *err = dlerror();
        return @{@"status": @"failed", @"detail": err ? @(err) : @"dlopen failed"};
    }
    NodeStartFunc nodeStart = (NodeStartFunc)dlsym(handle, "node_start");
    if (!nodeStart) {
        return @{@"status": @"failed", @"detail": @"dlsym(node_start) missing"};
    }
    static dispatch_once_t nodeOnce;
    static NSDictionary *cachedNodeResult = nil;
    dispatch_once(&nodeOnce, ^{
        NSString *cacheDir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        NSString *outFile = [cacheDir stringByAppendingPathComponent:@"node-probe-out.json"];
        [NSFileManager.defaultManager removeItemAtPath:outFile error:NULL];
        NSString *jsCode = [NSString stringWithFormat:
            @"const fs = require('fs'), crypto = require('crypto'), https = require('https');"
            @"const hash = crypto.createHash('sha256').update('ios16-node').digest('hex').slice(0, 16);"
            @"fs.writeFileSync(%@, JSON.stringify({nodeVersion: process.version, arch: process.arch, platform: process.platform, sha256Prefix: hash}));",
            [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:@[outFile] options:0 error:NULL] encoding:NSUTF8StringEncoding]];
        // Strip array brackets around outFile JSON string
        NSString *escapedOutPath = [jsCode substringWithRange:NSMakeRange(0, jsCode.length)];
        jsCode = [NSString stringWithFormat:
            @"const fs = require('fs'), crypto = require('crypto');"
            @"const p = %@[0];"
            @"const hash = crypto.createHash('sha256').update('ios16-node').digest('hex').slice(0, 16);"
            @"fs.writeFileSync(p, JSON.stringify({nodeVersion: process.version, arch: process.arch, platform: process.platform, sha256Prefix: hash}));",
            [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:@[outFile] options:0 error:NULL] encoding:NSUTF8StringEncoding]];
        NSArray<NSString *> *args = @[@"node", @"-e", jsCode];
        size_t totalBytes = 0;
        for (NSString *s in args) totalBytes += strlen(s.UTF8String) + 1;
        char *contiguous = calloc(totalBytes, 1);
        char **argv = calloc(args.count + 1, sizeof(char *));
        size_t offset = 0;
        for (NSUInteger i = 0; i < args.count; i++) {
            const char *utf8 = args[i].UTF8String;
            size_t len = strlen(utf8) + 1;
            memcpy(contiguous + offset, utf8, len);
            argv[i] = contiguous + offset;
            offset += len;
        }
        argv[args.count] = NULL;
        int rc = nodeStart((int)args.count, argv);
        NSData *data = [NSData dataWithContentsOfFile:outFile];
        NSDictionary *parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        if (rc == 0 && parsed) {
            cachedNodeResult = @{@"status": @"passed", @"exitCode": @(rc), @"result": parsed};
        } else {
            cachedNodeResult = @{@"status": @"failed", @"exitCode": @(rc)};
        }
    });
    return cachedNodeResult ?: @{@"status": @"failed", @"detail": @"Node did not produce output"};
}

- (NSDictionary *)probePython:(NSString *)bundlePath {
    NSString *fwPath = [bundlePath stringByAppendingPathComponent:@"Frameworks/Python.framework/Python"];
    if (![NSFileManager.defaultManager fileExistsAtPath:fwPath]) {
        return @{@"status": @"not_bundled", @"detail": @"Frameworks/Python.framework not present in this build"};
    }
#if HAS_APPLE_PYTHON
    char *raw = TVPythonRequest(bundlePath.UTF8String, "{\"action\":\"ping\"}");
    NSString *resp = raw ? @(raw) : @"<null>";
    if (raw) free(raw);
    BOOL ok = ![resp containsString:@"The Python runtime could not start"] && ![resp containsString:@"does not include the Python runtime"];
    return @{@"status": ok ? @"passed" : @"failed", @"response": resp};
#else
    return @{@"status": @"not_compiled", @"detail": @"Built without HAS_APPLE_PYTHON"};
#endif
}

- (NSDictionary *)probeJava:(NSString *)bundlePath {
    NSString *modulesPath = [bundlePath stringByAppendingPathComponent:@"lib/lib/modules"];
    if (![NSFileManager.defaultManager fileExistsAtPath:modulesPath]) {
        return @{@"status": @"not_bundled", @"detail": @"lib/lib/modules (jimage) not present in this build"};
    }
#if HAS_APPLE_JVM
    char *raw = TVAppleRuntimeRequest(bundlePath.UTF8String, "{\"command\":\"trim\"}");
    NSString *resp = raw ? @(raw) : @"<null>";
    if (raw) free(raw);
    BOOL ok = ![resp containsString:@"Could not start the embedded Java runtime"];
    return @{@"status": ok ? @"passed" : @"failed", @"response": resp};
#else
    return @{@"status": @"not_compiled", @"detail": @"Built without HAS_APPLE_JVM"};
#endif
}

- (void)runDiagnosticsWorker {
    @autoreleasepool {
        UIDevice *device = UIDevice.currentDevice;
        NSString *bundlePath = NSBundle.mainBundle.bundlePath;
        NSDictionary *info = NSBundle.mainBundle.infoDictionary;

        NSDictionary *qjs = [self probeQuickJS];
        NSDictionary *ffmpeg = [self probeFFmpeg];
        NSDictionary *node = [self probeNodeMobile:bundlePath];
        NSDictionary *python = [self probePython:bundlePath];
        NSDictionary *java = [self probeJava:bundlePath];

        NSDictionary *report = @{
            @"timestamp": [NSISO8601DateFormatter stringFromDate:NSDate.date timeZone:NSTimeZone.localTimeZone formatOptions:NSISO8601DateFormatWithInternetDateTime],
            @"device": @{
                @"name": device.name ?: @"",
                @"systemName": device.systemName ?: @"",
                @"systemVersion": device.systemVersion ?: @"",
                @"model": device.model ?: @"",
                @"idiom": (device.userInterfaceIdiom == UIUserInterfaceIdiomPad) ? @"iPad" : @"iPhone"
            },
            @"bundle": @{
                @"bundleIdentifier": NSBundle.mainBundle.bundleIdentifier ?: @"",
                @"minimumOSVersion": info[@"MinimumOSVersion"] ?: @""
            },
            @"probes": @{
                @"quickjs": qjs,
                @"ffmpeg": ffmpeg,
                @"nodejs": node,
                @"python": python,
                @"java": java
            }
        };

        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] ?: @"{}";

        NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        [jsonString writeToFile:[caches stringByAppendingPathComponent:@"ios16-runtime-report.json"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [jsonString writeToFile:[docs stringByAppendingPathComponent:@"ios16-runtime-report.json"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.latestReportJSON = jsonString;
            self.logTextView.text = jsonString;
            self.runButton.enabled = YES;
        });
    }
}

@end

@interface TestEntrySceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation TestEntrySceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [[TestEntryViewController alloc] init];
    [self.window makeKeyAndVisible];
}
@end

@interface TestEntryAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation TestEntryAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([TestEntryAppDelegate class]));
    }
}
