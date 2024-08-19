//
//  YPLogTool.m
//  YPLogToolPro
//
//  Created by zyp on 2022/7/26.
//


#import "QNVCCYPLoggerTool.h"
#import <CommonCrypto/CommonCrypto.h>



// 日志数据模型
@implementation YPLogContentModel

- (void)setValue:(id)value forUndefinedKey:(NSString *)key {
    
}


- (void)setTimeStr:(NSString *)timeStr {
    _timeStr = timeStr;
    _timeStrUTF8 = [timeStr UTF8String];
}

- (void)setFmtLogLevelStr:(NSString *)fmtLogLevelStr {
    _fmtLogLevelStr = fmtLogLevelStr;
    _fmtLogLevelStrUTF8 = [fmtLogLevelStr UTF8String];
}

- (void)setPrintLogLevelFlag:(NSString *)printLogLevelFlag {
    _printLogLevelFlag = printLogLevelFlag;
    _printLogLevelFlagUTF8 = [printLogLevelFlag UTF8String];
}

- (void)setKeyIdentifierStr:(NSString *)keyIdentifierStr {
    _keyIdentifierStr = keyIdentifierStr;
    _keyIdentifierStrUTF8 = [keyIdentifierStr UTF8String];
}

- (void)setFile:(NSString *)file {
    _file = file;
    _fileUTF8 = [file UTF8String];
}

- (void)setThreadFlag:(NSString *)threadFlag {
    _threadFlag = threadFlag;
    _threadFlagUTF8 = [threadFlag UTF8String];
}

- (void)setFunction:(NSString *)function {
    _function = function;
    _functionUTF8 = [function UTF8String];
}

- (void)setFunctionName:(NSString *)functionName {
    _functionName = functionName;
    _functionNameUTF8 = [functionName UTF8String];
}

- (void)setFormat:(NSString *)format {
    _format = format;
    _formatUTF8 = [format UTF8String];
}




@end




// 日志工具类
@implementation QNVCCYPLoggerTool

// AES 加密key值
const NSString *yp_AESKey = @"abcdefghABCDEFGH";

// 存储所有用户日志的根文件夹 - 内涵所有用户文件夹
static NSString *yp_saveLogsPath;
/**
 * 最大存储日志文件大小(Mb)
 * 默认值为50Mb
 * 即当日志文件总大小高于100Mb时，会触发自动清理最早的日志文件
 * - 注意：如果设置了『yp_maxSaveDays』强制保留期天数， 则不会自动清除处于保留天数内的日志文件
 */
static float yp_maxFoldSize = 100;

/**
 * 最长保留最近『yp_maxSaveDays』天数内的日志  - - - 时间限制 优先级 高于空间限制
 * 默认保留30天当日志文件
 * 当大于『maxFoldSize』Mb时，如最早期的日志文件仍如处于『yp_maxSaveDays』天数范围内，优先保留，不会触发自动清除
 */
static int yp_maxSaveDays = 30;


// 当前允许写入的日志级别
static YP_LOG_LEVEL_TYPE yp_allowWriteLogLevel = YP_LOG_LEVEL_DEBUG;
// 当前日志所在的用户文件夹名称（用户唯一标识-根据此绑定标识，创建用户文件夹）
static NSString *yp_curUserIdentifier = @"DefaultUser";
// 是否脱敏的开关 (日志以密文的形式写入文件夹)
static BOOL yp_onSecure = NO;
// 当前用户所在的文件夹路径
static NSString *yp_curUserDirectoryPath = nil;
// 临时存储不需要清理的用户文件夹名称 数组 => [@"DefaultUser", ...]
static NSMutableArray *yp_tempNoClearUserDirectoryNames = nil;
// 开始启用日志工具时的日期 => 20220727
static NSString *yp_useBeginTimeDayStr = nil;
// 记录所有调用过日志打印的数组 - - - 不会做清空等处理 - 只用于记录
static NSMutableArray <YPLogContentModel *> *yp_logAllModelsDataArr = nil;

// 当次启用日志工具后写入文件的日志的总次数
static long long yp_writeLogTimes = 0;
// 写入日志的串行队列
static dispatch_queue_t yp_logWriteProcessingQueue;

// 用来缓存当次日志工具启用后的所有需要写入文件的日志内容
static NSMutableArray <YPLogContentModel *> *yp_logWriteModelsDataArr = nil;

