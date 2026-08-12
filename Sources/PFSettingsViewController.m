#import "PFSettingsViewController.h"
#import "PFConfiguration.h"
#import "PFCredentialStore.h"
#import "PFPhotoService.h"
#import "PFLocalization.h"

@interface PFSettingsViewController ()
@property (nonatomic, strong) PFConfiguration *configuration;
@property (nonatomic, strong) NSArray *fields;
@property (nonatomic, strong) UISwitch *randomSwitch;
@property (nonatomic, strong) UISwitch *swipeNavigationSwitch;
@property (nonatomic, strong) UISwitch *photoPanSwitch;
@property (nonatomic, strong) UISwitch *kenBurnsSwitch;
@property (nonatomic, strong) UISwitch *photoInfoSwitch;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSDictionary *indexSummary;
@end

@implementation PFSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = PFL(@"settings.title");
    self.configuration = [[PFPhotoService sharedService] configuration];
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.94 alpha:1.0];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:PFL(@"common.save") style:UIBarButtonItemStyleDone target:self action:@selector(save:)];
    if (self.allowsCancel) self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)];

    UITextField *host = [self field:PFL(@"settings.placeholder.host") value:self.configuration.host secure:NO keyboard:UIKeyboardTypeNumbersAndPunctuation];
    UITextField *share = [self field:PFL(@"settings.placeholder.share") value:self.configuration.share secure:NO keyboard:UIKeyboardTypeDefault];
    UITextField *root = [self field:PFL(@"settings.placeholder.root") value:self.configuration.rootPath secure:NO keyboard:UIKeyboardTypeDefault];
    UITextField *domain = [self field:PFL(@"settings.placeholder.domain") value:self.configuration.domain secure:NO keyboard:UIKeyboardTypeDefault];
    UITextField *user = [self field:PFL(@"settings.placeholder.username") value:self.configuration.username secure:NO keyboard:UIKeyboardTypeDefault];
    UITextField *password = [self field:PFL(@"settings.placeholder.password") value:[PFCredentialStore password] secure:YES keyboard:UIKeyboardTypeDefault];
    UITextField *duration = [self field:PFL(@"settings.placeholder.minimum3") value:[NSString stringWithFormat:@"%.0f", self.configuration.slideDuration] secure:NO keyboard:UIKeyboardTypeDecimalPad];
    UITextField *hours = [self field:PFL(@"settings.placeholder.minimum025") value:[NSString stringWithFormat:@"%.1f", self.configuration.scanInterval / 3600.0] secure:NO keyboard:UIKeyboardTypeDecimalPad];
    UITextField *cache = [self field:PFL(@"settings.placeholder.minimum01") value:[NSString stringWithFormat:@"%.1f", self.configuration.cacheLimitBytes / (1024.0 * 1024.0 * 1024.0)] secure:NO keyboard:UIKeyboardTypeDecimalPad];
    [self setUnit:PFL(@"unit.seconds") forField:duration];
    [self setUnit:PFL(@"unit.hours") forField:hours];
    [self setUnit:@"GB" forField:cache];
    self.fields = @[host, share, root, domain, user, password, duration, hours, cache];
    self.randomSwitch = [[UISwitch alloc] init];
    self.randomSwitch.on = self.configuration.playbackMode == PFPlaybackModeRandom;
    self.swipeNavigationSwitch = [[UISwitch alloc] init];
    self.swipeNavigationSwitch.on = self.configuration.swipeNavigationEnabled;
    self.photoPanSwitch = [[UISwitch alloc] init];
    self.photoPanSwitch.on = self.configuration.photoPanEnabled;
    self.kenBurnsSwitch = [[UISwitch alloc] init];
    self.kenBurnsSwitch.on = self.configuration.kenBurnsEnabled;
    self.photoInfoSwitch = [[UISwitch alloc] init];
    self.photoInfoSwitch.on = self.configuration.photoInfoEnabled;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.navigationItem.titleView = nil;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scanFinished:) name:PFPhotoServiceScanDidFinishNotification object:nil];
    [self refreshIndexSummary];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UITextField *)field:(NSString *)placeholder value:(NSString *)value secure:(BOOL)secure keyboard:(UIKeyboardType)keyboard {
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];
    field.placeholder = placeholder;
    field.text = value;
    field.secureTextEntry = secure;
    field.keyboardType = keyboard;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.textAlignment = NSTextAlignmentRight;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    return field;
}

- (void)setUnit:(NSString *)unit forField:(UITextField *)field {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 0.0, 52.0, 36.0)];
    label.text = [NSString stringWithFormat:@"  %@", unit];
    label.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
    label.font = [UIFont systemFontOfSize:15.0];
    label.textAlignment = NSTextAlignmentLeft;
    field.rightView = label;
    field.rightViewMode = UITextFieldViewModeAlways;
}

