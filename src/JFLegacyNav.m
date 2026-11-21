// JFLegacyNav.m -- open straight into Jellyfin from the main menu.
//
// On AppleTV 8.4, beigelist7 shows an old-style appliance as a list of its
// categories (BLAppLegacyCategoryController) and only calls
// -controllerForIdentifier:args: when one is picked.  Jellyfin has a single
// category, so when that list appears for our appliance we push our controller
// at once; when the list comes back on screen after Jellyfin closes, it pops
// itself, so Menu returns to the main menu.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "JFLog.h"

@interface NSObject (JFLegacyNav)
- (id)stack;
- (void)pushController:(id)c;
- (void)popController;
- (id)controllerForIdentifier:(id)ident args:(id)args;
@end

static char kOpenedKey;
static void (*BLCat_activated_orig)(id, SEL);

// The appliance this category list belongs to: the first object ivar holding a
// JFAppliance.  nil for every other appliance's list.
static id jf_our_appliance(id list) {
    Class jf = objc_getClass("JFAppliance");
    // beigelist 2.2.6 keeps the appliance behind -legacyAppliance (no ivar).
    if ([list respondsToSelector:@selector(legacyAppliance)]) {
        id a = [list performSelector:@selector(legacyAppliance)];
        return [a isKindOfClass:jf] ? a : nil;
    }
    for (Class c = object_getClass(list); c && jf; c = class_getSuperclass(c)) {
        unsigned n = 0;
        Ivar *ivars = class_copyIvarList(c, &n);
        for (unsigned i = 0; i < n; i++) {
            const char *type = ivar_getTypeEncoding(ivars[i]);
            if (!type || type[0] != '@') continue;
            id v = object_getIvar(list, ivars[i]);
            if (v && [v isKindOfClass:jf]) { free(ivars); return v; }
        }
        free(ivars);
    }
    return nil;
}

static void jf_log_class(const char *name) {
    Class c = objc_getClass(name);
    if (!c) { jf_log(@"%s: not present", name); return; }
    NSMutableString *s = [NSMutableString stringWithFormat:@"%s : %s\n  ivars:", name, class_getName(class_getSuperclass(c))];
    unsigned n = 0;
    Ivar *iv = class_copyIvarList(c, &n);
    for (unsigned i = 0; i < n; i++) [s appendFormat:@" %s(%s)", ivar_getName(iv[i]), ivar_getTypeEncoding(iv[i])];
    free(iv);
    [s appendString:@"\n  methods:"];
    Method *m = class_copyMethodList(c, &n);
    for (unsigned i = 0; i < n; i++) [s appendFormat:@" %@", NSStringFromSelector(method_getName(m[i]))];
    free(m);
    jf_log(@"%@", s);
}

static void BLCat_activated(id self, SEL _cmd) {
    BLCat_activated_orig(self, _cmd);
    id app = jf_our_appliance(self);
    if (!app) return;
    if (!objc_getAssociatedObject(self, &kOpenedKey)) {
        objc_setAssociatedObject(self, &kOpenedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        jf_log(@"category list shown: opening Jellyfin directly");
        id ctl = [app controllerForIdentifier:@"jellyfin" args:nil];
        if (ctl) [[self stack] pushController:ctl];
    } else {
        // Popping from inside the list's own activation is ignored by the stack,
        // which left the list (question-mark icons) on screen; pop once it is up.
        jf_log(@"back from Jellyfin: closing category list");
        id stack = [self stack];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), dispatch_get_main_queue(), ^{
            [stack popController];
        });
    }
}

void jf_legacy_nav_install(void) {
    jf_log_class("BLAppLegacyCategoryController");
    jf_log_class("BLApplianceController");
    Class c = objc_getClass("BLAppLegacyCategoryController");
    if (!c) return;
    SEL sel = @selector(controlWasActivated);
    Method m = class_getInstanceMethod(c, sel);
    if (!m) { jf_log(@"BLAppLegacyCategoryController lacks controlWasActivated"); return; }
    BLCat_activated_orig = (void (*)(id, SEL))method_getImplementation(m);
    // Add to the class itself if the method is inherited, so the superclass
    // (shared by every BackRow controller) is not changed.
    if (!class_addMethod(c, sel, (IMP)BLCat_activated, method_getTypeEncoding(m)))
        method_setImplementation(m, (IMP)BLCat_activated);
    jf_log(@"category list hook installed");
}
