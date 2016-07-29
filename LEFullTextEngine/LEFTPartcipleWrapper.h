//
//  LEFTPartcipleWrapper.h
//  FullTextSearch
//
//  Created by Leo on 16/5/25.
//  Copyright © 2016年 leo. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LEFTPartcipleWrapper : NSObject

// 最小化分词(颗粒度细)
- (NSArray *)minimumParticpleContent:(NSString *)content;
// 简单分词
- (NSArray *)particpleContent:(NSString *)content;
// 取出有意义的关键字
- (NSArray *)extractKeywordsWithContent:(NSString *)content;

@end
