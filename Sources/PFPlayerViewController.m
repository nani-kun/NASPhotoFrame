#import "PFPlayerViewController.h"
#import "PFPhotoService.h"
#import "PFSettingsViewController.h"
#import "PFConfiguration.h"
#import "PFPhoto.h"
#import "PFOfflineGeocoder.h"
#import "PFLocalization.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

@interface PFPlayerViewController ()
@property (nonatomic, strong) UIImageView *firstImageView;
@property (nonatomic, strong) UIImageView *secondImageView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *photoInfoLabel;
@property (nonatomic, strong) NSArray *photos;
@property (nonatomic) NSUInteger nextIndex;
@property (nonatomic) NSUInteger currentIndex;
@property (nonatomic) BOOL hasCurrentPhoto;
@property (nonatomic) BOOL firstIsVisible;
@property (nonatomic) BOOL loading;
@property (nonatomic) NSUInteger generation;
@property (nonatomic, strong) NSTimer *slideTimer;
@property (nonatomic) BOOL settingsPresented;
@property (nonatomic, strong) NSError *lastScanError;
@property (nonatomic) CFTimeInterval panStartTime;
@property (nonatomic) CFTimeInterval panEndTime;
@property (nonatomic) CGSize lastPlayerSize;
@property (nonatomic) BOOL currentPanReversed;
@property (nonatomic) BOOL currentKenBurnsZoomIn;
@property (nonatomic, strong) NSCache *locationCache;
@property (nonatomic) NSUInteger photoInfoGeneration;
@end

@implementation PFPlayerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.firstImageView = [self imageView];
    self.secondImageView = [self imageView];
    self.firstImageView.alpha = 0.0;
    self.secondImageView.alpha = 0.0;
    [self.view addSubview:self.firstImageView];
    [self.view addSubview:self.secondImageView];

    self.photoInfoLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.photoInfoLabel.backgroundColor = [UIColor clearColor];
    self.photoInfoLabel.font = [UIFont systemFontOfSize:14.0];
    self.photoInfoLabel.numberOfLines = 2;
    self.photoInfoLabel.hidden = YES;
    self.photoInfoLabel.layer.shadowRadius = 1.0;
    self.photoInfoLabel.layer.shadowOpacity = 0.9;
    [self.view addSubview:self.photoInfoLabel];
    self.locationCache = [[NSCache alloc] init];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:@"PFLastGeocoderDiagnostic"];
    [defaults synchronize];
    NSDictionary *savedLocations = [defaults dictionaryForKey:@"PFReverseGeocodeCache"];
    for (NSString *key in savedLocations) {
        NSString *location = savedLocations[key];
        if ([location isKindOfClass:[NSString class]] && location.length) [self.locationCache setObject:location forKey:key];
    }

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    self.statusLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont systemFontOfSize:20.0];
    self.statusLabel.layer.cornerRadius = 10.0;
    self.statusLabel.layer.masksToBounds = YES;
    [self.view addSubview:self.statusLabel];
    [self showStatus:PFL(@"player.status.loadingIndex")];

    UILongPressGestureRecognizer *settings = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
    settings.minimumPressDuration = 1.5;
    [self.view addGestureRecognizer:settings];
    UITapGestureRecognizer *next = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
    [next requireGestureRecognizerToFail:settings];
    UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipedToNext:)];
    swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipedToPrevious:)];
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    [next requireGestureRecognizerToFail:swipeLeft];
    [next requireGestureRecognizerToFail:swipeRight];
    [self.view addGestureRecognizer:next];
    [self.view addGestureRecognizer:swipeLeft];
    [self.view addGestureRecognizer:swipeRight];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scanFinished:) name:PFPhotoServiceScanDidFinishNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(memoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [self reloadPlaylistAndAdvance:YES requestScanWhenEmpty:YES];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (UIImageView *)imageView {
    UIImageView *view = [[UIImageView alloc] initWithFrame:self.view.bounds];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    view.backgroundColor = [UIColor blackColor];
    // A correctly proportioned contentsRect is selected for each image below,
    // so stretching that cropped area fills the screen without distortion.
    view.contentMode = UIViewContentModeScaleToFill;
    view.clipsToBounds = YES;
    return view;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize playerSize = self.view.bounds.size;
    if (!CGSizeEqualToSize(playerSize, self.lastPlayerSize)) {
        self.lastPlayerSize = playerSize;
        UIImageView *visible = self.firstIsVisible ? self.firstImageView : self.secondImageView;
        if (visible.image) {
            CFTimeInterval now = CACurrentMediaTime();
            NSTimeInterval total = MAX(self.panEndTime - self.panStartTime, 0.0);
            CGFloat progress = total > 0.0 ? (CGFloat)((now - self.panStartTime) / total) : 1.0;
            progress = MIN(MAX(progress, 0.0), 1.0);
            [self configurePanForImageView:visible progress:progress remainingDuration:MAX(self.panEndTime - now, 0.0)];
        }
    }
    CGFloat width = MAX(CGRectGetWidth(self.view.bounds) - 160.0, 160.0);
    CGSize fittingSize = [self.statusLabel sizeThatFits:CGSizeMake(width - 32.0, CGFLOAT_MAX)];
    CGFloat maximumHeight = MAX(CGRectGetHeight(self.view.bounds) - 80.0, 120.0);
    CGFloat height = MIN(MAX(fittingSize.height + 32.0, 120.0), maximumHeight);
    self.statusLabel.frame = CGRectMake((CGRectGetWidth(self.view.bounds) - width) / 2.0,
                                        (CGRectGetHeight(self.view.bounds) - height) / 2.0,
                                        width, height);
    CGFloat infoWidth = MIN(CGRectGetWidth(self.view.bounds) * 0.62, 520.0);
    CGSize infoSize = [self.photoInfoLabel sizeThatFits:CGSizeMake(infoWidth, CGFLOAT_MAX)];
    self.photoInfoLabel.frame = CGRectMake(22.0,
                                           CGRectGetHeight(self.view.bounds) - infoSize.height - 18.0,
                                           infoWidth, infoSize.height);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (![[PFPhotoService sharedService] configuration].isComplete) [self presentSettingsAllowingCancel:NO];
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }

- (void)longPressed:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) [self presentSettingsAllowingCancel:YES];
}

