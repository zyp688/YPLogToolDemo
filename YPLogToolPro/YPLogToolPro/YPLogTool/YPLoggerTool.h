//
//  YPLoggerTool.h
//  YPLogToolPro
//
//  Created by zyp on 2022/7/26.
//
// >>> 日志文件 默认存储层级结构说明
/**
 * App根目录
 *  - Library
 *      - Caches
 *          - YPLogs
 *              - DefaultUser（默认用户）
 *                  - YPLog_DefaultUser_20160518.text
 *                  - YPLog_DefaultUser_20160519.text
 *                  - YPLog...
 *              - User1
 *                  - YPLog_User1_20160520.text
 *                  - YPLog_User1_20160521.text
 *                  - YPLog...
 *              - User...
 */
// <<< 其中 Library/Caches/YPLogs 为日志存储的根路径，提供了API可自行更新此路径

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>


// 便捷使用宏
/** 接管系统原有打印，替换为仅在DEBUG模式下打印 - 可根据实际情况删除*/
#define NSLog(frmt, ...) [YPLoggerTool yp_logWithLevel:YP_LOG_LEVEL_VERBOSE keyIdentifiers:nil file:[[NSString stringWithUTF8String:__FILE__] lastPathComponent] line:__LINE__ function:[NSString stringWithUTF8String:__PRETTY_FUNCTION__] format:[NSString stringWithFormat:frmt, ##__VA_ARGS__]]

/** 打印VERBOSE日志信息*/
#define YPLogVerbose(frmt, ...) [YPLoggerTool yp_logWithLevel:YP_LOG_LEVEL_VERBOSE keyIdentifiers:nil file:[[NSString stringWithUTF8String:__FILE__] lastPathComponent] line:__LINE__ function:[NSString stringWithUTF8String:__PRETTY_FUNCTION__] format:[NSString stringWithFormat:frmt, ##__VA_ARGS__]]
/** 打印DEBUG日志信息*/
#define YPLogDebug(frmt, ...) [YPLoggerTool yp_logWithLevel:YP_LOG_LEVEL_DEBUG keyIdentifiers:nil file:[[NSString stringWithUTF8String:__FILE__] lastPathComponent] line:__LINE__ function:[NSString stringWithUTF8String:__PRETTY_FUNCTION__] format:[NSString stringWithFormat:frmt, ##__VA_ARGS__]]
/** 打印INFO日志信息*/
#define YPLogInfo(frmt, ...) [YPLoggerTool yp_logWithLevel:YP_LOG_LEVEL_INFO keyIdentifiers:nil file:[[NSString stringWithUTF8String:__FILE__] lastPathComponent] line:__LINE__ function:[NSString stringWithUTF8String:__PRETTY_FUNCTION__] format:[NSString stringWithFormat:frmt, ##__VA_ARGS__]]
/** 打印WARN日志信息*/
#define YPLogWarn(frmt, ...) [YPLoggerTool yp_logWithLevel:YP_LOG_LEVEL_WARN keyIdentifiers:nil file:[[NSString stringWithUTF8String:__FILE__] lastPathComponent] line:__LINE__ function:[NSString stringWithUTF8String:__PRETTY_FUNCTION__] format:[NSString stringWithFormat:frmt, ##__VA_ARGS__]]
/** 打印ERROR日志信息*/
#define YPLogError(frmt, ...) [YPLoggerTool yp_logWithLevel:YP_LOG_LEVEL_ERROR keyIdentifiers:nil file:[[NSString stringWithUTF8String:__FILE__] lastPathComponent] line:__LINE__ function:[NSString stringWithUTF8String:__PRETTY_FUNCTION__] format:[NSString stringWithFormat:frmt, ##__VA_ARGS__]]



// 打印类型
typedef NS_ENUM(NSUInteger, YP_LOG_LEVEL_TYPE) {
    YP_LOG_LEVEL_VERBOSE = 0,              ///<  详细信息
    YP_LOG_LEVEL_DEBUG,                    ///<  调试信息
    YP_LOG_LEVEL_INFO,                     ///<  默认信息
    YP_LOG_LEVEL_WARN,                     ///<  警告信息
    YP_LOG_LEVEL_ERROR,                    ///<  错误信息
};


// 日志数据模型
@interface YPLogContentModel : NSObject

