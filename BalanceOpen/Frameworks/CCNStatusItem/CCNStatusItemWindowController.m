//
//  Created by Frank Gregor on 23.12.14.
//  Copyright (c) 2014 cocoa:naut. All rights reserved.
//

/*
 The MIT License (MIT)
 Copyright © 2014 Frank Gregor, <phranck@cocoanaut.com>
 http://cocoanaut.mit-license.org

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the “Software”), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 */


#import <QuartzCore/QuartzCore.h>
#import <Carbon/Carbon.h>
#import "CCNStatusItemWindowController.h"
#import "CCNStatusItemWindowConfiguration.h"

NSString *const CCNStatusItemWindowWillShowNotification    = @"CCNStatusItemWindowWillShowNotification";
NSString *const CCNStatusItemWindowDidShowNotification     = @"CCNStatusItemWindowDidShowNotification";
NSString *const CCNStatusItemWindowWillDismissNotification = @"CCNStatusItemWindowWillDismissNotification";
NSString *const CCNStatusItemWindowDidDismissNotification  = @"CCNStatusItemWindowDidDismissNotification";
NSString *const CCNSystemInterfaceThemeChangedNotification = @"CCNSystemInterfaceThemeChangedNotification";


static const CGFloat CCNTransitionDistance = 10.0;
typedef NS_ENUM(NSUInteger, CCNFadeDirection) {
    CCNFadeDirectionFadeIn = 0,
    CCNFadeDirectionFadeOut
};

typedef void (^CCNStatusItemWindowAnimationCompletion)(void);


@interface CCNStatusItemWindowController ()
@property (strong) CCNStatusItem *statusItemView;
@property (strong) CCNStatusItemWindowConfiguration *windowConfiguration;
@end

@implementation CCNStatusItemWindowController

- (id)initWithConnectedStatusItem:(CCNStatusItem *)statusItem
            contentViewController:(NSViewController *)contentViewController
              windowConfiguration:(CCNStatusItemWindowConfiguration *)windowConfiguration {

    if (!contentViewController) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.windowIsOpen = NO;
        self.statusItemView = statusItem;
        self.windowConfiguration = windowConfiguration;

        // StatusItem Window
        self.window = [CCNStatusItemWindow statusItemWindowWithConfiguration:windowConfiguration];
        self.contentViewController = contentViewController;

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleWindowDidResignKeyNotification:) name:NSWindowDidResignKeyNotification object:nil];
        [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(handleAppleInterfaceThemeChangedNotification:) name:@"AppleInterfaceThemeChangedNotification" object:nil];
        
        [self registerForMenuBarNotifications];
    }
    return self;
}

- (void)updateContentViewController:(NSViewController *)contentViewController {
    // Set nil first to trigger window resize
    self.contentViewController = nil;
    self.contentViewController = contentViewController;

    [self updateWindowFrame];
}

#pragma mark - Helper

- (void)updateWindowFrame {
    CGRect statusItemRect = [[self.statusItemView.statusItem.button window] frame];
    CGRect windowFrame = NSMakeRect(NSMinX(statusItemRect) - NSWidth(self.window.frame) / 2 + NSWidth(statusItemRect) / 2,
                                    NSMinY(statusItemRect) - NSHeight(self.window.frame) - self.windowConfiguration.windowToStatusItemMargin,
                                    self.window.frame.size.width,
                                    self.window.frame.size.height);
    [self.window setFrame:windowFrame display:YES];
    [self.window setAppearance:[NSAppearance currentAppearance]];
}

- (void)updateWindowOrigin {
    CGRect statusItemRect = [[self.statusItemView.statusItem.button window] frame];
    CGPoint windowOrigin = CGPointMake(NSMinX(statusItemRect) - NSWidth(self.window.frame) / 2 + NSWidth(statusItemRect) / 2,
                                       NSMinY(statusItemRect) - NSHeight(self.window.frame) - self.windowConfiguration.windowToStatusItemMargin);
    [self.window setFrameOrigin:windowOrigin];
}