- (void)tapped:(UITapGestureRecognizer *)recognizer {
    [self.slideTimer invalidate];
    self.slideTimer = nil;
    [self advance];
}

- (void)swipedToNext:(UISwipeGestureRecognizer *)recognizer {
    if (![[PFPhotoService sharedService] configuration].swipeNavigationEnabled) return;
    [self.slideTimer invalidate];
    self.slideTimer = nil;
    [self advance];
}

- (void)swipedToPrevious:(UISwipeGestureRecognizer *)recognizer {
    if (![[PFPhotoService sharedService] configuration].swipeNavigationEnabled) return;
    [self.slideTimer invalidate];
    self.slideTimer = nil;
    [self goBack];
}

- (void)presentSettingsAllowingCancel:(BOOL)allowCancel {
    if (self.settingsPresented || self.presentedViewController) return;
    self.settingsPresented = YES;
    PFSettingsViewController *settings = [[PFSettingsViewController alloc] initWithStyle:UITableViewStyleGrouped];
    settings.allowsCancel = allowCancel;
    __weak typeof(self) weakSelf = self;
    settings.saveHandler = ^(PFConfiguration *configuration) {
        weakSelf.lastScanError = nil;
        [weakSelf reloadPlaylistAndAdvance:YES requestScanWhenEmpty:YES];
    };
    settings.closeHandler = ^{ weakSelf.settingsPresented = NO; };
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)scanFinished:(NSNotification *)notification {
    NSError *error = notification.userInfo[PFPhotoServiceScanErrorKey];
    self.lastScanError = error;
    [self reloadPlaylistAndAdvance:self.photos.count == 0 requestScanWhenEmpty:NO];
}

