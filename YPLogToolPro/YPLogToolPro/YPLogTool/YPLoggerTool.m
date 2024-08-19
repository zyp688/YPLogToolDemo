//
//  YPLogTool.m
//  YPLogToolPro
//
//  Created by zyp on 2022/7/26.
//


#import "YPLoggerTool.h"
#import <CommonCrypto/CommonCrypto.h>
#include <pthread.h>
#include <string.h>


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
@interface YPLoggerTool ()


@end

@implementation YPLoggerTool


const NSString *yp_AESKey = @"abcdefghABCDEFGH";


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


static dispatch_source_t yp_loopCheckTimer;


static YP_LOG_LEVEL_TYPE yp_allowWriteLogLevel = YP_LOG_LEVEL_DEBUG;

static NSString *yp_curUserIdentifier = @"DefaultUser";

static BOOL yp_onSecure = NO;

static NSString *yp_curUserDirectoryPath = nil;

static NSMutableArray *yp_tempNoClearUserDirectoryNames = nil;

static NSString *yp_useBeginTimeDayStr = nil;

static NSMutableArray <YPLogContentModel *> *yp_logAllModelsDataArr = nil;


static long long yp_writeLogTimes = 0;

static dispatch_queue_t yp_logWriteProcessingQueue;


static NSMutableArray <YPLogContentModel *> *yp_logWriteModelsDataArr = nil;


static long long yp_printLogTimes = 0;

#pragma mark -
#pragma mark - 🔥 public Methods 🔥 公共方法

// MARK: - initialize 初始化方法
+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        [YPLoggerTool initMembers];
        
        
        [YPLoggerTool yp_createSaveDirectory];
        
        [YPLoggerTool yp_monitorCrashExceptionHandler];
    });
}


#pragma mark -
#pragma mark - ⭐️ methods ⭐️
//MARK: - initMembers
+ (void)initMembers {
    
    yp_saveLogsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/YPLogs"];
    yp_logWriteModelsDataArr = [NSMutableArray array];
    yp_tempNoClearUserDirectoryNames = [NSMutableArray array];
    
    yp_logWriteProcessingQueue = dispatch_queue_create("com.ypLoggerTool.yp_logProcessingQueue", DISPATCH_QUEUE_SERIAL);
    
    dispatch_set_target_queue(yp_logWriteProcessingQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
    yp_writeLogTimes = [[NSUserDefaults standardUserDefaults] objectForKey:@"yp_writeLogTimesKey"] ? [[[NSUserDefaults standardUserDefaults] objectForKey:@"yp_writeLogTimesKey"] longLongValue] : 0;
    
    dispatch_queue_t timerQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    
    yp_loopCheckTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, timerQueue);
    uint64_t interval = (uint64_t)(1 * NSEC_PER_SEC);
    dispatch_time_t start = dispatch_time(DISPATCH_TIME_NOW, 0);
    
    dispatch_source_set_timer(yp_loopCheckTimer, start, interval, 0);
    dispatch_source_set_event_handler(yp_loopCheckTimer, ^{
        if (!yp_logWriteModelsDataArr.count) return;
        dispatch_async(yp_logWriteProcessingQueue, ^{
            [YPLoggerTool yp_logWriteProcessingQueue];
        });
    });
    
    dispatch_resume(yp_loopCheckTimer);
    
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillTerminate:) name:UIApplicationWillTerminateNotification object:nil];
}

