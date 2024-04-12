//
//  YPLogTool.m
//  YPLogToolPro
//
//  Created by zyp on 2022/7/26.
//


#import "YPLoggerTool.h"
#import <CommonCrypto/CommonCrypto.h>

// 日志数据模型
@implementation YPLogContentModel

- (void)setValue:(id)value forUndefinedKey:(NSString *)key {
    
}

@end




// 日志工具类
@implementation YPLoggerTool

const NSString *yp_AESKey = @"abcdefghABCDEFGH";
static NSString *yp_saveLogsPath;
static float yp_maxFoldSize = 50;
static int yp_maxSaveDays = 10;



static YP_LOG_LEVEL_TYPE yp_allowWriteLogLevel = YP_LOG_LEVEL_DEBUG;
static NSString *yp_curUserIdentifier = @"DefaultUser";
static BOOL yp_onSecure = NO;
static NSString *yp_curUserDirectoryPath = nil;
static NSMutableArray *yp_tempNoClearUserDirectoryNames = nil;
static NSString *yp_useBeginTimeDayStr = nil;
static NSMutableArray <YPLogContentModel *> *yp_logAllModelsDataArr = nil;
static long long yp_writeLogTimes = 0;
static dispatch_semaphore_t yp_fileWriteSemaphore;
static NSMutableArray <YPLogContentModel *> *yp_logWriteModelsDataArr = nil;
static dispatch_semaphore_t yp_logPrintSemaphore;
static NSMutableArray <YPLogContentModel *> *yp_logPrintModelsDataArr = nil;

static NSLock *yp_logFmtQueueLock;
static NSLock *yp_logWriteLock;
static NSLock *yp_logPrintLock;

#pragma mark -
#pragma mark - 🔥 public Methods 🔥 公共方法

// 初始化方法
+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [YPLoggerTool initMembers];
        [YPLoggerTool yp_createSaveDirectory];
        [YPLoggerTool yp_monitorCrashExceptionHandler];
        
        dispatch_queue_t yp_logWriteProcessingQueue = dispatch_queue_create("com.ypLogTool.yp_logWriteProcessingQueue", DISPATCH_QUEUE_CONCURRENT);
        dispatch_async(yp_logWriteProcessingQueue, ^{
            while (true) {
                [YPLoggerTool yp_logWriteProcessingQueue];
                sleep(1);
            }
        });
        
        dispatch_queue_t yp_logPrintProcessingQueue = dispatch_queue_create("com.ypLogTool.yp_logPrintProcessingQueue", DISPATCH_QUEUE_CONCURRENT);
        dispatch_async(yp_logPrintProcessingQueue, ^{
            while (true) {
                [YPLoggerTool yp_logPrintProcessingQueue];
                sleep(0.02);
            }
        });
        
        
        
    });
}