- (void)reloadPlaylistAndAdvance:(BOOL)advance requestScanWhenEmpty:(BOOL)requestScanWhenEmpty {
    NSString *currentRemotePath = nil;
    if (!advance && self.hasCurrentPhoto && self.currentIndex < self.photos.count) {
        currentRemotePath = [self.photos[self.currentIndex] remotePath];
    }
    if (advance) {
        ++self.generation;
        self.loading = NO;
        [self.slideTimer invalidate];
        self.slideTimer = nil;
    }
    NSUInteger generation = self.generation;
    [[PFPhotoService sharedService] photosWithCompletion:^(NSArray *photos) {
        if (generation != self.generation) return;
        NSMutableArray *playlist = [photos mutableCopy];
        if ([[PFPhotoService sharedService] configuration].playbackMode == PFPlaybackModeRandom) {
            for (NSUInteger i = playlist.count; i > 1; i--) [playlist exchangeObjectAtIndex:i - 1 withObjectAtIndex:arc4random_uniform((u_int32_t)i)];
        }
        self.photos = playlist;
        self.nextIndex = 0;
        self.hasCurrentPhoto = NO;
        if (currentRemotePath.length) {
            for (NSUInteger i = 0; i < playlist.count; i++) {
                PFPhoto *photo = playlist[i];
                if ([photo.remotePath isEqualToString:currentRemotePath]) {
                    self.currentIndex = i;
                    self.nextIndex = (i + 1) % playlist.count;
                    self.hasCurrentPhoto = YES;
                    break;
                }
            }
        }
        if (!playlist.count) {
            if (self.lastScanError) {
                [self showStatus:[NSString stringWithFormat:PFL(@"player.status.scanFailed"), self.lastScanError.localizedDescription]];
            } else if (requestScanWhenEmpty) {
                [self showStatus:PFL(@"player.status.scanning")];
                [[PFPhotoService sharedService] requestScan];
            } else {
                [self showStatus:PFL(@"player.status.noSupportedPhotos")];
            }
        } else if (advance && !self.loading) [self advance];
    }];
}

- (void)advance {
    if (self.loading || self.photos.count == 0) return;
    self.loading = YES;
    [self loadPhotoStartingAtIndex:self.nextIndex direction:1 attempts:self.photos.count generation:self.generation];
}

- (void)goBack {
    if (self.loading || self.photos.count == 0) return;
    self.loading = YES;
    NSUInteger startIndex = self.hasCurrentPhoto ?
        (self.currentIndex + self.photos.count - 1) % self.photos.count :
        (self.nextIndex + self.photos.count - 1) % self.photos.count;
    [self loadPhotoStartingAtIndex:startIndex direction:-1 attempts:self.photos.count generation:self.generation];
}

- (void)loadPhotoStartingAtIndex:(NSUInteger)index direction:(NSInteger)direction attempts:(NSUInteger)attempts generation:(NSUInteger)generation {
    if (!attempts || !self.photos.count) {
        self.loading = NO;
        [self showStatus:PFL(@"player.status.photosUnavailable")];
        [self scheduleNextAfter:30.0];
        return;
    }
    NSUInteger candidateIndex = index % self.photos.count;
    PFPhoto *photo = self.photos[candidateIndex];
    NSUInteger followingIndex = direction > 0 ?
        (candidateIndex + 1) % self.photos.count :
        (candidateIndex + self.photos.count - 1) % self.photos.count;
    CGFloat maximum = MAX(CGRectGetWidth([UIScreen mainScreen].bounds), CGRectGetHeight([UIScreen mainScreen].bounds));
    maximum *= [UIScreen mainScreen].scale;
    [[PFPhotoService sharedService] loadImageForPhoto:photo maximumPixelSize:maximum completion:^(UIImage *image, NSDictionary *metadata, NSError *error) {
        if (generation != self.generation) return;
        if (!image) {
            [self loadPhotoStartingAtIndex:followingIndex direction:direction attempts:attempts - 1 generation:generation];
            return;
        }
        self.currentIndex = candidateIndex;
        self.hasCurrentPhoto = YES;
        self.nextIndex = (candidateIndex + 1) % self.photos.count;
        NSTimeInterval slideDuration = [[PFPhotoService sharedService] configuration].slideDuration;
        [self displayImage:image metadata:metadata panDuration:slideDuration];
        self.loading = NO;
        [self showStatus:nil];
        [self scheduleNextAfter:slideDuration];
    }];
}