/** 字体颜色*/
@property (strong, nonatomic) UIColor *fontColor;
@property (strong, nonatomic) NSString *timeStr;
@property (assign, nonatomic) YP_LOG_LEVEL_TYPE logLevel;
@property (strong, nonatomic) NSString *printLogLevelFlag;
@property (strong, nonatomic) NSString *fmtLogLevelStr;
@property (strong, nonatomic) NSArray <NSString *> *keyIdentifiers;
@property (strong, nonatomic) NSString *keyIdentifierStr;
@property (strong, nonatomic) NSString *file;
@property (assign, nonatomic) NSUInteger line;
@property (strong, nonatomic) NSString *threadFlag;
@property (strong, nonatomic) NSString *function;
@property (strong, nonatomic) NSString *functionName;
@property (strong, nonatomic) NSString *format;
@property (strong, nonatomic) NSString *fullLogContent;


@property (assign, nonatomic) const char *timeStrUTF8;
@property (assign, nonatomic) const char *fmtLogLevelStrUTF8;
@property (assign, nonatomic) const char *printLogLevelFlagUTF8;
@property (assign, nonatomic) const char *keyIdentifierStrUTF8;
@property (assign, nonatomic) const char *fileUTF8;
@property (assign, nonatomic) const char *threadFlagUTF8;
@property (assign, nonatomic) const char *functionUTF8;
@property (assign, nonatomic) const char *functionNameUTF8;
@property (assign, nonatomic) const char *formatUTF8;


@end




// 日志工具类
@interface YPLoggerTool : NSObject


/**
 * @brief 设置日志文件存储的根路径 - 完整目录路径
 * @param saveLogsPath - 路径地址（默认: @"Library/Caches/YPLogs"，可参考上方层级分析）
 * @discuss 当前仅支持调整一次，注意不要频繁更改！！！否则会影响空间、时间限制的统计
 */
+ (void)yp_setSaveLogsPath:(NSString *)saveLogsPath;

/**
 * @brief 设置 >= 此日志级别的日志 才需要写入文件 默认为 YP_LOG_LEVEL_DEBUG， 即只有YP_LOG_LEVEL_VERBOSE 级别日志没有写入文件
 * @param writelogLevel - >= 此日志级别的日志 可写入文件
 */
+ (void)yp_setWriteLogLevel:(YP_LOG_LEVEL_TYPE)writelogLevel;

/**
 * @brief 绑定日志文件夹用户名称
 * @param userIndentifier - 用户唯一标识
 */
+ (void)yp_bindUserIndentifier:(NSString *)userIndentifier;


/**
 * @brief 设置日志最大存储空间
 * @param maxFoldSize - 最大存储空间（默认为100Mb）
 */
+ (void)yp_setMaxFoldSize:(CGFloat)maxFoldSize;

/**
 * @brief 设置日志最长保留时间
 * @param maxSaveDays - 最长保留时间（默认为30天）
 * @discuss 目前优先级方面：时间限制  > 空间限制， 即即使超过了空间限制，但只要日志仍处于有效的保留时间内，不会进行清理
 */
+ (void)yp_setMaxSaveDays:(int)maxSaveDays;



/**
 * @brief 设置密文加密时用到的key
 * @param aesKey - 加密日志用到的key，目前支持AES加密 16位
 */
+ (void)yp_setSecureAesKey:(NSString *)aesKey;

/**
 * @brief 脱敏开关设置
 * @param onSecure - 是否脱敏，日志以密文形式写入文件夹
 * @discuss 开发控制台始终会是明文，此设置仅会对写入文件的日志有影响
 */
+ (void)yp_switchSecure:(BOOL)onSecure;


/**
 * @brief 核心 打印日志内容方法
 * @param logLevel - 日志等级
 * @param keyIdentifiers - 关键字标识数组 用以查询便捷检索
 * @param file - 文件名称/类名
 * @param line - 对应类中的行数
 * @param function - 对应类中调用的方法
 * @param format - 打印内容
 */
+ (void)yp_logWithLevel:(YP_LOG_LEVEL_TYPE)logLevel keyIdentifiers:(NSArray <NSString *> *)keyIdentifiers file:(NSString *)file line:(NSUInteger)line function:(NSString *)function format:(NSString *)format;


/**
 * @brief 获取当前的打印过的数据 （可以用于一些图形化日志回显）
 * @return 存储打印过的内容的数组
 * @discuss  记录所有调用过日志打印的数组 - - - 仅在 DEBUG 模式下起作用，不会做清空等处理 - 只用于记录(按需使用！，如果需要回显，才会持续持有数据，此处日志量过大会造成内存持续增长)
 */
+ (NSArray <YPLogContentModel *> *)yp_getAllLogContents;


/**
 * @brief 提交一次写入日志任务 -
 * @discuss - 防止内置检测机制，仍有遗失日志风险
 */
+ (void)yp_commitWriteLog;

@end