//MARK: - appWillTerminate:
+ (void)appWillTerminate:(NSNotification *)nt {
    dispatch_source_cancel(yp_loopCheckTimer);
    yp_loopCheckTimer = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


//MARK: - yp_commitWriteLog
+ (void)yp_commitWriteLog {
    dispatch_async(yp_logWriteProcessingQueue, ^{
        if (!yp_logWriteModelsDataArr.count) return;
        [YPLoggerTool yp_logWriteProcessingQueue];
    });
}

//MARK: - yp_setSaveLogsPath:
+ (void)yp_setSaveLogsPath:(NSString *)saveLogsPath {
    yp_saveLogsPath = [NSHomeDirectory() stringByAppendingPathComponent:saveLogsPath];
    [YPLoggerTool yp_createSaveDirectory];
}

//MARK: - yp_setWriteLogLevel:
+ (void)yp_setWriteLogLevel:(YP_LOG_LEVEL_TYPE)writelogLevel {
    yp_allowWriteLogLevel = writelogLevel;
}

//MARK: - yp_bindUserIndentifier:
+ (void)yp_bindUserIndentifier:(NSString *)userIndentifier {
    yp_curUserIdentifier = (userIndentifier && userIndentifier.length) ? userIndentifier : @"DefaultUser";
}

//MARK: - yp_setMaxFoldSize:
+ (void)yp_setMaxFoldSize:(CGFloat)maxFoldSize {
    yp_maxFoldSize = maxFoldSize;
}

//MARK: - yp_setMaxSaveDays:
+ (void)yp_setMaxSaveDays:(int)maxSaveDays {
    yp_maxSaveDays = maxSaveDays;
}

//MARK: - yp_switchSecure:
+ (void)yp_switchSecure:(BOOL)onSecure {
    yp_onSecure = onSecure;
}


//MARK: - yp_logWriteProcessingQueue
+ (void)yp_logWriteProcessingQueue {
   
    dispatch_barrier_async(yp_logWriteProcessingQueue, ^{
        if (!yp_logWriteModelsDataArr.count) return;

        NSMutableString *multiLinesLog = [NSMutableString string];
        [yp_logWriteModelsDataArr enumerateObjectsUsingBlock:^(YPLogContentModel *obj, NSUInteger index, BOOL *stop) {
            if (obj.fullLogContent && obj.fullLogContent.length > 0) {
                [multiLinesLog appendString:obj.fullLogContent];
            }
        }];
        
        [YPLoggerTool yp_writeLogWithContentModel:yp_logWriteModelsDataArr.firstObject multiLinesLog:multiLinesLog];
        
        [yp_logWriteModelsDataArr removeAllObjects];
        
    });
}

//MARK: - yp_logWithLevel: keyIdentifiers: file: line: function: format:
+ (void)yp_logWithLevel:(YP_LOG_LEVEL_TYPE)logLevel keyIdentifiers:(NSArray <NSString *> *)keyIdentifiers file:(NSString *)file line:(NSUInteger)line function:(NSString *)function format:(NSString *)format {
    NSString *timeStr = [YPLoggerTool yp_getFormatTimeStr];
    NSString *fmtLogLevelStr = [YPLoggerTool yp_getFormatLogLevelStrWithLevel:logLevel];
    NSString *keyIdentifierStr = [YPLoggerTool yp_getFormatKeyIdentifiersString:keyIdentifiers];
    NSString *functionName = function;
    if ([function containsString:@" "]) {
        functionName = [function componentsSeparatedByString:@" "][1];
        if ([functionName containsString:@"]"])
            functionName = [functionName componentsSeparatedByString:@"]"][0];
    }
    BOOL isMainThread = [[NSThread currentThread] isMainThread];
    NSString *threadFlag = isMainThread ? @"Main" : @"Thread";
    NSString *printLogLevelFlag = logLevel == YP_LOG_LEVEL_VERBOSE || logLevel == YP_LOG_LEVEL_INFO ? @"❄️" : logLevel == YP_LOG_LEVEL_DEBUG ? @"🐭" : logLevel == YP_LOG_LEVEL_WARN ? @"⚠️" : logLevel == YP_LOG_LEVEL_ERROR ? @"❌" : @"";
    
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
    NSString *fullLogContent = [YPLoggerTool yp_getFmtFullLogContentStr:model];
    model.fullLogContent = fullLogContent;
    UIColor *fontColor = logLevel <= YP_LOG_LEVEL_INFO ? [UIColor blackColor] : logLevel == YP_LOG_LEVEL_WARN ? [UIColor yellowColor] : logLevel == YP_LOG_LEVEL_ERROR ? [UIColor redColor] : [UIColor blackColor];
    model.fontColor = fontColor;
    
    
    // 确保线程安全
    dispatch_barrier_async(yp_logWriteProcessingQueue, ^{
        
#if DEBUG
        // 所有的日志对象缓存
        if (yp_logAllModelsDataArr)
        {
            [yp_logAllModelsDataArr addObject:model];
        }
#endif
        // 允许写入文件的日志对象缓存
        if (model.logLevel >= yp_allowWriteLogLevel) {
            [yp_logWriteModelsDataArr addObject:model];
        }
        // 触发了阈值，触发一次写入
        if (yp_logWriteModelsDataArr.count >= 50) {
            [YPLoggerTool yp_logWriteProcessingQueue];
        }
    });
    
#if DEBUG
    // DEBUG 模式下输出到控制台
    [YPLoggerTool yp_printLogWithContentModel:model];
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

//MARK: - yp_getFormatLogLevelStrWithLevel:
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
//MARK: - yp_getFormatKeyIdentifiersString:
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


//MARK: - yp_getFmtFullLogContentStr:
+ (NSString *)yp_getFmtFullLogContentStr:(YPLogContentModel *)model {
    NSString *logStr;
    NSString *format = yp_onSecure ? [self yp_aesEncrypt:model.format] : model.format;
    if (model.keyIdentifierStr.length) {
        logStr = [NSString stringWithFormat:@"[%@] [%@] %@ [%@:%lu] [%@] [%@] :%@\n", model.timeStr, model.fmtLogLevelStr, model.keyIdentifierStr, model.file, (unsigned long)model.line, model.functionName, model.threadFlag, format];
    }else {
        logStr = [NSString stringWithFormat:@"[%@] [%@] [%@:%lu] [%@] [%@] :%@\n", model.timeStr, model.fmtLogLevelStr, model.file, (unsigned long)model.line, model.functionName, model.threadFlag, format];
    }
    
    return logStr;
}


//MARK: - yp_getAllLogContents
+ (NSArray <YPLogContentModel *> *)yp_getAllLogContents {
    if (!yp_logAllModelsDataArr) {
        yp_logWriteModelsDataArr = [NSMutableArray array];
    }
    return yp_logAllModelsDataArr;
}



//MARK: - yp_createSaveDirectory
+ (void)yp_createSaveDirectory {
    NSString *timeStr = [YPLoggerTool yp_getFormatTimeStr];
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


//MARK: - yp_setSecureAesKey:
+ (void)yp_setSecureAesKey:(NSString *)aesKey {
    yp_AESKey = aesKey;
}

//MARK: - yp_aesEncrypt:
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
        
        return [encryptData base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed];
    } else {
        free(buffer);
        return nil;
    }
}

//MARK: - yp_decryptAES:
+ (NSString *)yp_decryptAES:(NSString *)content key:(NSString *)key {
    
    char keyPtr[[key length]+1];
    memset(keyPtr, 0, sizeof(keyPtr));
    [key getCString:keyPtr maxLength:sizeof(keyPtr) encoding:NSUTF8StringEncoding];
    
    
    NSData *contentData = [[NSData alloc]initWithBase64EncodedString:content options:0];
    NSUInteger contentDataLength = [contentData length];
    
    size_t bufferSize = contentDataLength + kCCBlockSizeAES128;
    void *buffer = malloc(bufferSize);
    size_t numBytesDecrypted = 0;
    CCCryptorStatus cryptStatus = CCCrypt(kCCDecrypt,
                                          kCCAlgorithmAES,
                                          kCCOptionPKCS7Padding | kCCOptionECBMode,
                                          keyPtr,
                                          [key length],
                                          NULL,
                                          contentData.bytes,
                                          contentDataLength,
                                          buffer,
                                          bufferSize,
                                          &numBytesDecrypted);
    if (cryptStatus == kCCSuccess) {
        
        NSData *dataOut = [NSData dataWithBytesNoCopy:buffer length:numBytesDecrypted];
       
        NSString *decryptStr = [[NSString alloc] initWithData:dataOut encoding:NSUTF8StringEncoding];
        return decryptStr;
    }
    free(buffer);
    return nil;
}



//MARK: - yp_printLogWithContentModel:
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

//MARK: - yp_writeLogWithContentModel:
+ (void)yp_writeLogWithContentModel:(YPLogContentModel *)contentModel multiLinesLog:(NSString *)linesLog{
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
        FILE_SIZE_CHECK_LOOP: {
            
            float curFileSize = [YPLoggerTool yp_getTotalLogsSizeMb];
            if (curFileSize >= yp_maxFoldSize) {
                FILE_EARLIEST_LOOP: {
                    
                    NSString *earliestFilePath = [YPLoggerTool yp_getEarliestLogFilePath];
                    if ([earliestFilePath isEqualToString:@"NoFilePath"]) {
                        return;
                    }
                    
                    NSMutableArray *temp = [NSMutableArray arrayWithArray:[earliestFilePath componentsSeparatedByString:@"/"]];
                    
                    [temp removeLastObject];
                    
                    NSString *earliestUserPath = [temp componentsJoinedByString:@"/"];
                    
                    NSInteger userLogsCount = [YPLoggerTool yp_getUserPathLogsCount:earliestUserPath];
                    if (userLogsCount > yp_maxSaveDays) {
                        if ([fileManager fileExistsAtPath:earliestFilePath]) {
                            [fileManager removeItemAtPath:earliestFilePath error:nil];
                
                            goto FILE_SIZE_CHECK_LOOP;
                        }
                        
                    }else {
                        NSString *userDirectoryName = temp.lastObject;
                        
                        [yp_tempNoClearUserDirectoryNames addObject:userDirectoryName];
                        
                        goto FILE_EARLIEST_LOOP;
                    }
                }
            }
        }
    }
}



