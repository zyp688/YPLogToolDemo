//
//  ViewController.m
//  YPLogToolPro
//
//  Created by admin on 2022/7/26.
//

#import "ViewController.h"
#import "YPLogTool.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    
    
    
    
    [self printLogs];
    
//    NSString *a = @{};
//    if (a.length) { // crash test
//        YPDLog(@"aaa");
//    }
}


- (void)printLogs {
    for (int i = 0 ; i < 2000; i ++) {
        if (i % 3 == 0) {
            YPWLogInfo(@"哒哒哒冒蓝火的加特林, 第%d把", i);
        }else if (i % 3 == 1) {
            YPWLogWarn(@"哒哒哒冒蓝火的加特林, 第%d把", i);
        }else {
            YPWLogError(@"哒哒哒冒蓝火的加特林, 第%d把", i);
        }
        
        [NSThread sleepForTimeInterval:0.5];
    }
}

@end