- (UITextField *)inputFieldAtIndex:(NSUInteger)index {
    return (UITextField *)[self.fields objectAtIndex:index];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 5; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0 || section == 1) return 4;
    if (section == 2) return 2;
    if (section == 3) return 6;
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[PFL(@"settings.section.summary"), PFL(@"settings.section.nas"), PFL(@"settings.section.account"), PFL(@"settings.section.playback"), PFL(@"settings.section.maintenance")][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return PFL(@"settings.footer.summary");
    if (section == 1) return PFL(@"settings.footer.nas");
    if (section == 3) return PFL(@"settings.footer.playback");
    if (section == 4) return PFL(@"settings.footer.maintenance");
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCellStyle style = indexPath.section == 0 ? UITableViewCellStyleValue1 : UITableViewCellStyleDefault;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSArray *titles = @[
        @[PFL(@"settings.row.indexed"), PFL(@"settings.row.nasPhotos"), PFL(@"settings.row.dateRange"), PFL(@"settings.row.lastIndex")],
        @[PFL(@"settings.row.server"), PFL(@"settings.row.share"), PFL(@"settings.row.photoDirectory"), PFL(@"settings.row.domain")],
        @[PFL(@"settings.row.username"), PFL(@"settings.row.password")],
        @[PFL(@"settings.row.random"), PFL(@"settings.row.swipe"), PFL(@"settings.row.pan"), PFL(@"settings.row.kenBurns"), PFL(@"settings.row.photoInfo"), PFL(@"settings.row.slideInterval")],
        @[PFL(@"settings.row.scanInterval"), PFL(@"settings.row.cacheLimit"), PFL(@"settings.row.testConnection")]
    ];
    cell.textLabel.text = titles[indexPath.section][indexPath.row];
    if (indexPath.section == 0) {
        cell.detailTextLabel.text = [self indexDetailAtRow:indexPath.row];
        cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
        cell.detailTextLabel.minimumScaleFactor = 0.7;
    } else if (indexPath.section == 3 && indexPath.row == 0) {
        cell.accessoryView = self.randomSwitch;
    } else if (indexPath.section == 3 && indexPath.row == 1) {
        cell.accessoryView = self.swipeNavigationSwitch;
    } else if (indexPath.section == 3 && indexPath.row == 2) {
        cell.accessoryView = self.photoPanSwitch;
    } else if (indexPath.section == 3 && indexPath.row == 3) {
        cell.accessoryView = self.kenBurnsSwitch;
    } else if (indexPath.section == 3 && indexPath.row == 4) {
        cell.accessoryView = self.photoInfoSwitch;
    } else if (indexPath.section == 4 && indexPath.row == 2) {
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryView = self.spinner;
    } else {
        NSInteger fieldIndex = indexPath.section == 1 ? indexPath.row :
            (indexPath.section == 2 ? 4 + indexPath.row :
             (indexPath.section == 3 ? 1 + indexPath.row : 7 + indexPath.row));
        UITextField *field = [self inputFieldAtIndex:fieldIndex];
        field.frame = CGRectMake(0, 0, 390, 36);
        cell.accessoryView = field;
    }
    return cell;
}

- (NSString *)indexDetailAtRow:(NSInteger)row {
    NSUInteger indexedCount = [self.indexSummary[@"count"] unsignedIntegerValue];
    if (row == 0) return self.indexSummary ? [NSString stringWithFormat:PFL(indexedCount == 1 ? @"format.photoCount.one" : @"format.photoCount.other"), (unsigned long)indexedCount] : PFL(@"common.loading");
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSTimeInterval lastScan = [defaults doubleForKey:@"PFLastSuccessfulScan"];
    if (row == 1) {
        NSUInteger nasCount = [defaults objectForKey:@"PFLastSuccessfulPhotoCount"] ?
            (NSUInteger)[defaults integerForKey:@"PFLastSuccessfulPhotoCount"] : indexedCount;
        return (lastScan > 0 || self.indexSummary) ? [NSString stringWithFormat:PFL(nasCount == 1 ? @"format.photoCount.one" : @"format.photoCount.other"), (unsigned long)nasCount] : PFL(@"common.none");
    }
    if (row == 3) return lastScan > 0 ? [self formattedDate:[NSDate dateWithTimeIntervalSinceReferenceDate:lastScan]] : PFL(@"settings.neverIndexed");
    NSTimeInterval earliest = [self.indexSummary[@"earliestTime"] doubleValue];
    NSTimeInterval latest = [self.indexSummary[@"latestTime"] doubleValue];
    if (indexedCount == 0 || earliest <= 0 || latest <= 0) return self.indexSummary ? PFL(@"common.none") : PFL(@"common.loading");
    NSString *first = [self formattedDate:[NSDate dateWithTimeIntervalSince1970:earliest]];
    NSString *last = [self formattedDate:[NSDate dateWithTimeIntervalSince1970:latest]];
    return [first isEqualToString:last] ? first : [NSString stringWithFormat:@"%@ — %@", first, last];
}