//MARK: - yp_getTotalLogsSizeMb
+ (float)yp_getTotalLogsSizeMb {
    long long folderSize = 0;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:yp_saveLogsPath]) {
        return 0.0;
    }
    
    NSEnumerator *logsFilesEnumerator = [[fileManager subpathsAtPath:yp_saveLogsPath] objectEnumerator];
    
    NSString *pathName;
    while ((pathName = [logsFilesEnumerator nextObject]) != nil) {
        if ([pathName hasSuffix:@".log"]) {
            
            NSString *logFilePath = [yp_saveLogsPath stringByAppendingPathComponent:pathName];
            folderSize += [YPLoggerTool yp_fileSizeAtPath:logFilePath];
        }
    }
    
    float totalSize = folderSize / (1000.0 * 1000.0);
    YPLogInfo(@"current total logs filesize:%lld, ≈:%fMb", folderSize, totalSize);
    return totalSize;
}

//MARK: - yp_fileSizeAtPath:
+ (long long)yp_fileSizeAtPath:(NSString *)filePath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:filePath]) {
        return [fileManager attributesOfItemAtPath:filePath error:nil].fileSize;
    }
    return 0;
}

//MARK: - yp_getEarliestLogFilePath
+ (NSString *)yp_getEarliestLogFilePath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSEnumerator *logsFilesEnumerator = [[fileManager subpathsAtPath:yp_saveLogsPath] objectEnumerator];
    
    NSString *pathName;
    
    int minDay = 22161231;
    NSString *earliestFilePath = @"NoFilePath";
    
    while ((pathName = [logsFilesEnumerator nextObject]) != nil) {
        if ([pathName hasSuffix:@".log"]) {
            
            NSString *userDirectoryName = [pathName componentsSeparatedByString:@"/"][0];
            if (![yp_tempNoClearUserDirectoryNames containsObject:userDirectoryName]) {
                
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

//MARK: - yp_getUserPathLogsCount:
+ (NSInteger)yp_getUserPathLogsCount:(NSString *)userPath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSEnumerator *childFilesEnumerator = [[fileManager subpathsAtPath:userPath] objectEnumerator];
    return childFilesEnumerator.allObjects.count;
}

//MARK: - yp_monitorCrashExceptionHandler
+ (void)yp_monitorCrashExceptionHandler {
    static BOOL _hasMonitor = NO;
    if (!_hasMonitor) {
//  取消监听信号
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
    //    _exit(1); // 确保程序退出
}
//MARK: - yp_handleExceptions
void yp_handleExceptions(NSException *exception) {
    YPLogError(@"crash exception = %@",exception);
    YPLogError(@"crash callStackSymbols = %@",[exception callStackSymbols]);
}






@end