// 用来缓存当次日志工具启用后的输出到Xcode控制台的所有日志内容
static NSMutableArray <YPLogContentModel *> *yp_logPrintModelsDataArr = nil;

// 当次启用日志工具后输出到控制台的日志的总次数
static long long yp_printLogTimes = 0;
// 轮询定时器 - 触发打印任务
static dispatch_source_t yp_loopCheckTimer;


#pragma mark -
#pragma mark - 🔥 public Methods 🔥 公共方法

// MARK: - initialize 初始化方法
+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 初始化成功变量
        [QNVCCYPLoggerTool initMembers];
        
        // 创建保存日志文件的文件夹路径 => 默认:/Library/Log/QNVCCSDKLogs/DefaultUser/  => yp_saveLogsPath/DefaultUser
        [QNVCCYPLoggerTool yp_createSaveDirectory];
        // 监听异常Crash
        [QNVCCYPLoggerTool yp_monitorCrashExceptionHandler];
    });
}

#pragma mark -
#pragma mark - ⭐️ methods ⭐️
//MARK: - initMembers 初始化一些必要变量
+ (void)initMembers {
    // 日志写入文件相关
    yp_saveLogsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Log/QNVCCSDKLogs"];
    yp_logAllModelsDataArr = [NSMutableArray array];
    yp_logWriteModelsDataArr = [NSMutableArray array];
    yp_logPrintModelsDataArr = [NSMutableArray array];
    yp_tempNoClearUserDirectoryNames = [NSMutableArray array];
    yp_writeLogTimes = [[NSUserDefaults standardUserDefaults] objectForKey:@"yp_writeLogTimesKey"] ? [[[NSUserDefaults standardUserDefaults] objectForKey:@"yp_writeLogTimesKey"] longLongValue] : 0;
    
    
    // 创建串行队列 - 用于写入日志
    yp_logWriteProcessingQueue = dispatch_queue_create("com.ypLoggerTool.yp_logProcessingQueue", DISPATCH_QUEUE_SERIAL);
    // 将串行队列 - 指定为后台优先级队列 - 尽可能的确保它们不会与主线程上的UI更新操作竞争CPU时间
    dispatch_set_target_queue(yp_logWriteProcessingQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
    // 使用后台优先级的全局队列作为定时器的执行队列
    dispatch_queue_t timerQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    // 创建并配置定时器
    yp_loopCheckTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, timerQueue);
    uint64_t interval = (uint64_t)(1 * NSEC_PER_SEC); // 例如，每1秒触发一次
    dispatch_time_t start = dispatch_time(DISPATCH_TIME_NOW, 0);
    
    dispatch_source_set_timer(yp_loopCheckTimer, start, interval, 0);
    dispatch_source_set_event_handler(yp_loopCheckTimer, ^{
        if (!yp_logWriteModelsDataArr.count) return;
        dispatch_async(yp_logWriteProcessingQueue, ^{
            [QNVCCYPLoggerTool yp_logWriteProcessingQueue];
        });
    });
    // 启动定时器
    dispatch_resume(yp_loopCheckTimer);
    
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(yp_appWillTerminate:) name:UIApplicationWillTerminateNotification object:nil];
}