#pragma mark - Handling Window Visibility

- (void)showStatusItemWindow {
    if (self.animationIsRunning) return;

    [self updateWindowOrigin];
    [self.window setAlphaValue:0.0];
    [self showWindow:nil];

    [self animateWindow:(CCNStatusItemWindow *) self.window withFadeDirection:CCNFadeDirectionFadeIn];
}

- (void)dismissStatusItemWindow {
    if (self.animationIsRunning) return;

    [self animateWindow:(CCNStatusItemWindow *) self.window withFadeDirection:CCNFadeDirectionFadeOut];
}

- (void)animateWindow:(CCNStatusItemWindow *)window withFadeDirection:(CCNFadeDirection)fadeDirection {
    switch (self.windowConfiguration.presentationTransition) {
        case CCNPresentationTransitionNone:
        case CCNPresentationTransitionFade: {
            [self animateWindow:window withFadeTransitionUsingFadeDirection:fadeDirection];
            break;
        }
        case CCNPresentationTransitionSlideAndFade: {
            [self animateWindow:window withSlideAndFadeTransitionUsingFadeDirection:fadeDirection];
            break;
        }
    }
}

- (void)animateWindow:(CCNStatusItemWindow *)window withFadeTransitionUsingFadeDirection:(CCNFadeDirection)fadeDirection {
    NSString *notificationName = (fadeDirection == CCNFadeDirectionFadeIn ? CCNStatusItemWindowWillShowNotification : CCNStatusItemWindowWillDismissNotification);
    [[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:window];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = self.windowConfiguration.animationDuration;
        context.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.16 :0.46 :0.33 :1];
        [[window animator] setAlphaValue:(fadeDirection == CCNFadeDirectionFadeIn ? 1.0 : 0.0)];

    }                   completionHandler:[self animationCompletionForWindow:window fadeDirection:fadeDirection]];
}

- (void)animateWindow:(CCNStatusItemWindow *)window withSlideAndFadeTransitionUsingFadeDirection:(CCNFadeDirection)fadeDirection {
    NSString *notificationName = (fadeDirection == CCNFadeDirectionFadeIn ? CCNStatusItemWindowWillShowNotification : CCNStatusItemWindowWillDismissNotification);
    [[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:window];

    CGRect windowStartFrame, windowEndFrame;
    CGRect calculatedFrame = NSMakeRect(NSMinX(window.frame), NSMinY(window.frame) + CCNTransitionDistance, NSWidth(window.frame), NSHeight(window.frame));

    switch (fadeDirection) {
        case CCNFadeDirectionFadeIn: {
            windowStartFrame = calculatedFrame;
            windowEndFrame = window.frame;
            break;
        }
        case CCNFadeDirectionFadeOut: {
            windowStartFrame = window.frame;
            windowEndFrame = calculatedFrame;
            break;
        }
    }
    [window setFrame:windowStartFrame display:NO];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = self.windowConfiguration.animationDuration;
        context.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.18 :0.4 :0.57 :1];
        [[window animator] setFrame:windowEndFrame display:NO];
        [[window animator] setAlphaValue:(fadeDirection == CCNFadeDirectionFadeIn ? 1.0 : 0.0)];

    }                   completionHandler:[self animationCompletionForWindow:window fadeDirection:fadeDirection]];
}

- (CCNStatusItemWindowAnimationCompletion)animationCompletionForWindow:(CCNStatusItemWindow *)window fadeDirection:(CCNFadeDirection)fadeDirection {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    __weak typeof(self) wSelf = self;

    return ^{
        wSelf.animationIsRunning = NO;
        wSelf.windowIsOpen = (fadeDirection == CCNFadeDirectionFadeIn);

        if (fadeDirection == CCNFadeDirectionFadeIn) {
            [window makeKeyWindow];
            [nc postNotificationName:CCNStatusItemWindowDidShowNotification object:window];
        }
        else {
            [window orderOut:wSelf];
            [window close];
            [nc postNotificationName:CCNStatusItemWindowDidDismissNotification object:window];
        }
    };
}

