#import "PFImageDecoder.h"
#import <ImageIO/ImageIO.h>

@implementation PFImageDecoder
+ (UIImage *)screenImageAtPath:(NSString *)path
             maximumPixelSize:(CGFloat)maximumPixelSize
                      metadata:(NSDictionary **)metadata {
    NSURL *url = [NSURL fileURLWithPath:path];
    NSDictionary *sourceOptions = @{(id)kCGImageSourceShouldCache: @NO};
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, (__bridge CFDictionaryRef)sourceOptions);
    if (!source) return nil;
    if (metadata) {
        NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        NSDictionary *exif = properties[(id)kCGImagePropertyExifDictionary];
        NSDictionary *tiff = properties[(id)kCGImagePropertyTIFFDictionary];
        NSString *dateText = exif[(id)kCGImagePropertyExifDateTimeOriginal] ?: tiff[(id)kCGImagePropertyTIFFDateTime];
        if (dateText.length) {
            NSDateFormatter *parser = [[NSDateFormatter alloc] init];
            parser.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            parser.dateFormat = @"yyyy:MM:dd HH:mm:ss";
            NSDate *date = [parser dateFromString:dateText];
            if (date) result[@"date"] = date;
        }
        NSDictionary *iptc = properties[(id)kCGImagePropertyIPTCDictionary];
        NSArray *placeCandidates = @[
            iptc[(id)kCGImagePropertyIPTCSubLocation] ?: @"",
            iptc[(id)kCGImagePropertyIPTCCity] ?: @"",
            iptc[(id)kCGImagePropertyIPTCProvinceState] ?: @"",
            iptc[(id)kCGImagePropertyIPTCCountryPrimaryLocationName] ?: @""
        ];
        NSMutableArray *placeParts = [NSMutableArray array];
        for (NSString *part in placeCandidates) {
            if (![part isKindOfClass:[NSString class]] || !part.length || [placeParts containsObject:part]) continue;
            [placeParts addObject:part];
        }
        if (placeParts.count) result[@"location"] = [placeParts componentsJoinedByString:@" · "];
        NSDictionary *gps = properties[(id)kCGImagePropertyGPSDictionary];
        NSNumber *latitude = gps[(id)kCGImagePropertyGPSLatitude];
        NSNumber *longitude = gps[(id)kCGImagePropertyGPSLongitude];
        if (latitude && longitude) {
            double latitudeValue = latitude.doubleValue;
            double longitudeValue = longitude.doubleValue;
            NSString *latitudeRef = gps[(id)kCGImagePropertyGPSLatitudeRef];
            NSString *longitudeRef = gps[(id)kCGImagePropertyGPSLongitudeRef];
            if ([latitudeRef.uppercaseString isEqualToString:@"S"]) latitudeValue = -latitudeValue;
            if ([longitudeRef.uppercaseString isEqualToString:@"W"]) longitudeValue = -longitudeValue;
            result[@"latitude"] = @(latitudeValue);
            result[@"longitude"] = @(longitudeValue);
        }
        *metadata = result;
    }
    NSDictionary *options = @{
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (id)kCGImageSourceShouldCacheImmediately: @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize: @(maximumPixelSize)
    };
    CGImageRef imageRef = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!imageRef) return nil;
    UIImage *image = [UIImage imageWithCGImage:imageRef scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(imageRef);
    return image;
}
@end
