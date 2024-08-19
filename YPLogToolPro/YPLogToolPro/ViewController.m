//
//  ViewController.m
//  YPLogToolPro
//
//  Created by admin on 2022/7/26.
//

#import "ViewController.h"
#import "YPLoggerTool.h"

#import <Photos/Photos.h>

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [YPLoggerTool yp_setSaveLogsPath:@"Library/Log/YPLogs"];
    
    [self printTooMuchLogs:nil param:nil];
    
   
}


- (void)printTooMuchLogs:(NSString *)a param:(NSString *)b {
    // 并行队列 + 子线程 模拟并发写日志
    dispatch_queue_t concurrentQueue = dispatch_queue_create("com.example.concurrentQueue", DISPATCH_QUEUE_CONCURRENT);
    for (int j = 10000; j < 20000; j++) {
        dispatch_async(concurrentQueue, ^{
            if (j % 3 == 0) {
                YPLogWarn(@"小螺号滴滴的吹，海鸥听了瞎几把飞---%d", j);
            }else if (j % 3 == 1) {
                YPLogInfo(@"小螺号滴滴的吹，海鸥听了瞎几把飞---%d", j);
            }else {
                YPLogError(@"小螺号滴滴的吹，海鸥听了瞎几把飞---%d", j);
            }
        });
    }
}


- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    YPLogInfo(@"点击了----");
    
    for (int i = 80000; i < 90000; i ++) {
        YPLogInfo(@"哒哒哒冒蓝火的加特林, 第&&%d把", i);
    }
}

@end