- (void)displayImage:(UIImage *)image metadata:(NSDictionary *)metadata panDuration:(NSTimeInterval)panDuration {
    UIImageView *incoming = self.firstIsVisible ? self.secondImageView : self.firstImageView;
    UIImageView *outgoing = self.firstIsVisible ? self.firstImageView : self.secondImageView;
    [incoming.layer removeAllAnimations];
    incoming.image = image;
    incoming.alpha = 0.0;
    self.panStartTime = CACurrentMediaTime();
    self.panEndTime = self.panStartTime + panDuration;
    self.currentPanReversed = arc4random_uniform(2) == 1;
    self.currentKenBurnsZoomIn = arc4random_uniform(2) == 1;
    [self configurePanForImageView:incoming progress:0.0 remainingDuration:panDuration];
    [self displayPhotoInfo:metadata forImage:image];
    [UIView animateWithDuration:1.0 animations:^{ incoming.alpha = 1.0; outgoing.alpha = 0.0; } completion:^(BOOL finished) {
        UIImageView *visible = self.firstIsVisible ? self.firstImageView : self.secondImageView;
        if (outgoing != visible) {
            [outgoing.layer removeAllAnimations];
            outgoing.image = nil;
            outgoing.layer.contentsRect = CGRectMake(0.0, 0.0, 1.0, 1.0);
        }
    }];
    self.firstIsVisible = !self.firstIsVisible;
}

- (void)configurePanForImageView:(UIImageView *)imageView progress:(CGFloat)progress remainingDuration:(NSTimeInterval)remainingDuration {
    [imageView.layer removeAnimationForKey:@"PFPhotoPan"];
    if (!imageView.image || CGRectGetWidth(self.view.bounds) <= 0.0 || CGRectGetHeight(self.view.bounds) <= 0.0) return;

    CGFloat imageAspect = imageView.image.size.width / MAX(imageView.image.size.height, 1.0);
    CGFloat viewAspect = CGRectGetWidth(self.view.bounds) / CGRectGetHeight(self.view.bounds);
    CGRect startRect = CGRectMake(0.0, 0.0, 1.0, 1.0);
    CGRect endRect = startRect;
    if (imageAspect > viewAspect) {
        CGFloat visibleWidth = viewAspect / imageAspect;
        startRect.size.width = visibleWidth;
        endRect = startRect;
        endRect.origin.x = 1.0 - visibleWidth;
    } else if (imageAspect < viewAspect) {
        CGFloat visibleHeight = imageAspect / viewAspect;
        startRect.size.height = visibleHeight;
        endRect = startRect;
        endRect.origin.y = 1.0 - visibleHeight;
    }

    PFConfiguration *configuration = [[PFPhotoService sharedService] configuration];
    BOOL hasOverflow = !CGRectEqualToRect(startRect, endRect);
    if (!configuration.photoPanEnabled || !hasOverflow) {
        CGRect centeredRect = startRect;
        centeredRect.origin.x = (startRect.origin.x + endRect.origin.x) * 0.5;
        centeredRect.origin.y = (startRect.origin.y + endRect.origin.y) * 0.5;
        startRect = centeredRect;
        endRect = centeredRect;
    } else if (self.currentPanReversed) {
        CGRect swap = startRect;
        startRect = endRect;
        endRect = swap;
    }

    // Photos that overflow the screen use panning only. Ken Burns is reserved
    // for photos that already fit the screen crop, so the effects never stack.
    if (configuration.kenBurnsEnabled && !hasOverflow) {
        NSTimeInterval totalDuration = MAX(self.panEndTime - self.panStartTime, 0.0);
        // Keep the zoom deliberately subtle. Short slides receive an even
        // smaller change so the perceived zoom speed always remains gentle.
        CGFloat zoomAmount = MIN(0.035, MAX(0.005, totalDuration * 0.0015));
        CGFloat zoomScale = 1.0 - zoomAmount;
        CGRect zoomedStart = CGRectInset(startRect,
                                         CGRectGetWidth(startRect) * (1.0 - zoomScale) * 0.5,
                                         CGRectGetHeight(startRect) * (1.0 - zoomScale) * 0.5);
        CGRect zoomedEnd = CGRectInset(endRect,
                                       CGRectGetWidth(endRect) * (1.0 - zoomScale) * 0.5,
                                       CGRectGetHeight(endRect) * (1.0 - zoomScale) * 0.5);
        if (self.currentKenBurnsZoomIn) {
            endRect = zoomedEnd;
        } else {
            startRect = zoomedStart;
        }
    }

    if (CGRectEqualToRect(startRect, endRect)) {
        imageView.layer.contentsRect = startRect;
        return;
    }

    CGRect currentRect = startRect;
    currentRect.origin.x += (endRect.origin.x - startRect.origin.x) * progress;
    currentRect.origin.y += (endRect.origin.y - startRect.origin.y) * progress;
    currentRect.size.width += (endRect.size.width - startRect.size.width) * progress;
    currentRect.size.height += (endRect.size.height - startRect.size.height) * progress;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    imageView.layer.contentsRect = endRect;
    [CATransaction commit];

    if (remainingDuration > 0.0) {
        CABasicAnimation *pan = [CABasicAnimation animationWithKeyPath:@"contentsRect"];
        pan.fromValue = [NSValue valueWithCGRect:currentRect];
        pan.toValue = [NSValue valueWithCGRect:endRect];
        pan.duration = remainingDuration;
        pan.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        [imageView.layer addAnimation:pan forKey:@"PFPhotoPan"];
    }
}

