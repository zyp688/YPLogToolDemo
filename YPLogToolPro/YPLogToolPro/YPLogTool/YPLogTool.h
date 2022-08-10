//
//  YPLogTool.h
//  YPLogToolPro
//
//  Created by zyp on 2022/7/26.
//
// >>> 日志文件存储层级结构说明
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

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>


/** 提供给外部使用的便捷打印宏*/
// ----- 单纯DEBEG环境下的打印 不参与写入文件 🐭
#define NSLog(frmt, ...) [YPLogTool yp_logWithType:YP_LOG_LEVEL_ONLY_DEBUG_PRINT_NSLOG file:[[NSString stringWithUTF8String:__FILE__] lastPathComponent]  line:__LINE__ function:[NSString stringWithFormat:@"%s", __FUNCTION__] format:[NSString stringWithFormat:frmt, ##__VA_ARGS__]]
#define YPDLog(frmt, ...) [YPLogTool yp_logWithType:YP_LOG_LEVEL_ONLY_DEBUG_PRINT_NSLOG file:[[NSString stringWithUTF8String:__FILE__] lastPathComponent]  line:__LINE__ function:[NSString stringWithFormat:@"%s", __FUNCTION__] format:[NSString stringWithFormat:frmt, ##__VA_ARGS__]]


// ------ 有可能会写入文件的宏 具体根据开关等环境变量判定 YPWLog***
// 打印输出普通信息 ❄️
#define YPWLogInfo(frmt, ...) [YPLogTool yp_logWithType:YP_LOG_LEVEL_INFO file:[[NSString stringWithUTF8String:__FILE__] lastPathComponent]  line:__LINE__ function:[NSString stringWithFormat:@"%s", __FUNCTION__] format:[NSString stringWithFormat:frmt, ##__VA_ARGS__]]
// 打印输出警告信息 ⚠️
#define YPWLogWarn(frmt, ...) [YPLogTool yp_logWithType:YP_LOG_LEVEL_WARN file:[[NSString stringWithUTF8String:__FILE__] lastPathComponent]  line:__LINE__ function:[NSString stringWithFormat:@"%s", __FUNCTION__] format:[NSString stringWithFormat:frmt, ##__VA_ARGS__]]
// 打印输出错误信息 ❌
#define YPWLogError(frmt, ...) [YPLogTool yp_logWithType:YP_LOG_LEVEL_ERROR file:[[NSString stringWithUTF8String:__FILE__] lastPathComponent]  line:__LINE__ function:[NSString stringWithFormat:@"%s", __FUNCTION__] format:[NSString stringWithFormat:frmt, ##__VA_ARGS__]]


/**
 * 最大存储日志文件大小(Mb)
 * 默认值为30Mb
 * 即当日志文件总大小高于30Mb时，会触发自动清理最早的日志文件
 * - 注意：如果设置了『yp_forceSaveDays』强制保留期天数， 则不会自动清除处于保留天数内的日志文件
 */
static float yp_maxFoldSize = 30;


/**
 * 强制保留最近『yp_forceSaveDays』天数内的日志
 * 默认保留7天当日志文件
 * 当大于『yp_maxFoldSize』Mb时，如最早期的日志文件仍如处于『yp_forceSaveDays』天数范围内，优先保留，不会触发自动清除
 */
static int yp_forceSaveDays = 7;

// 打印类型
typedef NS_ENUM(NSUInteger, YP_LOG_LEVEL_TYPE) {
    YP_LOG_LEVEL_INFO = 0,                ///<  默认信息 ❄️
    YP_LOG_LEVEL_WARN,                    ///<  警告信息 ⚠️
    YP_LOG_LEVEL_ERROR,                   ///<  错误信息 ❌
    YP_LOG_LEVEL_VERBOSE,                 ///<  详细信息 (暂未使用)
    YP_LOG_LEVEL_ONLY_DEBUG_PRINT_NSLOG,  ///< 只在DEBUG环境下输出日志内容，不参与写入 🐭
};


// 日志数据模型
@interface YPLogContentModel : NSObject

/** 打印的内容*/
@property (strong, nonatomic) NSString *content;
/** 字体颜色*/
@property (strong, nonatomic) UIColor *fontColor;
@property (assign, nonatomic) YP_LOG_LEVEL_TYPE logType;

@end



// 日志工具类
@interface YPLogTool : NSObject


/**
 * @brief 设置是否写入本地文件中开关 - 建议再尽量靠前的情况下设置开关 - 该方法内部会同步捕捉一些异常信息
 * @param on - 开关 内部会自动区分开发环境/生产环境 (只有生产环境&&设置为YES时会写入文件)
 * @param userId - 用户唯一标识，用于区分写入文件名称，如需要上传服务器时-也便于区分用户
 */
+ (void)yp_setWriteToFileOn:(BOOL)on bindUserId:(NSString *)userId;


/**
 * @brief 应对一些BT性的需求（如SDK封装等），要求不区分环境，必须要将日志写入到文件中。
 *  - 可用于真机联调的测试直接down包看效果【一般不建议使用强制写入】
 * @param forceToWrite - 不区分环境 强制写入到文件中
 */
+ (void)yp_setForceWirteToFile:(BOOL)forceToWrite;


/**
 * @brief 打印日志内容方法
 * @param file - 文件名称/类名
 * @param line - 对应类中的行数
 * @param function - 对应类中调用的方法
 * @param format - 打印内容
 */
+ (void)yp_logWithType:(YP_LOG_LEVEL_TYPE)type file:(NSString *)file line:(NSUInteger)line function:(NSString *)function format:(NSString *)format;


/**
 * @brief 获取当前的打印过的数据 （可以用于一些图形化日志回显）
 * @return 存储打印过的内容的数组
 */
+ (NSArray <YPLogContentModel *> *)yp_getCurrentLogContents;



@end