//MARK: - 程序将要关闭时 - 清理资源
+ (void)yp_appWillTerminate:(NSNotification *)nt {
    dispatch_source_cancel(yp_loopCheckTimer);
    yp_loopCheckTimer = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

//MARK: - yp_setSaveLogsPath: 设置日志存储的外层路径
+ (void)yp_setSaveLogsPath:(NSString *)saveLogsPath {
    yp_saveLogsPath = [NSHomeDirectory() stringByAppendingPathComponent:saveLogsPath];
    [QNVCCYPLoggerTool yp_createSaveDirectory];
}

//MARK: - yp_setWriteLogLevel: 设置 高于 此日志级别的日志 才需要写入文件 默认为 YP_LOG_LEVEL_DEBUG
+ (void)yp_setWriteLogLevel:(YP_LOG_LEVEL_TYPE)writelogLevel {
    yp_allowWriteLogLevel = writelogLevel;
}

//MARK: - yp_bindUserIndentifier: 绑定日志文件夹用户名称
+ (void)yp_bindUserIndentifier:(NSString *)userIndentifier {
    yp_curUserIdentifier = (userIndentifier && userIndentifier.length) ? userIndentifier : @"DefaultUser";
}

//MARK: - yp_setMaxFoldSize: 设置日志最大存储空间
+ (void)yp_setMaxFoldSize:(CGFloat)maxFoldSize {
    yp_maxFoldSize = maxFoldSize;
}

//MARK: - yp_setMaxSaveDays: 设置日志最长保留时间
+ (void)yp_setMaxSaveDays:(int)maxSaveDays {
    yp_maxSaveDays = maxSaveDays;
}

//MARK: - yp_switchSecure: 脱敏开关设置
+ (void)yp_switchSecure:(BOOL)onSecure {
    yp_onSecure = onSecure;
}


//MARK: - yp_logWriteProcessingQueue 后台处理队列中的待写入文件的日志
+ (void)yp_logWriteProcessingQueue {
    // 确保线程安全
    dispatch_barrier_async(yp_logWriteProcessingQueue, ^{
        if (!yp_logWriteModelsDataArr.count) return;
        // 拼接多行日志
        NSMutableString *multiLinesLog = [NSMutableString string];
        [yp_logWriteModelsDataArr enumerateObjectsUsingBlock:^(YPLogContentModel *obj, NSUInteger index, BOOL *stop) {
            if (obj.fullLogContent && obj.fullLogContent.length > 0) {
                [multiLinesLog appendString:obj.fullLogContent];
            }
        }];
        // 拼接多行日志之后，再执行一次写入 - 降低I/O效率
        [QNVCCYPLoggerTool yp_writeLogWithContentModel:yp_logWriteModelsDataArr.firstObject multiLinesLog:multiLinesLog];
        // 执行完成后，清空一下数组
        [yp_logWriteModelsDataArr removeAllObjects];
        
    });
}

//MARK: - yp_logWithLevel: keyIdentifiers: file: line: function: format: 打印日志核心方法 缓存日志数据 等待后台线程去实现打印与写入
+ (void)yp_logWithLevel:(YP_LOG_LEVEL_TYPE)logLevel keyIdentifiers:(NSArray <NSString *> *)keyIdentifiers file:(NSString *)file line:(NSUInteger)line function:(NSString *)function format:(NSString *)format {
    NSString *timeStr = [QNVCCYPLoggerTool yp_getFormatTimeStr];
    NSString *fmtLogLevelStr = [QNVCCYPLoggerTool yp_getFormatLogLevelStrWithLevel:logLevel];
    NSString *keyIdentifierStr = [QNVCCYPLoggerTool yp_getFormatKeyIdentifiersString:keyIdentifiers];
    NSString *functionName = function;
    if ([function containsString:@" "]) {
        functionName = [function componentsSeparatedByString:@" "][1];
        if ([functionName containsString:@"]"])
            functionName = [functionName componentsSeparatedByString:@"]"][0];
    }
    BOOL isMainThread = [[NSThread currentThread] isMainThread];
    NSString *threadFlag = isMainThread ? @"Main" : @"Thread";
    NSString *printLogLevelFlag = logLevel == YP_LOG_LEVEL_VERBOSE || logLevel == YP_LOG_LEVEL_INFO ? @"❄️" : logLevel == YP_LOG_LEVEL_DEBUG ? @"🐭" : logLevel == YP_LOG_LEVEL_WARN ? @"⚠️" : logLevel == YP_LOG_LEVEL_ERROR ? @"❌" : @"";
    // 去除自定义控制台特殊标记，高频调用会出现转码异常
    printLogLevelFlag = @"";
    
    // 格式化日志数据 - 存入对象中
    YPLogContentModel *model = [YPLogContentModel new];
    model.timeStr = timeStr;
    model.logLevel = logLevel;
    model.printLogLevelFlag = printLogLevelFlag;
    model.fmtLogLevelStr = fmtLogLevelStr;
    model.keyIdentifiers = keyIdentifiers;
    model.keyIdentifierStr = keyIdentifierStr;
    model.file = file;
    model.line = line;
    model.threadFlag = threadFlag;
    model.function = function;
    model.functionName = functionName;
    model.format = format;
    NSString *fullLogContent = [QNVCCYPLoggerTool yp_getFmtFullLogContentStr:model];
    model.fullLogContent = fullLogContent;
    UIColor *fontColor = logLevel <= YP_LOG_LEVEL_INFO ? [UIColor blackColor] : logLevel == YP_LOG_LEVEL_WARN ? [UIColor yellowColor] : logLevel == YP_LOG_LEVEL_ERROR ? [UIColor redColor] : [UIColor blackColor];
    model.fontColor = fontColor;
    
    
    // 确保线程安全
    dispatch_barrier_async(yp_logWriteProcessingQueue, ^{
        // 所有的日志对象缓存
        [yp_logAllModelsDataArr addObject:model];
        // 允许写入文件的日志对象缓存
        if (model.logLevel >= yp_allowWriteLogLevel) {
            [yp_logWriteModelsDataArr addObject:model];
        }
        // 触发了阈值，触发一次写入
        if (yp_logWriteModelsDataArr.count >= 50) {
            [QNVCCYPLoggerTool yp_logWriteProcessingQueue];
        }
    });
    
#if DEBUG
    // DEBUG 模式下输出到控制台
    [QNVCCYPLoggerTool yp_printLogWithContentModel:model];
#endif
}

//MARK: - yp_getFormatTimeStr 获取格式化好的时间字符串 =》@"2022-07-27 14:44:32:888"
+ (NSString *)yp_getFormatTimeStr {
    // 曾考虑日志复杂性，使用日历类 - 实际使用中，没有用到 - 换用效率更高的NSDateFormatter对象
    //    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    //    NSInteger unitFlags = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitWeekday |
    //    NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond | NSCalendarUnitNanosecond;
    //    NSDateComponents *comps  = [calendar components:unitFlags fromDate:[NSDate date]];
    //    // 格式化时间
    //    NSString *nanosencondStr = [NSString stringWithFormat:@"%ld", (long)comps.nanosecond];
    //    if (nanosencondStr.length > 3) {
    //        nanosencondStr = [nanosencondStr substringToIndex:3];
    //    }
    //    NSString *timeStr = [NSString stringWithFormat:@"%ld-%02ld-%02ld %02ld:%02ld:%02ld:%@", (long)comps.year, (long)comps.month, (long)comps.day, (long)comps.hour, (long)comps.minute, (long)comps.second, nanosencondStr];
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timeStr = [formatter stringFromDate:[NSDate date]];
    
    return timeStr;
}

//MARK: - yp_getFormatLogLevelStrWithLevel: 格式化日志等级为字符串
+ (NSString *)yp_getFormatLogLevelStrWithLevel:(YP_LOG_LEVEL_TYPE)logLevel {
    switch (logLevel) {
        case YP_LOG_LEVEL_VERBOSE:
            return @"VERBOSE";
            break;
        case YP_LOG_LEVEL_DEBUG:
            return @"DEBUG";
            break;
        case YP_LOG_LEVEL_INFO:
            return @"INFO";
            break;
        case YP_LOG_LEVEL_WARN:
            return @"WARN";
            break;
        case YP_LOG_LEVEL_ERROR:
            return @"ERROR";
            break;
            
        default:
            return @"UNKNOWN";
            break;
    }
}
//MARK: - yp_getFormatKeyIdentifiersString: 格式化关键字标识为字符串
+ (NSString *)yp_getFormatKeyIdentifiersString:(NSArray <NSString *> *)keyIdentifiers {
    NSMutableString *formatResult = [NSMutableString stringWithString:@""];
    if (!keyIdentifiers.count) {
        return formatResult;
    }
    [keyIdentifiers enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (idx != keyIdentifiers.count - 1) {
            [formatResult appendFormat:@"[%@] ", obj];
        }else {
            [formatResult appendFormat:@"[%@]", obj];
        }
    }];
    
    return formatResult;
}