- (void)displayPhotoInfo:(NSDictionary *)metadata forImage:(UIImage *)image {
    ++self.photoInfoGeneration;
    if (![[PFPhotoService sharedService] configuration].photoInfoEnabled) {
        self.photoInfoLabel.hidden = YES;
        return;
    }

    NSDate *date = metadata[@"date"];
    NSString *embeddedLocation = metadata[@"location"];
    NSNumber *latitude = metadata[@"latitude"];
    NSNumber *longitude = metadata[@"longitude"];
    [self updatePhotoInfoDate:date location:embeddedLocation image:image];
    if (embeddedLocation.length || !latitude || !longitude) return;
    // Include a format version so locations cached before the administrative
    // area was added do not keep displaying the old "city · country" form.
    NSString *localization = [[[NSBundle mainBundle] preferredLocalizations] firstObject] ?: @"zh-Hans";
    NSString *cacheKey = [NSString stringWithFormat:@"v3:%@:%.2f,%.2f", localization, latitude.doubleValue, longitude.doubleValue];
    NSString *cachedLocation = [self.locationCache objectForKey:cacheKey];
    if (cachedLocation.length) {
        [self updatePhotoInfoDate:date location:cachedLocation image:image];
        return;
    }

    NSUInteger generation = self.photoInfoGeneration;
    // CLGeocoder is network-backed and delivers its completion on the main
    // thread.  Reusing and cancelling one geocoder for every slide can wedge
    // the iOS 8 main run loop after the service becomes unresponsive.  Keep
    // slideshow progress independent of that legacy service: the bundled city
    // database runs on its own serial queue and needs no network connection.
    [PFOfflineGeocoder nearestCityForLatitude:latitude.doubleValue longitude:longitude.doubleValue completion:^(NSString *offlineLocation) {
        NSString *fallback = offlineLocation.length ? offlineLocation :
            [self coordinateTextWithLatitude:latitude.doubleValue longitude:longitude.doubleValue];
        if (offlineLocation.length) {
            [self.locationCache setObject:offlineLocation forKey:cacheKey];
            [self persistLocation:offlineLocation forCacheKey:cacheKey];
        }
        if (generation == self.photoInfoGeneration) [self updatePhotoInfoDate:date location:fallback image:image];
    }];
}

- (void)persistLocation:(NSString *)location forCacheKey:(NSString *)cacheKey {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *saved = [[defaults dictionaryForKey:@"PFReverseGeocodeCache"] mutableCopy] ?: [NSMutableDictionary dictionary];
    saved[cacheKey] = location;
    while (saved.count > 300) [saved removeObjectForKey:[[saved allKeys] firstObject]];
    [defaults setObject:saved forKey:@"PFReverseGeocodeCache"];
    [defaults synchronize];
}

- (NSString *)coordinateTextWithLatitude:(double)latitude longitude:(double)longitude {
    return [NSString stringWithFormat:@"%.4f°%@, %.4f°%@",
            fabs(latitude), latitude >= 0.0 ? @"N" : @"S",
            fabs(longitude), longitude >= 0.0 ? @"E" : @"W"];
}

