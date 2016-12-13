//
//  LEFTPartcipleWrapper.h
//  FullTextSearch
//
//  Created by Leo on 16/5/25.
//  Copyright © 2016年 leo. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LEFTPartcipleWrapper : NSObject

+ (instancetype)shareInstance;

// 最小化分词(颗粒度细)
- (NSArray *)minimumParticipleContent:(NSString *)content;
// 最小化分词，不删减英语
- (NSArray *)minimumTestParticipleContent:(NSString *)content;
// 简单分词
- (NSArray *)participleContent:(NSString *)content;
// 兼容英语中文的分词
- (NSArray *)participleKeywordsContent:(NSString *)content;
// 取出有意义的关键字
- (NSArray *)extractKeywordsWithContent:(NSString *)content;

@end