- (void)resizeStatusItemWindow:(NSSize)size animated:(BOOL)animated {
    //NSLog(@"resizeStatusItemWindow: %@\n%@", NSStringFromSize(size), [NSThread callStackSymbols]);
    size.height += CCNDefaultArrowHeight;
    CGRect frame = self.window.frame;
    if (!NSEqualSizes(frame.size, size) || !NSEqualSizes(self.contentViewController.view.frame.size, size)) {
        //CGFloat xDiff = frame.size.width - size.width / 2.0;
        CGFloat yDiff = frame.size.height - size.height;
        frame.origin = CGPointMake(frame.origin.x, frame.origin.y + yDiff);
        frame.size = size;
        
        [self.window setFrame:frame display:YES animate:animated];
        self.contentViewController.view.frame = self.window.contentView.bounds;
    }
}

- (void)resizeStatusItemWindowHeight:(CGFloat)height animated:(BOOL)animated {
    CGSize size = CGSizeMake(self.window.frame.size.width, height);
    [self resizeStatusItemWindow:size animated:animated];
}

static __weak CCNStatusItemWindowController *controller = nil;
void menuBarWillBeShownHidden (EventHandlerCallRef inHandlerRef, EventRef inEvent, void *data) {
    return [controller menuBarWillBeShownHidden:inEvent];
}

- (void)registerForMenuBarNotifications {
    controller = self;
    
    EventTypeSpec opt[] = {
        { kEventClassMenu, kEventMenuBarShown },
        { kEventClassMenu, kEventMenuBarHidden }
    };
    
    OSStatus err = InstallEventHandler(GetEventDispatcherTarget(),
                                       NewEventHandlerUPP((EventHandlerProcPtr)menuBarWillBeShownHidden),
                                       2,
                                       opt,
                                       nil,
                                       nil);
    if (err != 0) {
        NSLog(@"CCNStatusItemWindowController error registering for menu bar notifications  %d", err);
    }
}

- (void)menuBarWillBeShownHidden:(EventRef)inEvent
{
    CGRect statusItemRect = [[self.statusItemView.statusItem.button window] frame];
    CGPoint windowOrigin = CGPointMake(NSMinX(statusItemRect) - NSWidth(self.window.frame) / 2 + NSWidth(statusItemRect) / 2,
                                       NSMinY(statusItemRect) - NSHeight(self.window.frame) - self.windowConfiguration.windowToStatusItemMargin);
    CGFloat menuBarHeight = [[[NSApplication sharedApplication] mainMenu] menuBarHeight];
    
    // The calculated value will always be the opposite as the menu is in the opposite state when this is called,
    // so we have to adjust it.
    if (GetEventKind(inEvent) == kEventMenuBarShown)
        // Will be shown
        windowOrigin.y -= menuBarHeight;
    else
        // Will be hidden
        windowOrigin.y += menuBarHeight;
    
    CGRect frame = (NSRect){.origin = windowOrigin, .size = self.window.frame.size};
    [self.window setFrame:frame display:YES animate:YES];
}

#pragma mark - Notifications

- (void)handleWindowDidResignKeyNotification:(NSNotification *)note {
    if (![note.object isEqual:self.window]) return;
    if (!self.windowConfiguration.isPinned) {
        [self dismissStatusItemWindow];
    }
}

#pragma mark - NSDistributedNotificationCenter

- (void)handleAppleInterfaceThemeChangedNotification:(NSNotification *)note {
    [[NSNotificationCenter defaultCenter] postNotificationName:CCNSystemInterfaceThemeChangedNotification object:nil];
}

@end

