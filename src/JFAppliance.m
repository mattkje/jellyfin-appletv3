// JFAppliance.m -- registers "Jellyfin" as an Apple TV (3rd gen, 8.4) main-menu
// appliance and hands the screen to a UIKit view while it is open.
//
// The AppleTV.app has no public plugin API. beigelist (installed by blackb0x)
// loads any .frappliance bundle in /Applications, and the BackRow classes
// (BRBaseAppliance, BRController, BRWindow...) live inside AppleTV.app itself,
// so they cannot be linked against: every class is looked up at run time and
// our subclasses are built with the Objective-C runtime.  This is the same
// approach Kodi's ATV2 port uses (xbmc/osx/atv2 in Kodi 14, GPLv2+).
//
// Built without ARC: init-style overrides reassign self.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "JFRootView.h"
#import "JFLog.h"

void jf_legacy_nav_install(void);   // JFLegacyNav.m

#define JF_CATEGORY_ID @"jellyfin"

// ---- BackRow declarations (resolved at run time) ---------------------------------------
@interface NSObject (JFBackRow)
+ (id)categoryWithName:(NSString *)name identifier:(NSString *)ident preferredOrder:(float)order;
+ (CGRect)interfaceFrame;
+ (CALayer *)rootLayer;
+ (id)sharedApplication;
- (void)setFirstResponder:(id)responder;
- (id)stack;
- (void)popController;
- (unsigned int)originator;
- (id)initWithApplianceInfo:(id)info;
// ours, added at run time
- (JFRootView *)jfView;
- (void)setJfView:(JFRootView *)v;
- (void)setApplianceCategories:(id)cats;
- (void)setTopShelfController:(id)c;
@end

static Class BRWindowCls;
JFRootView *jf_current_root;          // for JFDevHooks' remote commands
static char kViewKey, kCatsKey, kShelfKey;

// Adds `imp` to `cls` for `sel` with the superclass's type encoding; returns the
// superclass implementation so overrides can call [super sel].
static IMP jf_override(Class cls, SEL sel, IMP imp) {
    Class sup = class_getSuperclass(cls);
    Method m = class_getInstanceMethod(sup, sel);
    if (!m) { jf_log(@"base class %s lacks %@", class_getName(sup), NSStringFromSelector(sel)); return NULL; }
    class_addMethod(cls, sel, imp, method_getTypeEncoding(m));
    return method_getImplementation(m);
}

// ---- top shelf (empty: the main menu just shows our icon) ------------------------------
@interface JFTopShelfController : NSObject
@end
@implementation JFTopShelfController
- (void)selectCategoryWithIdentifier:(id)ident {}
- (id)topShelfView { return [[[objc_getClass("BRTopShelfView") alloc] init] autorelease]; }
- (id)mainMenuShelfView { return [[[objc_getClass("BRTopShelfView") alloc] init] autorelease]; }
- (void)refresh {}
@end

// ---- JFApplianceInfo : BRApplianceInfo ---------------------------------------------------
static NSDictionary *jf_bundle_info(void) {
    return [[NSBundle bundleForClass:[JFTopShelfController class]] infoDictionary];
}
static id JFInfo_key(id self, SEL _cmd)  { return [jf_bundle_info() objectForKey:(NSString *)kCFBundleIdentifierKey]; }
static id JFInfo_name(id self, SEL _cmd) { return [jf_bundle_info() objectForKey:(NSString *)kCFBundleNameKey]; }
static id JFInfo_strings(id self, SEL _cmd) { return @"jellyfin"; }

// ---- JFAppliance : BRBaseAppliance -------------------------------------------------------
static id (*JFApp_initWithInfo_orig)(id, SEL, id);

static id (*JFApp_init_orig)(id, SEL);

