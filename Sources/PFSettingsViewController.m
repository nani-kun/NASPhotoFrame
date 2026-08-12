#import "PFSettingsViewController.h"
#import "PFConfiguration.h"
#import "PFCredentialStore.h"
#import "PFPhotoService.h"

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
    self.title = @"NAS 相框设置";
    self.configuration = [[PFPhotoService sharedService] configuration];
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.94 alpha:1.0];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save:)];
    if (self.allowsCancel) self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)];

    UITextField *host = [self field:@"例如 192.168.1.10" value:self.configuration.host secure:NO keyboard:UIKeyboardTypeNumbersAndPunctuation];
    UITextField *share = [self field:@"共享名，例如 Photos" value:self.configuration.share secure:NO keyboard:UIKeyboardTypeDefault];
    UITextField *root = [self field:@"子目录，可留空" value:self.configuration.rootPath secure:NO keyboard:UIKeyboardTypeDefault];
    UITextField *domain = [self field:@"工作组/域，可留空" value:self.configuration.domain secure:NO keyboard:UIKeyboardTypeDefault];
    UITextField *user = [self field:@"SMB 用户名" value:self.configuration.username secure:NO keyboard:UIKeyboardTypeDefault];
    UITextField *password = [self field:@"SMB 密码" value:[PFCredentialStore password] secure:YES keyboard:UIKeyboardTypeDefault];
    UITextField *duration = [self field:@"最少 3" value:[NSString stringWithFormat:@"%.0f", self.configuration.slideDuration] secure:NO keyboard:UIKeyboardTypeDecimalPad];
    UITextField *hours = [self field:@"最少 0.25" value:[NSString stringWithFormat:@"%.1f", self.configuration.scanInterval / 3600.0] secure:NO keyboard:UIKeyboardTypeDecimalPad];
    UITextField *cache = [self field:@"最少 0.1" value:[NSString stringWithFormat:@"%.1f", self.configuration.cacheLimitBytes / (1024.0 * 1024.0 * 1024.0)] secure:NO keyboard:UIKeyboardTypeDecimalPad];
    [self setUnit:@"秒" forField:duration];
    [self setUnit:@"小时" forField:hours];
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
    return @[@"照片概况", @"NAS 地址", @"账户（密码保存在 Keychain）", @"播放", @"维护"][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"日期范围使用 NAS 文件的“创建时间”字段。";
    if (section == 1) return @"仅填写共享名，不要写 smb://；NAS 需启用 SMB2 或 SMB3。";
    if (section == 3) return @"超出屏幕的照片只做随机方向的缓慢平移；其他照片可使用小幅度 Ken Burns。地点优先在线转换，失败时使用 GeoNames 离线城市数据（CC BY 4.0）。";
    if (section == 4) return @"扫描、下载、建索引和图片解码均在后台执行。长按播放画面可再次打开设置。";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCellStyle style = indexPath.section == 0 ? UITableViewCellStyleValue1 : UITableViewCellStyleDefault;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSArray *titles = @[
        @[@"已索引照片", @"NAS 照片", @"拍摄时间范围", @"最近索引"],
        @[@"服务器", @"共享", @"照片目录", @"域/工作组"],
        @[@"用户名", @"密码"],
        @[@"随机播放", @"滑动切换", @"照片缓慢滑动", @"Ken Burns 效果", @"显示拍摄信息", @"切换间隔"],
        @[@"扫描间隔", @"缓存上限", @"连接测试"]
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
    if (row == 0) return self.indexSummary ? [NSString stringWithFormat:@"%lu 张", (unsigned long)indexedCount] : @"读取中…";
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSTimeInterval lastScan = [defaults doubleForKey:@"PFLastSuccessfulScan"];
    if (row == 1) {
        NSUInteger nasCount = [defaults objectForKey:@"PFLastSuccessfulPhotoCount"] ?
            (NSUInteger)[defaults integerForKey:@"PFLastSuccessfulPhotoCount"] : indexedCount;
        return (lastScan > 0 || self.indexSummary) ? [NSString stringWithFormat:@"%lu 张", (unsigned long)nasCount] : @"暂无";
    }
    if (row == 3) return lastScan > 0 ? [self formattedDate:[NSDate dateWithTimeIntervalSinceReferenceDate:lastScan]] : @"尚未成功索引";
    NSTimeInterval earliest = [self.indexSummary[@"earliestTime"] doubleValue];
    NSTimeInterval latest = [self.indexSummary[@"latestTime"] doubleValue];
    if (indexedCount == 0 || earliest <= 0 || latest <= 0) return self.indexSummary ? @"暂无" : @"读取中…";
    NSString *first = [self formattedDate:[NSDate dateWithTimeIntervalSince1970:earliest]];
    NSString *last = [self formattedDate:[NSDate dateWithTimeIntervalSince1970:latest]];
    return [first isEqualToString:last] ? first : [NSString stringWithFormat:@"%@ — %@", first, last];
}

- (NSString *)formattedDate:(NSDate *)date {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm";
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
    if (!configuration.host.length) return @"请输入 NAS 的 IP 地址或主机名。";
    if (!configuration.share.length) return @"请输入 SMB 共享名。";
    if (!configuration.username.length) return @"请输入 SMB 用户名。";
    if (![[[self inputFieldAtIndex:5] text] length]) return @"请输入 SMB 密码。";
    return nil;
}

- (void)save:(id)sender {
    PFConfiguration *configuration = [self configurationFromFields];
    NSString *message = [self validationMessageForConfiguration:configuration];
    if (message) { [self showMessage:@"设置不完整" detail:message]; return; }
    NSError *error = nil;
    if (![PFCredentialStore savePassword:[[self inputFieldAtIndex:5] text] error:&error]) {
        [self showMessage:@"无法保存密码" detail:error.localizedDescription]; return;
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
    if (message) { [self showMessage:@"设置不完整" detail:message]; return; }
    [self.spinner startAnimating];
    self.view.userInteractionEnabled = NO;
    [[PFPhotoService sharedService] testConfiguration:configuration password:[[self inputFieldAtIndex:5] text] completion:^(NSError *error) {
        [self.spinner stopAnimating];
        self.view.userInteractionEnabled = YES;
        [self showMessage:error ? @"连接失败" : @"连接成功" detail:error ? error.localizedDescription : @"账户有效，并且照片目录可以访问。"];
    }];
}

- (void)cancel:(id)sender {
    if (self.closeHandler) self.closeHandler();
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showMessage:(NSString *)title detail:(NSString *)detail {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:detail preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