- (NSString *)formattedDate:(NSDate *)date {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = PFLocalizationLocale();
        formatter.dateStyle = NSDateFormatterShortStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
    });
    return [formatter stringFromDate:date];
}

- (void)refreshIndexSummary {
    [[PFPhotoService sharedService] indexSummaryWithCompletion:^(NSDictionary *summary) {
        self.indexSummary = summary;
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
    }];
}

- (void)scanFinished:(NSNotification *)notification {
    [self refreshIndexSummary];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 4 && indexPath.row == 2) [self testConnection];
}

- (PFConfiguration *)configurationFromFields {
    PFConfiguration *configuration = [self.configuration copy];
    configuration.host = [[[self inputFieldAtIndex:0] text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    configuration.share = [[[self inputFieldAtIndex:1] text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    configuration.rootPath = [[[self inputFieldAtIndex:2] text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    configuration.domain = [[[self inputFieldAtIndex:3] text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    configuration.username = [[[self inputFieldAtIndex:4] text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    configuration.slideDuration = MAX([[[self inputFieldAtIndex:6] text] doubleValue], 3.0);
    configuration.scanInterval = MAX([[[self inputFieldAtIndex:7] text] doubleValue] * 3600.0, 15.0 * 60.0);
    double gigabytes = MAX([[[self inputFieldAtIndex:8] text] doubleValue], 0.1);
    configuration.cacheLimitBytes = (unsigned long long)(gigabytes * 1024.0 * 1024.0 * 1024.0);
    configuration.playbackMode = self.randomSwitch.on ? PFPlaybackModeRandom : PFPlaybackModeSequential;
    configuration.swipeNavigationEnabled = self.swipeNavigationSwitch.on;
    configuration.photoPanEnabled = self.photoPanSwitch.on;
    configuration.kenBurnsEnabled = self.kenBurnsSwitch.on;
    configuration.photoInfoEnabled = self.photoInfoSwitch.on;
    return configuration;
}

- (NSString *)validationMessageForConfiguration:(PFConfiguration *)configuration {
    if (!configuration.host.length) return PFL(@"settings.validation.host");
    if (!configuration.share.length) return PFL(@"settings.validation.share");
    if (!configuration.username.length) return PFL(@"settings.validation.username");
    if (![[[self inputFieldAtIndex:5] text] length]) return PFL(@"settings.validation.password");
    return nil;
}

- (void)save:(id)sender {
    PFConfiguration *configuration = [self configurationFromFields];
    NSString *message = [self validationMessageForConfiguration:configuration];
    if (message) { [self showMessage:PFL(@"settings.alert.incomplete") detail:message]; return; }
    NSError *error = nil;
    if (![PFCredentialStore savePassword:[[self inputFieldAtIndex:5] text] error:&error]) {
        [self showMessage:PFL(@"settings.alert.passwordSaveFailed") detail:error.localizedDescription]; return;
    }
    [configuration save];
    [[PFPhotoService sharedService] applyConfiguration:configuration];
    if (self.saveHandler) self.saveHandler(configuration);
    if (self.closeHandler) self.closeHandler();
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)testConnection {
    PFConfiguration *configuration = [self configurationFromFields];
    NSString *message = [self validationMessageForConfiguration:configuration];
    if (message) { [self showMessage:PFL(@"settings.alert.incomplete") detail:message]; return; }
    [self.spinner startAnimating];
    self.view.userInteractionEnabled = NO;
    [[PFPhotoService sharedService] testConfiguration:configuration password:[[self inputFieldAtIndex:5] text] completion:^(NSError *error) {
        [self.spinner stopAnimating];
        self.view.userInteractionEnabled = YES;
        [self showMessage:error ? PFL(@"settings.alert.connectionFailed") : PFL(@"settings.alert.connectionSucceeded") detail:error ? error.localizedDescription : PFL(@"settings.alert.connectionSucceededDetail")];
    }];
}

- (void)cancel:(id)sender {
    if (self.closeHandler) self.closeHandler();
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showMessage:(NSString *)title detail:(NSString *)detail {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:detail preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:PFL(@"common.ok") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