//MARK: - yp_getFmtFullLogContentStr: 格式化拼接好完整的日志内容String
+ (NSString *)yp_getFmtFullLogContentStr:(YPLogContentModel *)model {
    NSString *logStr;
    NSString *format = model.format;
    
//    // - GM4 日志加密
//    NSString *logKey = [NSString stringWithFormat:@"%@", [QNVCCManager sharedManager].logEncryptKey];
//    if (![[QNVCCManager sharedManager] stringIsNull:logKey]) {// 需要 国密加密写入
//        if (![format isEqualToString:@"\n"]) { // 非换行符 - 再加密
//            format = [GMSm4Utils ecbEncryptText:format key:[QNVCCManager sharedManager].logEncryptKey];
//        }
//        
//    }else { // 无需国密 加密
//        if (yp_onSecure) { // 需要内置 aes 脱敏
//            if (![format isEqualToString:@"\n"]) { // 非换行符 - 再加密
//                format = [self yp_aesEncrypt:model.format];
//            }
//        }
//    }
    
    if (model.keyIdentifierStr.length) {
        logStr = [NSString stringWithFormat:@"[%@] [%@] %@ [%@:%lu] [%@] [%@] :%@\n", model.timeStr, model.fmtLogLevelStr, model.keyIdentifierStr, model.file, (unsigned long)model.line, model.functionName, model.threadFlag, format];
    }else {
        logStr = [NSString stringWithFormat:@"[%@] [%@] [%@:%lu] [%@] [%@] :%@\n", model.timeStr, model.fmtLogLevelStr, model.file, (unsigned long)model.line, model.functionName, model.threadFlag, format];
    }
    
    return logStr;
}