static void jf_app_setup(id self) {
    [self setTopShelfController:[[[JFTopShelfController alloc] init] autorelease]];
    Class cat = objc_getClass("BRApplianceCategory");
    [self setApplianceCategories:@[[cat categoryWithName:@"Jellyfin" identifier:JF_CATEGORY_ID preferredOrder:0]]];
    jf_log(@"appliance created");
}
static id JFApp_initWithInfo(id self, SEL _cmd, id info) {
    if ((self = JFApp_initWithInfo_orig(self, _cmd, info))) jf_app_setup(self);
    return self;
}
static id JFApp_init(id self, SEL _cmd) {
    if (JFApp_initWithInfo_orig) return [self initWithApplianceInfo:nil];
    if ((self = JFApp_init_orig(self, _cmd))) jf_app_setup(self);
    return self;
}
static id JFApp_applianceInfo(id self, SEL _cmd) { return [[[objc_getClass("JFApplianceInfo") alloc] init] autorelease]; }
static id JFApp_shelf(id self, SEL _cmd) { return objc_getAssociatedObject(self, &kShelfKey); }
static void JFApp_setShelf(id self, SEL _cmd, id c) { objc_setAssociatedObject(self, &kShelfKey, c, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static id JFApp_cats(id self, SEL _cmd) { return objc_getAssociatedObject(self, &kCatsKey); }
static void JFApp_setCats(id self, SEL _cmd, id c) { objc_setAssociatedObject(self, &kCatsKey, c, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static id JFApp_alias(id self, SEL _cmd, id alias) { return JF_CATEGORY_ID; }
static BOOL JFApp_select(id self, SEL _cmd, id a, id b) { return YES; }

static id JFApp_controller(id self, SEL _cmd, id ident, id args) {
    jf_log(@"open %@", ident);
    id ctl = [[objc_getClass("JFController") alloc] init];
    [[objc_getClass("BRApplication") sharedApplication] setFirstResponder:ctl];
    return [ctl autorelease];
}

// ---- JFController : BRController ---------------------------------------------------------
static id   (*JFCtl_init_orig)(id, SEL);
static void (*JFCtl_dealloc_orig)(id, SEL);
static void (*JFCtl_activated_orig)(id, SEL);
static void (*JFCtl_deactivated_orig)(id, SEL);
static BOOL (*JFCtl_event_orig)(id, SEL, id);

static id JFCtl_view(id self, SEL _cmd) { return objc_getAssociatedObject(self, &kViewKey); }
static void JFCtl_setView(id self, SEL _cmd, id v) { objc_setAssociatedObject(self, &kViewKey, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }

static id JFCtl_init(id self, SEL _cmd) {
    if ((self = JFCtl_init_orig(self, _cmd))) {
        JFRootView *v = [[JFRootView alloc] initWithFrame:[BRWindowCls interfaceFrame]];
        id ctl = self;
        v.onExit = ^{ [[ctl stack] popController]; };
        [self setJfView:v];
        [v release];
    }
    return self;
}
static void JFCtl_dealloc(id self, SEL _cmd) {
    [[self jfView].layer removeFromSuperlayer];
    JFCtl_dealloc_orig(self, _cmd);
}
static void JFCtl_activated(id self, SEL _cmd) {
    JFCtl_activated_orig(self, _cmd);
    JFRootView *v = [self jfView];
    [[BRWindowCls rootLayer] addSublayer:v.layer];
    jf_current_root = v;
    [v didAppear];
}
static void JFCtl_deactivated(id self, SEL _cmd) {
    JFRootView *v = [self jfView];
    [v willDisappear];
    [v.layer removeFromSuperlayer];
    if (jf_current_root == v) jf_current_root = nil;
    JFCtl_deactivated_orig(self, _cmd);
}
static BOOL JFCtl_recreate(id self, SEL _cmd) { return YES; }

// Remote codes: the BackRow enum (Kodi's KodiController.mm) plus the raw values
// later AppleTV versions send for the same buttons.
static JFKey jf_key(int action) {
    switch (action) {
        case 3:  case 65676: return JFKeyUp;
        case 4:  case 65677: return JFKeyDown;
        case 6:  case 65675: return JFKeyLeft;
        case 7:  case 65674: return JFKeyRight;
        case 5:  case 65673: case 10: case 786637: return JFKeySelect;
        case 16: case 15: case 786608: return JFKeyPlayPause;
        case 1:  case 65670: return JFKeyMenu;
        case 2:  case 786496: return JFKeyMenuHold;
        case 22: case 23: case 24: case 65668: return JFKeySelectHold;
        case 18: case 9: case 786611: return JFKeyForward;
        case 19: case 8: case 786612: return JFKeyRewind;
        default: return JFKeyNone;
    }
}
// BREvent's -remoteAction and -value return int; called through a typed
// objc_msgSend because other classes declare an object-returning -value.
static int jf_int(id o, SEL sel) { return ((int (*)(id, SEL))objc_msgSend)(o, sel); }

static BOOL JFCtl_event(id self, SEL _cmd, id event) {
    int action = jf_int(event, @selector(remoteAction));
    int value  = jf_int(event, @selector(value));
    JFKey k = jf_key(action);
    if (k == JFKeyNone) {
        NSLog(@"[Jellyfin] unhandled remote action %d value %d", action, value);
        return JFCtl_event_orig(self, _cmd, event);
    }
    BOOL pressed = value == 1;
    // Arrows repeat while held: value 1 on press, 0 on release.
    if (k == JFKeyUp || k == JFKeyDown || k == JFKeyLeft || k == JFKeyRight)
        [[self jfView] arrow:k pressed:pressed];
    else if (pressed)
        [[self jfView] key:k];
    return YES;
}

// ---- registration ----------------------------------------------------------------------------
static __attribute__((constructor)) void jf_register(void) {
    @autoreleasepool {
        if (objc_getClass("JFAppliance")) return;   // a second copy of the bundle was loaded
        if (!objc_getClass("BRBaseAppliance")) return;  // not inside AppleTV.app
        jf_log(@"loading");
        BRWindowCls = objc_getClass("BRWindow");
        if (!objc_getClass("BRBaseAppliance") || !BRWindowCls) {
            NSLog(@"[Jellyfin] not inside AppleTV.app, nothing registered");
            return;
        }

        Class info = objc_allocateClassPair(objc_getClass("BRApplianceInfo"), "JFApplianceInfo", 0);
        jf_override(info, @selector(key), (IMP)JFInfo_key);
        jf_override(info, @selector(name), (IMP)JFInfo_name);
        jf_override(info, @selector(localizedStringsFileName), (IMP)JFInfo_strings);
        objc_registerClassPair(info);

        Class app = objc_allocateClassPair(objc_getClass("BRBaseAppliance"), "JFAppliance", 0);
        class_addMethod(app, @selector(setTopShelfController:), (IMP)JFApp_setShelf, "v@:@");
        class_addMethod(app, @selector(setApplianceCategories:), (IMP)JFApp_setCats, "v@:@");
        JFApp_init_orig = (void *)jf_override(app, @selector(init), (IMP)JFApp_init);
        JFApp_initWithInfo_orig = (void *)jf_override(app, @selector(initWithApplianceInfo:), (IMP)JFApp_initWithInfo);
        jf_override(app, @selector(applianceInfo), (IMP)JFApp_applianceInfo);
        jf_override(app, @selector(topShelfController), (IMP)JFApp_shelf);
        jf_override(app, @selector(applianceCategories), (IMP)JFApp_cats);
        jf_override(app, @selector(identifierForContentAlias:), (IMP)JFApp_alias);
        jf_override(app, @selector(handleObjectSelection:userInfo:), (IMP)JFApp_select);
        jf_override(app, @selector(controllerForIdentifier:args:), (IMP)JFApp_controller);
        objc_registerClassPair(app);

        Class ctl = objc_allocateClassPair(objc_getClass("BRController"), "JFController", 0);
        class_addMethod(ctl, @selector(jfView), (IMP)JFCtl_view, "@@:");
        class_addMethod(ctl, @selector(setJfView:), (IMP)JFCtl_setView, "v@:@");
        JFCtl_init_orig        = (void *)jf_override(ctl, @selector(init), (IMP)JFCtl_init);
        JFCtl_dealloc_orig     = (void *)jf_override(ctl, @selector(dealloc), (IMP)JFCtl_dealloc);
        JFCtl_activated_orig   = (void *)jf_override(ctl, @selector(controlWasActivated), (IMP)JFCtl_activated);
        JFCtl_deactivated_orig = (void *)jf_override(ctl, @selector(controlWasDeactivated), (IMP)JFCtl_deactivated);
        JFCtl_event_orig       = (void *)jf_override(ctl, @selector(brEventAction:), (IMP)JFCtl_event);
        jf_override(ctl, @selector(recreateOnReselect), (IMP)JFCtl_recreate);
        objc_registerClassPair(ctl);

        jf_log(@"appliance registered");
        jf_legacy_nav_install();
    }
}