- (void)updatePhotoInfoDate:(NSDate *)date location:(NSString *)location image:(UIImage *)image {
    NSMutableArray *lines = [NSMutableArray array];
    if (date) {
        static NSDateFormatter *formatter = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            formatter = [[NSDateFormatter alloc] init];
            formatter.locale = PFLocalizationLocale();
            formatter.dateStyle = NSDateFormatterLongStyle;
            formatter.timeStyle = NSDateFormatterShortStyle;
        });
        [lines addObject:[formatter stringFromDate:date]];
    }
    if (location.length) [lines addObject:location];
    self.photoInfoLabel.text = [lines componentsJoinedByString:@"\n"];
    self.photoInfoLabel.hidden = lines.count == 0;
    if (self.photoInfoLabel.hidden) return;

    CGFloat luminance = [self bottomLeftLuminanceForImage:image];
    BOOL useDarkText = luminance > 0.58;
    self.photoInfoLabel.textColor = useDarkText ? [UIColor colorWithWhite:0.05 alpha:0.92] : [UIColor colorWithWhite:1.0 alpha:0.95];
    self.photoInfoLabel.layer.shadowOpacity = useDarkText ? 0.0 : 0.9;
    self.photoInfoLabel.shadowColor = useDarkText ? [UIColor clearColor] : [UIColor colorWithWhite:0.0 alpha:0.9];
    self.photoInfoLabel.shadowOffset = CGSizeMake(1.0, 1.0);
    [self.view setNeedsLayout];
}

- (CGFloat)bottomLeftLuminanceForImage:(UIImage *)image {
    CGImageRef source = image.CGImage;
    if (!source) return 0.0;
    size_t width = CGImageGetWidth(source);
    size_t height = CGImageGetHeight(source);
    CGFloat imageAspect = (CGFloat)width / MAX((CGFloat)height, 1.0);
    CGFloat viewAspect = CGRectGetWidth(self.view.bounds) / MAX(CGRectGetHeight(self.view.bounds), 1.0);
    CGRect visibleRect = CGRectMake(0.0, 0.0, 1.0, 1.0);
    if (imageAspect > viewAspect) {
        visibleRect.size.width = viewAspect / imageAspect;
        visibleRect.origin.x = (1.0 - visibleRect.size.width) * 0.5;
    } else if (imageAspect < viewAspect) {
        visibleRect.size.height = imageAspect / viewAspect;
        visibleRect.origin.y = (1.0 - visibleRect.size.height) * 0.5;
    }
    CGRect sampleRect = CGRectMake((visibleRect.origin.x + visibleRect.size.width * 0.02) * width,
                                   (visibleRect.origin.y + visibleRect.size.height * 0.72) * height,
                                   MAX(visibleRect.size.width * width * 0.42, 1.0),
                                   MAX(visibleRect.size.height * height * 0.25, 1.0));
    CGImageRef sample = CGImageCreateWithImageInRect(source, sampleRect);
    if (!sample) return 0.0;
    unsigned char pixels[8 * 8 * 4] = {0};
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, 8, 8, 8, 8 * 4, colorSpace,
                                                  kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!context) { CGImageRelease(sample); return 0.0; }
    CGContextSetInterpolationQuality(context, kCGInterpolationLow);
    CGContextDrawImage(context, CGRectMake(0.0, 0.0, 8.0, 8.0), sample);
    CGContextRelease(context);
    CGImageRelease(sample);
    double total = 0.0;
    for (NSUInteger index = 0; index < 8 * 8; index++) {
        CGFloat red = pixels[index * 4] / 255.0;
        CGFloat green = pixels[index * 4 + 1] / 255.0;
        CGFloat blue = pixels[index * 4 + 2] / 255.0;
        total += 0.2126 * red + 0.7152 * green + 0.0722 * blue;
    }
    return (CGFloat)(total / (8.0 * 8.0));
}

- (void)scheduleNextAfter:(NSTimeInterval)interval {
    [self.slideTimer invalidate];
    self.slideTimer = [NSTimer scheduledTimerWithTimeInterval:MAX(interval, 3.0) target:self selector:@selector(slideTimerFired:) userInfo:nil repeats:NO];
}

- (void)slideTimerFired:(NSTimer *)timer { [self advance]; }

- (void)showStatus:(NSString *)status {
    self.statusLabel.text = status;
    self.statusLabel.hidden = status.length == 0;
    if (status.length) [self.view setNeedsLayout];
}

- (void)memoryWarning:(NSNotification *)notification {
    UIImageView *hidden = self.firstIsVisible ? self.secondImageView : self.firstImageView;
    [hidden.layer removeAllAnimations];
    hidden.image = nil;
}

@end