//MARK: - yp_getAllLogContents 获取当前打印的所有日志信息
+ (NSArray <YPLogContentModel *> *)yp_getAllLogContents {
    return yp_logAllModelsDataArr;
}



//MARK: - yp_createSaveDirectory 创建保存日志的文件夹 => 默认:Library/Log/QNVCCSDKLogs/DefaultUser
+ (void)yp_createSaveDirectory {
    NSString *timeStr = [QNVCCYPLoggerTool yp_getFormatTimeStr];
    yp_useBeginTimeDayStr = [[timeStr componentsSeparatedByString:@" "][0] stringByReplacingOccurrencesOfString:@"-" withString:@""];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    yp_curUserDirectoryPath = [yp_saveLogsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@", yp_curUserIdentifier]];
    if (![fileManager fileExistsAtPath:yp_curUserDirectoryPath]) {
        NSError *error = nil;
        [fileManager createDirectoryAtPath:yp_curUserDirectoryPath withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            YPLogError(@"用户存储日志文件夹路径创建失败 errorInfo: %@", error.domain);
        }else {
            YPLogInfo(@"用户存储日志文件夹路径创建成功!");
        }
    }
}


//MARK: - yp_setSecureAesKey: 设置密文加密时用到的key 16位
+ (void)yp_setSecureAesKey:(NSString *)aesKey {
    yp_AESKey = aesKey;
}

//MARK: - yp_aesEncrypt: AES+Key加密
+ (NSString *)yp_aesEncrypt:(NSString *)sourceStr {
    if (!sourceStr) {
        return nil;
    }
    char keyPtr[kCCKeySizeAES256 + 1];
    bzero(keyPtr, sizeof(keyPtr));
    [yp_AESKey getCString:keyPtr maxLength:sizeof(keyPtr) encoding:NSUTF8StringEncoding];
    
    NSData *sourceData = [sourceStr dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger dataLength = [sourceData length];
    size_t buffersize = dataLength + kCCBlockSizeAES128;
    void *buffer = malloc(buffersize);
    size_t numBytesEncrypted = 0;
    CCCryptorStatus cryptStatus = CCCrypt(kCCEncrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding | kCCOptionECBMode, keyPtr, kCCBlockSizeAES128, NULL, [sourceData bytes], dataLength, buffer, buffersize, &numBytesEncrypted);
    
    if (cryptStatus == kCCSuccess) {
        NSData *encryptData = [NSData dataWithBytesNoCopy:buffer length:numBytesEncrypted];
        //对加密后的二进制数据进行base64转码
        return [encryptData base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed];
    } else {
        free(buffer);
        return nil;
    }
}

//MARK: - yp_decryptAES: AES+Key解密
+ (NSString *)yp_decryptAES:(NSString *)content key:(NSString *)key {
    //为结束符'\0' +1
    char keyPtr[[key length]+1];//kCCKeySizeAES128,kCCKeySizeAES256
    memset(keyPtr, 0, sizeof(keyPtr));
    [key getCString:keyPtr maxLength:sizeof(keyPtr) encoding:NSUTF8StringEncoding];
    
    //1，string转Data Base64解密（系统方法）
    NSData *contentData = [[NSData alloc]initWithBase64EncodedString:content options:0];
    NSUInteger contentDataLength = [contentData length];
    //密文长度 <= 明文程度 + BlockSize
    size_t bufferSize = contentDataLength + kCCBlockSizeAES128;//key：16位
    void *buffer = malloc(bufferSize);
    size_t numBytesDecrypted = 0;
    CCCryptorStatus cryptStatus = CCCrypt(kCCDecrypt,
                                          kCCAlgorithmAES,
                                          kCCOptionPKCS7Padding | kCCOptionECBMode,//ECB
                                          keyPtr,//key
                                          [key length],//key.length=16（kCCBlockSizeAES128）
                                          NULL,//ECB时iv为空
                                          contentData.bytes,
                                          contentDataLength,
                                          buffer,
                                          bufferSize,
                                          &numBytesDecrypted);
    if (cryptStatus == kCCSuccess) {
        //2，Data转Data 解密
        NSData *dataOut = [NSData dataWithBytesNoCopy:buffer length:numBytesDecrypted];
        //3，Data转string UTF8
        NSString *decryptStr = [[NSString alloc] initWithData:dataOut encoding:NSUTF8StringEncoding];
        return decryptStr;
    }
    free(buffer);
    return nil;
}



//MARK: - yp_printLogWithContentModel: 将缓存的待输出到Xcode控制台的日志内容 输出到Xcode控制台
+ (void)yp_printLogWithContentModel:(YPLogContentModel *)contentModel {
    yp_printLogTimes ++;
    if (contentModel.keyIdentifierStr.length) {
        fprintf(contentModel.logLevel == YP_LOG_LEVEL_ERROR ? stderr : stdout,"%s [%s] [%s] %s [%s:%lu] [%s] [%s] :%s\n",contentModel.printLogLevelFlagUTF8, contentModel.timeStrUTF8, contentModel.fmtLogLevelStrUTF8, contentModel.keyIdentifierStrUTF8, contentModel.fileUTF8, (unsigned long)contentModel.line, contentModel.functionNameUTF8, contentModel.threadFlagUTF8, contentModel.formatUTF8);
    }else {
        fprintf(contentModel.logLevel == YP_LOG_LEVEL_ERROR ? stderr : stdout,"%s [%s] [%s] [%s:%lu] [%s] [%s] :%s\n",contentModel.printLogLevelFlagUTF8, contentModel.timeStrUTF8, contentModel.fmtLogLevelStrUTF8, contentModel.fileUTF8, (unsigned long)contentModel.line, contentModel.functionNameUTF8, contentModel.threadFlagUTF8, contentModel.formatUTF8);
    }
    if (!(yp_printLogTimes % 5000)) { //
        if (contentModel.logLevel == YP_LOG_LEVEL_ERROR) {
            fflush(stderr);
        }else {
            fflush(stdout);
        }
    }
}

//MARK: - yp_writeLogWithContentModel: 将缓存的待写入的日志内容 写入文件
+ (void)yp_writeLogWithContentModel:(YPLogContentModel *)contentModel multiLinesLog:(NSString *)linesLog {
    // 校验下轮转清理
    NSString *curDayStr = [[contentModel.timeStr componentsSeparatedByString:@" "][0] stringByReplacingOccurrencesOfString:@"-" withString:@""];
    if (yp_useBeginTimeDayStr && (![curDayStr isEqualToString:yp_useBeginTimeDayStr])) {// 当启用日志组件时的日期 与 当前打印日志时的日期 不一致时  && 当前打印日志时的日期有值 ， 即跨夜了...
        YPLogWarn(@"少年好厉害,决战到天亮！跨夜时间:【%@->%@】", yp_useBeginTimeDayStr, curDayStr);
        yp_useBeginTimeDayStr = curDayStr;
        if (yp_tempNoClearUserDirectoryNames) {
            [yp_tempNoClearUserDirectoryNames removeAllObjects];
        }
    }
    
    NSError *error = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    //写入文件的路径 => /yp_curUserDirectoryPath/YPLog_DefaultUser_20220727.log
    NSString *filePath = [yp_curUserDirectoryPath stringByAppendingPathComponent:[NSString stringWithFormat:@"YPLog_%@_%@.log", yp_curUserIdentifier, curDayStr]];
    if(![fileManager fileExistsAtPath:filePath]) {// 如果日志文件不存在 - 创建并写入日志文件
        [linesLog writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (error) {
            YPLogError(@"日志信息写入文件失败,errorInfo: %@ 对应日志内容:%@", error.domain, contentModel.fullLogContent);
        }
        
    }else {// 日志文件存在 - 则继续追加写入
        NSFileHandle *fileHandle;
        @try {
            fileHandle = [NSFileHandle fileHandleForUpdatingAtPath:filePath];
            [fileHandle seekToEndOfFile];
            NSData* stringData = [linesLog dataUsingEncoding:NSUTF8StringEncoding];
            [fileHandle writeData:stringData];
            [fileHandle synchronizeFile];
            
        } @catch (NSException *exception) {
            
        } @finally {
            // 确保句柄被有效关闭
            [fileHandle closeFile];
        }
    }
    
    // 打印日志写入 次数 ++
    yp_writeLogTimes ++;
    [[NSUserDefaults standardUserDefaults] setObject:[NSString stringWithFormat:@"%lld", (long long)yp_writeLogTimes] forKey:@"yp_writeLogTimesKey"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    if (!(yp_writeLogTimes % 10000)) {// 每10000次打印，校验一回文件大小相关问题，降低频率，增加性能   => 实测 10000次大概是1.*Mb左右
    FILE_SIZE_CHECK_LOOP: {// 当前日志文件的总大小跟可以支持的最大文件夹大小相比 循环辨识
        // 当前文件夹下所有的日志文件的容量 **.Mb
        float curFileSize = [QNVCCYPLoggerTool yp_getTotalLogsSizeMb];
        if (curFileSize >= yp_maxFoldSize) { // 总大小 >= 可存储的最大容量 => 有可能会产品日志文件销毁的审查
        FILE_EARLIEST_LOOP: { // 校验最小文件夹 循环标识
            // 获取除了不足 [yp_forceSaveDays] 天数用户文件夹 以外的最小文件夹路径 => /yp_curUserDirectoryPath/YPLog_DefaultUser_20220727.log
            NSString *earliestFilePath = [QNVCCYPLoggerTool yp_getEarliestLogFilePath];
            if ([earliestFilePath isEqualToString:@"NoFilePath"]) {// 没有获取到最小文件夹
                return;
            }
            // => @[@"Library", @"Caches", @"YPLogs", @"DefaultUser", @"YPLog_DefaultUser_20220727.log"]
            NSMutableArray *temp = [NSMutableArray arrayWithArray:[earliestFilePath componentsSeparatedByString:@"/"]];
            // => @[@"Library", @"Caches", @"YPLogs", @"DefaultUser"]
            [temp removeLastObject];
            // => yp_curUserDirectoryPath
            NSString *earliestUserPath = [temp componentsJoinedByString:@"/"];
            // 获取对应用户文件夹下的日志文件数量
            NSInteger userLogsCount = [QNVCCYPLoggerTool yp_getUserPathLogsCount:earliestUserPath];
            if (userLogsCount > yp_maxSaveDays) {// 对应用户文件夹下的日志文件数量 > 强制保留文件个数 => 可以删除
                if ([fileManager fileExistsAtPath:earliestFilePath]) {
                    [fileManager removeItemAtPath:earliestFilePath error:nil];
                    //                    YPWLogInfo(@"发现符合条件的日志文件，已清理:%@", [earliestFilePath componentsSeparatedByString:@"/"].lastObject);
                    // 删除最早的文件夹之后，再去校验是否还大于 可存储的最大容量...
                    goto FILE_SIZE_CHECK_LOOP;
                }
                
            }else { //对应用户文件夹下的日志文件数量 <= 强制保留文件个数 => 无需删除日志文件
                // => DefaultUser
                NSString *userDirectoryName = temp.lastObject;
                // => 将无需删除的用户文件夹名称 - 添加到临时的存储数组中
                [yp_tempNoClearUserDirectoryNames addObject:userDirectoryName];
                // 当前最早的日志文件无需删除 -> 再去校验其他用户文件下的最早的日志可不可以删除...
                goto FILE_EARLIEST_LOOP;
            }
        }
        }
    }
    }
    
}



//MARK: - yp_getTotalLogsSizeMb 获取所有日志文件的总容量 return *Mb
+ (float)yp_getTotalLogsSizeMb {
    long long folderSize = 0;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:yp_saveLogsPath]) {
        return 0.0;
    }
    // => /yp_saveLogsPath/*  文件夹下的枚举器
    NSEnumerator *logsFilesEnumerator = [[fileManager subpathsAtPath:yp_saveLogsPath] objectEnumerator];
    // DefaultUser ... DefaultUser/YPLog_DefaultUser_20220727.log
    NSString *pathName;
    while ((pathName = [logsFilesEnumerator nextObject]) != nil) {
        if ([pathName hasSuffix:@".log"]) { //是日志文件 => DefaultUser/YPLog_DefaultUser_20220727.log
            // => /yp_saveLogsPath/DefaultUser/YPLog_DefaultUser_20220727.log
            NSString *logFilePath = [yp_saveLogsPath stringByAppendingPathComponent:pathName];
            folderSize += [QNVCCYPLoggerTool yp_fileSizeAtPath:logFilePath];
        }
    }
    
    float totalSize = folderSize / (1000.0 * 1000.0);
    YPLogInfo(@"current total logs filesize:%lld, ≈:%fMb", folderSize, totalSize);
    return totalSize;
}

//MARK: - yp_fileSizeAtPath: 计算单一路径下的文件的大小
+ (long long)yp_fileSizeAtPath:(NSString *)filePath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:filePath]) {
        return [fileManager attributesOfItemAtPath:filePath error:nil].fileSize;
    }
    return 0;
}

