// A disposable application, never SeeUsage itself. No provider code is linked.
#import <AppKit/AppKit.h>
#import <Sparkle/Sparkle.h>

static void record(NSString *event) {
    NSString *path = [NSBundle.mainBundle objectForInfoDictionaryKey:@"TestLogPath"];
    FILE *file = fopen(path.fileSystemRepresentation, "a");
    if (file) { fprintf(file, "%s\n", event.UTF8String); fclose(file); }
}

static void finish(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), dispatch_get_main_queue(), ^{ exit(0); });
}

@interface UpdateFixture : NSObject <NSApplicationDelegate, SPUUserDriver>
@property SPUUpdater *updater;
@property BOOL recordedExtraction;
@end

@implementation UpdateFixture
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([[NSBundle.mainBundle objectForInfoDictionaryKey:@"TestUpdatedPayload"] boolValue]) {
        record([@"relaunched:" stringByAppendingString:[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"]]);
        record([@"preference:" stringByAppendingString:[defaults stringForKey:@"IntegrationPreference"] ?: @"missing"]);
        finish();
        return;
    }
    [defaults setObject:@"preserved" forKey:@"IntegrationPreference"];
    self.updater = [[SPUUpdater alloc] initWithHostBundle:NSBundle.mainBundle applicationBundle:NSBundle.mainBundle userDriver:self delegate:nil];
    NSError *error = nil;
    if (![self.updater startUpdater:&error]) {
        record([@"startup-error:" stringByAppendingString:error.description]); finish(); return;
    }
    [self.updater checkForUpdates];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 45 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ record(@"timeout"); exit(2); });
}
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply {
    record(@"unexpected-permission"); exit(3);
}
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation { record(@"checking"); }
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply {
    record([@"found:" stringByAppendingString:item.versionString]);
    NSString *choice = [NSBundle.mainBundle objectForInfoDictionaryKey:@"TestChoice"];
    if ([choice isEqualToString:@"dismiss"]) { record(@"dismissed"); reply(SPUUserUpdateChoiceDismiss); }
    else if ([choice isEqualToString:@"skip"]) { record(@"skipped"); reply(SPUUserUpdateChoiceSkip); }
    else { record(@"consented"); reply(SPUUserUpdateChoiceInstall); }
}
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)data {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error {}
- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement {
    record(@"no-update"); acknowledgement(); finish();
}
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement {
    record([NSString stringWithFormat:@"error:%ld:%@", (long)error.code, error.localizedDescription]);
    acknowledgement(); finish();
}
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancellation { record(@"downloading"); }
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)length {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length {}
- (void)showDownloadDidStartExtractingUpdate { record(@"extracting"); }
- (void)showExtractionReceivedProgress:(double)progress {
    if (progress > 0 && !self.recordedExtraction) { self.recordedExtraction = YES; record(@"extraction-progress"); }
}
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply { record(@"installing-consented-update"); reply(SPUUserUpdateChoiceInstall); }
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)terminated retryTerminatingApplication:(void (^)(void))retry { record(@"installing"); }
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))acknowledgement { acknowledgement(); finish(); }
- (void)dismissUpdateInstallation {
    record(@"dismissed-driver");
    NSString *choice = [NSBundle.mainBundle objectForInfoDictionaryKey:@"TestChoice"];
    if (![choice isEqualToString:@"install"]) finish();
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        UpdateFixture *fixture = [UpdateFixture new];
        application.delegate = fixture;
        [application run];
    }
    return 0;
}
