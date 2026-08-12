#import <Foundation/Foundation.h>

#define PFL(key) NSLocalizedString((key), nil)

static inline NSLocale *PFLocalizationLocale(void) {
    NSString *identifier = [[[NSBundle mainBundle] preferredLocalizations] firstObject];
    return identifier.length ? [[NSLocale alloc] initWithLocaleIdentifier:identifier] : [NSLocale currentLocale];
}
