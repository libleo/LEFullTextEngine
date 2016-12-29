//
//  LEFTCPUUsage.h
//  FullTextSearch
//
//  Created by leo on 2016/12/29.
//  Copyright © 2016年 leo. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LEFTCPUUsage : NSObject

+ (instancetype)defaultInstance;

- (NSUInteger)cpuNumber;

- (CGFloat)totalUsage;
- (CGFloat)usageWithCoreNumber:(NSUInteger)coreNumber;

@end