//MARK: - yp_getEarliestLogFilePath 获取最早的日志文件路径 => /yp_saveLogsPath/DefaultUser/YPLog_DefaultUser_20220727.log
+ (NSString *)yp_getEarliestLogFilePath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    // => /yp_saveLogsPath/*/*/..   文件夹下的枚举器
    NSEnumerator *logsFilesEnumerator = [[fileManager subpathsAtPath:yp_saveLogsPath] objectEnumerator];
    // DefaultUser ... DefaultUser/YPLog_DefaultUser_20220727.log
    NSString *pathName;
    
    int minDay = 22161231;
    NSString *earliestFilePath = @"NoFilePath";
    
    while ((pathName = [logsFilesEnumerator nextObject]) != nil) {
        if ([pathName hasSuffix:@".log"]) { //是日志文件 => DefaultUser/YPLog_DefaultUser_20220727.log
            // 文件夹名称 => DefaultUser
            NSString *userDirectoryName = [pathName componentsSeparatedByString:@"/"][0];
            if (![yp_tempNoClearUserDirectoryNames containsObject:userDirectoryName]) {// 已忽略不清除的用户文件夹名称数组中 不包含当前文件夹名称
                // => /yp_saveLogsPath/DefaultUser/YPLog_DefaultUser_20220727.log
                NSString *logFilePath = [yp_saveLogsPath stringByAppendingPathComponent:pathName];
                int day = [[[[pathName componentsSeparatedByString:@"/"][1] componentsSeparatedByString:@"_"].lastObject componentsSeparatedByString:@"."][0] intValue];
                if (day < minDay) {
                    minDay = day;
                    earliestFilePath = logFilePath;
                }
            }
        }
    }
    
    return earliestFilePath;
}

