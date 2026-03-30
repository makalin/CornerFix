#import <AppKit/AppKit.h>

@interface CornerFixTestAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property (strong) NSWindow *window;
@end

@implementation CornerFixTestAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;

    NSRect frame = NSMakeRect(0, 0, 900, 620);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskTitled |
                                                         NSWindowStyleMaskClosable |
                                                         NSWindowStyleMaskMiniaturizable |
                                                         NSWindowStyleMaskResizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"CornerFix Test App";
    self.window.delegate = self;
    [self.window center];

    NSView *contentView = self.window.contentView;

    NSTextField *headline = [NSTextField labelWithString:@"Unsigned test app for CornerFix injection"];
    headline.font = [NSFont boldSystemFontOfSize:24.0];
    headline.frame = NSMakeRect(30, 540, 520, 32);

    NSTextField *body = [NSTextField wrappingLabelWithString:@"Use this app to verify that libcornerfix.dylib loads and that standard NSWindow corners respond to radius changes. Try resizing, opening extra windows, and changing the radius live with cornerfixctl."];
    body.frame = NSMakeRect(30, 470, 760, 54);

    NSButton *newWindowButton = [NSButton buttonWithTitle:@"Open Another Window"
                                                   target:self
                                                   action:@selector(openAnotherWindow:)];
    newWindowButton.frame = NSMakeRect(30, 420, 180, 32);

    NSBox *panel = [[NSBox alloc] initWithFrame:NSMakeRect(30, 60, 840, 330)];
    panel.boxType = NSBoxCustom;
    panel.cornerRadius = 16.0;
    panel.borderWidth = 1.0;
    panel.borderColor = NSColor.separatorColor;
    panel.fillColor = [NSColor colorWithRed:0.95 green:0.97 blue:0.99 alpha:1.0];
    panel.title = @"Visual reference";

    NSTextField *panelLabel = [NSTextField wrappingLabelWithString:@"This inner panel stays rounded so you can compare app content with the native outer window frame. If CornerFix is injected successfully, the top-level window corners should change while this panel remains unchanged."];
    panelLabel.frame = NSMakeRect(24, 180, 760, 90);
    [panel.contentView addSubview:panelLabel];

    [contentView addSubview:headline];
    [contentView addSubview:body];
    [contentView addSubview:newWindowButton];
    [contentView addSubview:panel];

    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)openAnotherWindow:(id)sender {
    (void)sender;

    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 360)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskMiniaturizable |
                                                              NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Secondary Test Window";
    [window cascadeTopLeftFromPoint:NSMakePoint(180, 180)];

    NSTextField *label = [NSTextField wrappingLabelWithString:@"Resize this secondary window and toggle cornerfixctl radius values to confirm live updates."];
    label.frame = NSMakeRect(24, 240, 460, 52);
    [window.contentView addSubview:label];

    [window makeKeyAndOrderFront:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        CornerFixTestAppDelegate *delegate = [[CornerFixTestAppDelegate alloc] init];
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        return NSApplicationMain(argc, argv);
    }
}