#pragma mark -
#pragma mark - ⭐️ methods ⭐️
//MARK: - initMembers
+ (void)initMembers {
    yp_saveLogsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/YPLogs"];
    yp_logAllModelsDataArr = [NSMutableArray array];
    yp_logWriteModelsDataArr = [NSMutableArray array];
    yp_logPrintModelsDataArr = [NSMutableArray array];
    yp_tempNoClearUserDirectoryNames = [NSMutableArray array];
    
    yp_fileWriteSemaphore = dispatch_semaphore_create(1);
    yp_logPrintSemaphore = dispatch_semaphore_create(1);
    yp_logFmtQueueLock = [[NSLock alloc] init];
    yp_logPrintLock = [[NSLock alloc] init];
    yp_logWriteLock = [[NSLock alloc] init];
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

//MARK: -  yp_setMaxSaveDays:
+ (void)yp_setMaxSaveDays:(int)maxSaveDays {
    yp_maxSaveDays = maxSaveDays;
}

//MARK: - yp_switchSecure:
+ (void)yp_switchSecure:(BOOL)onSecure {
    yp_onSecure = onSecure;
}


//MARK: - yp_logWriteProcessingQueue
+ (void)yp_logWriteProcessingQueue {
    dispatch_semaphore_wait(yp_fileWriteSemaphore, DISPATCH_TIME_FOREVER);
    NSMutableArray *tempWriteQueue = [yp_logWriteModelsDataArr mutableCopy];
    [yp_logWriteModelsDataArr removeAllObjects];
    dispatch_semaphore_signal(yp_fileWriteSemaphore);
    [tempWriteQueue enumerateObjectsUsingBlock:^(YPLogContentModel *obj, NSUInteger index, BOOL *stop) {
        [YPLoggerTool yp_writeLogWithContentModel:obj];
    }];
}

//MARK: - yp_logPrintProcessingQueue
+ (void)yp_logPrintProcessingQueue {
    dispatch_semaphore_wait(yp_logPrintSemaphore, DISPATCH_TIME_FOREVER);
    NSMutableArray *tempPrintQueue = [yp_logPrintModelsDataArr mutableCopy];
    [yp_logPrintModelsDataArr removeAllObjects];
    dispatch_semaphore_signal(yp_logPrintSemaphore);
    [tempPrintQueue enumerateObjectsUsingBlock:^(YPLogContentModel *obj, NSUInteger index, BOOL *stop) {
        [YPLoggerTool yp_printLogWithContentModel:obj];
    }];
}

 
//MARK: - yp_logWithLevel: keyIdentifiers: file: line: function: format:
+ (void)yp_logWithLevel:(YP_LOG_LEVEL_TYPE)logLevel keyIdentifiers:(NSArray <NSString *> *)keyIdentifiers file:(NSString *)file line:(NSUInteger)line function:(NSString *)function format:(NSString *)format {
    [yp_logFmtQueueLock lock];
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
    YPLogContentModel *model = [YPLogContentModel new];
    model.timeStr = timeStr;
    model.logLevel = logLevel;
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
    
    [yp_logAllModelsDataArr addObject:model];
    dispatch_semaphore_wait(yp_fileWriteSemaphore, DISPATCH_TIME_FOREVER);
    if (model.logLevel >= yp_allowWriteLogLevel) {
        [yp_logWriteModelsDataArr addObject:model];
    }
    dispatch_semaphore_signal(yp_fileWriteSemaphore);
    
#if DEBUG
    dispatch_semaphore_wait(yp_logPrintSemaphore, DISPATCH_TIME_FOREVER);
    [yp_logPrintModelsDataArr addObject:model];
    dispatch_semaphore_signal(yp_logPrintSemaphore);
#endif
    
    [yp_logFmtQueueLock unlock];
}

//MARK: - yp_getFormatTimeStr
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
            YPLogError(@"用户存储日志文件夹路径创建失败 errorInfo: %@, path:%@", error.domain, yp_curUserDirectoryPath);
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

//MARK: - yp_decryptAES: key:
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
    [yp_logPrintLock lock];
    NSString *logLevelFlag = contentModel.logLevel == YP_LOG_LEVEL_VERBOSE || contentModel.logLevel == YP_LOG_LEVEL_INFO ? @"❄️" : contentModel.logLevel == YP_LOG_LEVEL_DEBUG ? @"🐭" : contentModel.logLevel == YP_LOG_LEVEL_WARN ? @"⚠️" : contentModel.logLevel == YP_LOG_LEVEL_ERROR ? @"❌" : @"";
    logLevelFlag = @"";
    if (contentModel.keyIdentifierStr.length) {
        fprintf(contentModel.logLevel == YP_LOG_LEVEL_ERROR ? stderr : stdout,"%s [%s] [%s] %s [%s:%lu] [%s] [%s] :%s\n",[logLevelFlag UTF8String], [contentModel.timeStr UTF8String], [contentModel.fmtLogLevelStr UTF8String], [contentModel.keyIdentifierStr UTF8String], [contentModel.file UTF8String], (unsigned long)contentModel.line, [contentModel.functionName UTF8String], [contentModel.threadFlag UTF8String], [contentModel.format UTF8String]);
    }else {
        fprintf(contentModel.logLevel == YP_LOG_LEVEL_ERROR ? stderr : stdout,"%s [%s] [%s] [%s:%lu] [%s] [%s] :%s\n",[logLevelFlag UTF8String], [contentModel.timeStr UTF8String], [contentModel.fmtLogLevelStr UTF8String], [contentModel.file UTF8String], (unsigned long)contentModel.line, [contentModel.functionName UTF8String], [contentModel.threadFlag UTF8String], [contentModel.format UTF8String]);
    }
    [yp_logPrintLock unlock];
}

//MARK: - yp_writeLogWithContentModel:
+ (void)yp_writeLogWithContentModel:(YPLogContentModel *)contentModel {
    [yp_logWriteLock lock];
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
    if(![fileManager fileExistsAtPath:filePath]) {
        [contentModel.fullLogContent writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (error) {
            YPLogError(@"日志信息写入文件失败,errorInfo: %@ 对应日志内容:%@", error.domain, contentModel.fullLogContent);
        }
        
    }else {
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForUpdatingAtPath:filePath];
        [fileHandle seekToEndOfFile];
        NSData* stringData = [contentModel.fullLogContent dataUsingEncoding:NSUTF8StringEncoding];
        [fileHandle writeData:stringData];
        [fileHandle synchronizeFile];
        [fileHandle closeFile];
    }
    
    yp_writeLogTimes ++;
    if (!(yp_writeLogTimes % 5000)) {
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
    
    [yp_logWriteLock unlock];
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
    YPLogInfo(@"日志文件总大小:%lld, 折合约:%fMb", folderSize, totalSize);
    
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
        struct sigaction newSignalAction;
        memset(&newSignalAction, 0,sizeof(newSignalAction));
        newSignalAction.sa_handler = &yp_signalHandler;
        sigaction(SIGABRT, &newSignalAction, NULL);
        sigaction(SIGILL, &newSignalAction, NULL);
        sigaction(SIGSEGV, &newSignalAction, NULL);
        sigaction(SIGFPE, &newSignalAction, NULL);
        sigaction(SIGBUS, &newSignalAction, NULL);
        sigaction(SIGPIPE, &newSignalAction, NULL);
        
        NSSetUncaughtExceptionHandler(&yp_handleExceptions);
        _hasMonitor = YES;
    }
    
}
//MARK: - yp_signalHandler
void yp_signalHandler(int sig) {
    YPLogError(@"crash signal = %d", sig);
}
//MARK: - yp_handleExceptions
void yp_handleExceptions(NSException *exception) {
    YPLogError(@"crash exception = %@",exception);
    YPLogError(@"crash callStackSymbols = %@",[exception callStackSymbols]);
}






@end
