//
//  LEFullTextEngine.h
//  FullTextSearch
//
//  Created by Leo on 16/5/25.
//  Copyright © 2016年 leo. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "LEFTDataImporter.h"
#import "LEFTPartcipleWrapper.h"

#include <sqlite3.h>

@class LEFTValue;

typedef NS_ENUM(NSUInteger, LEFTSearchOrderType) {
    LEFTSearchOrderTypeNone,
    LEFTSearchOrderTypeAsc,
    LEFTSearchOrderTypeDesc
};

@interface LEFTSearchResult : NSObject

- (instancetype)initWithStmt:(sqlite3_stmt *)stmt;

- (LEFTValue *)next;

@end

/*
 * 搜索主封装
 */
@interface LEFullTextEngine : NSObject

@property (nonatomic, readonly) NSString *rootDirectory;
@property (nonatomic, readonly) LEFTPartcipleWrapper *partcipleWrapper;

- (instancetype)initWithRootDirectory:(NSString *)rootDirectory;

// 通过关键字搜索，返回迭代器
- (LEFTSearchResult *)searchValueWithKeyword:(NSString *)keyword until:(NSTimeInterval)time;
- (LEFTSearchResult *)searchValueWithSentence:(NSString *)sentence until:(NSTimeInterval)time;
- (LEFTSearchResult *)searchValueWithKeyword:(NSString *)keyword until:(NSTimeInterval)time orderBy:(LEFTSearchOrderType)type;
- (LEFTSearchResult *)searchValueWithSentence:(NSString *)sentence until:(NSTimeInterval)time orderBy:(LEFTSearchOrderType)type;
// 记录关键字信息(add,update)
- (BOOL)importValue:(LEFTValue *)value;
- (BOOL)importValues:(NSArray *)values;
// 清理数据库(delete)
- (BOOL)deleteValuesWithKeyword:(NSString *)keyword;
- (BOOL)truncate;

// 批量装入数据
- (void)startImporter:(id<LEFTDataImporter>)importer;
- (void)pauseImporter:(id<LEFTDataImporter>)importer;
- (void)resumeImporter:(id<LEFTDataImporter>)importer;
- (BOOL)cancelImporter:(id<LEFTDataImporter>)importer;
- (NSArray *)importers;

@end