//MARK: - yp_getUserPathLogsCount: 获取用户路径下的日志文件个数
+ (NSInteger)yp_getUserPathLogsCount:(NSString *)userPath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSEnumerator *childFilesEnumerator = [[fileManager subpathsAtPath:userPath] objectEnumerator];
    return childFilesEnumerator.allObjects.count;
}

//MARK: - yp_monitorCrashExceptionHandler 监听crash、捕捉异常
+ (void)yp_monitorCrashExceptionHandler {
    static BOOL _hasMonitor = NO;
    if (!_hasMonitor) {
        // 取消监听信号
        //        struct sigaction newSignalAction;
        //        memset(&newSignalAction, 0,sizeof(newSignalAction));
        //        newSignalAction.sa_handler = &yp_signalHandler;
        //        sigaction(SIGABRT, &newSignalAction, NULL); // 异常终止请求
        //        sigaction(SIGILL, &newSignalAction, NULL); // 非法指令
        //        sigaction(SIGSEGV, &newSignalAction, NULL); // 段错误
        //        sigaction(SIGFPE, &newSignalAction, NULL); // 浮点异常
        //        sigaction(SIGBUS, &newSignalAction, NULL); // 总线错误，可能是因为非法的内存访问
        //        sigaction(SIGPIPE, &newSignalAction, NULL); // 管道写入错误，可能是因为管道另一端的接收方已经关闭
        
        NSSetUncaughtExceptionHandler(&yp_handleExceptions);
        _hasMonitor = YES;
    }
    
}
//MARK: - yp_signalHandler
void yp_signalHandler(int sig) {
    // 退出程序前可以添加一些清理操作
    // YPLogError(@"crash signal = %d", sig);
    // ...
    // _exit(1); // 确保程序退出
}

//MARK: - yp_handleExceptions
void yp_handleExceptions(NSException *exception) {
    YPLogError(@"crash exception = %@",exception);
    YPLogError(@"crash callStackSymbols = %@",[exception callStackSymbols]);
    
}






@end
