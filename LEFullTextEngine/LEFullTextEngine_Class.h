//
//  LEFullTextEngine.h
//  FullTextSearch
//
//  Created by Leo on 16/5/25.
//  Copyright © 2016年 leo. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol LEFTDataImporter;
@class LEFTPartcipleWrapper;
@class LEFTValue;
@class LEFTSearchResult;

typedef void(^LEFTResultHandler)(LEFTSearchResult *result);

typedef NS_ENUM(NSUInteger, LEFTSearchOrderType) {
    LEFTSearchOrderTypeNone,
    LEFTSearchOrderTypeAsc,
    LEFTSearchOrderTypeDesc
};

@interface LEFTSearchResult : NSObject

- (LEFTValue *)next;

@end

/*
 * 搜索主封装
 */
@interface LEFullTextEngine : NSObject

@property (nonatomic, readonly) NSString *rootDirectory;
@property (nonatomic, readonly) LEFTPartcipleWrapper *partcipleWrapper;

- (instancetype)initWithRootDirectory:(NSString *)rootDirectory;

// 查看是否存在关键字索引
- (BOOL)hasKeyword:(NSString *)keyword;
// 通过关键字搜索
- (void)searchValueWithKeywords:(NSArray *)keywords until:(NSTimeInterval)time resultHandler:(LEFTResultHandler)handler;
- (void)searchValueWithSentence:(NSString *)sentence until:(NSTimeInterval)time resultHandler:(LEFTResultHandler)handler;
- (void)searchValueWithSentence:(NSString *)sentence customType:(NSUInteger)customType until:(NSTimeInterval)time tag:(NSString *)tag orderBy:(LEFTSearchOrderType)orderType resultHandler:(LEFTResultHandler)handler;
// ==>
- (void)searchValueWithKeywords:(NSArray *)keywords until:(NSTimeInterval)time customType:(NSUInteger)customType tag:(NSString *)tag orderBy:(LEFTSearchOrderType)orderType resultHandler:(LEFTResultHandler)handler;

// 记录关键字信息(add,update)
- (BOOL)importValue:(LEFTValue *)value;
- (BOOL)importValues:(NSArray *)values;
- (BOOL)importValuesSync:(NSArray *)values;
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
